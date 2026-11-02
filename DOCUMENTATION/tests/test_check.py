import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))

import bootstrap
import check
import validate_mod

MOD_INFO = 'name = "x"\nversion = 1\nuid = "x"\ndescription = ""\nui_only = true\n'


def git(cwd, *args):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class ValidateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def problems(self, code, name="modules/main.lua"):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(code if isinstance(code, bytes) else code.encode("utf-8"))
        return validate_mod.check_file(path)

    def test_wait_inside_pcall_is_reported_with_its_line(self):
        found = self.problems("pcall(function()\n    WaitSeconds(1)\nend)\n")
        self.assertEqual(len(found), 1)
        self.assertIn("2", found[0])

    def test_wait_after_finished_pcall_is_allowed(self):
        code = "local ok = pcall(function() return 1 end)\nWaitSeconds(1)\n"
        self.assertEqual(self.problems(code), [])

    def test_wait_after_pcall_of_named_function_is_allowed(self):
        self.assertEqual(self.problems("pcall(Start, 1)\nWaitSeconds(1)\n"), [])

    def test_wait_in_a_comment_is_ignored(self):
        code = "pcall(function()\n    -- WaitSeconds(1)\n    return 1\nend)\n"
        self.assertEqual(self.problems(code), [])

    def test_dot_in_prefs_key_is_reported(self):
        self.assertEqual(len(self.problems("Prefs.SetToCurrentProfile('my.mod', 1)\n")), 1)

    def test_dot_in_prefs_key_from_variable_is_reported(self):
        code = "local KEY = 'my.mod'\nPrefs.SetToCurrentProfile(KEY, 1)\n"
        self.assertEqual(len(self.problems(code)), 1)

    def test_dotted_read_is_allowed(self):
        self.assertEqual(self.problems("Prefs.GetFromCurrentProfile('options.gui')\n"), [])

    def test_wait_ticks_inside_pcall_is_reported(self):
        self.assertEqual(len(self.problems("pcall(function()\n    WaitTicks(1)\nend)\n")), 1)

    def test_wait_after_one_line_if_inside_pcall_is_reported(self):
        code = "pcall(function()\n    if a then b() end\n    WaitSeconds(1)\nend)\n"
        self.assertEqual(len(self.problems(code)), 1)

    def test_wait_in_a_thread_started_inside_pcall_is_allowed(self):
        code = "pcall(function()\n    ForkThread(function()\n        WaitSeconds(1)\n    end)\nend)\n"
        self.assertEqual(self.problems(code), [])

    def test_table_return_inside_a_function_is_allowed(self):
        self.assertEqual(self.problems("function F()\n    return { 1 }\nend\n"), [])

    def test_plain_prefs_key_is_allowed(self):
        self.assertEqual(self.problems("Prefs.SetToCurrentProfile('MyMod', 1)\n"), [])

    def test_table_return_in_module_is_reported(self):
        self.assertEqual(len(self.problems("return { Start = 1 }\n")), 1)

    def test_table_return_outside_modules_is_allowed(self):
        self.assertEqual(self.problems("return { Start = 1 }\n", "hook/main.lua"), [])

    def test_byte_order_mark_in_hook_file_is_reported(self):
        self.assertEqual(len(self.problems(b"\xef\xbb\xbflocal a = 1\n", "hook/lua/main.lua")), 1)

    def test_byte_order_mark_in_ordinary_file_is_allowed(self):
        self.assertEqual(self.problems(b"\xef\xbb\xbflocal a = 1\n"), [])

    def test_method_called_with_a_dot_is_reported(self):
        code = "local function F(unit)\n    return unit.GetPosition()\nend\n"
        self.assertIn("unit.GetPosition", " ".join(self.problems(code)))

    def test_method_called_with_a_colon_is_allowed(self):
        code = "local function F(unit)\n    return unit:GetPosition()\nend\n"
        self.assertEqual(self.problems(code), [])

    def test_control_size_getter_is_allowed(self):
        self.assertEqual(self.problems("local w = panel.Width() + panel.Left()\n"), [])

    def test_function_of_an_imported_module_is_allowed(self):
        code = 'local options = import("/lua/options.lua")\noptions.Start()\n'
        self.assertEqual(self.problems(code), [])

    def test_common_variable_names_are_allowed(self):
        code = "local line, index, name = 1, 2, 3\nlocal count = line + index + name\n"
        self.assertEqual(self.problems(code), [])

    def test_lines_after_a_block_comment_keep_their_numbers(self):
        code = "--[[ one\ntwo ]]\npcall(function()\n    WaitSeconds(1)\nend)\n"
        self.assertIn("4", self.problems(code)[0])


