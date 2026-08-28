# Repository Guidelines

## Scope

AgentShell is a dependency-light Bash and Windows PowerShell utility for named, account-isolated AI CLI sessions. Keep the default path non-destructive and preserve native CLI arguments on both platforms.

## Rules

- Never commit profile homes, credentials, session histories, browser data, or private environment files.
- Keep ordinary `codex`, `claude`, `gemini`, and `copilot` behavior unchanged unless `--account` or `--project` is explicitly supplied.
- Account isolation must not change the caller's working directory.
- Prefer documented provider-specific home variables over changing `HOME` or `USERPROFILE`.
- Use quoted Bash variables, preserve PowerShell argument boundaries, and validate account names before using them in paths or command names.
- Keep Bash and PowerShell behavior aligned, including ordinary-command passthrough, profile creation, history routing, and dedicated account shells.

## Validation

Run before committing:

```text
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tests\test.ps1
git diff --check
```
