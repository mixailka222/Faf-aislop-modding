"""Runs a UI mod in the real game: a smoke run, then the scenarios from tests/game of its project.

    python DOCUMENTATION/tools/game_test.py "My_mods/project/Mod"
    python DOCUMENTATION/tools/game_test.py "My_mods/project/Mod" --only scenario
    python DOCUMENTATION/tools/game_test.py "My_mods/project/Mod" --only scenario --without-mod

--without-mod is the control run of a new scenario: without the mod the scenario has to fail.

Needs a PC with FAF: the game has no mode without a window, so this does not work in CI. Nothing
is written to the game or to the installed mods: the init file and the settings are temporary,
the mods are mounted from their folders and the installed ones are left out of the session.

The smoke run has UI mods only, as for a player. A scenario also needs ModTestSim, because a UI
mod cannot create units, and the run fails if anything else gets into the sim.

Lines at the top of a scenario file change its run:

    -- stand: ai                           the other armies of the map are played by the AI
    -- stand: profile options = { ... }    this text goes into the profile of the temporary settings
    -- stand: expect text                  the log has to contain this text
    -- stand: mod name                     this library from references/ui-libs/mods is active as well
"""
import argparse
import ctypes
import ntpath
import os
import re
import subprocess
import sys
import tempfile
import time
from ctypes import wintypes
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEST_MODS = Path(__file__).resolve().parent / "game_mods"
LIBRARY_MODS = ROOT / "references" / "ui-libs" / "mods"
LOG_DIR = ROOT / ".tools" / "game_test"
DEFAULT_FAF = Path(r"C:\ProgramData\FAForever")

TEST_MOD_UID = "modtest-ui-1"
SIM_HELPER_UID = "modtest-sim-1"
NO_TARGET = "none"
PROFILE = "modtest"
SMOKE = "smoke"
MAP = "SCMP_009"
TIMEOUT = 120

UID = re.compile(r"""^uid\s*=\s*["']([^"']+)""", re.M)
UI_ONLY = re.compile(r"^ui_only\s*=\s*true\b", re.M)
REUI_TAG = re.compile(r"^ReUI\s*=", re.M)
UMT_FLAG = re.compile(r"^__umt\s*=\s*true\b", re.M)
REPLAY = re.compile(r'Saving replay to "([^"]+)"')
SIM_MODS = re.compile(r"\[MODTEST\] sim mods:(.*)")
ERROR_LINE = re.compile(r"FAILED|: ERROR\b|CRASH in|Error importing|Error running lua script|SCR_LuaDoFileConcat"
                        r"|[Aa]ttempt to |nonexistent global|stack traceback")
DIRECTIVE = re.compile(r"^-- stand: (\w+) ?(.*?)\s*$", re.M)
INPUT = re.compile(r"\[MODTEST\] (PRESS \w|MOUSE \d+ \d+)\s*$", re.M)
POLL_SECONDS = 0.2
MOUSE_REPEAT_SECONDS = 0.02
VIEW_CLASS = "wxWindowClass"
WM_KEYDOWN = 0x0100
WM_KEYUP = 0x0101
WM_MOUSEMOVE = 0x0200
SW_SHOWNOACTIVATE = 4


class GameTestError(Exception):
    pass


@dataclass
class ModInfo:
    uid: str
    ui_only: bool
    libraries: list[str]


@dataclass
class ScenarioSetup:
    ai: bool = False
    profile: list[str] = field(default_factory=list)
    expected: list[str] = field(default_factory=list)
    mods: list[str] = field(default_factory=list)


def read_mod_info(mod: Path) -> ModInfo:
    text = (mod / "mod_info.lua").read_text(encoding="utf-8", errors="replace")
    uid = UID.search(text)
    if not uid:
        raise GameTestError(f"В {mod.name}/mod_info.lua нет uid")
    libraries = []
    if REUI_TAG.search(text):
        libraries.append("ReUI")
    if UMT_FLAG.search(text):
        libraries.append("UMT")
    return ModInfo(uid.group(1), bool(UI_ONLY.search(text)), libraries)


