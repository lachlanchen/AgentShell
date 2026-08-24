#!/usr/bin/env bash
# Install AgentShell for the current user. No sudo is required.

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
install_root="${AGENT_SHELL_INSTALL_ROOT:-$HOME/.local/lib/agentshell}"
bin_dir="${AGENT_SHELL_BIN_DIR:-$HOME/.local/bin}"
shell_helper="${AGENT_SHELL_SHELL_HELPER:-$HOME/scripts/sourced_agent_shell.sh}"
bashrc="${AGENT_SHELL_BASHRC:-$HOME/.bashrc}"
commands=(agentshell agent-run agent-profile agent-codex agent-codexr agent-codexmv agent-claude agent-gemini agent-copilot)

install -d -m 0755 "$install_root" "$bin_dir" "$(dirname -- "$shell_helper")"
install -m 0755 "$repo_root/bin/agentshell" "$install_root/agentshell"
install -m 0644 "$repo_root/shell/agentshell.bash" "$shell_helper"

for command_name in "${commands[@]}"; do
  link="$bin_dir/$command_name"
  if [ -L "$link" ]; then
    if [ "$(readlink -f -- "$link" 2>/dev/null || true)" != "$(readlink -f -- "$install_root/agentshell")" ]; then
      printf 'Refusing to replace unrelated symlink: %s -> %s\n' "$link" "$(readlink -- "$link")" >&2
      exit 1
    fi
  elif [ -e "$link" ]; then
    printf 'Refusing to replace existing path: %s\n' "$link" >&2
    exit 1
  fi
  ln -sfn "$install_root/agentshell" "$link"
done

marker_begin='# >>> AgentShell >>>'
marker_end='# <<< AgentShell <<<'
source_line='if [ -f "$HOME/scripts/sourced_agent_shell.sh" ]; then . "$HOME/scripts/sourced_agent_shell.sh"; fi'

if [ -f "$bashrc" ] && ! grep -Fq "$marker_begin" "$bashrc"; then
  backup="$bashrc.agentshell-backup-$(date +%Y%m%d-%H%M%S)"
  cp -p -- "$bashrc" "$backup"
  {
    printf '\n%s\n' "$marker_begin"
    printf '%s\n' "$source_line"
    printf '%s\n' "$marker_end"
  } >> "$bashrc"
  printf 'Updated %s (backup: %s)\n' "$bashrc" "$backup"
elif [ ! -f "$bashrc" ]; then
  {
    printf '%s\n' "$marker_begin"
    printf '%s\n' "$source_line"
    printf '%s\n' "$marker_end"
  } > "$bashrc"
  printf 'Created %s\n' "$bashrc"
fi

printf 'AgentShell installed. Reload Bash with:\n  . %s\n' "$bashrc"
