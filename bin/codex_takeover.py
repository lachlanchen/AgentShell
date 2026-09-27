"""Explicit, session-scoped Linux takeover for AgentShell's Codex launchers."""

import os
from pathlib import Path
import re
import signal
import sqlite3
import sys
import time


CLOSE_FLAGS = {"--kill", "--close-other", "--as-close-other"}
INSPECT_FLAGS = {"--where"}
PRIVATE_FLAGS = CLOSE_FLAGS | INSPECT_FLAGS
UUID = re.compile(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}")
VALUE_OPTIONS = {
    "-c", "--config", "--enable", "--disable", "-m", "--model",
    "-p", "--profile", "-s", "--sandbox", "-a", "--ask-for-approval",
    "-C", "--cd", "--add-dir", "-i", "--image", "--local-provider",
}
FLAG_OPTIONS = {
    "--strict-config", "--full-auto", "--approve-for-me", "--oss",
    "--dangerously-bypass-approvals-and-sandbox", "--dangerously-bypass-hook-trust",
    "--no-alt-screen", "--search", "--all", "--include-non-interactive", "--no-daemon",
}


class TakeoverError(RuntimeError):
    pass


def requested(command):
    return (
        len(command) > 1 and command[1] in PRIVATE_FLAGS
        or len(command) > 2 and command[1] == "resume" and command[2] in PRIVATE_FLAGS
    )


def parse_command(command):
    """Consume only leading wrapper flags, never a flag-looking prompt/value."""
    clean = list(command)
    index = 2 if clean[1:2] == ["resume"] else 1
    while len(clean) > index and clean[index] in PRIVATE_FLAGS:
        del clean[index]
    positionals = []
    i = 1
    help_requested = False
    while i < len(clean):
        arg = clean[i]
        option, separator, value = arg.partition("=")
        if arg == "--":
            positionals.extend(clean[i + 1:])
            break
        if option in {"--remote", "--remote-auth-token-env"}:
            raise TakeoverError("--close-other is local-only; remote endpoints are not supported.")
        if option in VALUE_OPTIONS:
            if separator:
                if not value:
                    raise TakeoverError(f"{option} requires a value.")
                i += 1
            else:
                if i + 1 >= len(clean):
                    raise TakeoverError(f"{option} requires a value.")
                i += 2
            continue
        if arg in {"-h", "--help", "-V", "--version"}:
            help_requested = True
        elif arg in FLAG_OPTIONS:
            pass
        elif arg.startswith("-"):
            raise TakeoverError(f"Cannot safely resolve {arg} for takeover; choose a session in codexr --close-other or supply its UUID.")
        else:
            positionals.append(arg)
        i += 1
    if help_requested:
        return clean, None
    if not 2 <= len(positionals) <= 3 or positionals[0] != "resume" or not UUID.fullmatch(positionals[1]):
        raise TakeoverError("Takeover requires one exact resume UUID. Use codexr --close-other to select it, or codex --close-other resume UUID.")
    return clean, positionals[1].lower()


def lock_records():
    records = []
    for line in Path("/proc/locks").read_text().splitlines():
        fields = line.split()
        if len(fields) < 6 or fields[1] == "->" or fields[3] != "WRITE":
            continue
        major, minor, inode = fields[5].split(":")
        records.append((int(fields[4]), os.makedev(int(major, 16), int(minor, 16)), int(inode)))
    return records


def owners(path, records=None):
    try:
        stat = path.stat()
    except FileNotFoundError:
        return set()
    records = lock_records() if records is None else records
    return {pid for pid, dev, inode in records if dev == stat.st_dev and inode == stat.st_ino}


def process_info(pid):
    root = Path("/proc") / str(pid)
    stat = (root / "stat").read_text().rsplit(") ", 1)[1].split()
    return {
        "pid": pid, "ppid": int(stat[1]), "start": stat[19],
        "uid": root.stat().st_uid, "exe": os.readlink(root / "exe"),
        "argv": (root / "cmdline").read_bytes().decode(errors="replace").rstrip("\0").split("\0"),
    }


