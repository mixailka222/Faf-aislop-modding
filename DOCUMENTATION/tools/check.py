"""Single check for mods: LuaLS, FAF Lua compiler, rules, imports, mod_info, tests.

    python DOCUMENTATION/tools/check.py                         all tracked mods
    python DOCUMENTATION/tools/check.py "My_mods/project/Mod"   one mod
    python DOCUMENTATION/tools/check.py --changed-since main    changed mods
    --no-luac    CI only: the compiler and the tests run there as a separate job
"""
import argparse
import functools
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

import bootstrap
import validate_mod

ROOT = bootstrap.ROOT
MOD_INFO = "mod_info.lua"
ALWAYS_CHECKED = "My_mods/Custom Hotkeys/customhotkeys"
VERSIONS_PATH = "DOCUMENTATION/tools/tool_versions.json"
LUALS_REPORT = ".tools/luals_report.json"
REQUIRED_FIELDS = ("name", "version", "uid", "description", "ui_only")
LIBRARIES = {"reui": "ReUI", "umt": "UMT"}
KNOWLEDGE_DIR = "DOCUMENTATION/knowledge"
SOURCE_ROOTS = {
    "fa": "references/fa",
    "ui-libs": "references/ui-libs",
    "lua-lang": "references/lua-lang",
}
SOURCE_MARK = "Источник:"
FACT_MARKS = ("Наблюдение:", "Не подтверждено:")

SOURCE = re.compile(r"^(fa|ui-libs|lua-lang):([^#]+)#(.+)$")
IMPORT =re.compile(r"""\bimport\s*\(?\s*(['"])([^'"]+)\1\s*(\.\.)?""")
FIELD = re.compile(r"^([A-Za-z_]\w*)\s*=", re.MULTILINE)
LIBRARY_TAG = re.compile(r"""^ReUI\s*=\s*['"]([^'"=]+)""", re.MULTILINE)


class CheckError(Exception):
    pass


def git(root: Path, *args: str) -> list[str]:
    done = subprocess.run(["git", *args], cwd=root, capture_output=True, encoding="utf-8",
                          errors="replace")
    if done.returncode != 0:
        raise CheckError(f"git {args[0]}: {done.stderr.strip()}")
    return [item for item in done.stdout.split("\0") if item]


def find_mods(root: Path) -> list[Path]:
    """Tracked mods only: a local experiment may be unfinished on purpose."""
    files = (Path(name) for name in git(root, "ls-files", "-z", "--", "My_mods"))
    return sorted({root / path.parent for path in files
                   if path.name == MOD_INFO and "tests" not in path.parts})


def project_dir(mod: Path) -> Path:
    parts = mod.parts
    return Path(*parts[:parts.index("My_mods") + 2])


def tests_project(mod: Path) -> Path | None:
    """The project whose tests/ checks this mod.

    Tests belong to the mod next to them. A mod nested deeper in the project, like a
    diagnostic build, has no tests of its own and must not inherit their result.
    """
    project = project_dir(mod)
    return project if mod == project or mod.parent == project else None


