"""Runs a UI mod in the real game: a smoke run and the scenarios from tests/game of its project.

    python DOCUMENTATION/tools/game_test.py "My_mods/project/Mod"
    python DOCUMENTATION/tools/game_test.py "My_mods/project/Mod" --only scenario --only smoke
    python DOCUMENTATION/tools/game_test.py "My_mods/project/Mod" --only scenario --without-mod
    python DOCUMENTATION/tools/game_test.py "My_mods/project/Mod" --all

Without --only or --all the game does not start: the command shows the scenarios and the cost of a
full run. One start of the game takes from 15 seconds to 2 minutes, so --all is a run for the end of
the work and needs the permission of the developer.

--without-mod is the control run of a new scenario: without the mod the scenario has to start and fail.

Needs a PC with FAF: the game has no mode without a window, so this does not work in CI. Nothing
is written to the game or to the installed mods: the init file and the settings are temporary,
the mods are mounted from their folders and the installed ones are left out of the session.

The smoke run has UI mods only, as for a player. A scenario also needs ModTestSim, because a UI
mod cannot create units, and the run fails if anything else gets into the sim.

A scenario with the line "players" is a real match of two clients on this PC over LAN, each with
its own settings and log. The auto lobby of the game starts it without sim mods, so ModTestSim
stays out. The first client hosts and runs the scenario, the second plays its army until it ends.
The verdict needs the scenario to pass on the host, and an error line in any log fails the run.

Lines at the top of a scenario file change its run:

    -- stand: ai                           the other armies of the map are played by the AI
    -- stand: profile options = { ... }    this text goes into the profile of the temporary settings
    -- stand: expect text                  the log has to contain this text
    -- stand: mod name                     this library from references/ui-libs/mods is active as well
    -- stand: players 2                    two clients play on one team, see above
"""
import argparse
import ctypes
import math
import ntpath
import os
import re
import socket
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
SCENARIO_START = "[MODTEST] start scenario="
SCENARIO_PASS = "[MODTEST] PASS"
MAP = "SCMP_009"
MAP_FILE = f"/maps/{MAP}/{MAP}_scenario.lua"
LAN_PROTOCOL = "udp"
LAN_HOST = "127.0.0.1"
LAN_TEAM = "2"
LAN_OPTIONS = "Victory:sandbox"
TIMEOUT = 120
ROUGH_RUN_SECONDS = 30

UID = re.compile(r"""^uid\s*=\s*["']([^"']+)""", re.M)
UI_ONLY = re.compile(r"^ui_only\s*=\s*true\b", re.M)
REUI_TAG = re.compile(r"^ReUI\s*=", re.M)
UMT_FLAG = re.compile(r"^__umt\s*=\s*true\b", re.M)
REPLAY = re.compile(r'Saving replay to "([^"]+)"')
SIM_MODS = re.compile(r"\[MODTEST\] sim mods:(.*)")
ERROR_LINE = re.compile(r"FAILED|: ERROR\b|CRASH in|Error importing|Error running lua script|SCR_LuaDoFileConcat"
                        r"|[Aa]ttempt to |nonexistent global|stack traceback")
DIRECTIVE = re.compile(r"^-- stand: (\w+) ?(.*?)\s*$", re.M)
INPUT = re.compile(r"\[MODTEST\] (PRESS (?:(?:Ctrl|Alt|Shift)-)*\w|MOUSE \d+ \d+)\s*$", re.M)
ATTEMPTS = 3
POLL_SECONDS = 0.2
MOUSE_REPEAT_SECONDS = 0.02
HOLD_SECONDS = 0.2
VIEW_CLASS = "wxWindowClass"
WM_KEYDOWN = 0x0100
WM_KEYUP = 0x0101
WM_MOUSEMOVE = 0x0200
SW_SHOWNOACTIVATE = 4
MOUSEEVENTF_MOVE = 0x0001
KF_ALTDOWN = 1 << 29
KEY_DOWN = 0x80
HELD_KEYS = {"Ctrl": (0x11, 0xA2), "Shift": (0x10, 0xA0)}


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
    players: int = 1


