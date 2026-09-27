import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("codex_takeover", ROOT / "bin/codex_takeover.py")
takeover = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(takeover)
SESSION = "11111111-2222-3333-4444-555555555555"
OTHER = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"


class ArgumentTests(unittest.TestCase):
    def test_explicit_aliases_and_native_arguments(self):
        for flag in takeover.CLOSE_FLAGS:
            for command in (
                ["codex", flag, "-m", "a model", "resume", SESSION, "a prompt"],
                ["codex", "resume", flag, SESSION],
            ):
                clean, session = takeover.parse_command(command)
                self.assertEqual(session, SESSION)
                self.assertNotIn(flag, clean)
                self.assertEqual(clean, [arg for arg in command if arg != flag])

    def test_do_not_consume_native_flags_values_or_prompts(self):
        for command in (
            ["codex", "-f", "--force"],
            ["codex", "-m", "--close-other"],
            ["codex", "resume", SESSION, "--", "--close-other"],
            ["codex", "exec", "--force"],
        ):
            self.assertFalse(takeover.requested(command))
            self.assertEqual(takeover.prepare_command(command), command)
        clean, session = takeover.parse_command(["codex", "--close-other", "resume", SESSION, "--", "--close-other"])
        self.assertEqual(clean[-1], "--close-other")
        self.assertEqual(session, SESSION)

    def test_reject_ambiguous_and_remote_requests(self):
        for args in (
            [], ["resume"], ["resume", "--last"], ["resume", "named-session"],
            ["fork", SESSION], ["delete", SESSION, "--force"], ["login"],
            ["resume", SESSION, "--remote", "unix:///tmp/elsewhere"],
            ["resume", SESSION, "--remote=unix:///tmp/elsewhere"],
            ["resume", SESSION, "--unknown"], ["resume", SESSION, "-m"],
        ):
            with self.subTest(args=args), self.assertRaises(takeover.TakeoverError):
                takeover.parse_command(["codex", "--close-other", *args])

    def test_help_never_closes_anything(self):
        with patch.object(takeover, "close_session") as close:
            self.assertEqual(
                takeover.prepare_command(["codex", "--close-other", "resume", "--help"]),
                ["codex", "resume", "--help"],
            )
            close.assert_not_called()

    def test_where_never_closes_or_launches(self):
        with patch.object(takeover, "close_session") as close, patch.object(takeover, "describe_session") as inspect:
            self.assertIsNone(takeover.prepare_command(["codex", "--where", "resume", SESSION]))
            inspect.assert_called_once_with(SESSION)
            close.assert_not_called()
            with self.assertRaises(takeover.TakeoverError):
                takeover.prepare_command(["codex", "--where", "--kill", "resume", SESSION])
            close.assert_not_called()


class MoveTests(unittest.TestCase):
    def test_newest_only_and_other_active_migration_refusal(self):
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / 'state.sqlite'
            with sqlite3.connect(db) as c:
                c.execute('CREATE TABLE threads(id TEXT,cwd TEXT,recency_at_ms INTEGER,updated_at_ms INTEGER,updated_at INTEGER)')
                c.executemany('INSERT INTO threads VALUES(?,?,?,0,0)', [(SESSION, '/old', 2), (OTHER, '/old/child', 1)])
            with patch.object(takeover, 'owners', return_value=set()), patch.object(takeover, 'close_session') as close:
                self.assertEqual(takeover.prepare_move(str(db), '/old'), SESSION)
                close.assert_called_once_with(SESSION)
            with patch.object(takeover, 'owners', return_value={123}), patch.object(takeover, 'close_session') as close:
                with self.assertRaises(takeover.TakeoverError):
                    takeover.prepare_move(str(db), '/old')
                close.assert_not_called()
            with sqlite3.connect(db) as c:
                self.assertEqual(c.execute('SELECT cwd FROM threads ORDER BY recency_at_ms DESC').fetchall(), [('/old',), ('/old/child',)])


