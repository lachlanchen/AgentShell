import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


LAUNCHER = Path(__file__).resolve().parents[1] / "bin" / "codex-startup"
LOADER = importlib.machinery.SourceFileLoader("codex_startup", str(LAUNCHER))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
startup = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(startup)
ERROR = (
    "Error: account/read failed during TUI bootstrap: account/read failed: "
    "workspace routing discovery timed out (code -32603)"
)
STUB = r'''
#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time
record = Path(os.environ["TEST_RECORD"])
count = len(record.read_text().splitlines()) if record.exists() else 0
with record.open("a") as stream:
    stream.write(json.dumps({"argv": sys.argv[1:], "cwd": os.getcwd(),
        "account": os.environ.get("AGENT_SHELL_ACCOUNT"),
        "home": os.environ.get("CODEX_HOME"),
        "stdin_tty": sys.stdin.isatty(), "stdout_tty": sys.stdout.isatty()}) + "\n")
mode = os.environ.get("TEST_MODE", "success")
if mode == "wait":
    print("ready", flush=True)
    time.sleep(30)
if mode == "stdin":
    print("input=" + input(), flush=True)
if mode != "success" and not (mode == "transient" and count > 0):
    print(os.environ["TEST_ERROR"], file=sys.stderr, flush=True)
    sys.exit(int(os.environ.get("TEST_EXIT", "1")))
'''


