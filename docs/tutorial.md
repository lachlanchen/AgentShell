# AgentShell complete tutorial

AgentShell lets several terminal windows use different AI-service logins while they all work in the same real project directory. It changes each tool's state directory; it does not copy the project, change the OS user, or create a container. The commands in this guide work in Bash and Windows PowerShell 5.1 unless an OS-specific block is shown.

This guide uses three example profiles:

- `personal` for personal work
- `lab` for laboratory work
- `company` for company work

Profile names are labels chosen locally. They may contain letters, numbers, dots, underscores, and hyphens.

## The important distinction

AgentShell's `--account` selects an authentication/state profile:

```bash
codex --account personal
```

Codex's native `--profile`/`-p` option selects a configuration profile. It does not select a different ChatGPT login. The two concepts are independent.

The AgentShell option must be the first option. Everything after it is passed to the native tool:

```bash
# Correct
codex --account lab -m gpt-5.6-sol "Review this repository"

# Incorrect: native Codex receives an unknown --account option
codex -m gpt-5.6-sol --account lab
```

Plain commands remain unchanged:

```bash
codex
codexr
codexmv
```

## The three commands to remember

Run these from any current directory.

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

That is the normal workflow. Replace `personal` with `lab` or `company` when needed. Once inside the named shell, plain `codex`, `codexr`, and `codexmv` all use that account.

For the first login only:

```text
codex --account personal login
agent-profile history personal shared
```

Reload the integration first with `source ~/.bashrc` on Bash or `. $PROFILE` on PowerShell.

After login, return to the three-command workflow. Run `exit` when you want to leave the named AgentShell terminal.

One-shot commands remain available when a dedicated shell is not wanted:

```bash
codex --account personal
codexr --account personal
codexr --account personal --all
```

## 1. Install AgentShell

### Bash

On a new computer:

```bash
cd "$HOME/ProjectsLFS"
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. "$HOME/.bashrc"
```

No `sudo`, Docker, or additional OS user is required.

The installer creates:

```text
~/.local/lib/agentshell/agentshell       installed runtime
~/.local/bin/agent-*                     command links
~/scripts/sourced_agent_shell.sh         Bash integration
~/.local/share/agentshell/profiles/      account state
```

Confirm the integration:

```bash
type codex
type agentshell
agentshell --help
```

`type codex` should report a Bash function after `.bashrc` is loaded. The function only intercepts a leading `--account` or `--project`; otherwise it preserves the normal workstation wrapper.