@unittest.skipUnless(sys.platform == "linux", "Linux process identity checks")
class SafetyTests(unittest.TestCase):
    def setUp(self):
        self.cli = {"pid": 70001, "ppid": 70000, "uid": os.getuid(), "start": "1", "exe": "/test/codex", "argv": ["codex", "resume", SESSION]}
        self.app = {"pid": 70000, "ppid": 1, "uid": os.getuid(), "start": "2", "exe": "/test/ChatGPT", "argv": ["ChatGPT"]}

    def plan(self, info=None, sessions=None):
        info = info or self.cli
        with patch.object(takeover, "process_info", side_effect=lambda pid: info if pid == 70001 else self.app), \
             patch.object(takeover, "process_tree", return_value={70001}), \
             patch.object(takeover, "held_sessions", return_value=sessions or {SESSION}):
            return takeover.close_plan(70001, SESSION)

    def test_cli_is_scoped_to_exact_writer(self):
        self.assertEqual(self.plan()[0], self.cli)

    def test_refuse_multiple_sessions(self):
        with self.assertRaises(takeover.TakeoverError):
            self.plan(sessions={SESSION, OTHER})

    def test_refuse_unrecognized_process(self):
        for change in ({"exe": "/test/python3"}, {"uid": os.getuid() + 1}):
            with self.assertRaises(takeover.TakeoverError):
                self.plan({**self.cli, **change})

    def test_refuse_shared_daemon(self):
        with self.assertRaises(takeover.TakeoverError):
            self.plan({**self.cli, "argv": ["codex", "app-server", "--managed-daemon"]})

    def test_desktop_parent_only_when_one_session(self):
        self.assertEqual(self.plan({**self.cli, "argv": ["codex", "app-server"]})[0], self.app)
        self.app["exe"] = "/test/unrelated-app"
        with self.assertRaises(takeover.TakeoverError):
            self.plan({**self.cli, "argv": ["codex", "app-server"]})

    def test_ambiguous_lock_owner(self):
        for holders in ({-1}, {70001, 70002}):
            with patch.object(takeover, "owners", return_value=holders), self.assertRaises(takeover.TakeoverError):
                takeover.close_session(SESSION)