class ClassificationTests(unittest.TestCase):
    def test_long_profile_socket_uses_no_daemon(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            long_home = root / ("profile-" + "a" * 90)
            long_home.mkdir()
            alias = root / "s"
            alias.symlink_to(long_home, target_is_directory=True)
            with patch.dict(os.environ, {"AGENT_SHELL_ACCOUNT": "company", "CODEX_HOME": str(alias)}):
                with patch.object(sys, "platform", "linux"):
                    for args in ([], ["resume", "session-id", "--cd", "/a directory"], ["fork", "--last"]):
                        command = ["codex", *args]
                        self.assertEqual(startup.socket_safe_command(command), ["codex", "--no-daemon", *command[1:]])
                    for args in (["login"], ["exec", "hello"], ["--remote", "unix:///tmp/server"], ["--no-daemon", "resume"]):
                        self.assertEqual(startup.socket_safe_command(["codex", *args]), ["codex", *args])
                with patch.object(sys, "platform", "darwin"):
                    self.assertEqual(startup.socket_safe_command(["codex"]), ["codex"])
            with patch.dict(os.environ, {"AGENT_SHELL_ACCOUNT": "company", "CODEX_HOME": str(root)}):
                self.assertEqual(startup.socket_safe_command(["codex"]), ["codex"])
            with patch.dict(os.environ, {"AGENT_SHELL_ACCOUNT": "", "CODEX_HOME": str(alias)}):
                self.assertEqual(startup.socket_safe_command(["codex"]), ["codex"])

    def test_arguments(self):
        for arguments in (
            [], ["resume", "thread-id"], ["fork", "--last"],
            ["-s", "danger-full-access", "-a", "never", "resume", "thread-id"],
            ["-C", "/a directory", "-m", "model", "hello world"],
            ["--config=key=42", "--no-alt-screen"],
        ):
            with self.subTest(arguments=arguments):
                self.assertTrue(startup.interactive_arguments(arguments))
        for arguments in (
            ["exec", "a task"], ["-m", "model", "exec", "resume", "--last"],
            ["login"], ["app-server"], ["review"], ["--help"], ["--version"],
            ["--unknown-option"], ["--remote", "ws://localhost:1234"],
            ["--worktree"], ["-m"], ["queue", "thread-id", "task"],
        ):
            with self.subTest(arguments=arguments):
                self.assertFalse(startup.interactive_arguments(arguments))

    def test_exact_failure_only(self):
        self.assertTrue(startup.retryable(1, ERROR.encode() + b"\n", 16))
        self.assertFalse(startup.retryable(0, ERROR.encode(), 16))
        self.assertFalse(startup.retryable(130, ERROR.encode(), 16))
        self.assertFalse(startup.retryable(1, ERROR.encode(), 121))
        self.assertFalse(startup.retryable(1, b"transcript: " + ERROR.encode(), 16))
        self.assertFalse(startup.retryable(1, ERROR.encode() + b"\nanother error", 16))
        self.assertFalse(startup.retryable(1, b"Error: unauthorized (401)", 16))


@unittest.skipUnless(sys.platform == "linux", "Linux TTY guard")
class TerminalTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.stub = self.root / "codex"
        self.stub.write_text(STUB.lstrip())
        self.stub.chmod(0o700)
        self.record = self.root / "invocations.jsonl"
        self.environment = dict(os.environ, TERM="xterm-256color", TEST_ERROR=ERROR,
            TEST_RECORD=str(self.record), AGENT_SHELL_ACCOUNT="lab",
            CODEX_HOME=str(self.root / "lab-home"), CODEX_STARTUP_ATTEMPTS="3")

    def tearDown(self):
        self.directory.cleanup()

    def launch(self, arguments=(), mode="success", updates=None, cancel_on=None):
        environment = dict(self.environment, TEST_MODE=mode, **(updates or {}))
        master, slave = pty.openpty()
        output = bytearray()
        process = subprocess.Popen(
            [sys.executable, str(LAUNCHER), str(self.stub), *arguments],
            stdin=slave, stdout=slave, stderr=slave, env=environment,
            cwd=self.root, start_new_session=True,
        )
        os.close(slave)
        deadline = time.monotonic() + 15
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.1)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    output.extend(chunk)
                    if cancel_on and cancel_on in output:
                        process.send_signal(signal.SIGINT)
                        cancel_on = None
                if process.poll() is not None and not ready:
                    break
            returncode = process.wait(timeout=2)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            os.close(master)
        rows = [json.loads(line) for line in self.record.read_text().splitlines()]
        return returncode, output.decode(errors="replace"), rows

    def test_success_and_arguments(self):
        arguments = ["resume", "a-thread-id", "--cd", "/a project", "prompt with spaces"]
        status, output, rows = self.launch(arguments)
        self.assertEqual(status, 0)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["argv"], arguments)
        self.assertTrue(rows[0]["stdin_tty"] and rows[0]["stdout_tty"])
        self.assertNotIn("Retry", output)

    def test_transient_preserves_account_and_session(self):
        status, output, rows = self.launch(["resume", "same-thread"], "transient")
        self.assertEqual(status, 0)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0], rows[1])
        self.assertEqual(rows[0]["account"], "lab")
        self.assertEqual(rows[0]["home"], str(self.root / "lab-home"))
        self.assertEqual(rows[0]["cwd"], str(self.root))
        self.assertIn("Retry 2/3", output)

    def test_bounded_failure(self):
        status, output, rows = self.launch(mode="failure")
        self.assertEqual(status, 1)
        self.assertEqual(len(rows), 3)
        self.assertEqual(output.count("Retry"), 2)

    def test_never_retry_exec_or_login_or_unknown_options(self):
        for arguments in (["exec", "resume", "id"], ["login"], ["--future-option"]):
            self.record.unlink(missing_ok=True)
            status, output, rows = self.launch(arguments, "failure")
            self.assertEqual(status, 1)
            self.assertEqual(len(rows), 1)
            self.assertNotIn("Retry", output)

    def test_no_retry_other_errors(self):
        status, output, rows = self.launch(mode="failure", updates={"TEST_ERROR": "Error: unauthorized"})
        self.assertEqual(status, 1)
        self.assertEqual(len(rows), 1)

    def test_disabled(self):
        status, output, rows = self.launch(mode="failure", updates={"CODEX_STARTUP_ATTEMPTS": "1"})
        self.assertEqual(status, 1)
        self.assertEqual(len(rows), 1)

    def test_ctrl_c_during_backoff(self):
        status, output, rows = self.launch(mode="failure", cancel_on=b"Retry 2/3")
        self.assertEqual(status, 130)
        self.assertEqual(len(rows), 1)

    def test_ctrl_c_during_child(self):
        status, output, rows = self.launch(mode="wait", cancel_on=b"ready")
        self.assertEqual(status, 130)
        self.assertEqual(len(rows), 1)

    def test_no_retry_on_success_even_with_error_text(self):
        status, output, rows = self.launch(mode="failure", updates={"TEST_EXIT": "0"})
        self.assertEqual(status, 0)
        self.assertEqual(len(rows), 1)

    def test_nonterminal_passthrough(self):
        result = subprocess.run([sys.executable, str(LAUNCHER), str(self.stub)],
            capture_output=True, env=dict(self.environment, TEST_MODE="failure"), timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(self.record.read_text().splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
