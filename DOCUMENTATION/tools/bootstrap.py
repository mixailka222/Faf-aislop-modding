"""Prepare everything the mod checks need: sources, LuaLS, FAF Lua.

Pinned versions live in tool_versions.json. Run again after they change: only
what differs is updated.

    python DOCUMENTATION/tools/bootstrap.py
    python DOCUMENTATION/tools/bootstrap.py --check-updates
    python DOCUMENTATION/tools/bootstrap.py --no-luac    CI only, it uses the official image
"""
import argparse
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERSIONS_FILE = Path(__file__).with_name("tool_versions.json")
GITHUB = "https://github.com/"
GITHUB_API = "https://api.github.com/repos/"
EXE = ".exe" if os.name == "nt" else ""

# Folders of each source repository that are downloaded. An empty list means all of it.
SPARSE = {
    "fa": ["engine", "lua"],
    "fa-addon": ["lua-ls-addon"],
    "ui-libs": ["mods/ReUI", "mods/UMT", "mods/ASE"],
    "lua-lang": [],
}

# USE_FLOAT and LUA_USER_H repeat the "config" file of FAForever/lua-lang: the game
# uses single precision numbers, so a build without them computes differently.
CC_FLAGS = [
    "-O2",
    "-w",
    "-std=gnu89",
    "-fno-sanitize=undefined",
    "-DLUA_OPNAMES",
    '-DLUA_USER_H="../etc/luser_number.h"',
    "-DUSE_FLOAT",
]


class BootstrapError(Exception):
    pass


def tools_dir() -> Path:
    return ROOT / ".tools"


def installed_file() -> Path:
    return tools_dir() / "installed.json"


def luac_path() -> Path:
    return tools_dir() / "faf-lua" / f"luac{EXE}"


def lua_path() -> Path:
    return tools_dir() / "faf-lua" / f"lua{EXE}"


def luals_path() -> Path:
    return tools_dir() / "lua-language-server" / "bin" / f"lua-language-server{EXE}"


def load_versions() -> dict:
    return json.loads(VERSIONS_FILE.read_text(encoding="utf-8"))


def load_installed() -> dict:
    """A damaged record counts as empty: the next run simply reinstalls."""
    if not installed_file().exists():
        return {}
    try:
        return json.loads(installed_file().read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def mark_installed(name: str, value: str) -> None:
    installed = load_installed()
    installed[name] = value
    installed_file().parent.mkdir(parents=True, exist_ok=True)
    # Written aside and swapped in, so an interrupted run cannot leave half a file.
    partial = installed_file().with_suffix(".partial")
    partial.write_text(json.dumps(installed, indent=2), encoding="utf-8")
    os.replace(partial, installed_file())


def expected_versions(versions: dict) -> dict:
    """Flat name -> value map to compare with installed.json.

    The compiler is built from lua-lang by ziglang, so a change in either rebuilds it.
    """
    expected = {
        name: spec["ref"] if isinstance(spec, dict) else spec
        for name, spec in versions.items()
        if name != "ziglang"
    }
    expected["faf-lua"] = f"{expected['lua-lang']}+zig{versions['ziglang']}"
    return expected


def outdated(versions: dict, installed: dict) -> list[str]:
    return [name for name, value in versions.items() if installed.get(name) != value]


def install_step(name: str, value: str, action, *paths: Path) -> None:
    """Runs action unless this version is installed; marks it only after success."""
    if load_installed().get(name) == value and all(path.exists() for path in paths):
        return
    print(f"[..] {name} {value}", flush=True)
    action()
    mark_installed(name, value)


def run(args: list, cwd: Path | None = None, env: dict | None = None) -> str:
    try:
        done = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True,
                              encoding="utf-8", errors="replace")
    except FileNotFoundError as error:
        raise BootstrapError(f"Не найдена программа {args[0]}: {error}") from error
    if done.returncode != 0:
        raise BootstrapError(f"Команда {args[0]} {args[1]} завершилась ошибкой:\n{done.stderr[-1500:]}")
    return done.stdout.strip()


