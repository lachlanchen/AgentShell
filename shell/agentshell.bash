#!/usr/bin/env bash
# Optional Bash integration. Account routing is only activated when the first
# argument is --account/--project; all ordinary commands retain native behavior.

__agentshell_has_account_option() {
  case "${1:-}" in
    --account|--account=*|--project|--project=*) return 0 ;;
    *) return 1 ;;
  esac
}

codex() {
  if __agentshell_has_account_option "${1:-}"; then
    command agent-codex "$@"
  elif [ -x "$HOME/scripts/codex_wrapper.sh" ]; then
    "$HOME/scripts/codex_wrapper.sh" codex "$@"
  else
    command codex "$@"
  fi
}

codexr() {
  if __agentshell_has_account_option "${1:-}"; then
    command agent-codexr "$@"
  elif [ -x "$HOME/scripts/codex_wrapper.sh" ]; then
    "$HOME/scripts/codex_wrapper.sh" codexr "$@"
  else
    command codex resume "$@"
  fi
}

codexmv() {
  if __agentshell_has_account_option "${1:-}"; then
    command agent-codexmv "$@"
  elif [ -x "$HOME/scripts/codex_wrapper.sh" ]; then
    "$HOME/scripts/codex_wrapper.sh" codexmv "$@"
  else
    command codexmv "$@"
  fi
}

if type -P claude >/dev/null 2>&1; then
  claude() {
    if __agentshell_has_account_option "${1:-}"; then
      command agent-claude "$@"
    else
      command claude "$@"
    fi
  }
fi

if type -P gemini >/dev/null 2>&1; then
  gemini() {
    if __agentshell_has_account_option "${1:-}"; then
      command agent-gemini "$@"
    else
      command gemini "$@"
    fi
  }
fi

if type -P copilot >/dev/null 2>&1; then
  copilot() {
    if __agentshell_has_account_option "${1:-}"; then
      command agent-copilot "$@"
    else
      command copilot "$@"
    fi
  }
fi

alias cr='codexr'