@dataclass
class Client:
    args: list[str]
    log_path: Path
    prefs: Path
    process: subprocess.Popen | None = None
    code: int | None = None
    views: list[int] = field(default_factory=list)
    cursor: tuple[int, int] | None = None
    sent: int = 0
    started: bool = False


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
        elif name == "players":
            if value != "2":
                raise GameTestError(f"В сценарии {scenario} число игроков не 2: {value}")
            setup.players = 2
        else:
            raise GameTestError(f"В сценарии {scenario} неизвестная строка стенда: {name}")
    if setup.ai and setup.players > 1:
        raise GameTestError(f"В сценарии {scenario} строка ai не работает вместе с players: в автолобби нет ИИ")
    return setup


def uses_sim_helper(scenario: str, setup: ScenarioSetup) -> bool:
    """The auto lobby starts a match with an empty list of sim mods."""
    return scenario != SMOKE and setup.players == 1


def active_uids(info: ModInfo, library_uids: list[str], sim_helper: bool, without_mod: bool) -> list[str]:
    uids = [TEST_MOD_UID, *library_uids]
    if not without_mod:
        uids.append(info.uid)
    if sim_helper:
        uids.append(SIM_HELPER_UID)
    return uids


def prefs_argument(prefs: str | Path, prefs_dir: str | Path) -> str:
    """The engine glues this value onto its settings folder, so the path has to be relative."""
    try:
        return ntpath.relpath(str(prefs), str(prefs_dir))
    except ValueError as error:
        raise GameTestError(f"Временная папка на другом диске, чем настройки игры: {prefs}") from error


def prefs_text(uids: list[str], profile: list[str], several_clients: bool = False) -> str:
    """With enable_debug_facilities the engine skips its check for a running game, which otherwise stops
    every client after the first at a dialog."""
    mods = "".join(f"    ['{uid}'] = true,\n" for uid in uids)
    fields = "".join(f"            {line},\n" for line in [f"Name = '{PROFILE}'", *profile])
    debug = "debug = {\n    enable_debug_facilities = true,\n}\n" if several_clients else ""
    return (f"profile = {{\n    current = 1,\n    profiles = {{\n        {{\n{fields}"
            f"        }},\n    }},\n}}\nversion = {{\n    major = 1,\n}}\nactive_mods = {{\n{mods}}}\n{debug}")


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


def errors_in_log(log: str) -> list[str]:
    return [line.strip() for line in log.splitlines() if "[MODTEST] FAIL" in line or ERROR_LINE.search(line)]


def problems_in_log(log: str, sim_helper: bool, expected: list[str]) -> list[str]:
    """The verdict comes from the log: a mod that failed to load does not stop the test mod."""
    problems = errors_in_log(log)
    if SCENARIO_PASS not in log:
        problems.append(f"В логе нет строки {SCENARIO_PASS}")
    problems += [f"В логе нет строки: {text}" for text in expected if text not in log]
    if sim_helper:
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


def set_held_keys(keys: list[int], down: bool) -> None:
    user32 = ctypes.windll.user32
    state = (ctypes.c_ubyte * 256)()
    user32.GetKeyboardState(state)
    for key in keys:
        state[key] = KEY_DOWN if down else 0
    user32.SetKeyboardState(state)


