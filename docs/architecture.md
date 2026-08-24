# Architecture and safety

## Isolation model

AgentShell does not change the Unix user or `HOME`, and does not create a container. It exports provider-specific state roots into one child process:

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

## What is shared

On first creation, AgentShell may inherit authored configuration from the user's default provider directories:

- Codex: a private copy of `config.toml`, excluding `sqlite_home`, plus links to authored `AGENTS.md`, skills, plugins, and rules.
- Claude, Gemini, and Copilot: links only to known settings/customization paths when present.

It never seeds known credential or session files such as Codex `auth.json`, Gemini OAuth files, Copilot `config.json`, or provider histories. Shared Codex history is an explicit runtime SQLite selection, not a copied credential.

The linked customization folders are shared by design. This avoids duplicating tool installations and personal skills, but a change to a shared skill is visible to every profile. Profiles are not a security boundary because they all run as the same OS user.

## Inherited environment credentials

An exported API token normally overrides browser login state. AgentShell clears common inherited provider credential variables before launching a profile. Add account-specific variables to the profile's private `env.sh` only when a provider cannot use browser login.

To deliberately preserve the parent environment:

```bash
AGENT_SHELL_PRESERVE_AUTH_ENV=1 codex --account lab
```

That option reduces login isolation and should be used knowingly.

## Why not change HOME

Changing `HOME` would also hide shell configuration, package managers, SSH keys, GitHub CLI state, Conda, NVM, and many unrelated tools. Provider-specific state variables give the requested account separation without constructing a fragile artificial workstation.

## Why not Docker

A container is useful for OS dependency and filesystem isolation, but it adds bind mounts, UID mapping, CLI installation, browser-login forwarding, host-tool bridges, and credential handling. It is unnecessary when the goal is simply separate provider accounts operating on the same trusted folder.
