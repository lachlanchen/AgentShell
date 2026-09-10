# Codex desktops with separate AgentShell accounts on Linux

OpenAI's official Linux preview is packaged as **ChatGPT** and includes Codex. AgentShell can open company, personal, and lab desktops simultaneously using the same named logins as its CLI. Reopening one account reuses that account's running app.

Verified on Ubuntu 24.04.4 amd64 with `chatgpt 26.903.71938` on 2026-09-10. This optional launcher requires Linux, Python 3, the AgentShell Bash runtime, and the official `chatgpt` command. The existing Windows and macOS CLI workflows are unchanged.

## Install the official app

Follow [OpenAI's Linux installation instructions](https://learn.chatgpt.com/docs/linux/linux-app). For an amd64 Debian/Ubuntu machine:

```bash
mkdir -p "$HOME/Downloads"
curl --fail --location --retry 3 \
  https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb \
  -o "$HOME/Downloads/chatgpt_amd64.deb"
sudo apt install "$HOME/Downloads/chatgpt_amd64.deb"
```

Use the arm64 download from the official guide on ARM computers. The package installs the app, its system launcher, and a signed OpenAI APT repository. Subsequent updates use APT:

```bash
sudo apt update
sudo apt install --only-upgrade chatgpt
```

Install or update AgentShell from its checkout:

```bash
./install.sh
source "$HOME/.bashrc"
agent-desktop --install-launchers company personal lab
```

The Applications menu now has **Codex — Company**, **Codex — Personal**, and **Codex — Lab**. Search for Codex, open a shortcut, and optionally pin it to the dock. The vendor's plain ChatGPT shortcut uses its normal default profile; use the named shortcuts to select an AgentShell account. No reboot is needed. Shortcuts persist across reboot but do not automatically start three apps at login.

## Login and open

If these AgentShell accounts are already logged in, open them directly:

```bash
agent-desktop company
agent-desktop personal
agent-desktop lab
```

For an account that has not logged in yet:

```bash
source "$HOME/.bashrc"
codex --account personal login
codex --account personal login status
agent-desktop personal
```

Use `codex --account personal login --device-auth` when browser callback login is impractical. Complete any provider-required authentication in your own browser. Local profile names are labels; verify the actual signed-in identity in the app's profile menu. The installed app reuses the profile's saved authentication rather than copying another account's credentials.

Equivalent commands:

```bash
codex-desktop --account company
agentshell lab -- agent-desktop

agentshell personal
codexr
agent-desktop
```

Inside the last example's account shell, `agent-desktop` selects `personal`. Use `exit` to leave that shell. `codexr` remains the terminal session picker; the new desktop launcher does not replace it.

## Data, history, and permissions

For a default installation:

| Path below `~/.local/share/agentshell/profiles/ACCOUNT/` | Purpose |
| --- | --- |
| `codex-home/` | Private account state and private history mode |
| `codex-shared-home/` | Account-specific state with the existing shared-history view |
| `codex-desktop/` | This account's Chromium/Electron settings, cookies, UI cache, and instance lock |
| `codex-desktop-launch.log` | Private startup diagnostics; rotated on launch after 10 MiB |

The launcher honors `AGENT_SHELL_HOME` and `XDG_DATA_HOME`. It delegates authentication and history routing to AgentShell. Your history choice is preserved:

```bash
agent-profile history personal shared
agent-profile history lab private
agentshell status personal
```

Close that account's desktop before changing its history mode, then reopen it. Shared history intentionally makes common session titles and content accessible to participating accounts. Separate GUI directories isolate cookies/settings; they are not OS security boundaries. Project files, `HOME`, and the current working directory stay unchanged. Use different OS users for mutually untrusted people.

Existing CLI flags and permissions remain unchanged. The desktop has its own visible approval controls; inspect those before asking it to modify a project. The verified package bundles Codex CLI 0.153.4; it does not overwrite a separately installed CLI. We did not force a different backend binary, disable Chromium sandboxing, or modify vendor JavaScript.

## Why both profile controls are required

The launch uses both:

```text
CODEX_ELECTRON_USER_DATA_PATH=.../ACCOUNT/codex-desktop
chatgpt --user-data-dir=.../ACCOUNT/codex-desktop --class=AgentShellCodex-ACCOUNT
```

The environment variable configures the app's Electron state. In the tested Linux build, the Chromium/native startup layer also needs `--user-data-dir`; supplying only the environment variable let early browser state use the default Codex directory. Both controls are necessary to avoid merging accounts or focusing another account's process. The vendor's own internal test launcher uses the same pair.

`--class` gives each X11 window a matching `StartupWMClass` in its desktop entry. Repeating a shortcut relies on the app's native per-profile instance lock. The launcher refuses extra arguments that override these two profile flags.

These Electron controls were verified against this package's installed source and behavior. Recheck isolation after a major preview update. They are implementation details rather than a guarantee that all future releases keep the same interface.

## Troubleshooting

```bash
agent-desktop company --status
agent-desktop personal --status
agent-desktop lab --status

agent-desktop personal --foreground
```

Status reads the profile's instance lock without starting an app. Foreground mode is useful after quitting that account's app normally. Inspect its private launch log for startup failures. Do not delete locks or profile directories while their processes are running.

If a new login presents onboarding, finish the visible setup or skip optional suggestions. In this tested preview, using **Back to ChatGPT** before completing onboarding could leave a blank loading screen. Quitting and reopening just that idle profile restored setup; completing it and skipping optional suggestions allowed progress. This did not require logging out, replacing credentials, or clearing history.

The launchers do not expose a debugging port. Temporary loopback CDP ports were used only during installation verification. Do not expose a browser debugging endpoint to the network: it grants control of the signed-in app.

Linux is a preview, and features may differ from other platforms; for example, the official Linux guide currently excludes Computer Use. Account subscriptions and model availability remain those of the selected login.

## Validation and implementation

- [Launcher](../bin/agent-desktop): uses argv lists, preserves argument boundaries, creates private state/logs, and starts apps detached from the terminal.
- [Installer](../install.sh): installs `agent-desktop` and its `codex-desktop` alias; reruns preserve unrelated files.
- [Tests](../tests/test_desktop.py): actual AgentShell routing with a stub app, distinct accounts, inherited credential clearing, paths with spaces, instance metadata, launcher quoting, and idempotent desktop entries.

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
python3 -m unittest discover -s tests -p test_desktop.py -v
git diff --check
```

Live checks on the workstation confirmed distinct account authentication and separate desktop directories/processes. Shared history remained accessible. Saved credentials, browser profiles, screenshots containing history, and private startup logs are excluded from this repository.