class RepoCase(unittest.TestCase):
    """A real git repository in a folder whose path contains spaces."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve() / "repo with spaces"
        self.root.mkdir()
        git(self.root, "init", "-q", "-b", "main")
        git(self.root, "config", "user.email", "test@example.com")
        git(self.root, "config", "user.name", "test")
        git(self.root, "config", "core.autocrlf", "false")
        for module in (check, bootstrap):
            patcher = mock.patch.object(module, "ROOT", self.root)
            patcher.start()
            self.addCleanup(patcher.stop)
        check.existing_files.cache_clear()

    def commit(self, message="change"):
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "--allow-empty", "-m", message)
        done = subprocess.run(["git", "rev-parse", "HEAD"], cwd=self.root, check=True,
                              capture_output=True, text=True)
        return done.stdout.strip()

    def mod(self, relative, info=MOD_INFO):
        folder = self.root / relative
        write(folder / "mod_info.lua", info)
        return folder


class ProjectDirTests(unittest.TestCase):
    def test_project_with_a_space_in_its_name(self):
        project = check.project_dir(Path("My_mods/Custom Hotkeys/customhotkeys"))
        self.assertEqual(project.name, "Custom Hotkeys")

    def test_nested_mod_belongs_to_its_top_project(self):
        project = check.project_dir(Path("My_mods/overflow/diagnostic/testing"))
        self.assertEqual(project.name, "overflow")


class ModTestsOwnerTests(unittest.TestCase):
    def test_mod_next_to_the_tests_owns_them(self):
        mod = Path("My_mods/overflow/Overflow")
        self.assertEqual(check.tests_project(mod), Path("My_mods/overflow"))

    def test_nested_mod_does_not_own_project_tests(self):
        self.assertIsNone(check.tests_project(Path("My_mods/overflow/diagnostic/testing")))

    def test_project_folder_that_is_the_mod_owns_its_tests(self):
        mod = Path("My_mods/single")
        self.assertEqual(check.tests_project(mod), mod)


class FindModsTests(RepoCase):
    def test_only_tracked_mods_are_found(self):
        tracked = self.mod("My_mods/one/Mod")
        self.commit()
        self.mod("My_mods/two/Local")
        self.assertEqual(check.find_mods(self.root), [tracked])


class ImportTests(RepoCase):
    def setUp(self):
        super().setUp()
        write(self.root / "references/fa/lua/ui/game/selection.lua", "")
        write(self.root / "references/ui-libs/mods/ReUI/Core/Main.lua", "")
        self.folder = self.mod("My_mods/one/MyMod")
        write(self.folder / "modules/own.lua", "")

    def problems(self, code):
        write(self.folder / "Main.lua", code)
        check.existing_files.cache_clear()
        return check.check_imports(self.folder)

    def test_missing_game_file_with_double_quotes_is_reported(self):
        self.assertIn("/lua/missing.lua", " ".join(self.problems('import("/lua/missing.lua")\n')))

    def test_missing_game_file_with_single_quotes_is_reported(self):
        self.assertIn("/lua/missing.lua", " ".join(self.problems("import('/lua/missing.lua')\n")))

    def test_existing_game_file_is_accepted(self):
        self.assertEqual(self.problems('import("/lua/ui/game/selection.lua")\n'), [])

    def test_path_case_does_not_matter(self):
        self.assertEqual(self.problems('import("/Lua/UI/Game/Selection.lua")\n'), [])

    def test_own_file_is_found_in_the_mod(self):
        self.assertEqual(self.problems('import("/mods/MyMod/modules/own.lua")\n'), [])

    def test_missing_own_file_is_reported(self):
        self.assertEqual(len(self.problems('import("/mods/MyMod/modules/gone.lua")\n')), 1)

    def test_library_file_is_found_in_references(self):
        self.assertEqual(self.problems('import("/mods/ReUI/Core/Main.lua")\n'), [])

    def test_missing_library_file_is_reported(self):
        self.assertEqual(len(self.problems('import("/mods/ReUI/Core/Gone.lua")\n')), 1)

    def test_other_mod_is_not_an_error(self):
        self.assertEqual(self.problems('import("/mods/ASE/modules/Lock.lua")\n'), [])

    def test_commented_import_is_ignored(self):
        self.assertEqual(self.problems('-- import("/lua/missing.lua")\n'), [])

    def test_path_built_at_runtime_is_ignored(self):
        self.assertEqual(self.problems('import("/lua/" .. name)\n'), [])


class ModInfoTests(RepoCase):
    def test_complete_file_is_accepted(self):
        self.assertEqual(check.check_mod_info(self.mod("My_mods/one/Mod")), [])

    def test_missing_field_is_reported(self):
        folder = self.mod("My_mods/one/Mod", 'name = "x"\nversion = 1\n')
        self.assertIn("uid", " ".join(check.check_mod_info(folder)))

    def test_library_tag_must_match_the_folder(self):
        folder = self.mod("My_mods/one/Mod", MOD_INFO + 'ReUI = "Other=1.0.0"\n')
        self.assertEqual(len(check.check_mod_info(folder)), 1)

    def test_matching_library_tag_is_accepted(self):
        folder = self.mod("My_mods/one/Mod", MOD_INFO + 'ReUI = "Mod=1.0.0"\n')
        self.assertEqual(check.check_mod_info(folder), [])


class RunTestsTests(RepoCase):
    def setUp(self):
        super().setUp()
        patcher = mock.patch.object(bootstrap, "lua_path", lambda: Path(sys.executable))
        patcher.start()
        self.addCleanup(patcher.stop)
        self.project = self.root / "My_mods/one"

    def test_only_test_scripts_are_run(self):
        marker = self.root / "negative_ran"
        # The stand-in interpreter is Python, so these scripts are Python too.
        write(self.project / "tests/test_ok.lua", "print('ok')\n")
        write(self.project / "tests/negative_breaks_mod.lua",
              f"open({str(marker)!r}, 'w').close()\n")
        self.assertEqual(check.run_tests(self.project), [])
        self.assertFalse(marker.exists())

    def test_failing_exit_code_is_reported(self):
        write(self.project / "tests/test_bad.lua", "raise SystemExit(1)\n")
        self.assertIn("test_bad.lua", " ".join(check.run_tests(self.project)))

    def test_fail_marker_in_output_is_reported(self):
        write(self.project / "tests/test_bad.lua", "print('[FAIL] something')\n")
        self.assertIn("test_bad.lua", " ".join(check.run_tests(self.project)))

    def test_project_without_tests_is_fine(self):
        self.project.mkdir(parents=True)
        self.assertEqual(check.run_tests(self.project), [])


class TestsLineTests(RepoCase):
    def output(self, mod):
        buffer = io.StringIO()
        with mock.patch.object(check, "check_luac", return_value=[]), \
                contextlib.redirect_stdout(buffer):
            check.check_mod(mod, {}, False)
        return buffer.getvalue()

    def test_mod_without_tests_is_not_reported_as_tested(self):
        output = self.output(self.mod("My_mods/one/Mod"))
        self.assertIn("[SKIP] тесты Mod", output)
        self.assertNotIn("[OK] тесты", output)

    def test_tests_folder_without_test_scripts_counts_as_no_tests(self):
        mod = self.mod("My_mods/one/Mod")
        write(self.root / "My_mods/one/tests/negative_mod.py", "")
        self.assertIn("[SKIP] тесты Mod", self.output(mod))

    def test_mod_with_tests_is_reported_as_tested(self):
        mod = self.mod("My_mods/one/Mod")
        # The stand-in interpreter is Python, so the script is Python too.
        write(self.root / "My_mods/one/tests/test_ok.lua", "print('ok')\n")
        with mock.patch.object(bootstrap, "lua_path", lambda: Path(sys.executable)):
            self.assertIn("[OK] тесты Mod", self.output(mod))


class ChangedModsTests(RepoCase):
    def setUp(self):
        super().setUp()
        self.one = self.mod("My_mods/one/ModOne")
        self.hotkeys = self.mod("My_mods/Custom Hotkeys/customhotkeys")
        self.two = self.mod("My_mods/two/ModTwo")
        self.base = self.commit("base")

    def test_only_the_mod_with_changed_code_is_selected(self):
        write(self.one / "Main.lua", "")
        self.commit()
        self.assertEqual(check.changed_mods(self.root, self.base), [self.one])

    def test_change_outside_the_mods_selects_none(self):
        write(self.root / "notes.txt", "notes")
        self.commit()
        self.assertEqual(check.changed_mods(self.root, self.base), [])

    def test_changed_rules_of_the_check_select_all_mods(self):
        for name in ("DOCUMENTATION/tools/check.py", "DOCUMENTATION/tools/validate_mod.py", ".luarc.json"):
            with self.subTest(name):
                write(self.root / name, name)
                base = self.commit()
                write(self.root / name, "changed")
                self.commit()
                self.assertEqual(len(check.changed_mods(self.root, base)), 3)

    def test_changed_test_script_selects_its_mod(self):
        write(self.root / "My_mods/two/tests/test_x.lua", "")
        self.commit()
        self.assertIn(self.two, check.changed_mods(self.root, self.base))

    def test_readme_next_to_the_mod_selects_nothing(self):
        write(self.root / "My_mods/two/README.md", "")
        self.commit()
        self.assertNotIn(self.two, check.changed_mods(self.root, self.base))

    def test_readme_inside_the_mod_folder_selects_nothing(self):
        write(self.two / "README.md", "")
        self.commit()
        self.assertNotIn(self.two, check.changed_mods(self.root, self.base))

    def test_file_moved_out_of_a_mod_selects_that_mod(self):
        write(self.two / "Main.lua", "code")
        base = self.commit()
        git(self.root, "mv", "My_mods/two/ModTwo/Main.lua", "moved.lua")
        self.commit()
        self.assertIn(self.two, check.changed_mods(self.root, base))

    def test_commits_made_only_on_the_base_branch_are_ignored(self):
        git(self.root, "switch", "-q", "-c", "topic")
        write(self.root / "notes.txt", "notes")
        self.commit()
        git(self.root, "switch", "-q", "main")
        write(self.two / "Main.lua", "code")
        self.commit()
        git(self.root, "switch", "-q", "topic")
        self.assertNotIn(self.two, check.changed_mods(self.root, "main"))

    def test_versions_added_only_on_the_base_branch_are_ignored(self):
        git(self.root, "switch", "-q", "-c", "topic")
        write(self.root / check.VERSIONS_PATH, "{}")
        self.commit()
        git(self.root, "switch", "-q", "main")
        write(self.root / check.VERSIONS_PATH, '{"a": 1}')
        self.commit()
        git(self.root, "switch", "-q", "topic")
        self.assertNotIn(self.two, check.changed_mods(self.root, "main"))

    def test_first_appearance_of_versions_is_not_a_bump(self):
        write(self.root / check.VERSIONS_PATH, "{}")
        self.commit()
        self.assertNotIn(self.two, check.changed_mods(self.root, self.base))

    def test_changed_versions_select_all_mods(self):
        write(self.root / check.VERSIONS_PATH, "{}")
        base = self.commit()
        write(self.root / check.VERSIONS_PATH, '{"a": 1}')
        self.commit()
        self.assertEqual(len(check.changed_mods(self.root, base)), 3)


class ReadmeTests(RepoCase):
    def test_project_without_readme_is_reported(self):
        self.assertEqual(len(check.check_readme(self.mod("My_mods/one/Mod"))), 1)

    def test_project_with_readme_passes(self):
        folder = self.mod("My_mods/one/Mod")
        write(self.root / "My_mods/one/README.md", "")
        self.assertEqual(check.check_readme(folder), [])


class ReadmeWarningTests(RepoCase):
    def setUp(self):
        super().setUp()
        self.one = self.mod("My_mods/one/ModOne")
        self.base = self.commit("base")

    def test_changed_code_without_readme_is_reported(self):
        write(self.one / "Main.lua", "")
        self.commit()
        self.assertEqual(len(check.readme_warnings(self.root, self.base)), 1)

    def test_changed_code_with_readme_is_fine(self):
        write(self.one / "Main.lua", "")
        write(self.root / "My_mods/one/README.md", "")
        self.commit()
        self.assertEqual(check.readme_warnings(self.root, self.base), [])


class LualsReportTests(unittest.TestCase):
    def test_clean_run_writes_an_empty_list(self):
        self.assertEqual(check.parse_luals([]), {})

    def test_report_is_grouped_by_file(self):
        raw = {
            "file:///c%3A/repo%20name/My_mods/one/Mod/Main.lua": [{
                "code": "undefined-global",
                "message": "Undefined global `Foo`.",
                "range": {"start": {"line": 4}},
            }],
        }
        report = check.parse_luals(raw)
        self.assertEqual(len(report), 1)
        path, problems = next(iter(report.items()))
        self.assertTrue(path.as_posix().endswith("repo name/My_mods/one/Mod/Main.lua"))
        self.assertIn("5", problems[0])
        self.assertIn("undefined-global", problems[0])

    def test_report_from_another_folder_is_an_error(self):
        report = {Path("/elsewhere/Main.lua"): ["problem"]}
        with self.assertRaises(check.CheckError):
            check.require_paths_inside(report, Path("/repo"))

    def test_report_inside_the_repository_is_accepted(self):
        check.require_paths_inside({Path("/repo/My_mods/Main.lua"): ["problem"]}, Path("/repo"))

    def test_empty_report_is_accepted(self):
        check.require_paths_inside({}, Path("/repo"))


class VersionsTests(RepoCase):
    def install(self, versions, *paths):
        bootstrap.installed_file().parent.mkdir(parents=True)
        bootstrap.installed_file().write_text(json.dumps(versions), encoding="utf-8")
        for path in paths:
            write(path, "")
        for name in bootstrap.SPARSE:
            (self.root / "references" / name).mkdir(parents=True)

    def test_deleted_source_folder_is_reported(self):
        self.install(bootstrap.expected_versions(bootstrap.load_versions()),
                     bootstrap.luals_path(), bootstrap.luac_path(), bootstrap.lua_path())
        (self.root / "references" / "fa").rmdir()
        self.assertIn("bootstrap.py", " ".join(check.check_versions()))

    def test_stale_tools_stop_the_check_with_a_command(self):
        self.assertIn("bootstrap.py", " ".join(check.check_versions()))

    def test_installed_tools_pass(self):
        self.install(bootstrap.expected_versions(bootstrap.load_versions()),
                     bootstrap.luals_path(), bootstrap.luac_path(), bootstrap.lua_path())
        self.assertEqual(check.check_versions(), [])

    def test_deleted_tool_is_reported(self):
        self.install(bootstrap.expected_versions(bootstrap.load_versions()),
                     bootstrap.luals_path(), bootstrap.luac_path())
        self.assertIn("bootstrap.py", " ".join(check.check_versions()))

    def test_ci_does_not_need_the_built_compiler(self):
        versions = bootstrap.expected_versions(bootstrap.load_versions())
        del versions["faf-lua"]
        self.install(versions, bootstrap.luals_path())
        self.assertEqual(check.check_versions(no_luac=True), [])


class CommandLineTests(unittest.TestCase):
    def run_outside_ci(self, script, *args):
        env = {key: value for key, value in os.environ.items() if key != "GITHUB_ACTIONS"}
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        return subprocess.run([sys.executable, str(TOOLS / script), *args], capture_output=True,
                              env=env, encoding="utf-8", errors="replace")

    def test_no_luac_is_refused_outside_ci(self):
        done = self.run_outside_ci("check.py", "--no-luac")
        self.assertEqual(done.returncode, 1)
        self.assertIn("--no-luac", done.stdout)

    def test_bootstrap_no_luac_is_refused_outside_ci(self):
        done = self.run_outside_ci("bootstrap.py", "--no-luac")
        self.assertEqual(done.returncode, 1)
        self.assertIn("--no-luac", done.stdout)

    def test_console_without_cyrillic_does_not_crash(self):
        env = dict(os.environ, PYTHONIOENCODING="ascii", PYTHONDONTWRITEBYTECODE="1")
        done = subprocess.run([sys.executable, str(TOOLS / "check.py"), "no such folder"],
                              capture_output=True, env=env)
        self.assertEqual(done.returncode, 1)
        self.assertNotIn(b"Traceback", done.stderr)

    def test_check_without_a_target_is_refused(self):
        done = self.run_outside_ci("check.py")
        self.assertEqual(done.returncode, 1)
        self.assertIn("--all", done.stdout)

    def test_check_with_two_targets_is_refused(self):
        done = self.run_outside_ci("check.py", "--all", "--knowledge")
        self.assertEqual(done.returncode, 1)
        self.assertIn("--all", done.stdout)


class TargetTests(unittest.TestCase):
    """What each form of the command checks: the checks themselves are replaced."""

    def run_check(self, *args):
        mods = []
        knowledge = []

        def check_mod(mod, _luals, _no_luac):
            mods.append(mod.name)
            return True

        def check_knowledge(_root):
            knowledge.append(True)
            return []

        with mock.patch.object(sys, "argv", ["check.py", *args]), \
                mock.patch.object(check, "check_versions", return_value=[]), \
                mock.patch.object(check, "find_mods", return_value=[Path("One"), Path("Two")]), \
                mock.patch.object(check, "run_luals", return_value={}) as luals, \
                mock.patch.object(check, "check_mod", check_mod), \
                mock.patch.object(check, "check_knowledge", check_knowledge), \
                contextlib.redirect_stdout(io.TextIOWrapper(io.BytesIO(), encoding="utf-8")):
            code = check.main()
        return code, mods, bool(knowledge), luals.called

    def test_all_checks_every_mod_and_the_knowledge_base(self):
        self.assertEqual(self.run_check("--all"), (0, ["One", "Two"], True, True))

    def test_knowledge_checks_no_mod(self):
        self.assertEqual(self.run_check("--knowledge"), (0, [], True, False))

    def test_one_mod_leaves_the_others_and_the_knowledge_base_out(self):
        with tempfile.TemporaryDirectory() as temp:
            mod = Path(temp) / "Mod"
            write(mod / "mod_info.lua", MOD_INFO)
            self.assertEqual(self.run_check(str(mod)), (0, ["Mod"], False, True))


class KnowledgeTests(RepoCase):
    def setUp(self):
        super().setUp()
        write(self.root / "references/fa/lua/commandmode.lua", "function InCommandMode()\nend\n")

    def problems(self, text):
        write(self.root / "DOCUMENTATION/knowledge/topic.md", text)
        return check.check_knowledge(self.root)

    def test_fact_with_found_source_passes(self):
        text = "### Fact\n\nText.\n\nИсточник: fa:lua/commandmode.lua#function InCommandMode\n"
        self.assertEqual(self.problems(text), [])

    def test_missing_source_file_is_reported(self):
        text = "### Fact\n\nИсточник: fa:lua/gone.lua#function InCommandMode\n"
        self.assertIn("lua/gone.lua", " ".join(self.problems(text)))

    def test_missing_source_text_is_reported(self):
        text = "### Fact\n\nИсточник: fa:lua/commandmode.lua#function Removed\n"
        self.assertIn("function Removed", " ".join(self.problems(text)))

    def test_fact_without_source_is_reported(self):
        self.assertIn("Fact", " ".join(self.problems("### Fact\n\nJust text.\n")))

    def test_observation_needs_no_file(self):
        self.assertEqual(self.problems("### Fact\n\nНаблюдение: game, 2 players.\n"), [])

    def test_unconfirmed_mark_is_accepted(self):
        self.assertEqual(self.problems("### Fact\n\nНе подтверждено: needs a log.\n"), [])

    def test_web_source_is_accepted(self):
        text = "### Fact\n\nИсточник: https://github.com/FAForever/fa\n"
        self.assertEqual(self.problems(text), [])

    def test_unknown_source_format_is_reported(self):
        self.assertEqual(len(self.problems("### Fact\n\nИсточник: somewhere\n")), 1)

    def test_text_before_the_first_fact_is_free(self):
        self.assertEqual(self.problems("# Title\n\nIntro.\n"), [])

    def test_missing_folder_is_reported(self):
        self.assertEqual(len(check.check_knowledge(self.root)), 1)


REAL_LUAC = TOOLS.parents[1] / ".tools" / "faf-lua" / f"luac{bootstrap.EXE}"


@unittest.skipUnless(REAL_LUAC.exists(), "FAF Lua is not built")
class LuacTests(RepoCase):
    def setUp(self):
        super().setUp()
        patcher = mock.patch.object(bootstrap, "luac_path", lambda: REAL_LUAC)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_syntax_error_is_reported(self):
        folder = self.mod("My_mods/one/Mod")
        write(folder / "Main.lua", "function Main(\n")
        self.assertEqual(len(check.check_luac(folder)), 1)

    def test_valid_files_are_accepted(self):
        self.assertEqual(check.check_luac(self.mod("My_mods/one/Mod")), [])

    def test_failure_without_a_message_is_still_reported(self):
        folder = self.mod("My_mods/one/Mod")
        silent = subprocess.CompletedProcess([], 1, stdout="", stderr="")
        with mock.patch.object(check.subprocess, "run", return_value=silent):
            self.assertEqual(len(check.check_luac(folder)), 1)


if __name__ == "__main__":
    unittest.main()