def download(url: str, target: Path) -> None:
    # curl instead of urllib: Python's ssl module fails outright on a machine with one
    # malformed certificate in the Windows store, and curl uses the system TLS stack.
    run(["curl", "-fsSL", "--retry", "3", "-o", str(target), url])


def remove_tree(path: Path) -> None:
    if not path.exists():
        return
    # Git marks its objects read-only, which stops rmtree on Windows. Links are skipped:
    # chmod follows them, and a Linux venv links python to a system file.
    for item in path.rglob("*"):
        if not item.is_symlink():
            os.chmod(item, stat.S_IWRITE | stat.S_IREAD | stat.S_IEXEC)
    shutil.rmtree(path)


def fetch_ref(folder: Path, ref: str) -> None:
    run(["git", "fetch", "-q", "--depth", "1", "--filter=blob:none", "origin", ref], folder)
    run(["git", "checkout", "-q", "--detach", "FETCH_HEAD"], folder)


def same_repository(address: str, url: str) -> bool:
    """One repository has several spellings: with .git, or as an SSH address."""
    def normal(value: str) -> str:
        value = re.sub(r"^git@github\.com:", "https://github.com/", value.strip())
        return value.removesuffix("/").removesuffix(".git").lower()

    return normal(address) == normal(url)


def ensure_repo(name: str, spec: dict, sparse: list[str]) -> None:
    target = ROOT / "references" / name
    url = GITHUB + spec["repo"]

    if target.exists():
        origin = ""
        if (target / ".git").exists():
            origin = run(["git", "remote", "get-url", "origin"], target)
        if not same_repository(origin, url):
            raise BootstrapError(
                f"Папка references/{name} уже занята чем-то другим. "
                f"Ожидается клон {url}. Перенесите папку и запустите скрипт снова."
            )
        if sparse:
            run(["git", "sparse-checkout", "set", *sparse], target)
        fetch_ref(target, spec["ref"])
        return

    # Work in a side folder so that an interrupted download leaves nothing in target.
    partial = target.with_name(name + ".partial")
    remove_tree(partial)
    partial.mkdir(parents=True)
    try:
        run(["git", "init", "-q"], partial)
        run(["git", "remote", "add", "origin", url], partial)
        if sparse:
            run(["git", "sparse-checkout", "set", *sparse], partial)
        fetch_ref(partial, spec["ref"])
    except BootstrapError:
        remove_tree(partial)
        raise
    partial.rename(target)


def luals_asset(version: str, platform: str) -> str:
    suffixes = {"win32": "win32-x64.zip", "linux": "linux-x64.tar.gz"}
    if platform not in suffixes:
        raise BootstrapError(f"LuaLS для системы {platform} не поддержан в bootstrap.py")
    return f"lua-language-server-{version}-{suffixes[platform]}"


def unpack(archive: Path, target: Path) -> None:
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as package:
            package.extractall(target)
    else:
        safe = {"filter": "data"} if hasattr(tarfile, "data_filter") else {}
        with tarfile.open(archive) as package:
            package.extractall(target, **safe)


def install_luals(version: str) -> None:
    asset = luals_asset(version, sys.platform)
    target = tools_dir() / "lua-language-server"
    partial = tools_dir() / "lua-language-server.partial"
    remove_tree(partial)
    partial.mkdir(parents=True)
    archive = partial / asset
    url = f"{GITHUB}LuaLS/lua-language-server/releases/download/{version}/{asset}"
    download(url, archive)
    unpack(archive, partial)
    archive.unlink()
    remove_tree(target)
    partial.rename(target)