def scenario_names(mod: Path) -> list[str]:
    folder = mod.parent / "tests" / "game"
    return [SMOKE, *sorted(path.stem for path in folder.glob("*.lua"))]


def read_setup(mod: Path, scenario: str) -> ScenarioSetup:
    setup = ScenarioSetup()
    if scenario == SMOKE:
        return setup
    text = (mod.parent / "tests" / "game" / f"{scenario}.lua").read_text(encoding="utf-8")
    for name, value in DIRECTIVE.findall(text):
        if name == "ai":
            setup.ai = True
        elif name == "profile":
            setup.profile.append(value)
        elif name == "expect":
            setup.expected.append(value)
        elif name == "mod":
            setup.mods.append(value)
        else:
            raise GameTestError(f"В сценарии {scenario} неизвестная строка стенда: {name}")
    return setup


def active_uids(info: ModInfo, library_uids: list[str], scenario: str, without_mod: bool) -> list[str]:
    uids = [TEST_MOD_UID, *library_uids]
    if not without_mod:
        uids.append(info.uid)
    if scenario != SMOKE:
        uids.append(SIM_HELPER_UID)
    return uids


def prefs_argument(prefs: str | Path, prefs_dir: str | Path) -> str:
    """The engine glues this value onto its settings folder, so the path has to be relative."""
    try:
        return ntpath.relpath(str(prefs), str(prefs_dir))
    except ValueError as error:
        raise GameTestError(f"Временная папка на другом диске, чем настройки игры: {prefs}") from error


def prefs_text(uids: list[str], profile: list[str]) -> str:
    mods = "".join(f"    ['{uid}'] = true,\n" for uid in uids)
    fields = "".join(f"            {line},\n" for line in [f"Name = '{PROFILE}'", *profile])
    return (f"profile = {{\n    current = 1,\n    profiles = {{\n        {{\n{fields}"
            f"        }},\n    }},\n}}\nversion = {{\n    major = 1,\n}}\nactive_mods = {{\n{mods}}}\n")


def init_text(bin_dir: Path, prefs_folder: Path, mounts: dict[str, Path]) -> str:
    """The stock init looks for its files from InitFileDir, which the engine set to this file's folder.

    A result must not depend on the PC, so its installed mods leave the session. They are found by
    folder, because a mod also mounts its icons and sounds outside /mods. Blueprints.lua reads
    /preferences/Game.prefs past the /prefs switch, so that mount has to change as well.
    """
    lines = [f"InitFileDir = '{bin_dir.as_posix()}'",
             "dofile(InitFileDir .. '/init.lua')",
             "local installed = string.lower(custom_vault_path .. '/mods/')",
             "for index = table.getn(path), 1, -1 do",
             "    if path[index].mountpoint == '/preferences' then",
             f"        path[index].dir = '{prefs_folder.as_posix()}'",
             "    elseif string.sub(string.lower(path[index].dir), 1, string.len(installed)) == installed then",
             "        table.remove(path, index)",
             "    end",
             "end"]
    lines += [f"table.insert(path, {{ dir = '{folder.as_posix()}', mountpoint = '{point}' }})"
              for point, folder in mounts.items()]
    return "\n".join(lines) + "\n"


def problems_in_log(log: str, scenario: str, expected: list[str]) -> list[str]:
    """The verdict comes from the log: a mod that failed to load does not stop the test mod."""
    lines = log.splitlines()
    problems = [line.strip() for line in lines if "[MODTEST] FAIL" in line or ERROR_LINE.search(line)]
    if not any("[MODTEST] PASS" in line for line in lines):
        problems.append("В логе нет строки [MODTEST] PASS")
    problems += [f"В логе нет строки: {text}" for text in expected if text not in log]
    if scenario != SMOKE:
        found = SIM_MODS.search(log)
        if not found:
            problems.append("В логе нет списка модов в sim")
        elif found.group(1).split() != [SIM_HELPER_UID]:
            problems.append(f"В sim попали лишние моды:{found.group(1)}")
    return problems


