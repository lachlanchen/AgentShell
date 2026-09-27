# Find or close another opening before resuming (Linux)

## Commands

The optional workstation wrapper reserves `--where` for inspection and
`--kill`, `--close-other`, and `--as-close-other` for graceful takeover.
`--where` never starts a session or sends a signal. The three takeover options
They mean the same thing. Neither is forwarded to native Codex.
Native `-f` and `--force` retain their existing behavior; notably,
Codex already uses `--force` for deletion, so AgentShell must not redefine it.

```bash
# Select a session in the usual workstation picker, then take it over.
codexr --close-other

# The bare codex form opens that same picker.
codex --close-other

# Resume a known session directly.
codex --as-close-other resume SESSION_UUID
codexr --close-other SESSION_UUID

# Account selection still comes first.
codexr --account personal --close-other

# Find its current process, parent, directory and terminal without stopping it.
codexr --where
codexr --where SESSION_UUID

# Short alias requested for the same graceful takeover.
codexr --kill
codexr --account company --kill SESSION_UUID
codex resume --kill SESSION_UUID

# Migrate and resume the newest session; refuse other live migration targets.
codexmv --kill --latest /old/project /new/project
```

The private option must come before native options/subcommands, and after a
leading AgentShell account selector if present. Quoted prompts and native
option values are not searched for or stripped of these words. Ordinary
commands without the option are unchanged.

This feature is Linux-only (including WSL with a supporting kernel and Python).
It needs Python's `pidfd_open` and `pidfd_send_signal`. It is not a Windows
process-termination feature.

## What it closes

The picker first resolves one exact session UUID. After account/history-view
selection and before the native launch, the helper:

1. Finds the session's writer-lock inode through the active `CODEX_HOME`.
2. Reads its actual owner from the kernel's `/proc/locks`, not a guessed PID
   or a lock-file timestamp.
3. Verifies that the owner is a same-user Codex process holding only that
   session. For the ChatGPT desktop app, it checks the parent and its process
   tree for other held sessions.
4. Rechecks identity and ownership, then uses a PID file descriptor to send
   SIGTERM to that CLI or desktop app. PID reuse cannot redirect the signal.
5. Waits up to eight seconds for the writer lock to be released before resuming.

Using this option authorizes interrupting the selected session's other opening.
If that opening is in ChatGPT desktop, the whole matching desktop app instance
closes, not just a visual tab. The helper refuses if it detects another session
held by that instance. Other account apps and terminals are left alone.

If the session has no other opening, the helper continues without signaling
anything. Lock files, rollouts, SQLite files, account credentials and history
are never removed or rewritten by the takeover helper.

## Refusal is deliberate

There is no SIGKILL escalation, process-name-wide kill, or lock-file deletion.
These cases stop with a diagnostic instead of guessing:

- A managed/shared daemon owns the session.
- The process tree holds other session writer locks.
- Ownership changed, is ambiguous, cannot be inspected, or is not a verified
  same-user Codex/ChatGPT process.
- A remote endpoint is requested.
- The target is an unresolved session name, native picker, or `--last`.
- Unknown native flags make argument parsing ambiguous.

Use the regular workstation picker or an explicit UUID for takeover.
Without the workstation picker, AgentShell's native dispatcher supports
`agent-codexr --account ACCOUNT --close-other SESSION_UUID`.
`codexmv --kill` requires `--latest`, refuses `--no-resume` and `--native`, and
checks all migration targets before closing only the newest target's owner.
If another migration target is active it stops without changing anything.
The existing migration helper retains its private rollback journal. Its
metadata migration is separate from takeover; the takeover helper only reads
the database. If the newest target changes during migration it refuses to
close an additional process or resume a different target automatically.
Requests involving `fork`, automation or deletion are not takeovers.
Help/version invocations never close anything.

## Installation and workstation integration

`install.sh` installs `bin/codex_takeover.py` next to `codex-startup`.
The startup helper consumes the private flag only for an explicit request.
Its existing socket-length fallback and bounded startup retries remain separate.

On lachlanserver, `~/scripts/codex_wrapper.sh` consumes the leading private
option and forwards it to `codex-startup` only after the usual picker returns
the selected UUID. Existing terminals already using that wrapper pick up the
change on their next command; no desktop logout is needed.

For another custom workstation wrapper, preserve this order:
parse the leading private option, select one session, prepare its account/history
view, then call:

```bash
python3 "$HOME/.local/lib/agentshell/codex-startup" \
  /absolute/path/to/native/codex --close-other resume SESSION_UUID
```

Do not export a persistent takeover environment variable or wrap the picker
in a process-killing loop.

## Validation

```bash
AGENT_SHELL_TEST_WORKSTATION_WRAPPER="$HOME/scripts/codex_wrapper.sh" \
  python3 -m unittest discover -s tests -p test_takeover.py -v
python3 -m unittest discover -s tests -p test_startup.py
bash tests/test.sh
git diff --check
```

Tests cover argument preservation, refusals, identity revalidation, real kernel
writer locks, PID-file-descriptor termination of disposable fixtures, timeout
without escalation, and the full workstation picker-to-startup dispatch using
a fake native executable. They never terminate real user Codex sessions.

Official native command reference:
[Codex developer commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli).

## Native task manager versus takeover

Codex 0.157.1 prints “Disconnected from this task. Any running work continues”
when detaching a daemon-backed view. `codex agents` lists native daemon tasks;
its `x` action stops the selected turn. Neither that message nor a file named
`UUID.lock` alone proves another terminal currently owns a conversation.
`--where` consults the live kernel lock, and can show a terminal such as
`/dev/pts/12` or a GUI/background process with no terminal.

`--kill` is a wrapper feature, not a new native Codex flag. It is opt-in on
each invocation. It does not replace `codex agents`, log out an account, kill
all Codex processes, or repair authentication. See
[ordinary login and stale backends](ordinary-login-and-daemons.md).