### Windows PowerShell

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\Projects" | Out-Null
Set-Location "$HOME\Projects"
git clone https://github.com/lachlanchen/AgentShell.git
Set-Location AgentShell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
. $PROFILE
```

No administrator window, Docker, or additional Windows user is required. The default current-user layout is:

```text
%LOCALAPPDATA%\AgentShell\lib\agentshell.ps1    installed runtime
%LOCALAPPDATA%\AgentShell\bin\*.cmd, *.ps1      command launchers
%LOCALAPPDATA%\AgentShell\shell\agentshell.ps1  PowerShell integration
%LOCALAPPDATA%\AgentShell\profiles\ACCOUNT\     account state
```

Confirm the integration:

```powershell
Get-Command codex
Get-Command agentshell
agentshell --help
```

`Get-Command codex` should report a PowerShell function after the profile is loaded. The function intercepts only a leading `--account` or `--project`; all ordinary invocations continue through the command that was available before AgentShell.

## 2. Create named profiles

Create as many profiles as needed:

```bash
agent-profile create personal
agent-profile create lab
agent-profile create company
```

Creation is idempotent: running the same command again reuses the profile.

List profiles:

```bash
agent-profile list
```

Example output:

```text
ACCOUNT                  CODEX LOGIN  HISTORY   STATE
company                  not logged in shared    .../profiles/company
lab                      not logged in shared    .../profiles/lab
personal                 saved        shared    .../profiles/personal
```

## 3. Log each profile into Codex

### Browser login

Run one login at a time:

```bash
codex --account personal login
codex --account lab login
codex --account company login
```

Codex opens its login flow. In the browser, authenticate with the account intended for that profile. The resulting credential is saved only in that profile's private `CODEX_HOME`.

This equivalent command is useful when managing profiles:

```bash
agent-profile login personal codex
```

### Device login for a remote or headless terminal

If the callback browser cannot reach the terminal machine, use:

```bash
codex --account personal login --device-auth
```

Follow the displayed URL and code from any convenient browser.

### Check login status

```bash
codex --account personal login status
agent-profile status personal codex
agent-profile list
```

Inside a running Codex TUI, `/status` is the best check for the exact authenticated identity and current session details.

### Log out or replace one login

```bash
codex --account lab logout
codex --account lab login
```

This affects only `lab`; it does not log out `personal`, `company`, or ordinary `~/.codex`.

## 4. Choose private or shared history

Authentication and the SQLite session index are separate choices.

| Mode | Authentication | Resume index | Best for |
|---|---|---|---|
| `private` | Profile-local | Profile-local | Confidential separation |
| `shared` | Profile-local | Shared default Codex index | Resuming the same workstation sessions with several accounts |

New profiles default to private history. Change a profile to shared history with:

```bash
agent-profile history personal shared
agent-profile history lab shared
agent-profile history company shared
```

Return one profile to private history:

```bash
agent-profile history company private
```

Show the current choice:

```bash
agent-profile history company
agentshell status company
```

In shared mode:

- credentials remain in the named profile (`~/.local/share/agentshell/profiles/ACCOUNT/codex-home/` on Bash or `%LOCALAPPDATA%\AgentShell\profiles\ACCOUNT\codex-home\` on Windows);
- the resume catalog is the default Codex index under `~/.codex` on Bash or `$HOME\.codex` on Windows;
- `codexr --account ACCOUNT` can discover established workstation sessions;
- session titles, previews, and paths in that index are visible to every shared profile.

Changing modes does not delete either history. It changes which SQLite location future commands use.

## 5. Start Codex with a selected account

### One command at a time

```bash
cd /path/to/project
codex --account personal
```

Windows PowerShell equivalent:

```powershell
Set-Location C:\path\to\project
codex --account personal
```

Native arguments and prompts continue to work:

```bash
codex --account lab -m gpt-5.6-sol
codex --account company --search "Review the current repository"
codex --account personal -C /path/to/project
```

AgentShell prints a short launch banner in an interactive terminal so the selected label is visible before Codex starts.

### Dedicate the whole terminal to one profile

This is the clearest workflow for long-running work:

```bash
cd /path/to/project
agentshell personal
```

The prompt begins with `[agent:personal]`. Inside that shell, use normal commands:

```bash
agentshell -v
codex
codexr
codexmv
```

The working directory remains unchanged. On Windows, `agentshell ACCOUNT` starts a nested PowerShell with the selected account environment; on Bash it starts a nested Bash shell. Exit either dedicated shell with:

```bash
exit
```

Open another terminal and run `agentshell lab` to use the lab login in the same repository.

### Generated account commands

Creating `lab` also creates account-specific command launchers. On Bash they have the following names; Windows exposes the same command names through its installed command directory:

```text
agent-lab-codex
agent-lab-codexr
agent-lab-codexmv
agent-lab-claude
agent-lab-gemini
agent-lab-copilot
```

These forms are equivalent:

```bash
codex --account lab --version
agent-codex --account lab --version
agent-lab-codex --version
agent-run --account lab codex --version
```

`--project` is an alias for `--account`:

```bash
codex --project lab
```

## 6. Resume Codex sessions

When the workstation already has a `codexr` wrapper, AgentShell preserves it, including its default of sessions whose recorded working directory exactly matches the current directory:

```bash
cd /path/to/project
codexr --account personal
```

Windows PowerShell equivalent:

```powershell
Set-Location C:\path\to\project
codexr --account personal
```

If no separate `codexr` command exists, the Windows integration falls back to `codex resume`. Standard native resume options still work, but workstation-only options such as `--non-strict`, `--include-non-interactive`, and `--native` require the pre-existing wrapper. Use the arrow keys to select, Enter to resume, and `q` or Ctrl+C to cancel.

Show sessions from every directory:

```bash
codexr --account personal --all
```

Search by a partial directory name:

```bash
codexr --account personal --non-strict EchoMind
```

Include non-interactive runs:

```bash
codexr --account personal --all --include-non-interactive
```

Use Codex's native picker instead of the fast workstation picker:

```bash
codexr --account personal --native
```

Resume the newest native session directly:

```bash
codex --account personal resume --last
```

Resume by UUID or a name assigned with `/rename`:

```bash
codex --account personal resume SESSION_ID_OR_NAME
```

`--non-strict` belongs to `codexr`, not plain `codex`:

```bash
# Correct
codexr --account personal --non-strict incoder