def process_tree(pid):
    parents = {}
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if entry.stat().st_uid != os.getuid():
                continue
            fields = (entry / "stat").read_text().rsplit(") ", 1)[1].split()
            parents[int(entry.name)] = int(fields[1])
        except (FileNotFoundError, ProcessLookupError):
            continue
    result = {pid}
    while True:
        expanded = result | {child for child, parent in parents.items() if parent in result}
        if expanded == result:
            return result
        result = expanded


def held_sessions(pids):
    records = lock_records()
    held = {(pid, dev, inode) for pid, dev, inode in records if pid in pids}
    sessions = set()
    for pid in pids:
        fd_root = Path("/proc") / str(pid) / "fd"
        try:
            descriptors = list(fd_root.iterdir())
        except FileNotFoundError:
            continue
        for descriptor in descriptors:
            try:
                link = Path(os.readlink(descriptor))
                if link.parent.name != "thread-writer-locks" or link.suffix != ".lock" or not UUID.fullmatch(link.stem):
                    continue
                stat = descriptor.stat()
                if (pid, stat.st_dev, stat.st_ino) in held:
                    sessions.add(link.stem.lower())
            except (FileNotFoundError, ProcessLookupError):
                continue
    return sessions


def close_plan(owner, session):
    info = process_info(owner)
    if info["uid"] != os.getuid() or Path(info["exe"]).name != "codex":
        raise TakeoverError(f"Lock holder PID {owner} is not a verified Codex process owned by you; nothing closed.")
    target = info
    if "app-server" in info["argv"]:
        if "--managed-daemon" in info["argv"]:
            raise TakeoverError("The session is held by a shared daemon. Close it in its app/client; takeover will not stop a shared daemon.")
        parent = process_info(info["ppid"])
        if parent["uid"] != os.getuid() or Path(parent["exe"]).name != "ChatGPT":
            raise TakeoverError("The app-server has no verified ChatGPT desktop parent; nothing closed.")
        target = parent
    pids = process_tree(target["pid"])
    if held_sessions(pids) != {session}:
        raise TakeoverError("That process/app holds other sessions, or its locks changed; nothing closed. Close only this conversation in the other app.")
    return target, pids


def close_session(session, timeout=8.0):
    if sys.platform != "linux" or not hasattr(os, "pidfd_open") or not hasattr(signal, "pidfd_send_signal"):
        raise TakeoverError("--close-other requires Linux with pidfd support; nothing closed.")
    # Follow the selected account's history view, including its writer-lock link.
    state_home = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
    lock_path = state_home / "thread-writer-locks" / f"{session}.lock"
    holders = owners(lock_path)
    if not holders:
        print(f"AgentShell: {session} has no live writer lock; no process was stopped.", file=sys.stderr)
        return
    if len(holders) != 1 or next(iter(holders)) <= 0:
        raise TakeoverError("The writer lock has an ambiguous owner; nothing closed.")
    owner = next(iter(holders))
    target, _ = close_plan(owner, session)
    if target["pid"] in {os.getpid(), os.getppid()}:
        raise TakeoverError("Refusing to terminate the current launcher.")
    descriptor = os.pidfd_open(target["pid"], 0)
    try:
        current, _ = close_plan(owner, session)
        if owners(lock_path) != {owner} or current != target:
            raise TakeoverError("Process or lock ownership changed; nothing closed. Retry after inspecting the other opening.")
        print(f"AgentShell: closing {Path(target['exe']).name} PID {target['pid']} for session {session} (SIGTERM only).", file=sys.stderr)
        signal.pidfd_send_signal(descriptor, signal.SIGTERM)
    finally:
        os.close(descriptor)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        remaining = owners(lock_path)
        if not remaining:
            print("AgentShell: session lock released; continuing resume.", file=sys.stderr)
            return
        if remaining != {owner}:
            raise TakeoverError("Another process acquired the session; no additional process was stopped.")
        time.sleep(0.1)
    raise TakeoverError("The other opening did not release its lock within 8 seconds. No forced kill or lock deletion was attempted.")