def press_key(views: list[int], combination: str) -> None:
    """A real key message. It goes to the game and nowhere else, so the player can go on working.

    The game reads Ctrl and Shift from the keyboard state of its thread, this thread shares that state for
    the time of the press, and Alt from a bit of the message. Only the key map sees them, IsKeyDown does not.
    """
    user32 = ctypes.windll.user32
    *modifiers, key = combination.split("-")
    code = ord(key.upper())
    flags = 1 | user32.MapVirtualKeyW(code, 0) << 16 | (KF_ALTDOWN if "Alt" in modifiers else 0)
    held = [virtual_key for name in modifiers for virtual_key in HELD_KEYS.get(name, ())]
    game_thread = user32.GetWindowThreadProcessId(views[0], None)
    own_thread = ctypes.windll.kernel32.GetCurrentThreadId()
    if held:
        user32.AttachThreadInput(own_thread, game_thread, True)
        set_held_keys(held, True)
    for hwnd in views:
        user32.PostMessageW(hwnd, WM_KEYDOWN, code, flags)
        user32.PostMessageW(hwnd, WM_KEYUP, code, flags | 1 << 30 | 1 << 31)
    if held:
        time.sleep(HOLD_SECONDS)
        set_held_keys(held, False)
        user32.AttachThreadInput(own_thread, game_thread, False)


def move_mouse(views: list[int], x: int, y: int) -> None:
    """A real mouse message, the cursor of the player stays."""
    user32 = ctypes.windll.user32
    for hwnd in views:
        user32.PostMessageW(hwnd, WM_MOUSEMOVE, 0, y << 16 | x)


def game_has_focus(pids: list[int]) -> bool:
    user32 = ctypes.windll.user32
    owner = wintypes.DWORD()
    user32.GetWindowThreadProcessId(user32.GetForegroundWindow(), ctypes.byref(owner))
    return owner.value in pids


def give_focus_back(window: int) -> None:
    """Windows lets go of the focus only for the program that made the last input, a zero move counts."""
    user32 = ctypes.windll.user32
    user32.mouse_event(MOUSEEVENTF_MOVE, 0, 0, 0, 0)
    user32.SetForegroundWindow(window)


def system_cursor() -> tuple[int, int]:
    point = wintypes.POINT()
    ctypes.windll.user32.GetCursorPos(ctypes.byref(point))
    return point.x, point.y


def send_input(client: Client) -> None:
    if not client.log_path.exists():
        return
    log = client.log_path.read_text(encoding="utf-8", errors="replace")
    client.started = SCENARIO_START in log
    commands = INPUT.findall(log)
    for command in commands[client.sent:]:
        client.views = client.views or view_windows(client.process.pid)
        kind, *values = command.split()
        if kind == "MOUSE":
            client.cursor = int(values[0]), int(values[1])
        else:
            press_key(client.views, values[0])
    client.sent = len(commands)


def run_game(clients: list[Client], cwd: Path) -> bool:
    """Waits for all clients and returns whether a person at the PC could disturb the run. A client that has
    not exited in time is killed and keeps code None. The windows open behind the others.

    The game soon replaces the position of a mouse message with the cursor of the system, so the message
    is repeated until the next one, and a moving cursor of the system can still win. The game can take
    the focus while it starts. With the focus it ignores such a message and gets the keys of the person,
    so the focus goes back at once, whichever client took it. Before a scenario starts there is nothing
    to disturb, so only the focus taken after that counts.
    """
    user32 = ctypes.windll.user32
    outer = user32.GetForegroundWindow() or user32.GetShellWindow()
    startup = subprocess.STARTUPINFO()
    startup.dwFlags = subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = SW_SHOWNOACTIVATE
    for client in clients:
        client.process = subprocess.Popen(client.args, cwd=cwd, startupinfo=startup)
    deadline = time.monotonic() + TIMEOUT
    next_read = 0.0
    disturbed = False
    person_cursor = system_cursor()
    try:
        while time.monotonic() < deadline:
            running = [client for client in clients if client.process.poll() is None]
            if not running:
                break
            time.sleep(MOUSE_REPEAT_SECONDS)
            if game_has_focus([client.process.pid for client in running]):
                disturbed = disturbed or any(client.started for client in clients)
                give_focus_back(outer)
            for client in running:
                if client.cursor:
                    move_mouse(client.views, *client.cursor)
                    disturbed = disturbed or system_cursor() != person_cursor
            person_cursor = system_cursor()
            if time.monotonic() < next_read:
                continue
            next_read = time.monotonic() + POLL_SECONDS
            for client in running:
                send_input(client)
        return disturbed
    finally:
        for client in clients:
            client.code = client.process.poll()
            if client.code is None:
                client.process.kill()
                client.process.wait()


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind((LAN_HOST, 0))
        return probe.getsockname()[1]


