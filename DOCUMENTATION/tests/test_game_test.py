import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "DOCUMENTATION" / "tools"
sys.path.insert(0, str(TOOLS))

import bootstrap
import check
import game_test
import validate_mod

TARGET = "target-uid"
PASS = "info: [MODTEST] PASS\n"
SIM_MODS = f"info: [MODTEST] sim mods: {game_test.SIM_HELPER_UID}\n"


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class TempCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)


class ProblemsInLogTests(unittest.TestCase):
    def problems(self, log, sim_helper=False, expected=()):
        return game_test.problems_in_log(log, sim_helper, list(expected))

    def test_clean_smoke_has_no_problems(self):
        self.assertEqual(self.problems(PASS), [])

    def test_log_without_pass_is_a_problem(self):
        self.assertEqual(len(self.problems("info: something\n")), 1)

    def test_failed_check_is_quoted(self):
        problems = self.problems("info: [MODTEST] FAIL engineer got paused\n")
        self.assertTrue(any("engineer got paused" in problem for problem in problems))

    def test_mod_that_failed_to_load_cannot_hide_behind_pass(self):
        log = "info: ReclaimPause: MODULE FAILED TO LOAD - mod stays disabled\n" + PASS
        self.assertEqual(len(self.problems(log)), 1)

    def test_error_in_a_thread_cannot_hide_behind_pass(self):
        log = "warning: Error running lua script: main.lua(10): x\n" + PASS
        self.assertEqual(len(self.problems(log)), 1)

    def test_guard_of_a_mod_cannot_hide_behind_pass(self):
        self.assertEqual(len(self.problems("info: ReclaimPause: IsBuilding FAILED: x\n" + PASS)), 1)
        self.assertEqual(len(self.problems("info: OverflowSync: ERROR (1/3): x\n" + PASS)), 1)

    def test_expected_line_has_to_be_in_the_log(self):
        self.assertEqual(self.problems("info: mod: installed\n" + PASS, expected=["mod: installed"]), [])
        self.assertEqual(len(self.problems(PASS, expected=["mod: installed"])), 1)

    def test_scenario_needs_the_list_of_sim_mods(self):
        self.assertEqual(len(self.problems(PASS, True)), 1)

    def test_scenario_with_only_the_sim_helper_in_sim_passes(self):
        self.assertEqual(self.problems(SIM_MODS + PASS, True), [])

    def test_target_inside_sim_is_a_problem(self):
        log = f"info: [MODTEST] sim mods: {game_test.SIM_HELPER_UID} {TARGET}\n" + PASS
        self.assertEqual(len(self.problems(log, True)), 1)

    def test_another_sim_mod_is_a_problem(self):
        log = f"info: [MODTEST] sim mods: {game_test.SIM_HELPER_UID} stranger\n" + PASS
        self.assertEqual(len(self.problems(log, True)), 1)


class SeveralClientsTests(TempCase):
    SETUP = game_test.ScenarioSetup(players=2)

    def clients(self, *logs, codes=None):
        clients = []
        for index, log in enumerate(logs):
            path = self.root / f"{index}.log"
            if log is not None:
                path.write_text(log, encoding="utf-8")
            code = codes[index] if codes else 0
            clients.append(game_test.Client([], path, self.root / "Game.prefs", code=code))
        return clients

    def problems(self, *logs, codes=None):
        return game_test.problems_of_clients(self.clients(*logs, codes=codes), False, [])

    def test_host_pass_and_a_clean_client_pass_the_run(self):
        self.assertEqual(self.problems(PASS, "info: played\n"), [])

    def test_host_has_to_pass(self):
        self.assertEqual(len(self.problems("info: played\n", PASS)), 1)

    def test_error_in_the_log_of_any_client_fails_the_run(self):
        self.assertEqual(len(self.problems("warning: Error running lua script: x\n" + PASS, PASS)), 1)
        problems = self.problems(PASS, "warning: Error running lua script: x\n")
        self.assertEqual(len(problems), 1)
        self.assertTrue(problems[0].startswith("Клиент 2"))

    def test_failed_check_on_a_client_fails_the_run(self):
        self.assertEqual(len(self.problems(PASS, "info: [MODTEST] FAIL x\n" + PASS)), 1)

    def test_client_without_a_log_fails_the_run(self):
        self.assertEqual(len(self.problems(PASS, None)), 1)

    def test_client_that_did_not_exit_fails_the_run(self):
        self.assertEqual(len(self.problems(PASS, PASS, codes=[0, None])), 1)

    def test_client_with_a_bad_exit_code_fails_the_run(self):
        self.assertEqual(len(self.problems(PASS, PASS, codes=[0, 3])), 1)

    def test_expected_lines_are_read_from_the_host_only(self):
        clients = self.clients("info: only here\n" + PASS, PASS)
        self.assertEqual(game_test.problems_of_clients(clients, False, ["only here"]), [])
        clients = self.clients(PASS, "info: only here\n")
        self.assertEqual(len(game_test.problems_of_clients(clients, False, ["only here"])), 1)