def build_faf_lua(zig_version: str) -> None:
    source = ROOT / "references" / "lua-lang"
    output = lua_path().parent
    output.mkdir(parents=True, exist_ok=True)
    cache = tools_dir() / "zig-cache"
    env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(cache), ZIG_LOCAL_CACHE_DIR=str(cache))

    common = [path for path in sorted((source / "src").glob("*.c")) if path.name != "ltests.c"]
    common += sorted((source / "src" / "lib").glob("*.c"))
    programs = {
        luac_path(): [source / "src/luac/luac.c", source / "src/luac/print.c"],
        lua_path(): [source / "src/lua/lua.c"],
    }
    includes = [f"-I{source / 'include'}", f"-I{source / 'src'}"]
    libraries = [] if os.name == "nt" else ["-lm"]
    # The compiler takes 381 MB unpacked and is only needed for this build.
    venv = tools_dir() / "zig-venv"
    remove_tree(venv)
    run([sys.executable, "-m", "venv", str(venv)])
    python = str(venv / ("Scripts" if os.name == "nt" else "bin") / f"python{EXE}")
    try:
        run([python, "-m", "pip", "install", "-q", "--disable-pip-version-check",
             f"ziglang=={zig_version}"])
        for program, sources in programs.items():
            run([python, "-m", "ziglang", "cc", *CC_FLAGS, *includes, *map(str, common),
                 *map(str, sources), *libraries, "-o", str(program)], env=env)
    finally:
        remove_tree(venv)
        remove_tree(cache)
        for leftover in output.glob("*.pdb"):
            leftover.unlink()


def install(versions: dict, build_luac: bool) -> None:
    expected = expected_versions(versions)
    for name, sparse in SPARSE.items():
        repository = ROOT / "references" / name
        install_step(name, expected[name],
                     lambda name=name, sparse=sparse: ensure_repo(name, versions[name], sparse),
                     repository, *(repository / folder for folder in sparse))
    install_step("lua-language-server", expected["lua-language-server"],
                 lambda: install_luals(expected["lua-language-server"]), luals_path())
    if build_luac:
        install_step("faf-lua", expected["faf-lua"], lambda: build_faf_lua(versions["ziglang"]),
                     luac_path(), lua_path())


def last_commit(spec: dict, ref: str, folder: str) -> str:
    """The commit that last touched folder. Compare lists are cut off on long ranges."""
    url = f"{GITHUB_API}{spec['repo']}/commits?sha={ref}&path={folder}&per_page=1"
    return fetch_json(url)[0]["sha"]


def fetch_json(url: str) -> dict | list:
    command = ["curl", "-fsSL", "--retry", "3", "-H", "Accept: application/vnd.github+json"]
    if os.environ.get("GITHUB_TOKEN"):
        command += ["-H", f"Authorization: Bearer {os.environ['GITHUB_TOKEN']}"]
    return json.loads(run([*command, url]))


def latest_versions(versions: dict) -> dict:
    """Returns name -> newer value for tracked components that changed upstream.

    A repository counts as changed only in its downloaded folders. ziglang is
    skipped: a newer build tool does not change what the checks see.
    """
    updates = {}
    for name, spec in versions.items():
        if name == "lua-language-server":
            release = fetch_json(f"{GITHUB_API}LuaLS/lua-language-server/releases/latest")
            if release["tag_name"] != spec:
                updates[name] = release["tag_name"]
        elif isinstance(spec, dict) and "branch" not in spec:
            release = fetch_json(f"{GITHUB_API}{spec['repo']}/releases/latest")
            if release["tag_name"] != spec["ref"]:
                updates[name] = release["tag_name"]
        elif isinstance(spec, dict):
            for folder in SPARSE[name]:
                latest = last_commit(spec, spec["branch"], folder)
                if latest != last_commit(spec, spec["ref"], folder):
                    updates[name] = latest
    return updates


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--no-luac", action="store_true", help="не собирать luac, только для CI")
    parser.add_argument("--check-updates", action="store_true",
                        help="показать новые версии у источников и ничего не менять")
    options = parser.parse_args()

    if options.no_luac and not os.environ.get("GITHUB_ACTIONS"):
        print("[FAIL] Ключ --no-luac работает только в CI")
        return 1
    try:
        if options.check_updates:
            for name, value in latest_versions(load_versions()).items():
                print(f"{name}: {value}")
            return 0
        install(load_versions(), build_luac=not options.no_luac)
    except BootstrapError as error:
        print(f"[FAIL] {error}")
        return 1
    print("[OK] Всё готово")
    return 0


if __name__ == "__main__":
    sys.exit(main())