def match_args(index: int, port: int, setup: ScenarioSetup) -> list[str]:
    """/players turns on the auto lobby, which launches the match as soon as all clients are connected.

    The clients share a team, and the game ends a match of allies only, unless it is a sandbox.
    """
    if setup.players == 1:
        return ["/map", MAP, *([] if setup.ai else ["/noAi"]), "/seed", "1", "/faction", "1"]
    if index == 0:
        role = ["/hostgame", LAN_PROTOCOL, str(port), "Player1", PROFILE, MAP_FILE]
    else:
        role = ["/joingame", LAN_PROTOCOL, f"{LAN_HOST}:{port}", f"Player{index + 1}"]
    return [*role, "/players", str(setup.players), "/team", LAN_TEAM, "/startspot", str(index + 1), "/uef",
            "/gameoptions", LAN_OPTIONS]


def log_name(mod: Path, scenario: str, index: int) -> str:
    return f"{mod.name}-{scenario}.log" if index == 0 else f"{mod.name}-{scenario}-{index + 1}.log"


def problems_of_clients(clients: list[Client], sim_helper: bool, expected: list[str]) -> list[str]:
    """Only the first client runs the scenario, the others can only add errors."""
    problems = []
    for index, client in enumerate(clients):
        tag = f"Клиент {index + 1}: " if index else ""
        if client.code is None:
            problems.append(f"{tag}Игра не завершилась за {TIMEOUT} с")
        elif client.code != 0:
            problems.append(f"{tag}Код выхода игры {client.code}")
        if not client.log_path.exists():
            problems.append(f"{tag}Игра не создала лог")
            continue
        log = client.log_path.read_text(encoding="utf-8", errors="replace")
        remove_replay(log)
        found = errors_in_log(log) if index else problems_in_log(log, sim_helper, expected)
        problems += [f"{tag}{problem}" for problem in found]
    return problems


def control_problems(clients: list[Client], expected: list[str], disturbed: bool) -> list[str]:
    """A control run counts only if the scenario started and failed by itself, with nobody at the PC.

    A game that did not exit is no reason for doubt: an error ends the thread of the scenario, and the
    game stays until the timeout.
    """
    problems = []
    logs = []
    for index, client in enumerate(clients):
        tag = f"Клиент {index + 1}: " if index else ""
        log = client.log_path.read_text(encoding="utf-8", errors="replace") if client.log_path.exists() else ""
        remove_replay(log)
        logs.append(log)
        if client.code not in (0, None):
            problems.append(f"{tag}Код выхода игры {client.code}")
        if SCENARIO_START not in log:
            problems.append(f"{tag}Сценарий не запустился")
    if problems:
        return problems
    if SCENARIO_PASS in logs[0] and all(text in logs[0] for text in expected):
        return ["Сценарий прошёл без мода, значит он ничего не проверяет"]
    return ["Сценарий упал, но мог упасть от чужого ввода"] if disturbed else []