def remove_replay(log: str) -> None:
    """A match started with /map saves a replay to the documents of the user."""
    found = REPLAY.search(log)
    if not found:
        return
    replay = Path(found.group(1))
    if replay.parent.name != PROFILE:
        return
    replay.unlink(missing_ok=True)
    for folder in (replay.parent, replay.parent.parent, replay.parent.parent.parent):
        try:
            folder.rmdir()
        except OSError:
            return


def library_folder(name: str) -> Path:
    folder = LIBRARY_MODS / name
    if not folder.is_dir():
        raise GameTestError(f"Нет {folder}. Запусти: python DOCUMENTATION/tools/bootstrap.py")
    return folder


def view_windows(pid: int) -> list[int]:
    """The windows of the view take keys and the mouse, the main window of the game ignores them."""
    user32 = ctypes.windll.user32
    callback_type = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
    views = []

    def on_child(hwnd, _):
        name = ctypes.create_unicode_buffer(len(VIEW_CLASS) + 1)
        user32.GetClassNameW(hwnd, name, len(name))
        if name.value == VIEW_CLASS:
            views.append(hwnd)
        return True

    def on_window(hwnd, _):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid:
            user32.EnumChildWindows(hwnd, callback_type(on_child), 0)
        return True

    user32.EnumWindows(callback_type(on_window), 0)
    if not views:
        raise GameTestError(f"У игры нет окна класса {VIEW_CLASS}")
    return views


def press_key(views: list[int], key: str) -> None:
    """A real key message. It goes to the game and nowhere else, so the player can go on working."""
    user32 = ctypes.windll.user32
    code = ord(key.upper())
    scan = user32.MapVirtualKeyW(code, 0)
    for hwnd in views:
        user32.PostMessageW(hwnd, WM_KEYDOWN, code, 1 | scan << 16)
        user32.PostMessageW(hwnd, WM_KEYUP, code, 1 | scan << 16 | 1 << 30 | 1 << 31)


def move_mouse(views: list[int], x: int, y: int) -> None:
    """A real mouse message, the cursor of the player stays."""
    user32 = ctypes.windll.user32
    for hwnd in views:
        user32.PostMessageW(hwnd, WM_MOUSEMOVE, 0, y << 16 | x)


def run_game(args: list[str], cwd: Path, log_path: Path) -> int | None:
    """The window opens behind the others and the stand never gives it the focus, so the player keeps working.

    The game soon replaces the position of a mouse message with the cursor of the system, so the message
    is repeated until the next one.
    """
    startup = subprocess.STARTUPINFO()
    startup.dwFlags = subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = SW_SHOWNOACTIVATE
    process = subprocess.Popen(args, cwd=cwd, startupinfo=startup)
    deadline = time.monotonic() + TIMEOUT
    next_read = 0.0
    sent = 0
    views = []
    cursor = None
    try:
        while time.monotonic() < deadline:
            if process.poll() is not None:
                return process.returncode
            time.sleep(MOUSE_REPEAT_SECONDS)
            if cursor:
                move_mouse(views, *cursor)
            if time.monotonic() < next_read or not log_path.exists():
                continue
            next_read = time.monotonic() + POLL_SECONDS
            commands = INPUT.findall(log_path.read_text(encoding="utf-8", errors="replace"))
            for command in commands[sent:]:
                views = views or view_windows(process.pid)
                kind, *values = command.split()
                if kind == "MOUSE":
                    cursor = int(values[0]), int(values[1])
                else:
                    press_key(views, values[0])
            sent = len(commands)
        return None
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