# Incorrect
codex non-strict incoder
```

## 7. Move session working-directory metadata

If a project directory was renamed or moved and the workstation provides `codexmv`, update the indexed session paths with:

```bash
codexmv --account personal /old/project/path /new/project/path
```

On Windows, quote paths when they can contain spaces:

```powershell
codexmv --account personal "C:\old project" "D:\new project"
```

This changes Codex session metadata; it does not move project files. The workstation wrapper writes a rollback journal before updating the SQLite rows.

Useful forms:

```bash
# Update metadata and resume the newest migrated session
codexmv --account personal --latest /old/path /new/path

# Update metadata without opening Codex
codexmv --account personal --no-resume /old/path /new/path

# Use the native picker after migration
codexmv --account personal --native /old/path /new/path
```

## 8. See which account is active

Inside a dedicated AgentShell terminal:

```bash
agentshell -v
```

Example:

```text
AgentShell <installed version>
Current account: personal
Codex login:    saved
History mode:   shared
Codex home:     .../profiles/personal/codex-home
SQLite home:    <default Codex state directory>
Working dir:    <current project directory>
```

From an ordinary terminal, inspect a named profile explicitly:

```bash
agentshell status personal
agent-profile status personal codex
```

`agentshell -v` in an ordinary shell correctly reports `none (ordinary shell)`. A one-shot child command such as `codex --account personal` cannot change the parent shell's environment. Its launch banner identifies the selected profile, and `/status` identifies the authenticated account inside Codex.

## 9. A practical multi-terminal workflow

### Bash

Terminal 1, personal work:

```bash
source ~/.bashrc
agentshell personal
codexr
```

Terminal 2, lab work:

```bash
source ~/.bashrc
agentshell lab
codex
```

Terminal 3, company work:

```bash
source ~/.bashrc
agentshell company
codex
```

Every terminal sees the same filesystem and Git worktrees. Only provider state and authentication are selected by the profile.

### Windows PowerShell

Terminal 1, personal work:

```powershell
. $PROFILE
agentshell personal
codexr
```

Terminal 2, lab work:

```powershell
. $PROFILE
agentshell lab
codex
```

Terminal 3, company work:

```powershell
. $PROFILE
agentshell company
codex
```

The labels are local roles, not account names or email addresses. Every terminal sees the same real Windows project files.

## 10. Other supported AI CLIs

AgentShell also prepares separate state roots for Claude Code, Gemini CLI, and GitHub Copilot CLI:

```bash
claude --account lab
gemini --account personal
copilot --account company
```

Or enter `agentshell lab` and run the commands without `--account`. Each provider still requires its own normal login flow. Codex is the most deeply integrated provider on this workstation.

## 11. Update AgentShell

### Bash

```bash
cd "$HOME/ProjectsLFS/AgentShell"
git pull --rebase
./install.sh
. "$HOME/.bashrc"
```

Validate after updating:

```bash
agentshell -v
agent-profile list
codex --version
codex --account personal login status
```

### Windows PowerShell

```powershell
Set-Location "$HOME\Projects\AgentShell"
git pull --rebase
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
. $PROFILE
```

Validate after updating:

```powershell
agentshell -v
agent-profile list
codex --version
codex --account personal login status
```

## 12. Troubleshooting

### `unexpected argument '--account'`

The current shell has not loaded AgentShell's shell integration, or `--account` was not first.

On Bash:

```bash
. "$HOME/.bashrc"
type codex
codex --account personal login status
```

New Bash terminals load the integration automatically.

On Windows PowerShell:

```powershell
. $PROFILE
Get-Command codex
codex --account personal login status
```

New PowerShell terminals load the integration automatically after the installer has added its guarded profile block.

### `state database not found`

Inspect the profile's history route:

```bash
agentshell status personal
```

To use the established workstation index:

```bash
agent-profile history personal shared
```

A new private profile may have no SQLite database until Codex creates state there. The workstation wrapper falls back to the native picker rather than treating that as corruption.

### The exact-directory picker shows no sessions

```bash
codexr --account personal --all
codexr --account personal --non-strict PART_OF_OLD_PATH
```

If a folder was renamed, use `codexmv` after confirming the old and new paths.

### The wrong ChatGPT account was used

```bash
codex --account personal logout
codex --account personal login
```

Then open Codex and run `/status`.

### Browser login cannot return to the terminal

```bash
codex --account personal login --device-auth
```

### `agentshell -v` says no account

You are in an ordinary parent shell. Either inspect a profile explicitly:

```bash
agentshell status personal
```

or enter it:

```bash
agentshell personal
agentshell -v
```

### Ctrl+C produced `KeyboardInterrupt` in the picker

This means the picker was cancelled. It does not indicate session-database damage. Run `codexr` again or use `q` to leave the picker.

### Commands are missing after installation

On Bash:

```bash
. "$HOME/.bashrc"
printf '%s\n' "$PATH"
ls -l "$HOME/.local/bin/agentshell"
```

If required, rerun `./install.sh`; it is designed to be idempotent and refuses to overwrite unrelated commands.

On Windows PowerShell:

```powershell
. $PROFILE
Get-Command agentshell
$env:Path -split ';'
```

If required, rerun `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install.ps1`. The installer is idempotent and keeps its PowerShell profile integration inside one guarded block.

### npm Codex update fails with `EBUSY` on Windows

An `EBUSY` error naming a Codex executable means Windows still has that npm-installed file open. Finish and exit active Codex CLI, desktop, and IDE sessions, then update from a new PowerShell window. If npm still cannot replace its package tree, use OpenAI's official standalone Windows installer instead of repeatedly retrying the npm update:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://chatgpt.com/codex/install.ps1 | iex"
Get-Command codex -All
codex --version
```