class ControlRunTests(SeveralClientsTests):
    START = "info: [MODTEST] start scenario=a\n"

    def control(self, *logs, codes=None, expected=(), disturbed=False):
        return game_test.control_problems(self.clients(*logs, codes=codes), list(expected), disturbed)

    def test_failed_check_counts(self):
        self.assertEqual(self.control(self.START + "info: [MODTEST] FAIL x\ninfo: [MODTEST] END\n"), [])

    def test_error_that_left_the_game_until_the_timeout_counts(self):
        self.assertEqual(self.control(self.START + "warning: attempt to index nil\n", codes=[None]), [])

    def test_missing_expected_line_counts(self):
        self.assertEqual(self.control(self.START + PASS, expected=["from the mod"]), [])

    def test_scenario_that_passed_is_a_problem(self):
        self.assertIn("ничего не проверяет", self.control(self.START + PASS)[0])

    def test_error_line_does_not_turn_a_passed_scenario_into_a_failure(self):
        self.assertIn("ничего не проверяет", self.control(self.START + "info: ERROR: other\n" + PASS)[0])

    def test_crash_is_a_problem(self):
        self.assertEqual(len(self.control(self.START, codes=[3])), 1)

    def test_game_that_did_not_reach_the_scenario_is_a_problem(self):
        self.assertEqual(len(self.control("info: loading\n", codes=[None])), 1)

    def test_game_without_a_log_is_a_problem(self):
        self.assertEqual(len(self.control(None)), 1)

    def test_every_client_has_to_reach_the_scenario(self):
        problems = self.control(self.START, "info: loading\n")
        self.assertEqual(len(problems), 1)
        self.assertTrue(problems[0].startswith("Клиент 2"))

    def test_failure_with_a_person_at_the_pc_is_a_problem(self):
        self.assertEqual(len(self.control(self.START + "info: [MODTEST] FAIL x\n", disturbed=True)), 1)

    def test_first_client_hosts_the_map_of_the_stand(self):
        args = game_test.match_args(0, 15000, self.SETUP)
        self.assertEqual(args[:6], ["/hostgame", "udp", "15000", "Player1", game_test.PROFILE, game_test.MAP_FILE])

    def test_other_clients_join_the_port_of_the_host(self):
        args = game_test.match_args(1, 15000, self.SETUP)
        self.assertEqual(args[:4], ["/joingame", "udp", "127.0.0.1:15000", "Player2"])

    def test_clients_share_a_team_and_take_their_own_start_spots(self):
        host, client = (game_test.match_args(index, 15000, self.SETUP) for index in range(2))
        for args in (host, client):
            self.assertEqual(args[args.index("/players") + 1], "2")
            self.assertEqual(args[args.index("/team") + 1], "2")
        self.assertEqual(host[host.index("/startspot") + 1], "1")
        self.assertEqual(client[client.index("/startspot") + 1], "2")

    def test_match_of_one_team_is_a_sandbox_or_it_ends_at_once(self):
        args = game_test.match_args(0, 15000, self.SETUP)
        self.assertEqual(args[args.index("/gameoptions") + 1], "Victory:sandbox")

    def test_single_match_stays_on_the_map_switch(self):
        self.assertEqual(game_test.match_args(0, 15000, game_test.ScenarioSetup())[:3], ["/map", game_test.MAP, "/noAi"])
        self.assertNotIn("/noAi", game_test.match_args(0, 15000, game_test.ScenarioSetup(ai=True)))

    def test_every_client_has_its_own_log(self):
        names = {game_test.log_name(Path("Overflow"), "scenario", index) for index in range(2)}
        self.assertEqual(names, {"Overflow-scenario.log", "Overflow-scenario-2.log"})

    def test_only_several_clients_skip_the_check_for_a_running_game(self):
        self.assertIn("enable_debug_facilities = true", game_test.prefs_text([], [], True))
        self.assertNotIn("enable_debug_facilities", game_test.prefs_text([], []))

    def test_free_port_is_a_port(self):
        self.assertGreater(game_test.free_port(), 0)