def run_scenario(mod: Path, info: ModInfo, scenario: str, faf: Path, without_mod: bool) -> list[str]:
    bin_dir = faf / "bin"
    setup = read_setup(mod, scenario)
    libraries = [library_folder(name) for name in [*info.libraries, *setup.mods]]
    mounts = {f"/mods/{folder.name.lower()}": folder
              for folder in [mod, *libraries, TEST_MODS / "ModTest", TEST_MODS / "ModTestSim"]}
    mounts["/mods/modtestscenarios"] = mod.parent / "tests" / "game"
    library_uids = [read_mod_info(folder).uid for folder in libraries]
    uids = active_uids(info, library_uids, scenario, without_mod)

    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_path = LOG_DIR / f"{mod.name}-{scenario}.log"
    log_path.unlink(missing_ok=True)
    prefs_dir = Path(os.environ["LOCALAPPDATA"]) / "Gas Powered Games" / "Supreme Commander Forged Alliance"

    with tempfile.TemporaryDirectory(prefix="modtest") as temp:
        prefs = Path(temp) / "Game.prefs"
        prefs.write_text(prefs_text(uids, setup.profile), encoding="utf-8")
        init = Path(temp) / "init_modtest.lua"
        init.write_text(init_text(bin_dir, Path(temp), mounts), encoding="utf-8")
        code = run_game([str(bin_dir / "ForgedAlliance.exe"), "/init", init.as_posix(),
                         "/prefs", prefs_argument(prefs, prefs_dir), "/profile", PROFILE, "/log", str(log_path),
                         "/map", MAP, *([] if setup.ai else ["/noAi"]), "/seed", "1", "/faction", "1",
                         "/windowed", "1024", "768", "/nomovie", "/nosound", "/nomusic", "/nobugreport",
                         "/novalidate", "/modtest", scenario, NO_TARGET if without_mod else info.uid],
                        bin_dir, log_path)
        problems = []
        if prefs.with_name("Game.prefs.bad").exists():
            problems.append("Игра отвергла временные настройки")

    if code is None:
        problems.append(f"Игра не завершилась за {TIMEOUT} с")
    elif code != 0:
        problems.append(f"Код выхода игры {code}")
    if not log_path.exists():
        return [*problems, "Игра не создала лог"]
    log = log_path.read_text(encoding="utf-8", errors="replace")
    remove_replay(log)
    return [*problems, *problems_in_log(log, scenario, setup.expected)]


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mod", help="папка мода, в ней лежит mod_info.lua")
    parser.add_argument("--only", metavar="NAME", help="один сценарий из tests/game или smoke")
    parser.add_argument("--without-mod", action="store_true", help="контрольный запуск сценария без мода")
    parser.add_argument("--faf", type=Path, default=DEFAULT_FAF, help="папка данных FAF, в ней лежит bin")
    options = parser.parse_args()

    mod = Path(options.mod).resolve()
    if options.without_mod and options.only in (None, SMOKE):
        print("[FAIL] --without-mod работает только вместе с --only и сценарием")
        return 1
    if not (options.faf / "bin" / "ForgedAlliance.exe").exists():
        print(f"[FAIL] Не найдена игра в {options.faf}. Стенд работает только на компьютере с FAF")
        return 1

    results = []
    try:
        info = read_mod_info(mod)
        if not info.ui_only:
            raise GameTestError("Стенд проверяет только моды с ui_only = true")
        known = scenario_names(mod)
        if options.only and options.only not in known:
            raise GameTestError(f"Нет сценария {options.only}, есть: {', '.join(known)}")
        for scenario in [options.only] if options.only else known:
            started = time.monotonic()
            problems = run_scenario(mod, info, scenario, options.faf, options.without_mod)
            if options.without_mod:
                problems = [] if problems else ["Сценарий прошёл без мода, значит он ничего не проверяет"]
            label = f"{scenario}, контроль без мода" if options.without_mod else scenario
            print(f"[{'FAIL' if problems else 'OK'}] {mod.name}: {label}, {time.monotonic() - started:.0f} с")
            for problem in problems[:8]:
                print(f"    {problem}")
            results.append(not problems)
    except GameTestError as error:
        print(f"[FAIL] {error}")
        return 1
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
