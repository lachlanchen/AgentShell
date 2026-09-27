# Architecture and safety

## Isolation model

AgentShell does not change the OS user, `HOME`, or `USERPROFILE`, and does not create a container. It exports provider-specific state roots into the activated shell or a one-shot child process:

| Provider | Isolated variable | Profile location |
|---|---|---|
| Codex | `CODEX_HOME`, `CODEX_SQLITE_HOME` | account state plus a private/shared history view |
| Claude Code | `CLAUDE_CONFIG_DIR` | `claude-home/` |
| Gemini CLI | `GEMINI_CLI_HOME` | `gemini-home/` |
| Copilot CLI | `COPILOT_HOME`, `COPILOT_CACHE_HOME` | `copilot-home/`, `cache/copilot/` |

By default this gives each profile separate credentials and provider state while preserving `PWD`, normal PATH entries, files, Git worktrees, Conda environments, and host tools. New Codex profiles share the ordinary workstation history, so switching accounts retains native current-folder session discovery. Existing profiles keep their configured history mode; separate Codex history can be selected explicitly.

Codex has a deliberate split:

- `codex-home/` is the private-mode account state and the migration source for profiles created by older AgentShell versions.
- In `private` mode, `CODEX_HOME` and `CODEX_SQLITE_HOME` both use that profile-local tree.
- In `shared` mode, `CODEX_SQLITE_HOME` uses the shared base index and `CODEX_HOME` uses a generated `codex-shared-home/` view. It owns a regular, profile-private `auth.json` so login/logout remains correct, while `sessions`, `archived_sessions`, `session_index.jsonl`, shell snapshots, attachments, generated images, and writer locks resolve to one coherent shared history tree.

Sharing only SQLite is insufficient for current paginated Codex histories. A resumed rollout can contain an immutable `history_base` reference, and Codex resolves that source ID by scanning `CODEX_HOME/sessions`. If the index and rollout tree point at different roots, the picker can find a thread but resume fails with `invalid paginated history lineage ... missing source rollout`.

```bash
agent-profile history lab private
agent-profile history personal shared
```

Shared history allows accounts to discover and resume the same indexed sessions, including local titles/previews and rollout paths. It is the default for newly registered accounts. Select private mode when a profile should use a separate history store. Registration never resets an existing profile's choice, and missing or invalid legacy history settings continue to fall back to private mode.

Older AgentShell versions wrote a small number of rollouts into profile-local trees even when SQLite was shared. AgentShell 0.4 resolves a credential-isolated history view over the selected legacy tree instead of moving or rewriting those rollouts. New shared-mode sessions use the common tree. Cross-tree lineage should be recovered only after confirming that every source rollout is inactive; AgentShell never rewrites rollout JSONL or live SQLite state.

The default data roots are platform-specific but contain the same profile layout:

| Platform | AgentShell data root | Default shared Codex SQLite root |
|---|---|---|
| Bash | `${XDG_DATA_HOME:-$HOME/.local/share}/agentshell` | `$HOME/.codex` |
| Windows PowerShell | `%LOCALAPPDATA%\AgentShell` | `$HOME\.codex` |

`AGENT_SHELL_HOME` can select a different AgentShell data root when required. On
Linux, a `$HOME/.as` symlink that resolves to the default AgentShell data root
is also recognized as a short lexical alias without moving profile data. This
alone does **not** fix Codex 0.157's socket limit: Codex canonicalizes the home.
The Linux startup helper checks the resolved control-socket path and adds
`--no-daemon` to supported local interactive launches if it reaches 108 bytes.
Login, automation, explicitly remote launches and running sessions are unchanged.
`AGENT_SHELL_SHARED_CODEX_SQLITE_HOME` selects the shared base, and the rollout tree follows it by default. Set `AGENT_SHELL_SHARED_CODEX_HOME` only when the shared Codex files intentionally live at a different path.

## What is shared

On first creation, AgentShell may inherit authored configuration from the user's default provider directories:

- Codex on both platforms: a private copy of `config.toml`, excluding `sqlite_home`, plus links to authored `AGENTS.md`, skills, plugins, and rules when the host supports them. Windows uses hard links for files and junctions for directories.
- Claude, Gemini, and Copilot on Bash: links only to known settings/customization paths when present. Windows prepares isolated provider directories without copying ordinary provider credentials or settings.

It never seeds a new profile from the default Codex `auth.json`, Gemini OAuth files, or Copilot `config.json`. When an existing Codex profile first enters shared mode, AgentShell materializes that same profile's credential once into its private shared view; it never copies credentials from one named account into another. History paths are then linked separately to the selected common or legacy rollout tree.

Where the host supports the required links, customization folders are shared by design. This avoids duplicating tool installations and personal skills, but a change to a shared skill is visible to every profile. Profiles are not a security boundary because they all run as the same OS user.

## Inherited environment credentials

An exported API token normally overrides browser login state. AgentShell clears common inherited provider credential variables before launching a profile. Add account-specific variables only when a provider cannot use browser login: use the profile's private `env.sh` on Bash or `env.ps1` on Windows, never a public repository or shared shell profile.

To deliberately preserve the parent environment:

```bash
AGENT_SHELL_PRESERVE_AUTH_ENV=1 codex --account lab
```

Windows PowerShell equivalent:

```powershell
$env:AGENT_SHELL_PRESERVE_AUTH_ENV = '1'
codex --account lab
Remove-Item Env:AGENT_SHELL_PRESERVE_AUTH_ENV
```

That option reduces login isolation and should be used knowingly.

## Shell integration

`agentshell default` explicitly selects the ordinary Codex home; `deactivate`
restores the previous shell snapshot. The optional workstation wrapper selects
a fresh backend for supported local interactive commands to avoid retained
daemon identity after changing the default login. `AGENT_SHELL_CODEX_DAEMON`
selects `off`, `auto` (socket-length fallback), or `on` (native behavior).
This never moves credentials or stops an existing daemon.
See [the incident and tradeoff](ordinary-login-and-daemons.md).

The Bash installer adds a guarded source line to `.bashrc`; the Windows installer backs up the active Windows PowerShell profile and adds one marked, guarded dot-source block. Both integrations intercept only a leading AgentShell `--account` or `--project` option. An ordinary `codex`, `codexr`, or `codexmv` invocation is passed to the pre-existing command path.

With the integration sourced, `agentshell ACCOUNT` (or `agentshell activate ACCOUNT`) changes the current shell's account without another Bash/PowerShell process. Repeated switches replace the account instead of stacking shells. `agentshell deactivate` restores the pre-activation values, including inherited credentials; only variables owned by activation are restored, and subsequent user changes such as Conda's PATH are retained. CWD and the OS home identity stay unchanged. Reloading the integration preserves the saved environment.

Bash prepares an exported-environment delta in a child, sends NUL-delimited records, validates them, and applies scalar values without `eval`. A completion marker prevents partial or failed preparation from changing the caller. PowerShell applies profile setup with an environment snapshot and restores the previous environment on failure. Neither implementation stores credentials on disk for deactivation.

One-shot `agentshell ACCOUNT -- COMMAND` still runs in a child and leaves the caller's account unchanged. Without shell integration, the standalone executable retains its child-shell behavior; `command agentshell ACCOUNT` deliberately selects that behavior on Bash. Previously nested shells cannot be unwound automatically without exiting those processes. Sourcing the new integration prevents further nesting, but deactivation can only restore the environment that existed when this integration first activated.

## Why not change HOME or USERPROFILE

Changing `HOME` or `USERPROFILE` would also hide shell configuration, package managers, SSH keys, GitHub CLI state, Conda, NVM, and many unrelated tools. Provider-specific state variables give the requested account separation without constructing a fragile artificial workstation.

## Why not Docker

A container is useful for OS dependency and filesystem isolation, but it adds bind mounts, UID mapping, CLI installation, browser-login forwarding, host-tool bridges, and credential handling. It is unnecessary when the goal is simply separate provider accounts operating on the same trusted folder.