@unittest.skipUnless(sys.platform == "win32", "the windows API of the stand")
class FocusTests(TempCase):
    """Real processes stand in for the game: run_game does not care what it starts."""

    def setUp(self):
        super().setUp()
        for name in ("lock_focus", "unlock_focus"):
            patcher = mock.patch.object(game_test, name)
            setattr(self, name, patcher.start())
            self.addCleanup(patcher.stop)

    def clients(self, *seconds):
        return [game_test.Client([sys.executable, "-c", f"import time; time.sleep({value})"],
                                 self.root / f"{index}.log", self.root / "Game.prefs")
                for index, value in enumerate(seconds)]

    def test_focus_goes_back_from_every_client(self):
        clients = self.clients(0, 1)
        write(clients[1].log_path, f"info: {game_test.SCENARIO_START}a\n")
        seen = []

        def has_focus(pids):
            seen.append(sorted(pids))
            return pids[-1] == clients[1].process.pid and len(seen) == 3

        with mock.patch.object(game_test, "game_has_focus", has_focus), \
                mock.patch.object(game_test, "give_focus_back") as give_back:
            disturbed = game_test.run_game(clients, self.root)
        self.assertTrue(disturbed)
        self.assertEqual(give_back.call_count, 1)
        self.assertIn(clients[1].process.pid, seen[0])

    def test_focus_taken_before_the_scenario_goes_back_and_disturbs_nothing(self):
        clients = self.clients(1)
        with mock.patch.object(game_test, "game_has_focus", return_value=True), \
                mock.patch.object(game_test, "give_focus_back") as give_back:
            disturbed = game_test.run_game(clients, self.root)
        self.assertFalse(disturbed)
        self.assertGreater(give_back.call_count, 0)

    def test_focus_is_locked_before_the_game_starts_and_unlocked_after_it(self):
        clients = self.clients(0)
        started = []
        self.lock_focus.side_effect = lambda: started.append(clients[0].process)
        with mock.patch.object(game_test, "game_has_focus", return_value=False):
            game_test.run_game(clients, self.root)
        self.assertEqual(started, [None])
        self.unlock_focus.assert_called_once_with()

    def test_focus_is_unlocked_when_the_run_fails(self):
        clients = self.clients(0)
        with mock.patch.object(game_test, "game_has_focus", side_effect=RuntimeError), \
                self.assertRaises(RuntimeError):
            game_test.run_game(clients, self.root)
        self.unlock_focus.assert_called_once_with()

    def test_run_goes_on_until_the_last_client_exits(self):
        clients = self.clients(0, 1)
        with mock.patch.object(game_test, "game_has_focus", return_value=False):
            self.assertFalse(game_test.run_game(clients, self.root))
        self.assertEqual([client.code for client in clients], [0, 0])

    def test_client_that_does_not_exit_is_killed_and_keeps_no_code(self):
        clients = self.clients(0, 60)
        with mock.patch.object(game_test, "game_has_focus", return_value=False), \
                mock.patch.object(game_test, "TIMEOUT", 1):
            game_test.run_game(clients, self.root)
        self.assertEqual(clients[0].code, 0)
        self.assertIsNone(clients[1].code)
        self.assertIsNotNone(clients[1].process.returncode)

    def test_lines_of_a_log_reach_only_the_game_of_that_client(self):
        clients = self.clients(0, 0)
        write(clients[1].log_path, "info: [MODTEST] MOUSE 300 200\n")
        clients[1].process = mock.Mock(pid=1)
        with mock.patch.object(game_test, "view_windows", return_value=[7]):
            game_test.send_input(clients[0])
            game_test.send_input(clients[1])
        self.assertIsNone(clients[0].cursor)
        self.assertEqual(clients[1].cursor, (300, 200))


