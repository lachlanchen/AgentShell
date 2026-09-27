# Optional Linux/WSL workstation picker

These are the reusable Bash wrapper and Python session picker used with
AgentShell on the documented workstation. They are optional; `install.sh`
does not replace an existing custom Codex wrapper automatically.

- `codex_wrapper.sh`: native command dispatch, current-folder picker, explicit
  account history-view selection, fork, move, `--where` and `--kill`.
- `codex_session_tool.py`: read-only SQLite session selection, saved names,
  and explicit `codexmv` metadata migration with a private rollback journal.

Install AgentShell first, then install these **only if you want this wrapper**:

```bash
mkdir -p "$HOME/scripts"
# Back up existing files first if they exist.
install -m 755 contrib/workstation/codex_wrapper.sh "$HOME/scripts/codex_wrapper.sh"
install -m 755 contrib/workstation/codex_session_tool.py "$HOME/scripts/codex_session_tool.py"
source "$HOME/scripts/sourced_agent_shell.sh"
codexr
```

It enforces the workstation's `danger-full-access` sandbox and `never`
approval defaults. It defaults supported local interactive commands to native
`--no-daemon`; use `AGENT_SHELL_CODEX_DAEMON=on` for native daemon behavior.
These policies are not universal AgentShell installation defaults.

The picker expects the current `state_5.sqlite` thread schema. Native flags,
prompts, and unknown flags retain native dispatch; private wrapper flags must
precede the session UUID. `codexr --kill` selects one session, not every session
under a path. `codexmv --kill --latest OLD NEW` refuses other live migration
targets. [Safety and commands](../../docs/session-takeover.md).
