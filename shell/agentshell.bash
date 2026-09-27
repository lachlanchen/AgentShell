#!/usr/bin/env bash
# Optional Bash integration. Account activation switches the current shell.
# Leading --account/--project options still route just one tool invocation.

# Do not reset a saved environment when this helper is sourced again.
if ! declare -p __agentshell_saved_values >/dev/null 2>&1; then
  declare -gA __agentshell_saved_values=() __agentshell_saved_set=()
  declare -gA __agentshell_saved_export=() __agentshell_applied_values=()
  declare -gA __agentshell_applied_set=()
fi

__agentshell_restore_environment() {
  local __ags_name
  for __ags_name in "${!__agentshell_saved_set[@]}"; do
    # Preserve a subsequent user change (for example conda changing PATH).
    [ "${!__ags_name+x}" = "${__agentshell_applied_set[$__ags_name]}" ] || continue
    [ "${!__ags_name-}" = "${__agentshell_applied_values[$__ags_name]}" ] || continue
    if [ "${__agentshell_saved_set[$__ags_name]}" = x ]; then
      printf -v "$__ags_name" '%s' "${__agentshell_saved_values[$__ags_name]}"
      if [ "${__agentshell_saved_export[$__ags_name]}" = x ]; then
        export "$__ags_name"
      else
        export -n "$__ags_name"
      fi
    else
      unset "$__ags_name"
    fi
  done
}

__agentshell_update_prompt() {
  [ "${PS1+x}" = x ] || return 0
  # Also remove labels inherited from older, nested AgentShell shells.
  while [[ "$PS1" =~ \[agent:[A-Za-z0-9._-]+\]\  ]]; do
    PS1="${PS1/"${BASH_REMATCH[0]}"/}"
  done
  if [ -n "${AGENT_SHELL_ACCOUNT:-}" ]; then
    PS1="[agent:${AGENT_SHELL_ACCOUNT}] $PS1"
  fi
}