class ModInfoTests(TempCase):
    def info(self, text):
        write(self.root / "Mod" / "mod_info.lua", text)
        return game_test.read_mod_info(self.root / "Mod")

    def test_uid_is_read(self):
        info = self.info('uid = "abc"\nui_only = true\n')
        self.assertEqual(info.uid, "abc")

    def test_ui_flag_is_read(self):
        self.assertTrue(self.info('uid = "a"\nui_only = true\n').ui_only)
        self.assertFalse(self.info('uid = "a"\nui_only = false\n').ui_only)

    def test_commented_flag_does_not_count(self):
        self.assertFalse(self.info('uid = "a"\n-- ui_only = true\n').ui_only)

    def test_libraries_follow_the_mod_info_marks(self):
        self.assertEqual(self.info('uid = "a"\n').libraries, [])
        self.assertEqual(self.info('uid = "a"\n__umt = true\n').libraries, ["UMT"])
        self.assertEqual(self.info('uid = "a"\nReUI = "mod=1.0.0"\n').libraries, ["ReUI"])

    def test_missing_uid_stops_the_run(self):
        with self.assertRaises(game_test.GameTestError):
            self.info('name = "a"\n')


class PrefsTests(unittest.TestCase):
    PREFS_DIR = r"C:\Users\a\AppData\Local\Gas Powered Games\Supreme Commander Forged Alliance"

    def test_path_is_relative_to_the_prefs_folder(self):
        result = game_test.prefs_argument(r"C:\Users\a\AppData\Local\Temp\run\Game.prefs", self.PREFS_DIR)
        self.assertEqual(result, r"..\..\Temp\run\Game.prefs")

    def test_another_drive_stops_the_run(self):
        with self.assertRaises(game_test.GameTestError):
            game_test.prefs_argument(r"D:\run\Game.prefs", self.PREFS_DIR)

    def test_prefs_activate_exactly_the_given_mods(self):
        text = game_test.prefs_text(["one", "two"], [])
        self.assertIn("['one'] = true", text)
        self.assertIn("['two'] = true", text)
        self.assertEqual(text.count("= true"), 2)

    def test_the_window_position_goes_into_the_prefs(self):
        text = game_test.prefs_text([], [], window=(-1920, 8))
        self.assertIn("maximized = false", text)
        self.assertIn("x = -1920", text)
        self.assertIn("y = 8", text)

    def test_without_a_position_the_game_places_the_window_itself(self):
        self.assertNotIn("Windows", game_test.prefs_text([], []))

    def test_scenario_text_goes_into_the_profile(self):
        text = game_test.prefs_text([], ["options = { ui_scale = 1.5 }"])
        self.assertLess(text.index("Name ="), text.index("options = { ui_scale = 1.5 },"))
        self.assertLess(text.index("options = { ui_scale = 1.5 },"), text.index("version ="))


class InitTests(unittest.TestCase):
    def text(self, mounts=None):
        return game_test.init_text(Path("C:/FAF/bin"), Path("C:/temp/run"), mounts or {})

    def test_folder_is_restored_before_the_stock_init_runs(self):
        text = self.text()
        self.assertLess(text.index("InitFileDir = 'C:/FAF/bin'"), text.index("dofile(InitFileDir .. '/init.lua')"))

    def test_mods_are_mounted_after_the_stock_init(self):
        text = self.text({"/mods/x": Path("U:/repo/X")})
        self.assertLess(text.index("dofile"), text.index("table.insert(path"))
        self.assertIn("{ dir = 'U:/repo/X', mountpoint = '/mods/x' }", text)

    def test_installed_mods_are_removed_before_the_tested_ones_are_added(self):
        text = self.text({"/mods/x": Path("U:/repo/X")})
        self.assertLess(text.index("table.remove(path"), text.index("table.insert(path"))

    def test_all_content_of_the_installed_mods_is_found_by_its_folder(self):
        self.assertIn("custom_vault_path .. '/mods/'", self.text())
        self.assertIn("path[index].dir", self.text())

    def test_game_prefs_read_past_the_engine_come_from_the_temporary_folder(self):
        """Blueprints.lua reads /preferences/Game.prefs itself, /prefs does not change that."""
        text = self.text()
        self.assertIn("path[index].mountpoint == '/preferences'", text)
        self.assertIn("path[index].dir = 'C:/temp/run'", text)


