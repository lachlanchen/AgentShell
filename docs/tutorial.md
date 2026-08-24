# AgentShell complete tutorial

AgentShell lets several terminal windows use different AI-service logins while they all work in the same real project directory. It changes each tool's state directory; it does not copy the project, change the Unix user, or create a container.

This guide uses three example profiles:

- `personal`
- `lab`
- `company`

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

Run these in any terminal and from any current directory:

```bash
source ~/.bashrc
agentshell personal
codexr
```

That is the normal workflow. Replace `personal` with `lab` or `company` when needed. Once inside the named shell, plain `codex`, `codexr`, and `codexmv` all use that account.

For the first login only:

```bash
source ~/.bashrc
codex --account personal login
agent-profile history personal shared
```

After login, return to the three-command workflow. Run `exit` when you want to leave the named AgentShell terminal.

One-shot commands remain available when a dedicated shell is not wanted:

```bash
codex --account personal
codexr --account personal
codexr --account personal --all
```

## 1. Install AgentShell

On a new computer:

```bash
cd "$HOME/ProjectsLFS"
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. "$HOME/.bashrc"
```

No `sudo`, Docker, or additional Unix user is required.

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
| `shared` | Profile-local | Shared `~/.codex` index | Resuming the same workstation sessions with several accounts |

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

- credentials remain under `~/.local/share/agentshell/profiles/ACCOUNT/codex-home/`;
- the resume catalog is `~/.codex/state_5.sqlite`;
- `codexr --account ACCOUNT` can discover established workstation sessions;
- session titles, previews, and paths in that index are visible to every shared profile.

Changing modes does not delete either history. It changes which SQLite location future commands use.

## 5. Start Codex with a selected account

### One command at a time

```bash
cd /path/to/project
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

The working directory remains unchanged. Exit the dedicated shell with:

```bash
exit
```

Open another terminal and run `agentshell lab` to use the lab login in the same repository.

### Generated account commands

Creating `lab` also creates:

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

The workstation `codexr` wrapper defaults to sessions whose recorded working directory exactly matches the current directory:

```bash
cd /path/to/project
codexr --account personal
```

Use the arrow keys to select, Enter to resume, and `q` or Ctrl+C to cancel.

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

If a project directory was renamed or moved, update the indexed session paths with:

```bash
codexmv --account personal /old/project/path /new/project/path
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
AgentShell 0.2.0
Current account: personal
Codex login:    saved
History mode:   shared
Codex home:     .../profiles/personal/codex-home
SQLite home:    /home/lachlan/.codex
Working dir:    /path/to/project
```

From an ordinary terminal, inspect a named profile explicitly:

```bash
agentshell status personal
agent-profile status personal codex
```

`agentshell -v` in an ordinary shell correctly reports `none (ordinary shell)`. A one-shot child command such as `codex --account personal` cannot change the parent shell's environment. Its launch banner identifies the selected profile, and `/status` identifies the authenticated account inside Codex.

## 9. A practical multi-terminal workflow

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

## 10. Other supported AI CLIs

AgentShell also prepares separate state roots for Claude Code, Gemini CLI, and GitHub Copilot CLI:

```bash
claude --account lab
gemini --account personal
copilot --account company
```

Or enter `agentshell lab` and run the commands without `--account`. Each provider still requires its own normal login flow. Codex is the most deeply integrated provider on this workstation.

## 11. Update AgentShell

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

## 12. Troubleshooting

### `unexpected argument '--account'`

The current shell has not loaded AgentShell's Bash integration, or `--account` was not first.

```bash
. "$HOME/.bashrc"
type codex
codex --account personal login status
```

New Bash terminals load the integration automatically.

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

```bash
. "$HOME/.bashrc"
printf '%s\n' "$PATH"
ls -l "$HOME/.local/bin/agentshell"
```

If required, rerun `./install.sh`; it is designed to be idempotent and refuses to overwrite unrelated commands.

## 13. State, privacy, and backups

Profile state lives under:

```text
~/.local/share/agentshell/profiles/ACCOUNT/
```

Important rules:

- Do not upload `auth.json`, profile state, cookies, or tokens.
- Shared history exposes indexed titles, previews, and paths to every profile using that index.
- AgentShell profiles are not an OS security boundary; all processes still run as the same Unix user.
- Use separate Unix users or separately controlled machines for mutually untrusted people.
- Prefer browser login. If an account-specific API variable is necessary, place it in that profile's mode-0600 `env.sh`, not a public repository or shared `.bashrc`.

AgentShell deliberately shares authored Codex configuration, skills, plugins, and rules where safe, while keeping provider credentials profile-local.

## 14. Command cheat sheet

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

## Official Codex basis

Codex documents `CODEX_HOME` as the root for config, authentication, logs, sessions, and skills. It separately documents `CODEX_SQLITE_HOME` for SQLite-backed state. AgentShell uses that supported separation to keep each login private while optionally sharing the resume index:

- [Official Codex environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables)