The official Codex guide lists the standalone installer as the Windows install and update command, with npm as an alternative: [Codex CLI installation](https://learn.chatgpt.com/docs/codex/cli#install-codex).

## 13. State, privacy, and backups

Profile state lives under one of these current-user paths:

```text
Bash:                ~/.local/share/agentshell/profiles/ACCOUNT/
Windows PowerShell:  %LOCALAPPDATA%\AgentShell\profiles\ACCOUNT\
```

Important rules:

- Do not upload `auth.json`, profile state, cookies, or tokens.
- Shared history exposes indexed titles, previews, and paths to every profile using that index.
- AgentShell profiles are not an OS security boundary; all processes still run as the same OS user.
- Use separate OS users or separately controlled machines for mutually untrusted people.
- Prefer browser login. If an account-specific API variable is necessary, use that profile's private environment file rather than a public repository or shared shell profile: mode-0600 `env.sh` on Bash or `env.ps1` under the Windows profile directory.

AgentShell deliberately shares authored Codex configuration, skills, plugins, and rules where safe, while keeping provider credentials profile-local.

## 14. Command cheat sheet

### Bash

```bash
# Reload integration
. "$HOME/.bashrc"

# Create and inspect profiles
agent-profile create personal
agent-profile list
agentshell status personal

# Login/status/logout
codex --account personal login
codex --account personal login --device-auth
codex --account personal login status
codex --account personal logout

# History mode
agent-profile history personal shared
agent-profile history personal private

# One-shot use
codex --account personal
codexr --account personal
codexr --account personal --all

# Dedicated terminal
agentshell personal
agentshell -v
exit

# Moved project sessions
codexmv --account personal /old/path /new/path

# Update
cd "$HOME/ProjectsLFS/AgentShell"
git pull --rebase
./install.sh
. "$HOME/.bashrc"
```

### Windows PowerShell

```powershell
# Reload integration
. $PROFILE

# Create and inspect profiles
agent-profile create personal
agent-profile list
agentshell status personal

# Login/status/logout
codex --account personal login
codex --account personal login --device-auth
codex --account personal login status
codex --account personal logout

# History mode
agent-profile history personal shared
agent-profile history personal private

# One-shot use
codex --account personal
codexr --account personal
codexr --account personal --all

# Dedicated terminal
agentshell personal
agentshell -v
exit

# Moved project sessions
codexmv --account personal "C:\old path" "D:\new path"

# Update
Set-Location "$HOME\Projects\AgentShell"
git pull --rebase
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
. $PROFILE
```

## Official Codex basis

Codex documents `CODEX_HOME` as the root for config, authentication, logs, sessions, and skills. It separately documents `CODEX_SQLITE_HOME` for SQLite-backed state. AgentShell uses that supported separation to keep each login private while optionally sharing the resume index:

- [Official Codex environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables)
