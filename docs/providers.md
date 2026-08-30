# Provider adapters

## Codex

Codex is the primary integration. Each account gets independent authentication through `CODEX_HOME`; SQLite and rollout history can remain private or be exposed together through a coherent shared view.

Each profile chooses one of two history modes:

- `private`: profile-local index and rollout tree; strongest separation and the default.
- `shared`: one existing Codex index and rollout tree for cross-account resume workflows.

```bash
agent-profile history personal shared
agent-profile history company private
agentshell status personal
```

AgentShell delegates to existing platform `codex`, `codexr`, and `codexmv` commands after activating the account. That preserves any installed fast session picker, `/rename` support, current-directory filtering, and safe cwd migration journals. On Windows, `codexr` falls back to `codex resume` when no separate `codexr` command exists; `codexmv` still requires the workstation command. Bash and PowerShell integrations intercept only a leading `--account` or `--project`; plain commands retain their ordinary behavior.

```bash
codex --account personal login
codex --account personal login status
codex --account personal
codexr --account personal --all
```

## Claude Code

Claude Code documents `CLAUDE_CONFIG_DIR` specifically for multiple accounts side by side. AgentShell sets it to the named profile's `claude-home/`.

```bash
claude --account lab
```

Complete `/login` inside Claude when prompted. Some Claude IDE integrations have historically handled custom config roots differently; AgentShell targets terminal CLI sessions.

## Gemini CLI

Gemini CLI appends `.gemini` beneath `GEMINI_CLI_HOME`. AgentShell therefore sets the variable to `gemini-home/` and prepares `gemini-home/.gemini/`.

```bash
gemini --account company
```

## GitHub Copilot CLI

Copilot CLI supports a complete alternate state directory through `COPILOT_HOME`. AgentShell also isolates its cache with `COPILOT_CACHE_HOME`.

```bash
copilot --account company
```

The GitHub CLI (`gh`) is intentionally not redirected. This avoids unexpectedly hiding the host's Git credentials. Copilot's own login state remains profile-specific.

## Generic commands

On Bash, any installed command can run with the named profile environment:

```bash
agent-run --account lab bash -lc 'printf "%s\n" "$CODEX_HOME"'
```

Windows PowerShell equivalent:

```powershell
agent-run --account lab powershell.exe -NoLogo -NoProfile -Command '$env:CODEX_HOME'
```

Only the four documented providers receive dedicated state directories. Unknown tools simply inherit the named environment.
