# Repository Guidelines

## Scope

AgentShell is a dependency-light Bash utility for named, account-isolated AI CLI sessions. Keep the default path non-destructive and preserve native CLI arguments.

## Rules

- Never commit profile homes, credentials, session histories, browser data, or private environment files.
- Keep ordinary `codex`, `claude`, `gemini`, and `copilot` behavior unchanged unless `--account` or `--project` is explicitly supplied.
- Account isolation must not change the caller's working directory.
- Prefer documented provider-specific home variables over changing the Unix `HOME` variable.
- Use quoted Bash variables and validate account names before using them in paths or command names.

## Validation

Run before committing:

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
git diff --check
```