__agentshell_activate() {
  local __ags_account="$1" __ags_i __ags_name __ags_op __ags_value __ags_decl
  local -a __ags_records=()
  # Prepare the next profile from the pre-activation environment in a child.
  # Failed preparation leaves the current account entirely intact.
  mapfile -d '' -t __ags_records < <(
    __agentshell_restore_environment
    command agent-profile shell-env "$__ags_account"
  )
  __ags_i=${#__ags_records[@]}
  if (( __ags_i < 3 || __ags_i % 3 != 0 )) ||
     [ "${__ags_records[__ags_i-3]}" != done ]; then
    printf 'AgentShell: account activation failed; current account retained.\n' >&2
    return 1
  fi
  for ((__ags_i=0; __ags_i<${#__ags_records[@]}-3; __ags_i+=3)); do
    __ags_op="${__ags_records[__ags_i]}"
    __ags_name="${__ags_records[__ags_i+1]}"
    if [[ ! "$__ags_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
       [[ "$__ags_op" != export && "$__ags_op" != unset ]]; then
      printf 'AgentShell: invalid environment response.\n' >&2
      return 1
    fi
    __ags_decl="$(declare -p "$__ags_name" 2>/dev/null || true)"
    if [[ "$__ags_decl" =~ ^declare\ -[^\ ]*[raAn] ]]; then
      printf 'AgentShell: cannot change non-scalar or readonly variable %s.\n' "$__ags_name" >&2
      return 1
    fi
  done
  __agentshell_restore_environment
  __agentshell_saved_values=() __agentshell_saved_set=() __agentshell_saved_export=()
  __agentshell_applied_values=() __agentshell_applied_set=()
  for ((__ags_i=0; __ags_i<${#__ags_records[@]}-3; __ags_i+=3)); do
    __ags_op="${__ags_records[__ags_i]}"
    __ags_name="${__ags_records[__ags_i+1]}"
    __ags_value="${__ags_records[__ags_i+2]}"
    if [[ ! -v __agentshell_saved_set[$__ags_name] ]]; then
      __agentshell_saved_set["$__ags_name"]="${!__ags_name+x}"
      __agentshell_saved_values["$__ags_name"]="${!__ags_name-}"
      __ags_decl="$(declare -p "$__ags_name" 2>/dev/null || true)"
      __agentshell_saved_export["$__ags_name"]=""
      [[ "$__ags_decl" =~ ^declare\ -[^\ ]*x ]] &&
        __agentshell_saved_export["$__ags_name"]=x
    fi
    if [ "$__ags_op" = export ]; then
      printf -v "$__ags_name" '%s' "$__ags_value"
      export "$__ags_name"
      __agentshell_applied_set["$__ags_name"]=x
      __agentshell_applied_values["$__ags_name"]="$__ags_value"
    else
      unset "$__ags_name"
      __agentshell_applied_set["$__ags_name"]=""
      __agentshell_applied_values["$__ags_name"]=""
    fi
  done
  __agentshell_update_prompt
  printf 'AgentShell account %s (current shell)\n' "$__ags_account" >&2
}

agentshell() {
  local __ags_account=""
  case "${1:-}" in
    default)
      [ "$#" -eq 1 ] || { printf 'Usage: agentshell default\n' >&2; return 2; }
      __agentshell_restore_environment
      # An older nested/inherited shell has no pre-activation snapshot. Drop
      # known provider overrides explicitly; never copy or log out credentials.
      if [ -n "${AGENT_SHELL_ACCOUNT:-}" ]; then
        unset CODEX_API_KEY CODEX_ACCESS_TOKEN OPENAI_API_KEY \
          ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN \
          GEMINI_API_KEY GOOGLE_API_KEY GOOGLE_APPLICATION_CREDENTIALS \
          COPILOT_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
      fi
      unset AGENT_SHELL_ACCOUNT AGENT_SHELL_PROFILE_ROOT AGENT_SHELL_PROFILE_ENV \
        AGENT_SHELL_CODEX_HISTORY_MODE AGENT_SHELL_CODEX_SQLITE_HOME AGENT_SHELL_CODEX_HOME \
        CODEX_SQLITE_HOME CODEX_SESSION_ID CODEX_THREAD_ID CODEX_CI \
        CLAUDE_CONFIG_DIR GEMINI_CLI_HOME COPILOT_HOME COPILOT_CACHE_HOME
      export CODEX_HOME="${AGENT_SHELL_BASE_CODEX_HOME:-$HOME/.codex}"
      __agentshell_saved_values=() __agentshell_saved_set=() __agentshell_saved_export=()
      __agentshell_applied_values=() __agentshell_applied_set=()
      __agentshell_update_prompt
      printf 'AgentShell: ordinary Codex at %s (current shell)\n' "$CODEX_HOME" >&2
      return 0
      ;;
    deactivate)
      [ "$#" -eq 1 ] || { printf 'Usage: agentshell deactivate\n' >&2; return 2; }
      __agentshell_restore_environment
      __agentshell_saved_values=() __agentshell_saved_set=() __agentshell_saved_export=()
      __agentshell_applied_values=() __agentshell_applied_set=()
      __agentshell_update_prompt
      return 0
      ;;
    activate)
      [ "$#" -eq 2 ] || { printf 'Usage: agentshell activate ACCOUNT\n' >&2; return 2; }
      __agentshell_activate "$2"
      return $?
      ;;
    ''|-h|--help|help|-v|--version|status|profile|run)
      command agentshell "$@"
      return $?
      ;;
    --account|--project)
      if [ "$#" -eq 2 ]; then __ags_account="$2"; fi
      ;;
    --account=*|--project=*)
      if [ "$#" -eq 1 ]; then __ags_account="${1#*=}"; fi
      ;;
    *)
      if [ "$#" -eq 1 ]; then __ags_account="$1"; fi
      ;;
  esac
  if [ -n "$__ags_account" ]; then
    __agentshell_activate "$__ags_account"
  else
    command agentshell "$@"
  fi
}

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
  elif [ -n "${AGENT_SHELL_ACCOUNT:-}" ]; then
    command agent-codex --account "$AGENT_SHELL_ACCOUNT" "$@"
  else
    command codex "$@"
  fi
}

codexr() {
  if __agentshell_has_account_option "${1:-}"; then
    command agent-codexr "$@"
  elif [ -x "$HOME/scripts/codex_wrapper.sh" ]; then
    "$HOME/scripts/codex_wrapper.sh" codexr "$@"
  elif [ -n "${AGENT_SHELL_ACCOUNT:-}" ]; then
    command agent-codexr --account "$AGENT_SHELL_ACCOUNT" "$@"
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

if ! alias cr >/dev/null 2>&1 && ! declare -F cr >/dev/null 2>&1 && ! type -P cr >/dev/null 2>&1; then
  alias cr='codexr'
fi