@unittest.skipUnless(sys.platform == "linux" and hasattr(os, "pidfd_open"), "Linux kernel lock tests")
class KernelTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "thread-writer-locks").mkdir()
        self.env = patch.dict(os.environ, {"CODEX_HOME": str(self.root)})
        self.env.start()
        self.children = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
            child.communicate(timeout=5)
        self.env.stop()
        self.tmp.cleanup()

    def holder(self, session):
        path = self.root / "thread-writer-locks" / f"{session}.lock"
        child = subprocess.Popen([
            sys.executable, "-c",
            "import fcntl,sys; f=open(sys.argv[1],'a'); fcntl.flock(f,fcntl.LOCK_EX); print('ready',flush=True); sys.stdin.read()",
            str(path),
        ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(child)
        self.assertEqual(child.stdout.readline().strip(), "ready")
        return child, path

    def test_real_owner_and_refusal_of_non_codex(self):
        child, path = self.holder(SESSION)
        self.assertEqual(takeover.owners(path), {child.pid})
        self.assertEqual(takeover.held_sessions({child.pid}), {SESSION})
        with self.assertRaises(takeover.TakeoverError):
            takeover.close_session(SESSION)
        self.assertIsNone(child.poll())

    def test_signal_only_fixture_and_leave_lockfile_and_other_session(self):
        child, path = self.holder(SESSION)
        other, _ = self.holder(OTHER)
        verified = takeover.process_info(child.pid)
        # Only process classification is mocked. Kernel ownership, pidfd signal,
        # bounded wait, and release detection are exercised on our own fixture.
        with patch.object(takeover, "close_plan", return_value=(verified, {child.pid})):
            takeover.close_session(SESSION)
        child.wait(timeout=5)
        self.assertEqual(child.returncode, -signal.SIGTERM)
        self.assertTrue(path.exists())  # no lock deletion
        self.assertFalse(takeover.owners(path))
        self.assertIsNone(other.poll())

    def test_revalidation_refuses_changed_identity(self):
        child, _ = self.holder(SESSION)
        verified = takeover.process_info(child.pid)
        changed = {**verified, "start": "changed"}
        with patch.object(takeover, "close_plan", side_effect=[(verified, {child.pid}), (changed, {child.pid})]), \
             patch.object(signal, "pidfd_send_signal") as send, self.assertRaises(takeover.TakeoverError):
            takeover.close_session(SESSION)
        send.assert_not_called()
        self.assertIsNone(child.poll())

    def test_no_owner_no_signal(self):
        with patch.object(signal, "pidfd_send_signal") as send:
            takeover.close_session(SESSION)
        send.assert_not_called()

    def test_timeout_never_escalates(self):
        child, path = self.holder(SESSION)
        verified = takeover.process_info(child.pid)
        with patch.object(takeover, "close_plan", return_value=(verified, {child.pid})), \
             patch.object(signal, "pidfd_send_signal") as send, \
             patch.object(takeover.time, "monotonic", side_effect=[0, 0, 9]), \
             patch.object(takeover.time, "sleep"), self.assertRaises(takeover.TakeoverError):
            takeover.close_session(SESSION)
        self.assertEqual(send.call_count, 1)
        self.assertEqual(send.call_args.args[1], signal.SIGTERM)
        self.assertTrue(path.exists())
        self.assertIsNone(child.poll())


@unittest.skipUnless(sys.platform == "linux" and os.environ.get("AGENT_SHELL_TEST_WORKSTATION_WRAPPER"), "Set AGENT_SHELL_TEST_WORKSTATION_WRAPPER for workstation tests")
class WrapperTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.wrapper = self.root / "codex_wrapper.sh"
        shutil.copyfile(os.environ["AGENT_SHELL_TEST_WORKSTATION_WRAPPER"], self.wrapper)
        self.stub = self.root / "native-codex"
        self.stub.write_text("#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n")
        self.stub.chmod(0o700)
        picker = self.root / "codex_session_tool.py"
        picker.write_text(
            "import sys\nfrom pathlib import Path\n"
            f"Path(sys.argv[sys.argv.index('--output')+1]).write_bytes({SESSION!r}.encode()+b'\\0'+"
            "str(Path.cwd()).encode()+b'\\0'+b'/test/rollout.jsonl\\0')\n"
        )
        picker.chmod(0o700)
        (self.root / "state_5.sqlite").touch()  # fake picker never reads it
        self.environment = dict(os.environ, CODEX_HOME=str(self.root), CODEX_SQLITE_HOME=str(self.root),
            CODEX_REAL_BIN=str(self.stub), AGENT_SHELL_INSTALL_ROOT=str(ROOT / "bin"),
            AGENT_SHELL_CODEX_HISTORY_MODE="", AGENT_SHELL_ACCOUNT="", CODEX_RESUME_PICKER_ENABLE_NATIVE="1",
            CODEX_RESUME_PICKER_ENABLE_WSL="1", CODEX_STARTUP_ATTEMPTS="1")

    def tearDown(self):
        self.tmp.cleanup()

    def run_wrapper(self, *args):
        return subprocess.run(["bash", str(self.wrapper), *args], env=self.environment, cwd=self.root,
            text=True, capture_output=True, timeout=10)

    def test_picker_and_bare_codex_alias(self):
        for mode in ("codex", "codexr"):
            for flag in takeover.CLOSE_FLAGS:
                result = self.run_wrapper(mode, flag)
                self.assertEqual(result.returncode, 0, result.stderr)
                args = json.loads(result.stdout)
                self.assertIn(SESSION, args)
                self.assertIn("resume", args)
                self.assertNotIn(flag, args)

    def test_explicit_resume_and_prompt(self):
        result = self.run_wrapper("codex", "--close-other", "resume", SESSION, "literal --close-other text")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)[-1], "literal --close-other text")

    def test_resume_kill_and_inspection(self):
        result = self.run_wrapper("codex", "resume", "--kill", SESSION)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("--kill", json.loads(result.stdout))
        for args in (("codexr", "--where"), ("codex", "resume", "--where", SESSION)):
            result = self.run_wrapper(*args)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('No live writer lock', result.stdout)
        result = self.run_wrapper("codexr", "--where", "--kill")
        self.assertEqual(result.returncode, 2)

    def test_policy_loads_ordinary_account_without_cached_daemon(self):
        result = self.run_wrapper("codex")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--no-daemon", json.loads(result.stdout))
        self.environment['AGENT_SHELL_CODEX_DAEMON'] = 'on'
        result = self.run_wrapper("codex")
        self.assertNotIn("--no-daemon", json.loads(result.stdout))

    def test_move_refuses_ambiguous_takeover_before_changing_history(self):
        for args in (("/old", "/new"), ("--no-resume", "--latest", "/old", "/new")):
            result = self.run_wrapper('codexmv', '--kill', *args)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn('Nothing changed', result.stderr)

    def test_move_latest_dispatch_uses_one_uuid_and_keeps_rollback(self):
        shutil.copyfile(ROOT / 'contrib/workstation/codex_session_tool.py', self.root / 'codex_session_tool.py')
        db = self.root / 'state_5.sqlite'
        old, new = self.root / 'old', self.root / 'new'
        old.mkdir(); new.mkdir()
        with sqlite3.connect(db) as c:
            c.execute('CREATE TABLE threads(id TEXT,cwd TEXT,recency_at_ms INTEGER,updated_at_ms INTEGER,updated_at INTEGER)')
            c.execute('INSERT INTO threads VALUES(?,?,2,0,0)', (SESSION, str(old)))
        result = self.run_wrapper('codexmv', '--kill', '--latest', str(old), str(new))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(SESSION, json.loads(result.stdout.splitlines()[-1]))
        self.assertEqual(result.stderr.count('no live writer lock'), 1)
        with sqlite3.connect(db) as c:
            self.assertEqual(c.execute('SELECT cwd FROM threads').fetchone(), (str(new),))
        self.assertEqual(len(list((self.root / 'backups/codexmv').glob('*.json'))), 1)

    def test_original_force_flags_remain_native(self):
        result = self.run_wrapper("codex", "-f", "--force")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)[-2:], ["-f", "--force"])

    def test_refuse_unresolved_native_picker_and_automation(self):
        for args in (("codexr", "--close-other", "--native"), ("codex", "--close-other", "exec", "hello")):
            result = self.run_wrapper(*args)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertFalse(result.stdout)


if __name__ == "__main__":
    unittest.main()
