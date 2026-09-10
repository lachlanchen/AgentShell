import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "bin/agent-desktop"
loader = importlib.machinery.SourceFileLoader("agent_desktop", str(LAUNCHER))
spec = importlib.util.spec_from_loader(loader.name, loader)
desktop = importlib.util.module_from_spec(spec)
loader.exec_module(desktop)


class DesktopTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agentshell-desktop-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.work = self.root / "working tree"
        self.work.mkdir()
        self.output = self.root / "invocation.json"
        self.app = self.root / "fake app"
        self.app.write_text(
            "#!/usr/bin/env python3\nimport os,json,sys\n"
            "from pathlib import Path\n"
            "Path(os.environ['DESKTOP_TEST_OUTPUT']).write_text(json.dumps({"
            "'argv':sys.argv[1:],'cwd':os.getcwd(),"
            "'account':os.environ.get('AGENT_SHELL_ACCOUNT'),"
            "'codex_home':os.environ.get('CODEX_HOME'),"
            "'ui_home':os.environ.get('CODEX_ELECTRON_USER_DATA_PATH'),"
            "'api_key':os.environ.get('OPENAI_API_KEY'),"
            "'home':os.environ.get('HOME')}))\n"
        )
        self.app.chmod(0o700)
        self.env = dict(os.environ)
        self.env.update({
            "AGENT_SHELL_HOME": str(self.root / "state with spaces"),
            "AGENT_SHELL_BIN_DIR": str(self.root / "bin"),
            "AGENT_SHELL_DESKTOP_APP": str(self.app),
            "DESKTOP_TEST_OUTPUT": str(self.output),
            "XDG_DATA_HOME": str(self.root / "xdg"),
            "OPENAI_API_KEY": "inherited-test-key-must-not-leak",
        })
        for provider in ("CODEX", "CLAUDE", "GEMINI", "COPILOT"):
            self.env[f"AGENT_SHELL_BASE_{provider}_HOME"] = str(self.root / provider.lower())
        for key in ("AGENT_SHELL_ACCOUNT", "AGENT_SHELL_PROFILE_ROOT", "CODEX_HOME", "CODEX_SQLITE_HOME"):
            self.env.pop(key, None)

    def run_cli(self, *args, check=True):
        return subprocess.run([sys.executable, str(LAUNCHER), *args], env=self.env,
                              cwd=self.work, text=True, capture_output=True, check=check)

    def test_real_runtime_routes_two_accounts_without_changing_home_or_cwd(self):
        results = []
        for account in ("personal", "company"):
            self.run_cli("--account", account, "--foreground", "--", "argument with spaces", "quote'\"$")
            result = json.loads(self.output.read_text())
            profile = Path(self.env["AGENT_SHELL_HOME"]) / "profiles" / account
            self.assertEqual(result["account"], account)
            self.assertEqual(result["codex_home"], str(profile / "codex-home"))
            self.assertEqual(result["ui_home"], str(profile / "codex-desktop"))
            self.assertIn("--user-data-dir=" + result["ui_home"], result["argv"])
            self.assertEqual(result["argv"][-2:], ["argument with spaces", "quote'\"$"])
            self.assertEqual(result["cwd"], str(self.work))
            self.assertEqual(result["home"], os.environ.get("HOME"))
            self.assertIsNone(result["api_key"])
            results.append(result)
        self.assertNotEqual(results[0]["codex_home"], results[1]["codex_home"])
        self.assertNotEqual(results[0]["ui_home"], results[1]["ui_home"])

    def test_account_shell_default(self):
        self.env["AGENT_SHELL_ACCOUNT"] = "lab"
        self.run_cli("--foreground")
        self.assertEqual(json.loads(self.output.read_text())["account"], "lab")

    def test_invalid_and_conflicting_accounts_and_profile_overrides(self):
        for args in (("../wrong",), ("--account", "company", "personal"),
                     ("personal", "--", "--user-data-dir=/other"),
                     ("personal", "--", "--class", "other")):
            self.assertNotEqual(self.run_cli(*args, check=False).returncode, 0)
        self.assertFalse(self.output.exists())

    def test_status_does_not_create_or_launch(self):
        response = json.loads(self.run_cli("personal", "--status").stdout)
        self.assertIsNone(response["running_pid"])
        self.assertFalse(Path(response["profile"]).exists())
        self.assertFalse(self.output.exists())

    def test_launchers_are_idempotent_and_do_not_replace_unrelated_files(self):
        self.run_cli("--install-launchers", "company", "personal", "lab")
        paths = sorted((Path(self.env["XDG_DATA_HOME"]) / "applications").glob("*.desktop"))
        first = [p.read_text() for p in paths]
        self.run_cli("--install-launchers", "company", "personal", "lab")
        self.assertEqual(first, [p.read_text() for p in paths])
        self.assertEqual(len(paths), 3)
        for p in paths:
            subprocess.run(["desktop-file-validate", str(p)], check=True)
        paths[0].write_text("[Desktop Entry]\nName=User-owned\n")
        result = self.run_cli("--install-launchers", "company", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("User-owned", paths[0].read_text())

    def test_desktop_exec_escape(self):
        quoted = desktop.desktop_quote('/tmp/a b/%quoted"$`\\tool')
        self.assertTrue(quoted.startswith('"') and quoted.endswith('"'))
        self.assertIn("%%quoted", quoted)
        self.assertIn('\\"', quoted)
        self.assertIn('\\$', quoted)


if __name__ == "__main__":
    unittest.main()