def run_scenario(mod: Path, info: ModInfo, scenario: str, faf: Path, without_mod: bool) -> tuple[list[str], bool]:
    bin_dir = faf / "bin"
    setup = read_setup(mod, scenario)
    libraries = [library_folder(name) for name in [*info.libraries, *setup.mods]]
    mounts = {f"/mods/{folder.name.lower()}": folder
              for folder in [mod, *libraries, TEST_MODS / "ModTest", TEST_MODS / "ModTestSim"]}
    mounts["/mods/modtestscenarios"] = mod.parent / "tests" / "game"
    library_uids = [read_mod_info(folder).uid for folder in libraries]
    sim_helper = uses_sim_helper(scenario, setup)
    uids = active_uids(info, library_uids, sim_helper, without_mod)

    LOG_DIR.mkdir(parents=True, exist_ok=True)
    prefs_dir = Path(os.environ["LOCALAPPDATA"]) / "Gas Powered Games" / "Supreme Commander Forged Alliance"
    port = free_port()

    with tempfile.TemporaryDirectory(prefix="modtest") as temp:
        clients = []
        for index in range(setup.players):
            folder = Path(temp) / str(index + 1)
            folder.mkdir()
            prefs = folder / "Game.prefs"
            prefs.write_text(prefs_text(uids, setup.profile, setup.players > 1), encoding="utf-8")
            init = folder / "init_modtest.lua"
            init.write_text(init_text(bin_dir, folder, mounts), encoding="utf-8")
            log_path = LOG_DIR / log_name(mod, scenario, index)
            log_path.unlink(missing_ok=True)
            clients.append(Client([str(bin_dir / "ForgedAlliance.exe"), "/init", init.as_posix(),
                                   "/prefs", prefs_argument(prefs, prefs_dir), "/profile", PROFILE,
                                   "/log", str(log_path), *match_args(index, port, setup),
                                   "/windowed", "1024", "768", "/nomovie", "/nosound", "/nomusic", "/nobugreport",
                                   "/novalidate", "/modtest", scenario, NO_TARGET if without_mod else info.uid],
                                  log_path, prefs))
        disturbed = run_game(clients, bin_dir)
        problems = []
        if any(client.prefs.with_name("Game.prefs.bad").exists() for client in clients):
            problems.append("Игра отвергла временные настройки")

    if without_mod:
        return [*problems, *control_problems(clients, setup.expected, disturbed)], disturbed
    return [*problems, *problems_of_clients(clients, sim_helper, setup.expected)], disturbed


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mod", help="папка мода, в ней лежит mod_info.lua")
    choice = parser.add_mutually_exclusive_group()
    choice.add_argument("--only", metavar="NAME", action="append",
                        help="сценарий из tests/game или smoke, ключ можно повторять")
    choice.add_argument("--all", action="store_true", help="весь мод, только с разрешения разработчика")
    parser.add_argument("--without-mod", action="store_true", help="контрольный запуск сценария без мода")
    parser.add_argument("--faf", type=Path, default=DEFAULT_FAF, help="папка данных FAF, в ней лежит bin")
    options = parser.parse_args()

    mod = Path(options.mod).resolve()
    if options.without_mod and (not options.only or SMOKE in options.only):
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
        if not options.only and not options.all:
            minutes = math.ceil(len(known) * ROUGH_RUN_SECONDS / 60)
            print(f"[FAIL] Игра не запускалась. Сценарии: {', '.join(known)}")
            print("    Для текущей работы выбери нужные: --only <сценарий>, ключ можно повторять")
            print(f"    Весь мод, запусков: {len(known)}, около {minutes} мин: --all, "
                  "только с разрешения разработчика")
            return 1
        unknown = [name for name in options.only or [] if name not in known]
        if unknown:
            raise GameTestError(f"Нет сценария {', '.join(unknown)}, есть: {', '.join(known)}")
        for scenario in options.only or known:
            started = time.monotonic()
            for attempt in range(1, ATTEMPTS + 1):
                problems, disturbed = run_scenario(mod, info, scenario, options.faf, options.without_mod)
                if not problems or not disturbed:
                    break
                if attempt == ATTEMPTS:
                    problems.insert(0, "За компьютером работал человек, результат может быть ложным")
                    break
                print(f"[..] {scenario}: за компьютером работал человек, его ввод мог попасть в игру, повторяю")
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