class ActiveModsTests(unittest.TestCase):
    INFO = game_test.ModInfo(uid=TARGET, ui_only=True, libraries=["UMT"])

    def test_without_the_helper_there_is_no_sim_mod(self):
        uids = game_test.active_uids(self.INFO, ["lib"], False, without_mod=False)
        self.assertEqual(sorted(uids), sorted([TARGET, "lib", game_test.TEST_MOD_UID]))

    def test_helper_is_added_on_request(self):
        uids = game_test.active_uids(self.INFO, [], True, without_mod=False)
        self.assertIn(game_test.SIM_HELPER_UID, uids)

    def test_control_run_leaves_the_target_out(self):
        uids = game_test.active_uids(self.INFO, ["lib"], True, without_mod=True)
        self.assertNotIn(TARGET, uids)
        self.assertIn("lib", uids)

    def test_only_a_scenario_of_one_client_uses_the_helper(self):
        self.assertFalse(game_test.uses_sim_helper(game_test.SMOKE, game_test.ScenarioSetup()))
        self.assertTrue(game_test.uses_sim_helper("pause", game_test.ScenarioSetup()))
        self.assertFalse(game_test.uses_sim_helper("pause", game_test.ScenarioSetup(players=2)))


class InputTests(unittest.TestCase):
    def test_lines_of_a_scenario_give_the_commands_in_their_order(self):
        log = "info: [MODTEST] MOUSE 300 200\ninfo: [MODTEST] PRESS K\ninfo: [MODTEST] PRESS Ctrl-Alt-R\n"
        self.assertEqual(game_test.INPUT.findall(log), ["MOUSE 300 200", "PRESS K", "PRESS Ctrl-Alt-R"])

    def test_other_lines_give_no_command(self):
        log = "info: [MODTEST] PRESS first\ninfo: PRESS K\ninfo: [MODTEST] MOUSE x y\ninfo: [MODTEST] PRESS Win-K\n"
        self.assertEqual(game_test.INPUT.findall(log), [])


class SetupTests(TempCase):
    def setup_of(self, text):
        write(self.root / "project" / "tests" / "game" / "scenario.lua", text)
        return game_test.read_setup(self.root / "project" / "Mod", "scenario")

    def test_plain_scenario_keeps_the_defaults(self):
        setup = self.setup_of("function Run()\nend\n")
        self.assertFalse(setup.ai)
        self.assertEqual(setup.profile, [])
        self.assertEqual(setup.expected, [])
        self.assertEqual(setup.mods, [])
        self.assertEqual(setup.players, 1)
        self.assertFalse(setup.mouse)

    def test_scenario_that_moves_the_mouse_is_marked(self):
        self.assertTrue(self.setup_of('Test.MoveMouseTo(unit:GetPosition())\n').mouse)

    def test_number_of_players_is_read(self):
        self.assertEqual(self.setup_of("-- stand: players 2\n").players, 2)

    def test_wrong_number_of_players_stops_the_run(self):
        for value in ("1", "3", "two", ""):
            with self.subTest(value), self.assertRaises(game_test.GameTestError):
                self.setup_of(f"-- stand: players {value}\n")

    def test_auto_lobby_has_no_ai_to_ask_for(self):
        with self.assertRaises(game_test.GameTestError):
            self.setup_of("-- stand: ai\n-- stand: players 2\n")

    def test_lines_of_the_stand_are_read(self):
        setup = self.setup_of("-- stand: ai\n-- stand: profile options = { a = 1 }\n-- stand: expect mod: ready\n"
                              "-- stand: mod ASE\n")
        self.assertTrue(setup.ai)
        self.assertEqual(setup.profile, ["options = { a = 1 }"])
        self.assertEqual(setup.expected, ["mod: ready"])
        self.assertEqual(setup.mods, ["ASE"])

    def test_unknown_line_stops_the_run(self):
        with self.assertRaises(game_test.GameTestError):
            self.setup_of("-- stand: aii\n")

    def test_smoke_has_no_file_to_read(self):
        self.assertFalse(game_test.read_setup(self.root / "project" / "Mod", game_test.SMOKE).ai)


