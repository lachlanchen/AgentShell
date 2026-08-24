# AgentShell

Named AI CLI accounts for separate terminals, with one shared working tree.

AgentShell lets a personal terminal, lab terminal, and company terminal use different Codex logins without copying projects or changing Unix users. It is deliberately lighter than Docker: the process stays in the real current directory, while supported CLIs receive separate account, session, and state directories.

## Why

```text
same folder
   ├── terminal A → personal Codex home/login/sessions
   ├── terminal B → lab Codex home/login/sessions
   └── terminal C → company Codex home/login/sessions
```

Ordinary commands remain ordinary. Account routing only happens when you explicitly use `--account`/`--project`, a generated account command, or an AgentShell subshell.

## Install

```bash
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. ~/.bashrc
```

No root access or container runtime is required.

## Codex quick start

Create and log in to two independent accounts:

```bash
agent-profile create personal
agent-profile create lab

codex --account personal login
codex --account lab login
```

Use each account directly:

```bash
codex --account personal
codex --account lab -m gpt-5.6-sol
codexr --account lab
codexmv --account lab /old/project /new/project
```

Or dedicate an entire terminal to one account:

```bash
agentshell personal
# Prompt now starts with [agent:personal]. These use personal state:
codex
codexr
codexmv
exit
```

The same profile can be opened from any project directory. `pwd` is retained exactly.

## Convenience commands

Creating `lab` generates:

```text
agent-lab-codex
agent-lab-codexr
agent-lab-codexmv
agent-lab-claude
agent-lab-gemini
agent-lab-copilot
```

These are equivalent:

```bash
codex --account lab --version
agent-codex --account lab --version
agent-lab-codex --version
agent-run --account lab codex --version
```

`--project` is an alias for `--account`:

```bash
codex --project company
agent-codex --project company
```

Place the custom account option first. Every remaining option and prompt is forwarded unchanged.

## Other AI CLIs

The profile core already supports the official state-home controls for Claude Code, Gemini CLI, and GitHub Copilot CLI:

```bash
claude --account lab
gemini --account personal
copilot --account company
```

Inside `agentshell lab`, plain `claude`, `gemini`, and `copilot` use the same named profile. Provider support is intentionally an adapter layer; Codex is the first fully integrated workflow on this workstation.

## Account management

```bash
agent-profile list
agent-profile show lab
agent-profile status lab
agent-profile login lab codex
agent-profile aliases lab
```

State lives under:

```text
~/.local/share/agentshell/profiles/ACCOUNT/
```

See [Architecture and safety](docs/architecture.md) and [Provider adapters](docs/providers.md).

## Design guarantees

- The current directory is never copied, mounted, or changed.
- Account credentials and conversation state are not copied from the default profile.
- Existing `codex`, `codexr`, and `codexmv` behavior is unchanged without an account option.
- Account creation is idempotent.
- Generated aliases refuse to overwrite unrelated files.
- Inherited provider API-token variables are cleared by default to prevent one terminal's token from silently defeating account isolation.
- Existing authored settings and skills can be inherited without sharing provider login state.

AgentShell is account/state separation for one trusted Unix user—not a security sandbox. Every profile has the same filesystem permissions as that user.

## Validation

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
```

## Standards used

AgentShell uses provider-supported state roots rather than changing `$HOME`:

- [Codex `CODEX_HOME`](https://learn.chatgpt.com/docs/config-file/environment-variables)
- [Claude Code `CLAUDE_CONFIG_DIR`](https://code.claude.com/docs/en/env-vars)
- [Gemini CLI `GEMINI_CLI_HOME`](https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/configuration.md)
- [Copilot CLI `COPILOT_HOME`](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)

## License

[MIT](LICENSE)

## Citation

GitHub exposes citation metadata from [`CITATION.cff`](CITATION.cff). A compact software citation is:

```bibtex
@software{chen_2026_agentshell,
  author = {Lachlan Chen},
  title = {AgentShell: named AI CLI account profiles for shared working trees},
  year = {2026},
  url = {https://github.com/lachlanchen/AgentShell}
}
```
