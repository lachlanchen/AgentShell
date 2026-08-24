# Security

AgentShell separates application account state; it does not isolate operating-system permissions.

- Every profile can access every file the current Unix user can access.
- Do not treat profiles as protection from untrusted prompts, repositories, plugins, MCP servers, or agents.
- Never commit `~/.local/share/agentshell`, profile `env.sh` files, authentication files, or session data.
- Prefer browser/device login. If an API token is necessary, store it only in the relevant profile's mode-0600 `env.sh`.
- Review shared skills and plugins before using them with company or lab accounts; shared customization is visible to all named profiles.

Report security issues privately to the repository owner rather than opening a public issue with credentials or private logs.