class ScenariosTests(TempCase):
    def test_smoke_goes_first_and_scenarios_follow_by_name(self):
        mod = self.root / "project" / "Mod"
        write(self.root / "project" / "tests" / "game" / "b.lua", "")
        write(self.root / "project" / "tests" / "game" / "a.lua", "")
        self.assertEqual(game_test.scenario_names(mod), ["smoke", "a", "b"])

    def test_mod_without_scenarios_gets_the_smoke(self):
        self.assertEqual(game_test.scenario_names(self.root / "project" / "Mod"), ["smoke"])


class ChoiceTests(TempCase):
    """What a command line runs: only the launch of the game is replaced."""

    def setUp(self):
        super().setUp()
        self.mod = self.root / "project" / "Mod"
        write(self.mod / "mod_info.lua", 'uid = "target"\nui_only = true\n')
        write(self.root / "project" / "tests" / "game" / "a.lua", "")
        write(self.root / "project" / "tests" / "game" / "b.lua", "")
        write(self.root / "faf" / "bin" / "ForgedAlliance.exe", "")

    def run_stand(self, *args, outcomes=()):
        ran = []
        outcomes = list(outcomes)

        def run_scenario(_mod, _info, scenario, _faf, _without_mod):
            ran.append(scenario)
            return outcomes.pop(0) if outcomes else ([], False)

        stream = io.TextIOWrapper(io.BytesIO(), encoding="utf-8")
        argv = ["game_test.py", str(self.mod), "--faf", str(self.root / "faf"), *args]
        with mock.patch.object(sys, "argv", argv), mock.patch.object(game_test, "run_scenario", run_scenario), \
                contextlib.redirect_stdout(stream):
            code = game_test.main()
        stream.flush()
        return code, ran, stream.buffer.getvalue().decode("utf-8")

    def test_without_a_choice_the_game_does_not_start(self):
        code, ran, _ = self.run_stand()
        self.assertEqual(code, 1)
        self.assertEqual(ran, [])

    def test_without_a_choice_the_scenarios_and_the_cost_are_shown(self):
        _, _, output = self.run_stand()
        self.assertIn("smoke, a, b", output)
        self.assertIn("запусков: 3, около 2 мин", output)

    def test_only_runs_the_named_scenario(self):
        code, ran, _ = self.run_stand("--only", "b")
        self.assertEqual((code, ran), (0, ["b"]))

    def test_only_can_be_repeated(self):
        code, ran, _ = self.run_stand("--only", "b", "--only", "smoke")
        self.assertEqual((code, ran), (0, ["b", "smoke"]))

    def test_all_runs_the_smoke_and_every_scenario(self):
        code, ran, _ = self.run_stand("--all")
        self.assertEqual((code, ran), (0, ["smoke", "a", "b"]))

    def test_every_result_shows_how_many_runs_are_done_and_left(self):
        _, _, output = self.run_stand("--all", outcomes=[([], False), (["failed"], False)])
        lines = [line for line in output.splitlines() if line.startswith("[")]
        self.assertIn("готово 1 из 3, осталось 2", lines[0])
        self.assertIn("готово 2 из 3, осталось 1", lines[1])
        self.assertTrue(lines[1].startswith("[FAIL]"))
        self.assertIn("готово 3 из 3, осталось 0", lines[2])

    def test_unknown_scenario_stops_before_the_game_starts(self):
        code, ran, output = self.run_stand("--only", "a", "--only", "gone")
        self.assertEqual((code, ran), (1, []))
        self.assertIn("gone", output)

    def test_all_and_only_cannot_go_together(self):
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            self.run_stand("--all", "--only", "a")

    def test_control_run_takes_several_scenarios(self):
        code, ran, _ = self.run_stand("--only", "a", "--only", "b", "--without-mod")
        self.assertEqual((code, ran), (0, ["a", "b"]))

    def test_control_run_fails_on_its_own_problems(self):
        code, ran, output = self.run_stand("--only", "a", "--without-mod", outcomes=[(["passed"], False)])
        self.assertEqual((code, ran), (1, ["a"]))
        self.assertIn("passed", output)

    def test_control_run_disturbed_by_a_person_is_repeated(self):
        code, ran, _ = self.run_stand("--only", "a", "--without-mod", outcomes=[(["person"], True)])
        self.assertEqual((code, ran), (0, ["a", "a"]))

    def test_control_run_always_disturbed_says_so(self):
        outcomes = [(["person"], True)] * game_test.ATTEMPTS
        code, ran, output = self.run_stand("--only", "a", "--without-mod", outcomes=outcomes)
        self.assertEqual((code, len(ran)), (1, game_test.ATTEMPTS))
        self.assertIn("результат может быть ложным", output)

    def test_control_run_is_refused_for_the_whole_mod(self):
        code, ran, _ = self.run_stand("--all", "--without-mod")
        self.assertEqual((code, ran), (1, []))

    def test_control_run_is_refused_for_the_smoke(self):
        code, ran, _ = self.run_stand("--only", "a", "--only", "smoke", "--without-mod")
        self.assertEqual((code, ran), (1, []))


