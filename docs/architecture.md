# Architecture and safety

## Isolation model

AgentShell does not change the OS user, `HOME`, or `USERPROFILE`, and does not create a container. It exports provider-specific state roots into one child process:

| Provider | Isolated variable | Profile location |
|---|---|---|
| Codex | `CODEX_HOME`, `CODEX_SQLITE_HOME` | `codex-home/` plus selected SQLite root |
| Claude Code | `CLAUDE_CONFIG_DIR` | `claude-home/` |
| Gemini CLI | `GEMINI_CLI_HOME` | `gemini-home/` |
| Copilot CLI | `COPILOT_HOME`, `COPILOT_CACHE_HOME` | `copilot-home/`, `cache/copilot/` |

By default this gives each profile separate credentials, sessions, history, and provider state while preserving `PWD`, normal PATH entries, files, Git worktrees, Conda environments, and host tools. Codex history can then be shared explicitly.

Codex has a deliberate split:

- `CODEX_HOME` always remains profile-local, so login credentials, logs, config, and newly written rollout files belong to that account profile.
- `CODEX_SQLITE_HOME` follows the profile's `private` or `shared` history mode.

The official Codex environment-variable reference defines `CODEX_SQLITE_HOME` separately for SQLite-backed state. AgentShell uses that public boundary rather than linking authentication files.

```bash
agent-profile history lab private
agent-profile history personal shared
```

Shared history allows accounts to discover and resume the same indexed sessions. It also means a lab or company profile can see local titles/previews from that shared index, so private mode is the safer default.

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

It never seeds known credential or session files such as Codex `auth.json`, Gemini OAuth files, Copilot `config.json`, or provider histories. Shared Codex history is an explicit runtime SQLite selection, not a copied credential.

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