def relative(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def changed_files(root: Path, base: str) -> list[str]:
    """Changes of this branch only: commits that landed on base meanwhile do not count.

    Without --no-renames a moved file is listed under its new path only, and the mod
    it left would not be checked.
    """
    return git(root, "diff", "--name-only", "--no-renames", "-z", f"{base}...HEAD")


def versions_changed(root: Path, base: str, files: list[str]) -> bool:
    """The first appearance of the file is not a version change."""
    if VERSIONS_PATH not in files:
        return False
    fork = git(root, "merge-base", base, "HEAD")[0].strip()
    known = subprocess.run(["git", "cat-file", "-e", f"{fork}:{VERSIONS_PATH}"], cwd=root,
                           capture_output=True)
    return known.returncode == 0


def touches_code(root: Path, mod: Path, files: list[str]) -> bool:
    prefix = relative(root, mod) + "/"
    return any(name.startswith(prefix) and not name.endswith("README.md") for name in files)


def touches_tests(root: Path, mod: Path, files: list[str]) -> bool:
    prefix = relative(root, project_dir(mod)) + "/tests/"
    return any(name.startswith(prefix) and name.endswith((".lua", ".py")) for name in files)


def changed_mods(root: Path, base: str) -> list[Path]:
    mods = find_mods(root)
    files = changed_files(root, base)
    if versions_changed(root, base, files):
        return mods
    return [mod for mod in mods
            if relative(root, mod) == ALWAYS_CHECKED
            or touches_code(root, mod, files)
            or touches_tests(root, mod, files)]


def readme_warnings(root: Path, base: str) -> list[str]:
    files = changed_files(root, base)
    warnings = []
    for mod in find_mods(root):
        readme = relative(root, project_dir(mod)) + "/README.md"
        if touches_code(root, mod, files) and readme not in files:
            warnings.append(f"Изменён код {relative(root, mod)}, но не {readme}")
    return warnings


def check_versions(no_luac: bool = False) -> list[str]:
    expected = bootstrap.expected_versions(bootstrap.load_versions())
    tools = [bootstrap.luals_path()]
    if no_luac:
        del expected["faf-lua"]
    else:
        tools += [bootstrap.luac_path(), bootstrap.lua_path()]
    stale = bootstrap.outdated(expected, bootstrap.load_installed())
    stale += [tool.name for tool in tools if not tool.exists()]
    stale += [f"references/{name}" for name in bootstrap.SPARSE
              if not (bootstrap.ROOT / "references" / name).is_dir()]
    if not stale:
        return []
    return [f"Инструменты устарели или не установлены: {', '.join(stale)}. "
            "Запусти: python DOCUMENTATION/tools/bootstrap.py"]


def parse_luals(raw: dict | list) -> dict[Path, list[str]]:
    """LuaLS writes an object of files, but an empty list when it found nothing."""
    if raw == []:
        return {}
    report = {}
    for uri, diagnostics in raw.items():
        name = unquote(urlparse(uri).path)
        path = Path(name[1:] if re.match(r"/[A-Za-z]:", name) else name)
        report[path] = [
            f"строка {item['range']['start']['line'] + 1}: [{item.get('code')}] "
            f"{item['message'].splitlines()[0]}"
            for item in diagnostics
        ]
    return report


def require_paths_inside(report: dict[Path, list[str]], root: Path) -> None:
    """Paths that match no mod would look like a clean result, so this has to fail loudly."""
    if report and not any(root in path.parents for path in report):
        raise CheckError(f"Пути в отчёте LuaLS не совпали с {root}: {next(iter(report))}")


def run_luals(root: Path) -> dict[Path, list[str]]:
    """One run for the whole repository: it takes seconds and the result is filtered by mod."""
    output = root / LUALS_REPORT
    output.unlink(missing_ok=True)
    done = subprocess.run(
        [str(bootstrap.luals_path()), "--check=.", "--checklevel=Warning", "--check_format=json",
         f"--check_out_path={LUALS_REPORT}", "--trust_all_plugins"],
        cwd=root, capture_output=True, encoding="utf-8", errors="replace")
    if "Diagnosis complete" not in done.stdout:
        raise CheckError(f"LuaLS не отработал: {done.stdout[-500:]} {done.stderr[-500:]}")
    if not output.exists():
        return {}
    report = parse_luals(json.loads(output.read_text(encoding="utf-8")))
    require_paths_inside(report, root)
    return report


def luals_problems(report: dict[Path, list[str]], mod: Path) -> list[str]:
    return [f"{path.name}: {problem}" for path, problems in report.items()
            if mod in path.parents for problem in problems]


def lua_files(mod: Path) -> list[Path]:
    return sorted(mod.rglob("*.lua"))


def check_luac(mod: Path) -> list[str]:
    problems = []
    for path in lua_files(mod):
        done = subprocess.run([str(bootstrap.luac_path()), "-p", str(path)], capture_output=True,
                              encoding="utf-8", errors="replace")
        if done.returncode != 0:
            lines = done.stderr.strip().splitlines()
            problems.append(lines[0] if lines else f"{path.name}: luac завершился с ошибкой")
    return problems


def check_rules(mod: Path) -> list[str]:
    return [f"{path.name}: {problem}" for path in lua_files(mod)
            for problem in validate_mod.check_file(path)]


@functools.lru_cache
def existing_files(base: Path) -> frozenset[str]:
    return frozenset(path.relative_to(base).as_posix().lower()
                     for path in base.rglob("*") if path.is_file())


def import_is_missing(mod: Path, target: str) -> bool:
    """Game paths are case-insensitive. Other mods and relative paths are not checked."""
    lowered = target.lower().lstrip("/")
    if not target.startswith("/"):
        return False
    if lowered.startswith("lua/"):
        return lowered not in existing_files(ROOT / "references" / "fa")
    parts = lowered.split("/", 2)
    if parts[0] != "mods" or len(parts) < 3:
        return False
    if parts[1] == mod.name.lower():
        return parts[2] not in existing_files(mod)
    if parts[1] in LIBRARIES:
        library = ROOT / "references" / "ui-libs" / "mods" / LIBRARIES[parts[1]]
        return parts[2] not in existing_files(library)
    return False


def check_imports(mod: Path) -> list[str]:
    problems = []
    for path in lua_files(mod):
        code = validate_mod.strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        for found in IMPORT.finditer(code):
            built_at_runtime = found.group(3)
            if not built_at_runtime and import_is_missing(mod, found.group(2)):
                problems.append(f"{path.name}: нет файла {found.group(2)}")
    return problems


def check_mod_info(mod: Path) -> list[str]:
    text = (mod / MOD_INFO).read_text(encoding="utf-8", errors="replace")
    fields = set(FIELD.findall(text))
    problems = [f"нет поля {field}" for field in REQUIRED_FIELDS if field not in fields]
    tag = LIBRARY_TAG.search(text)
    if tag and tag.group(1) != mod.name:
        problems.append(f"тег ReUI '{tag.group(1)}' не совпадает с папкой '{mod.name}'")
    return problems


def check_readme(mod: Path) -> list[str]:
    readme = project_dir(mod) / "README.md"
    return [] if readme.exists() else [f"нет файла {readme.name} в {project_dir(mod).name}"]


def run_tests(project: Path) -> list[str]:
    """Only test_*.lua, run from tests/ by the Lua of the game.

    Other scripts in tests/ are slow mutation checks, run by hand.
    """
    folder = project / "tests"
    if not folder.is_dir():
        return []
    problems = []
    for script in sorted(folder.glob("test_*.lua")):
        done = subprocess.run([str(bootstrap.lua_path()), script.name], cwd=folder,
                              capture_output=True, encoding="utf-8", errors="replace")
        output = done.stdout + done.stderr
        failed = [line.strip() for line in output.splitlines() if "[FAIL]" in line]
        if done.returncode != 0 or failed:
            problems.append(f"{script.name}: код выхода {done.returncode}, [FAIL]: {len(failed)}")
            problems += failed[:5]
    return problems


def source_problem(root: Path, value: str) -> str | None:
    if value.startswith("https://"):
        return None
    source = SOURCE.match(value)
    if not source:
        return f"неизвестный формат источника: {value}"
    base, name, text = source.groups()
    path = root / SOURCE_ROOTS[base] / name
    if not path.is_file():
        return f"нет файла {name}"
    if text not in path.read_text(encoding="utf-8", errors="replace"):
        return f"в {name} не найдено: {text}"
    return None


def check_knowledge(root: Path) -> list[str]:
    """Every fact needs a mark. A source is checked, so a removed function turns the check red."""
    folder = root / KNOWLEDGE_DIR
    if not folder.is_dir():
        return [f"нет папки {KNOWLEDGE_DIR}"]
    problems = []
    for path in sorted(folder.glob("*.md")):
        for fact in re.split(r"^### ", path.read_text(encoding="utf-8"), flags=re.M)[1:]:
            lines = fact.splitlines()
            sources = [line[len(SOURCE_MARK):].strip() for line in lines
                       if line.startswith(SOURCE_MARK)]
            if not sources and not any(line.startswith(FACT_MARKS) for line in lines):
                problems.append(f"{path.name}: факт без источника: {lines[0]}")
            for source in sources:
                problem = source_problem(root, source)
                if problem:
                    problems.append(f"{path.name}: {lines[0]}: {problem}")
    return problems


def report(title: str, problems: list[str]) -> bool:
    print(f"[{'FAIL' if problems else 'OK'}] {title}")
    for problem in problems:
        print(f"    {problem}")
    return not problems


def check_mod(mod: Path, luals: dict, no_luac: bool) -> bool:
    print(f"== {relative(ROOT, mod)}")
    results = [report("LuaLS", luals_problems(luals, mod))]
    if no_luac:
        print("[SKIP] luac: в CI его выполняет отдельное задание")
    else:
        results.append(report("luac", check_luac(mod)))
    results.append(report("правила", check_rules(mod)))
    results.append(report("импорты", check_imports(mod)))
    results.append(report("mod_info", check_mod_info(mod)))
    results.append(report("README", check_readme(mod)))
    project = tests_project(mod)
    if project and no_luac:
        print(f"[SKIP] тесты {mod.name}: в CI их выполняет отдельное задание")
    elif project:
        results.append(report(f"тесты {mod.name}", run_tests(project)))
    return all(results)


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mod", nargs="?", help="папка мода, в ней лежит mod_info.lua")
    parser.add_argument("--no-luac", action="store_true", help="только для CI")
    parser.add_argument("--changed-since", metavar="REF", help="только изменённые моды")
    options = parser.parse_args()

    if options.no_luac and not os.environ.get("GITHUB_ACTIONS"):
        print("[FAIL] Ключ --no-luac работает только в CI")
        return 1
    if options.mod and not (Path(options.mod) / MOD_INFO).exists():
        print(f"[FAIL] В папке '{options.mod}' нет {MOD_INFO}")
        return 1
    if not report("версии инструментов", check_versions(options.no_luac)):
        return 1

    try:
        if options.mod:
            mods = [Path(options.mod).resolve()]
        elif options.changed_since:
            mods = changed_mods(ROOT, options.changed_since)
        else:
            mods = find_mods(ROOT)
        luals = run_luals(ROOT)
        results = [check_mod(mod, luals, options.no_luac) for mod in mods]
        if not options.mod:
            results.append(report("база знаний", check_knowledge(ROOT)))
        if options.changed_since and os.environ.get("GITHUB_ACTIONS"):
            for warning in readme_warnings(ROOT, options.changed_since):
                print(f"::warning::{warning}")
    except CheckError as error:
        return 0 if report("запуск проверки", [str(error)]) else 1
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
