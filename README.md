[English](README.md) · [العربية](i18n/README.ar.md) · [Español](i18n/README.es.md) · [Français](i18n/README.fr.md) · [日本語](i18n/README.ja.md) · [한국어](i18n/README.ko.md) · [Tiếng Việt](i18n/README.vi.md) · [中文 (简体)](i18n/README.zh-Hans.md) · [中文（繁體）](i18n/README.zh-Hant.md) · [Deutsch](i18n/README.de.md) · [Русский](i18n/README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# AgentShell

*Named AI CLI accounts for separate terminals, sharing one real working tree.*

[![Test](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml/badge.svg)](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-22c55e.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Bash-dependency--light-4EAA25?logo=gnubash&logoColor=white)](bin/agentshell)
[![Windows PowerShell](https://img.shields.io/badge/Windows%20PowerShell-5.1-5391FE?logo=powershell&logoColor=white)](shell/agentshell.ps1)
[![Documentation](https://img.shields.io/badge/docs-complete%20tutorial-2563eb)](docs/tutorial.md)
[![LazyingArt](https://img.shields.io/badge/home-lazying.art-0EA5E9)](https://lazying.art)
[![GitHub Sponsors](https://img.shields.io/badge/sponsor-lachlanchen-EA4AAA?logo=githubsponsors)](https://github.com/sponsors/lachlanchen)

AgentShell lets personal, laboratory, and company terminals use different Codex logins without copying projects, changing OS users, or maintaining containers. Each process stays in the current directory while provider-supported environment variables route authentication and state into a named profile. Bash and Windows PowerShell are supported.

## Use in any terminal

On Bash:

```bash
source ~/.bashrc
agentshell personal
codexr
```

On Windows PowerShell:

```powershell
. $PROFILE
agentshell personal
codexr
```

It works from whichever directory that terminal is already using. Replace `personal` with `lab` or `company` when needed.

Only the first login needs two extra commands; these are identical in both shells:

```text
codex --account personal login
agent-profile history personal shared
```

Inside `agentshell personal`, plain `codex`, `codexr`, and `codexmv` all use that account. Run `exit` when finished.

| Donate | PayPal | Stripe |
| --- | --- | --- |
| [![Donate](https://img.shields.io/badge/Donate-LazyingArt-0EA5E9?style=for-the-badge&logo=kofi&logoColor=white)](https://chat.lazying.art/donate) | [![PayPal](https://img.shields.io/badge/PayPal-RongzhouChen-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/RongzhouChen) | [![Stripe](https://img.shields.io/badge/Stripe-Donate-635BFF?style=for-the-badge&logo=stripe&logoColor=white)](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400) |

## One folder, several identities

```text
                         same project folder
                       <project directory>
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
      terminal: personal   terminal: lab    terminal: company
              │                 │                 │
       personal login       lab login        company login
              └─────────────────┴─────────────────┘
                         shared real files
```

AgentShell is intentionally lighter than Docker. It separates application state for trusted accounts owned by one OS user; it is not a filesystem or OS security boundary.

## Why AgentShell

- **Independent authentication:** every label has its own Codex `auth.json` and provider state.
- **Optional shared history:** accounts may resume one coherent Codex index and rollout tree while credentials remain separate.
- **No workspace copies:** Git repositories, Conda environments, build tools, and files stay exactly where they are.
- **Native arguments preserved:** models, prompts, sandbox options, search, images, and future CLI flags pass through.
- **Fast workstation resume:** existing `codexr`, `/rename`, partial-path search, and `codexmv` workflows remain available.
- **Provider adapters:** Codex is fully integrated; Claude Code, Gemini CLI, and Copilot CLI receive named state roots.
- **Safe installation:** no root or administrator privileges; unrelated commands and profile data are never overwritten.

## Quick start

### Bash

```bash
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. "$HOME/.bashrc"

agent-profile create personal
codex --account personal login
codex --account personal
```

### Windows PowerShell

```powershell
git clone https://github.com/lachlanchen/AgentShell.git
Set-Location AgentShell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
. $PROFILE

agent-profile create personal
codex --account personal login
codex --account personal
```

For a remote/headless login:

```bash
codex --account personal login --device-auth
```

Read the [complete tutorial](docs/tutorial.md) for installation, browser login, account switching, shared/private history, resume, session migration, updates, and troubleshooting.

## Three ways to work

Run one account-aware command:

```bash
codex --account personal
codex --account lab -m gpt-5.6-sol "Review this repository"
codexr --account company --all
```

Dedicate a terminal to one account:

```text
cd /path/to/project                 # Bash
Set-Location C:\path\to\project    # Windows PowerShell
```

Then enter the account shell:

```bash
agentshell lab

# The prompt now starts with [agent:lab].
agentshell -v
codex
codexr
exit
```

Or use generated commands:

```bash
agent-personal-codex
agent-lab-codexr
agent-company-codexmv /old/path /new/path
```

The AgentShell `--account` option must appear first. Plain `codex`, `codexr`, and `codexmv` retain their existing behavior.

## Private credentials, selectable history

| History mode | Credentials | SQLite resume index | Rollout tree | Recommended use |
|---|---|---|---|---|
| `private` | Profile-local | Profile-local | Profile-local | Confidential lab/company separation |
| `shared` | Profile-local | Shared base index | Shared base tree | Resume the same workstation sessions from several accounts |

```bash
agent-profile history personal shared
agent-profile history company private
agentshell status personal
```

Codex documents `CODEX_HOME` as its state root and `CODEX_SQLITE_HOME` as the location for SQLite-backed state. AgentShell keeps account authentication under the profile while a generated shared-history view links only the history-bearing paths to the common Codex tree. This matters for current Codex releases because paginated sessions locate source rollouts through `CODEX_HOME/sessions`, not through SQLite alone.

### Sessions missing after switching accounts?

New accounts default to private history, so their picker does not show sessions from your ordinary Codex home. To locate saved sessions, run:

```bash
agent-profile sessions company
```

This read-only report lists the base, configured shared, and private account stores with rollout file counts, including archived files. Counts include agent threads and may differ from the picker. It does not read credentials or conversation contents. Run it separately in WSL and Windows to inspect each installation's stores.

To continue your existing workstation sessions using the company account's login:

```bash
agent-profile history company shared
agent-codex --account company resume --all
```

The selected account keeps its credentials; history is shared with other profiles that opt into the same store. Existing private sessions stay in their original directory and can be reached by switching back to `private`. Running Codex processes keep their current history route; launch a new account command after changing modes. Avoid manually setting `CODEX_HOME` to the base home when you want to retain the company login, because that also selects the base account's credentials.

## Account management

```bash
agent-profile create lab
agent-profile list
agent-profile show lab
agent-profile status lab codex
agent-profile login lab codex
agent-profile aliases lab

codex --account lab login status
codex --account lab logout
codex --account lab login
```

Inside Codex, `/status` remains the authoritative view of the authenticated identity and running session.

## Resume and migrate sessions

AgentShell preserves existing workstation `codexr` and `codexmv` wrappers. On Windows without a separate `codexr`, it falls back to `codex resume`; workstation-only picker flags and `codexmv` require those pre-existing wrappers.

```bash
# Exact current directory
codexr --account personal

# All directories or partial-path search
codexr --account personal --all
codexr --account personal --non-strict ProjectName

# Update stored cwd metadata after moving a project
codexmv --account personal /old/project/path /new/project/path
```

The move operation changes only indexed session metadata and writes a rollback journal. It does not move project files.

## Supported provider state

| Provider | Profile routing | Example |
|---|---|---|
| Codex | `CODEX_HOME`, `CODEX_SQLITE_HOME` | `codex --account lab` |
| Claude Code | `CLAUDE_CONFIG_DIR` | `claude --account lab` |
| Gemini CLI | `GEMINI_CLI_HOME` | `gemini --account personal` |
| GitHub Copilot CLI | `COPILOT_HOME`, `COPILOT_CACHE_HOME` | `copilot --account company` |

Provider details and limitations are documented in [docs/providers.md](docs/providers.md).

## Repository map

| Path | Purpose |
|---|---|
| [bin/agentshell](bin/agentshell) | Dependency-light profile runtime and command dispatcher |
| [bin/agentshell.ps1](bin/agentshell.ps1) | Windows PowerShell profile runtime and command dispatcher |
| [shell/agentshell.bash](shell/agentshell.bash) | Opt-in Bash interception for leading account options |
| [shell/agentshell.ps1](shell/agentshell.ps1) | PowerShell interception and account-shell integration |
| [install.sh](install.sh) | Idempotent current-user installer |
| [install.ps1](install.ps1) | Idempotent Windows current-user installer |
| [docs/tutorial.md](docs/tutorial.md) | Complete start-to-finish tutorial |
| [docs/architecture.md](docs/architecture.md) | State boundaries, inheritance, and safety design |
| [docs/providers.md](docs/providers.md) | Codex, Claude, Gemini, and Copilot adapters |
| [tests/test.sh](tests/test.sh) | Isolated integration tests |
| [tests/test.ps1](tests/test.ps1) | Windows PowerShell 5.1 integration tests |
| [SECURITY.md](SECURITY.md) | Credential and disclosure guidance |

## Installation layout

```text
~/.local/lib/agentshell/agentshell       runtime
~/.local/bin/agent-*                     commands
~/scripts/sourced_agent_shell.sh         Bash integration
~/.local/share/agentshell/profiles/      private profile state
  ACCOUNT/codex-home/                    private-mode and legacy account state
  ACCOUNT/codex-shared-home/             shared-mode account/history view
```

On Windows, the default current-user layout is:

```text
%LOCALAPPDATA%\AgentShell\lib\agentshell.ps1    runtime
%LOCALAPPDATA%\AgentShell\bin\*.cmd, *.ps1      command launchers
%LOCALAPPDATA%\AgentShell\shell\agentshell.ps1  PowerShell integration
%LOCALAPPDATA%\AgentShell\profiles\             private profile state
  ACCOUNT\codex-home\                            private-mode and legacy state
  ACCOUNT\codex-shared-home\                     shared-mode account/history view
```

AgentShell keeps `HOME`, `PWD`, Git credentials, and the real filesystem unchanged. Authored settings and skills may be inherited, but known provider credentials and histories are never copied into a new profile.

## Update and validate

```bash
cd "$HOME/ProjectsLFS/AgentShell"
git pull --rebase
./install.sh
. "$HOME/.bashrc"

bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
git diff --check
```

Windows PowerShell update and validation:

```powershell
Set-Location "$HOME\Projects\AgentShell"
git pull --rebase
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
. $PROFILE

agentshell -v
agent-profile list
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\test.ps1
git diff --check
```

## Security scope

- Never commit profile homes, `auth.json`, tokens, cookies, SQLite databases, or private environment files.
- Shared history intentionally exposes indexed session titles, previews, and paths to each participating profile.
- Inherited API-token variables are cleared unless a profile explicitly opts in.
- Use separate OS users, machines, or externally enforced containers for mutually untrusted people.

See [SECURITY.md](SECURITY.md) and [docs/architecture.md](docs/architecture.md).

## Citation

If you use AgentShell in research or tooling, cite the repository. GitHub reads [CITATION.cff](CITATION.cff) and shows a **Cite this repository** panel on the repository page.

```bibtex
@software{chen_agentshell_2026,
  author = {Chen, Lachlan},
  title = {AgentShell: Named AI CLI Account Profiles for Shared Working Trees},
  year = {2026},
  url = {https://github.com/lachlanchen/AgentShell}
}
```

## Status and license

AgentShell is an actively maintained, dependency-light Bash and Windows PowerShell utility. Codex is the primary verified integration; other provider adapters follow their documented state-directory controls. Licensed under the [MIT License](LICENSE).

## Links

- [Complete tutorial](docs/tutorial.md)
- [GitHub repository](https://github.com/lachlanchen/AgentShell)
- [LazyingArt](https://lazying.art)
- [GitHub Sponsors](https://github.com/sponsors/lachlanchen)
- [Official Codex environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables)
