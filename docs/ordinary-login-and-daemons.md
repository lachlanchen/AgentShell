# Ordinary Codex, account switching, and stale backends

## Commands

```bash
source "$HOME/scripts/sourced_agent_shell.sh"

# Explicitly return to the ordinary ~/.codex login in this terminal.
agentshell default
codex login status
codexr

# Select another account in the same terminal, preserving cwd and Conda.
agentshell company
codexr

# Restore the environment from before this shell's first activation.
agentshell deactivate
```

In Windows PowerShell, reload with `. $PROFILE`; `agentshell default` has
the same meaning. The default home honors `AGENT_SHELL_BASE_CODEX_HOME`
when explicitly configured. It does not create a named profile called default.

`deactivate` restores the saved environment. A shell inherited from an older
nested AgentShell may have inherited an account *before* that snapshot existed.
`default` is therefore explicit: restore tracked changes, clear account routing
and known inherited provider credential overrides when still inside a profile,
then select the ordinary Codex home. No auth files are copied, deleted, or
logged out. Existing shells and running agents are unaffected. Arbitrary
custom environment variables inherited before the snapshot cannot be recovered.

## Confirmed failure, 2026-09-27

A default-home conversation was running in a persistent Codex 0.157.1 backend.
The user logged out and logged in again. Its log then recorded **“Skipping auth
reload due to account id mismatch”**, followed by **“Your access token could
not be refreshed because you have since logged out or signed in to another
account.”** The backend retained the previous expected account while the
default auth file represented the newly selected account.

Both reported threads had already shut down when inspected; neither had a live
writer lock. A fresh backend using the unchanged default auth file passed
`account/read` and authenticated `account/rateLimits/read`. The existing CV
conversation then resumed and remained open during a TUI smoke check. No model
turn was submitted. These results identify stale backend identity in this
incident; they do not mean every authentication failure has that cause.

The separate repair on a Windows peer had previously installed current-shell
account switching and `--close-other` on the Linux workstation. Those changes
are retained. Credentials and private transcript excerpts are not published.

## Fresh backend policy

The optional workstation wrapper defaults new supported **local interactive**
launches to `AGENT_SHELL_CODEX_DAEMON=off`. The startup helper adds native
`--no-daemon`, so the new process reads the selected login instead of attaching
to a backend with stale account identity. This is a local compatibility policy,
not a patch to Codex's native daemon authentication implementation.

Existing daemons are not restarted or killed. `codex agents`, login/logout,
automation, explicitly remote commands, help/version and unknown native
arguments pass through. Detached work in existing daemons remains available.
New no-daemon CLI work does not have the daemon's “continue after closing the
view” lifecycle. Keep that terminal open if its work must continue.

```bash
# One launch with native background-server behavior:
AGENT_SHELL_CODEX_DAEMON=on codexr

# Previous behavior: only avoid daemon when an account socket path is too long.
AGENT_SHELL_CODEX_DAEMON=auto codexr

# Explicit fresh process; usable with the native CLI as well.
codex --no-daemon resume SESSION_UUID
```

Standalone AgentShell installations default to `auto`; the broader `off`
default belongs to the optional workstation wrapper. Unknown flags are not
guessed. If a new native option prevents automatic classification, use the
explicit `--no-daemon` flag. This workaround also avoids the previously
diagnosed account socket pathname limit, without moving live account homes.

If a fresh backend still reports invalid credentials, log in **only the intended
account**. Do not copy refresh tokens between profiles or repeatedly log all
accounts out. This repair did not require another login.

## Verification

- Read-only kernel owner inspection: real standalone CLI PID and terminal found.
- Disposable process tests: exact owner terminated, other owner preserved;
  ambiguous ownership and shared daemons refused; no lock deletion or SIGKILL.
- Native argv, prompt, and account isolation tests, including default return.
- Bash integration tests and Windows PowerShell 5.1 tests in isolated homes.
- Existing history resume smoke test, then only the test TUI was closed.

See [session inspection and takeover](session-takeover.md) for `--where` and
`--kill`. No public diagnostics should contain auth tokens, emails, or raw
session history.
