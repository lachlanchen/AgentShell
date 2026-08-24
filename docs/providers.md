# Provider adapters

## Codex

Codex is the primary integration. Each account gets independent authentication, SQLite state, logs, and sessions through `CODEX_HOME` and `CODEX_SQLITE_HOME`.

Each profile chooses one of two SQLite modes:

- `private`: profile-local index; strongest separation and the default.
- `shared`: one existing Codex index for cross-account `codexr` and `codexmv` workflows.

```bash
agent-profile history personal shared
agent-profile history company private
agentshell status personal
```

On this workstation, AgentShell delegates to the existing `codex/codexr/codexmv` dispatcher after activating the account. That preserves the fast session picker, `/rename` support, current-directory filtering, and safe cwd migration journals.

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

Any installed command can run with the named profile environment:

```bash
agent-run --account lab bash -lc 'printf "%s\n" "$CODEX_HOME"'
```

Only the four documented providers receive dedicated state directories. Unknown tools simply inherit the named environment.