class ReplayTests(TempCase):
    def log_for(self, path):
        return f'info: Saving replay to "{path}"\n'

    def test_replay_and_folders_created_by_the_run_are_removed(self):
        base = self.root / "My Games" / "Game"
        replay = base / "replays" / game_test.PROFILE / "LastGame.SCFAReplay"
        write(replay, "x")
        game_test.remove_replay(self.log_for(replay))
        self.assertFalse(base.exists())

    def test_folder_with_other_files_stays(self):
        base = self.root / "My Games" / "Game"
        replay = base / "replays" / game_test.PROFILE / "LastGame.SCFAReplay"
        write(replay, "x")
        write(base / "replays" / "player" / "match.SCFAReplay", "x")
        game_test.remove_replay(self.log_for(replay))
        self.assertFalse(replay.exists())
        self.assertTrue((base / "replays" / "player" / "match.SCFAReplay").exists())

    def test_replay_of_another_profile_is_not_touched(self):
        replay = self.root / "replays" / "player" / "LastGame.SCFAReplay"
        write(replay, "x")
        game_test.remove_replay(self.log_for(replay))
        self.assertTrue(replay.exists())


class TestModsTests(unittest.TestCase):
    """The test mods are not in My_mods, so check.py does not look at them."""

    def test_only_the_sim_helper_has_a_sim_part(self):
        self.assertTrue(game_test.read_mod_info(game_test.TEST_MODS / "ModTest").ui_only)
        self.assertFalse(game_test.read_mod_info(game_test.TEST_MODS / "ModTestSim").ui_only)

    def test_uids_match_the_mod_info_files(self):
        self.assertEqual(game_test.read_mod_info(game_test.TEST_MODS / "ModTest").uid, game_test.TEST_MOD_UID)
        self.assertEqual(game_test.read_mod_info(game_test.TEST_MODS / "ModTestSim").uid, game_test.SIM_HELPER_UID)

    def test_lua_files_follow_the_mod_rules(self):
        files = sorted(game_test.TEST_MODS.rglob("*.lua")) + sorted(ROOT.glob("My_mods/**/tests/game/**/*.lua"))
        self.assertTrue(files)
        for path in files:
            self.assertEqual(validate_mod.check_file(path), [], path.name)

    @unittest.skipUnless(bootstrap.luac_path().exists(), "FAF Lua is not built")
    def test_lua_files_compile(self):
        for folder in [game_test.TEST_MODS, *ROOT.glob("My_mods/**/tests/game")]:
            self.assertEqual(check.check_luac(folder), [])


if __name__ == "__main__":
    unittest.main()