def describe_session(session):
    """Read kernel ownership only; never acquire, remove or repair a lock."""
    if sys.platform != "linux":
        raise TakeoverError("--where currently requires Linux /proc; nothing changed.")
    home = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
    path = home / "thread-writer-locks" / f"{session}.lock"
    print(f"Session: {session}\nHistory home: {home}\nWriter lock: {path.resolve()}")
    holders = owners(path)
    if not holders:
        print("No live writer lock found. A disconnected message alone does not mean another terminal owns this session.")
    for pid in sorted(holders):
        if pid <= 0:
            print("Owner could not be identified safely.")
            continue
        try:
            info = process_info(pid)
            root = Path('/proc') / str(pid)
            print(f"Owner PID: {pid}; parent PID: {info['ppid']}; executable: {info['exe']}")
            print(f"Directory: {os.readlink(root / 'cwd')}; terminal: {os.readlink(root / 'fd/0')}")
            target, _ = close_plan(pid, session)
            print(f"--kill can gracefully close PID {target['pid']} before resuming.")
        except (OSError, TakeoverError) as error:
            print(f"Automatic close unavailable: {error}")
    print("Native background tasks: codex agents (x stops a selected turn; it is not a session-delete command).")


def prepare_move(database, old_path):
    """Close only the newest migration target; refuse other live targets."""
    old = os.path.realpath(os.path.expanduser(old_path))
    if old == os.path.sep:
        raise TakeoverError("Refusing a filesystem-root migration.")
    pattern = (old + os.sep).replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%'
    uri = Path(database).resolve().as_uri() + '?mode=ro'
    with sqlite3.connect(uri, uri=True) as connection:
        rows = connection.execute("""
            SELECT id FROM threads WHERE cwd = ? OR cwd LIKE ? ESCAPE '\\'
            ORDER BY COALESCE(NULLIF(recency_at_ms,0),NULLIF(updated_at_ms,0),updated_at*1000) DESC, id DESC
        """, (old, pattern)).fetchall()
    if not rows:
        raise TakeoverError("No sessions found under the migration source; nothing stopped.")
    home = Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex')))
    for (session,) in rows:
        if not UUID.fullmatch(session):
            raise TakeoverError("Invalid session ID in migration selection; nothing stopped.")
    for (session,) in rows[1:]:
        if owners(home / 'thread-writer-locks' / f'{session}.lock'):
            raise TakeoverError(f"Another migration target {session} is active. Close it explicitly first; nothing stopped.")
    session = rows[0][0]
    close_session(session)
    return session


def prepare_command(command):
    if not requested(command):
        return command
    clean, session = parse_command(command)
    start = 2 if command[1:2] == ["resume"] else 1
    options = []
    while start < len(command) and command[start] in PRIVATE_FLAGS:
        options.append(command[start])
        start += 1
    if INSPECT_FLAGS.intersection(options):
        if CLOSE_FLAGS.intersection(options):
            raise TakeoverError("Use --where or --kill separately; inspection never stops a process.")
        if session is not None:
            describe_session(session)
            return None
    if session is not None:
        close_session(session)
    return clean


if __name__ == '__main__':
    try:
        if len(sys.argv) == 4 and sys.argv[1] == 'prepare-move':
            print(prepare_move(sys.argv[2], sys.argv[3]))
        else:
            raise TakeoverError('Use codexr --where, codexr --kill, or codexmv --kill --latest OLD NEW.')
    except (OSError, RuntimeError, sqlite3.Error) as error:
        print(f'AgentShell takeover: {error}', file=sys.stderr)
        raise SystemExit(2)
