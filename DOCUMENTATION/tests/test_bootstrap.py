import json
import re
import subprocess
import sys
import tarfile
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

import bootstrap


def git(cwd, *args):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


class RootInTemp(unittest.TestCase):
    """Runs against a temporary root whose path contains spaces."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "path with spaces"
        self.root.mkdir()
        for patcher in (mock.patch.object(bootstrap, "ROOT", self.root),
                        mock.patch.object(bootstrap, "print", create=True)):
            patcher.start()
            self.addCleanup(patcher.stop)


class OutdatedTests(unittest.TestCase):
    def test_outdated_lists_only_changed_components(self):
        self.assertEqual(bootstrap.outdated({"a": "1", "b": "2"}, {"a": "1", "b": "1"}), ["b"])

    def test_outdated_lists_missing_components(self):
        self.assertEqual(bootstrap.outdated({"a": "1"}, {}), ["a"])


class ExpectedVersionsTests(unittest.TestCase):
    VERSIONS = {
        "fa": {"repo": "o/fa", "branch": "b", "ref": "aaa"},
        "lua-lang": {"repo": "o/lua", "ref": "v1"},
        "lua-language-server": "3.0",
        "ziglang": "0.1",
    }

    def test_repository_is_expected_at_its_ref(self):
        self.assertEqual(bootstrap.expected_versions(self.VERSIONS)["fa"], "aaa")

    def test_new_compiler_source_requires_a_rebuild(self):
        changed = json.loads(json.dumps(self.VERSIONS))
        changed["lua-lang"]["ref"] = "v2"
        self.assertNotEqual(
            bootstrap.expected_versions(self.VERSIONS)["faf-lua"],
            bootstrap.expected_versions(changed)["faf-lua"],
        )

    def test_new_build_compiler_requires_a_rebuild(self):
        changed = dict(self.VERSIONS, ziglang="0.2")
        self.assertNotEqual(
            bootstrap.expected_versions(self.VERSIONS)["faf-lua"],
            bootstrap.expected_versions(changed)["faf-lua"],
        )


class SameRepositoryTests(unittest.TestCase):
    URL = "https://github.com/owner/name"

    def test_same_address_matches(self):
        self.assertTrue(bootstrap.same_repository(self.URL, self.URL))

    def test_git_suffix_is_ignored(self):
        self.assertTrue(bootstrap.same_repository(self.URL + ".git", self.URL))

    def test_ssh_address_matches(self):
        self.assertTrue(bootstrap.same_repository("git@github.com:owner/name.git", self.URL))

    def test_other_repository_does_not_match(self):
        self.assertFalse(bootstrap.same_repository("https://github.com/owner/other", self.URL))


class UnpackTests(RootInTemp):
    def test_tarball_is_unpacked_without_warnings(self):
        source = self.root / "bin"
        source.mkdir()
        (source / "tool").write_text("data")
        archive = self.root / "tool.tar.gz"
        with tarfile.open(archive, "w:gz") as package:
            package.add(source, arcname="bin")
        target = self.root / "out"
        target.mkdir()
        with warnings.catch_warnings():
            warnings.simplefilter("error")
            bootstrap.unpack(archive, target)
        self.assertEqual((target / "bin" / "tool").read_text(), "data")

    def test_zip_is_unpacked(self):
        archive = self.root / "tool.zip"
        with zipfile.ZipFile(archive, "w") as package:
            package.writestr("bin/tool", "data")
        target = self.root / "out"
        target.mkdir()
        bootstrap.unpack(archive, target)
        self.assertEqual((target / "bin" / "tool").read_text(), "data")


class InstallStepTests(RootInTemp):
    def test_damaged_record_counts_as_nothing_installed(self):
        bootstrap.installed_file().parent.mkdir(parents=True)
        bootstrap.installed_file().write_text('{"fa": "aa', encoding="utf-8")
        self.assertEqual(bootstrap.load_installed(), {})

    def test_failed_step_is_not_marked_installed(self):
        calls = []

        def failing():
            calls.append("failed")
            raise bootstrap.BootstrapError("interrupted")

        with self.assertRaises(bootstrap.BootstrapError):
            bootstrap.install_step("fa", "aaa", failing)
        self.assertEqual(bootstrap.load_installed(), {})

        bootstrap.install_step("fa", "aaa", lambda: calls.append("done"))
        self.assertEqual(calls, ["failed", "done"])
        self.assertEqual(bootstrap.load_installed(), {"fa": "aaa"})

    def test_finished_step_is_not_repeated(self):
        calls = []
        bootstrap.install_step("fa", "aaa", lambda: calls.append("run"))
        bootstrap.install_step("fa", "aaa", lambda: calls.append("run"))
        self.assertEqual(calls, ["run"])

    def test_changed_version_repeats_the_step(self):
        calls = []
        bootstrap.install_step("fa", "aaa", lambda: calls.append("old"))
        bootstrap.install_step("fa", "bbb", lambda: calls.append("new"))
        self.assertEqual(calls, ["old", "new"])

    def test_missing_files_repeat_the_step(self):
        calls = []
        tool = self.root / "tool.exe"
        bootstrap.install_step("luals", "1", lambda: calls.append("run"), tool)
        bootstrap.install_step("luals", "1", lambda: calls.append("run"), tool)
        self.assertEqual(calls, ["run", "run"])


class InstallTests(RootInTemp):
    VERSIONS = {
        "ui-libs": {"repo": "o/mods", "ref": "aaa"},
        "lua-lang": {"repo": "o/lua", "ref": "v1"},
        "lua-language-server": "3.0",
        "ziglang": "0.1",
    }

    def test_new_sparse_folder_repeats_the_repository_step(self):
        (self.root / "references/ui-libs/mods/old").mkdir(parents=True)
        bootstrap.mark_installed("ui-libs", "aaa")
        with mock.patch.object(bootstrap, "SPARSE", {"ui-libs": ["mods/old", "mods/new"]}), \
                mock.patch.object(bootstrap, "ensure_repo") as ensure_repo, \
                mock.patch.object(bootstrap, "install_luals"):
            bootstrap.install(self.VERSIONS, build_luac=False)
        ensure_repo.assert_called_once_with("ui-libs", self.VERSIONS["ui-libs"], ["mods/old", "mods/new"])


class EnsureRepoTests(RootInTemp):
    def setUp(self):
        super().setUp()
        self.github = self.root / "github"
        origin = self.github / "owner" / "name"
        origin.mkdir(parents=True)
        git(origin, "init", "-q", "-b", "main")
        git(origin, "config", "user.email", "test@example.com")
        git(origin, "config", "user.name", "test")
        git(origin, "config", "uploadpack.allowAnySHA1InWant", "true")
        (origin / "lua").mkdir()
        (origin / "other").mkdir()
        (origin / "lua" / "x.lua").write_text("first")
        (origin / "other" / "y.lua").write_text("skip")
        git(origin, "add", ".")
        git(origin, "commit", "-q", "-m", "first")
        self.first = self.head(origin)
        (origin / "lua" / "x.lua").write_text("second")
        git(origin, "commit", "-q", "-am", "second")
        self.second = self.head(origin)
        patcher = mock.patch.object(bootstrap, "GITHUB", self.github.as_uri() + "/")
        patcher.start()
        self.addCleanup(patcher.stop)

    @staticmethod
    def head(cwd):
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=cwd, check=True, capture_output=True, text=True
        ).stdout.strip()

    def spec(self, ref):
        return {"repo": "owner/name", "branch": "main", "ref": ref}

    def test_repository_is_checked_out_at_pinned_commit(self):
        bootstrap.ensure_repo("fa", self.spec(self.first), ["lua"])
        self.assertEqual((self.root / "references/fa/lua/x.lua").read_text(), "first")

    def test_only_sparse_folders_are_checked_out(self):
        bootstrap.ensure_repo("fa", self.spec(self.first), ["lua"])
        self.assertFalse((self.root / "references/fa/other/y.lua").exists())

    def test_new_sparse_folder_reaches_an_existing_clone(self):
        bootstrap.ensure_repo("fa", self.spec(self.first), ["lua"])
        bootstrap.ensure_repo("fa", self.spec(self.first), ["lua", "other"])
        self.assertTrue((self.root / "references/fa/other/y.lua").exists())

    def test_existing_clone_moves_to_new_commit(self):
        bootstrap.ensure_repo("fa", self.spec(self.first), ["lua"])
        bootstrap.ensure_repo("fa", self.spec(self.second), ["lua"])
        self.assertEqual((self.root / "references/fa/lua/x.lua").read_text(), "second")

    def test_foreign_folder_is_refused_and_kept(self):
        foreign = self.root / "references/fa"
        foreign.mkdir(parents=True)
        (foreign / "keep.txt").write_text("mine")
        with self.assertRaises(bootstrap.BootstrapError):
            bootstrap.ensure_repo("fa", self.spec(self.first), ["lua"])
        self.assertEqual((foreign / "keep.txt").read_text(), "mine")

    def test_clone_of_other_repository_is_refused_and_kept(self):
        foreign = self.root / "references/fa"
        foreign.mkdir(parents=True)
        git(foreign, "init", "-q")
        git(foreign, "remote", "add", "origin", "https://example.com/other.git")
        (foreign / "keep.txt").write_text("mine")
        with self.assertRaises(bootstrap.BootstrapError):
            bootstrap.ensure_repo("fa", self.spec(self.first), ["lua"])
        self.assertEqual((foreign / "keep.txt").read_text(), "mine")

    def test_interrupted_clone_is_repeated(self):
        with self.assertRaises(bootstrap.BootstrapError):
            bootstrap.ensure_repo("fa", self.spec("0" * 40), ["lua"])
        self.assertFalse((self.root / "references/fa").exists())

        bootstrap.ensure_repo("fa", self.spec(self.first), ["lua"])
        self.assertEqual((self.root / "references/fa/lua/x.lua").read_text(), "first")


class RemoveTreeTests(RootInTemp):
    def test_link_targets_keep_their_permissions(self):
        # A Linux venv links bin/python to a system file that chmod must not touch.
        folder = self.root / "venv"
        (folder / "bin").mkdir(parents=True)
        (folder / "bin" / "python").write_text("link")
        with mock.patch.object(Path, "is_symlink", return_value=True), \
                mock.patch.object(bootstrap.os, "chmod") as chmod:
            bootstrap.remove_tree(folder)
        chmod.assert_not_called()
        self.assertFalse(folder.exists())


class DownloadTests(RootInTemp):
    def test_file_is_downloaded(self):
        source = self.root / "source.txt"
        source.write_text("data")
        target = self.root / "target.txt"
        bootstrap.download(source.as_uri(), target)
        self.assertEqual(target.read_text(), "data")

    def test_failed_download_is_reported(self):
        missing = (self.root / "missing.txt").as_uri()
        with self.assertRaises(bootstrap.BootstrapError):
            bootstrap.download(missing, self.root / "target.txt")

    def test_json_is_parsed(self):
        source = self.root / "data.json"
        source.write_text('{"tag_name": "v1"}')
        self.assertEqual(bootstrap.fetch_json(source.as_uri()), {"tag_name": "v1"})

    def test_failed_json_request_is_reported(self):
        with self.assertRaises(bootstrap.BootstrapError):
            bootstrap.fetch_json((self.root / "missing.json").as_uri())


class LualsAssetTests(unittest.TestCase):
    def test_windows_uses_zip(self):
        self.assertEqual(
            bootstrap.luals_asset("3.1", "win32"), "lua-language-server-3.1-win32-x64.zip"
        )

    def test_linux_uses_tarball(self):
        self.assertEqual(
            bootstrap.luals_asset("3.1", "linux"), "lua-language-server-3.1-linux-x64.tar.gz"
        )

    def test_unknown_system_is_an_error(self):
        with self.assertRaises(bootstrap.BootstrapError):
            bootstrap.luals_asset("3.1", "plan9")


class LatestVersionsTests(unittest.TestCase):
    VERSIONS = {
        "ui-libs": {"repo": "o/mods", "branch": "dev", "ref": "aaa"},
        "lua-lang": {"repo": "o/lua", "ref": "v1"},
        "lua-language-server": "3.0",
        "ziglang": "0.1",
    }

    def fetch(self, folder_commits=None, lua_tag="v1", luals_tag="3.0"):
        """folder_commits maps (ref, folder) to the last commit that touched the folder."""
        folder_commits = folder_commits or {}

        def fake(url):
            if "/commits?" in url:
                ref = re.search(r"sha=([^&]+)", url).group(1)
                folder = re.search(r"path=([^&]+)", url).group(1)
                return [{"sha": folder_commits.get((ref, folder), "same")}]
            if "o/lua/" in url:
                return {"tag_name": lua_tag}
            return {"tag_name": luals_tag}

        return mock.patch.object(bootstrap, "fetch_json", fake)

    def test_unchanged_tracked_folders_report_nothing(self):
        with self.fetch():
            self.assertEqual(bootstrap.latest_versions(self.VERSIONS), {})

    def test_change_in_a_tracked_folder_is_reported(self):
        with self.fetch({("dev", "mods/ReUI"): "bbb"}):
            self.assertEqual(bootstrap.latest_versions(self.VERSIONS), {"ui-libs": "bbb"})

    def test_new_compiler_release_is_reported(self):
        with self.fetch(lua_tag="v2"):
            self.assertEqual(bootstrap.latest_versions(self.VERSIONS), {"lua-lang": "v2"})

    def test_new_language_server_release_is_reported(self):
        with self.fetch(luals_tag="3.1"):
            self.assertEqual(
                bootstrap.latest_versions(self.VERSIONS), {"lua-language-server": "3.1"}
            )


@unittest.skipUnless(bootstrap.luac_path().exists(), "FAF Lua is not built")
class BuiltLuaTests(unittest.TestCase):
    def lua_prints(self, code):
        with tempfile.TemporaryDirectory() as folder:
            script = Path(folder) / "script.lua"
            script.write_text(code)
            done = subprocess.run(
                [str(bootstrap.lua_path()), str(script)], capture_output=True, text=True
            )
        return done.stdout.strip()

    def luac_accepts(self, code):
        with tempfile.TemporaryDirectory() as folder:
            script = Path(folder) / "script.lua"
            script.write_text(code)
            done = subprocess.run(
                [str(bootstrap.luac_path()), "-p", str(script)], capture_output=True, text=True
            )
        return done.returncode == 0

    def test_hash_starts_a_comment(self):
        self.assertEqual(self.lua_prints("print(1) # print(2)"), "1")

    def test_long_string_with_level_is_rejected(self):
        self.assertFalse(self.luac_accepts("local s = [=[text]=]\n"))

    def test_vararg_expression_is_rejected(self):
        self.assertFalse(self.luac_accepts("function F(...)\n    return ...\nend\n"))

    def test_varargs_are_in_the_arg_table(self):
        self.assertEqual(self.lua_prints(
            "function F(...)\n    return arg.n\nend\nprint(F(1, 2))\n"), "2")

    def test_math_library_replaces_missing_operators(self):
        self.assertEqual(self.lua_prints("print(math.mod(7, 3), math.pow(2, 3))"), "1\t8")

    def test_select_does_not_exist(self):
        self.assertEqual(self.lua_prints("print(select)"), "nil")

    def test_math_huge_does_not_exist(self):
        self.assertEqual(self.lua_prints("print(math.huge)"), "nil")

    def test_integer_format_truncates(self):
        self.assertEqual(self.lua_prints('print(string.format("%d", 3.7))'), "3")

    def test_bare_table_can_be_iterated(self):
        self.assertEqual(self.lua_prints(
            "local s = 0\nfor k, v in {1, 2} do\n    s = s + v\nend\nprint(s)\n"), "3")

    def test_numbers_are_single_precision_as_in_the_game(self):
        self.assertEqual(self.lua_prints("print(0.1 + 0.2 == 0.3)"), "true")

    def test_caret_is_xor(self):
        self.assertEqual(self.lua_prints("print(5 ^ 3)"), "6")

    def test_modulo_is_rejected(self):
        self.assertFalse(self.luac_accepts("local a = 7 % 3\n"))

    def test_upvalue_limit_is_enforced(self):
        names = [f"v{index}" for index in range(33)]
        code = "".join(f"local {name} = 1\n" for name in names)
        code += "function F()\n    return " + " + ".join(names) + "\nend\n"
        self.assertFalse(self.luac_accepts(code))


if __name__ == "__main__":
    unittest.main()
