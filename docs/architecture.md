# Architecture and safety

## Isolation model

AgentShell does not change the OS user, `HOME`, or `USERPROFILE`, and does not create a container. It exports provider-specific state roots into one child process:

| Provider | Isolated variable | Profile location |
|---|---|---|
| Codex | `CODEX_HOME`, `CODEX_SQLITE_HOME` | account state plus a private/shared history view |
| Claude Code | `CLAUDE_CONFIG_DIR` | `claude-home/` |
| Gemini CLI | `GEMINI_CLI_HOME` | `gemini-home/` |
| Copilot CLI | `COPILOT_HOME`, `COPILOT_CACHE_HOME` | `copilot-home/`, `cache/copilot/` |

By default this gives each profile separate credentials, sessions, history, and provider state while preserving `PWD`, normal PATH entries, files, Git worktrees, Conda environments, and host tools. Codex history can then be shared explicitly.

Codex has a deliberate split:

- `codex-home/` is the private-mode account state and the migration source for profiles created by older AgentShell versions.
- In `private` mode, `CODEX_HOME` and `CODEX_SQLITE_HOME` both use that profile-local tree.
- In `shared` mode, `CODEX_SQLITE_HOME` uses the shared base index and `CODEX_HOME` uses a generated `codex-shared-home/` view. It owns a regular, profile-private `auth.json` so login/logout remains correct, while `sessions`, `archived_sessions`, `session_index.jsonl`, shell snapshots, attachments, generated images, and writer locks resolve to one coherent shared history tree.

Sharing only SQLite is insufficient for current paginated Codex histories. A resumed rollout can contain an immutable `history_base` reference, and Codex resolves that source ID by scanning `CODEX_HOME/sessions`. If the index and rollout tree point at different roots, the picker can find a thread but resume fails with `invalid paginated history lineage ... missing source rollout`.

```bash
agent-profile history lab private
agent-profile history personal shared
```

Shared history allows accounts to discover and resume the same indexed sessions. It also means a lab or company profile can see local titles/previews and rollout paths from that shared history, so private mode is the safer default.

Older AgentShell versions wrote a small number of rollouts into profile-local trees even when SQLite was shared. AgentShell 0.3 resolves a credential-isolated history view over the selected legacy tree instead of moving or rewriting those rollouts. New shared-mode sessions use the common tree. Cross-tree lineage should be recovered only after confirming that every source rollout is inactive; AgentShell never rewrites rollout JSONL or live SQLite state.

The default data roots are platform-specific but contain the same profile layout:

| Platform | AgentShell data root | Default shared Codex SQLite root |
|---|---|---|
| Bash | `${XDG_DATA_HOME:-$HOME/.local/share}/agentshell` | `$HOME/.codex` |
| Windows PowerShell | `%LOCALAPPDATA%\AgentShell` | `$HOME\.codex` |

`AGENT_SHELL_HOME` can select a different AgentShell data root when required.

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

The Bash installer adds a guarded source line to `.bashrc`; the Windows installer backs up the active Windows PowerShell profile and adds one marked, guarded dot-source block. Both integrations intercept only a leading AgentShell `--account` or `--project` option. An ordinary `codex`, `codexr`, or `codexmv` invocation is passed to the pre-existing command path.

`agentshell ACCOUNT` starts a child Bash or PowerShell process with the selected profile environment. A child process cannot mutate its parent, so leaving it with `exit` restores the ordinary terminal environment. The child's working directory is the caller's current real directory.

## Why not change HOME or USERPROFILE

Changing `HOME` or `USERPROFILE` would also hide shell configuration, package managers, SSH keys, GitHub CLI state, Conda, NVM, and many unrelated tools. Provider-specific state variables give the requested account separation without constructing a fragile artificial workstation.

## Why not Docker

A container is useful for OS dependency and filesystem isolation, but it adds bind mounts, UID mapping, CLI installation, browser-login forwarding, host-tool bridges, and credential handling. It is unnecessary when the goal is simply separate provider accounts operating on the same trusted folder.
