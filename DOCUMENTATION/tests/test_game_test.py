import sys
import tempfile
import unittest
from pathlib import Path

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
    def problems(self, log, scenario="smoke", expected=()):
        return game_test.problems_in_log(log, scenario, list(expected))

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
        self.assertEqual(len(self.problems(PASS, "pause")), 1)

    def test_scenario_with_only_the_sim_helper_in_sim_passes(self):
        self.assertEqual(self.problems(SIM_MODS + PASS, "pause"), [])

    def test_target_inside_sim_is_a_problem(self):
        log = f"info: [MODTEST] sim mods: {game_test.SIM_HELPER_UID} {TARGET}\n" + PASS
        self.assertEqual(len(self.problems(log, "pause")), 1)

    def test_another_sim_mod_is_a_problem(self):
        log = f"info: [MODTEST] sim mods: {game_test.SIM_HELPER_UID} stranger\n" + PASS
        self.assertEqual(len(self.problems(log, "pause")), 1)


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

    def test_smoke_runs_without_any_sim_mod(self):
        uids = game_test.active_uids(self.INFO, ["lib"], "smoke", without_mod=False)
        self.assertEqual(sorted(uids), sorted([TARGET, "lib", game_test.TEST_MOD_UID]))

    def test_scenario_adds_the_sim_helper(self):
        uids = game_test.active_uids(self.INFO, [], "pause", without_mod=False)
        self.assertIn(game_test.SIM_HELPER_UID, uids)

    def test_control_run_leaves_the_target_out(self):
        uids = game_test.active_uids(self.INFO, ["lib"], "pause", without_mod=True)
        self.assertNotIn(TARGET, uids)
        self.assertIn("lib", uids)


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
