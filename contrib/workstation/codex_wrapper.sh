#!/usr/bin/env bash
# Shared implementation for codex, codexr, codexfork, and codexmv on this workstation.

set -uo pipefail

# Workstation policy: a new interactive backend reads the selected login fresh.
# Opt back into upstream daemon behavior with AGENT_SHELL_CODEX_DAEMON=on.
: "${AGENT_SHELL_CODEX_DAEMON:=off}"
export AGENT_SHELL_CODEX_DAEMON

# Preserve the AgentShell data alias; codex-startup handles long resolved sockets.
if [ -z "${AGENT_SHELL_HOME:-}" ] && [ -L "$HOME/.as" ]; then
  export AGENT_SHELL_HOME="$HOME/.as"
fi

codex_wrapper_mode="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi

# Private wrapper options must precede native arguments. Do not consume -f or
# --force, or flag-looking prompt/config values elsewhere in the argument list.
CODEX_WRAPPER_CLOSE_OTHER=0
CODEX_WRAPPER_INSPECT=0
while [[ "${1:-}" = --close-other || "${1:-}" = --as-close-other || "${1:-}" = --kill || "${1:-}" = --where ]]; do
  if [ "$1" = --where ]; then CODEX_WRAPPER_INSPECT=1; else
  CODEX_WRAPPER_CLOSE_OTHER=1
  fi
  shift
done
if [ "$CODEX_WRAPPER_CLOSE_OTHER" -eq 1 ] && [ "$CODEX_WRAPPER_INSPECT" -eq 1 ]; then
  printf 'Use --where or --kill separately.\n' >&2; exit 2
fi
if [ "$CODEX_WRAPPER_CLOSE_OTHER" -eq 1 ] || [ "$CODEX_WRAPPER_INSPECT" -eq 1 ]; then
  case "$codex_wrapper_mode" in
    codex)
      # A bare takeover request selects an existing session instead of starting
      # a new conversation, which has no other opening to close.
      if [ "$#" -eq 0 ]; then codex_wrapper_mode=codexr; fi
      ;;
    codexr) ;;
    codexmv)
      [ "$CODEX_WRAPPER_INSPECT" -eq 0 ] || { printf 'Use codexr --where to inspect a session.\n' >&2; exit 2; }
      ;;
    *) printf '%s\n' 'Takeover is supported by codex/codexr and codexmv --kill --latest; forking does not require closing the source.' >&2; exit 2 ;;
  esac
fi

codex_wrapper_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
codex_session_tool="$codex_wrapper_dir/codex_session_tool.py"

: "${CODEX_RESUME_PICKER_ENABLE_WSL:=1}"
: "${CODEX_RESUME_PICKER_ENABLE_NATIVE:=1}"
: "${CODEX_RESUME_PICKER_LIMIT:=500}"

codex_refresh_agentshell_home() {
  local rollout_path="${1:-}" profile_bin effective_home

  [ "${AGENT_SHELL_CODEX_HISTORY_MODE:-}" = "shared" ] || return 0
  [ -n "${AGENT_SHELL_ACCOUNT:-}" ] || return 0
  profile_bin="$(type -P agent-profile 2>/dev/null || true)"
  # installed AgentShell profile helper fallback
  if [ ! -x "$profile_bin" ] && [ -x "$HOME/.local/bin/agent-profile" ]; then
    profile_bin="$HOME/.local/bin/agent-profile"
  fi
  [ -x "$profile_bin" ] || return 0

  if [ -n "$rollout_path" ]; then
    effective_home="$(AGENT_SHELL_QUIET=1 "$profile_bin" codex-home "$AGENT_SHELL_ACCOUNT" "$rollout_path")" || return 1
  else
    effective_home="$(AGENT_SHELL_QUIET=1 "$profile_bin" codex-home "$AGENT_SHELL_ACCOUNT")" || return 1
  fi
  [ -n "$effective_home" ] || return 1
  export AGENT_SHELL_CODEX_HOME="$effective_home"
  export CODEX_HOME="$effective_home"
}

codex_is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
}

codex_picker_enabled() {
  if codex_is_wsl; then
    [ "${CODEX_RESUME_PICKER_ENABLE_WSL:-1}" = "1" ]
  else
    [ "${CODEX_RESUME_PICKER_ENABLE_NATIVE:-1}" = "1" ]
  fi
}

codex_find_real_bin() {
  local candidate resolved
  local shim_codex="$HOME/bin/codex"
  local shim_codexr="$HOME/bin/codexr"
  local shim_codexfork="$HOME/bin/codexfork"
  local shim_codexmv="$HOME/bin/codexmv"

  if [ -n "${CODEX_REAL_BIN:-}" ] && [ -x "$CODEX_REAL_BIN" ]; then
    printf '%s\n' "$CODEX_REAL_BIN"
    return 0
  fi

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    resolved="$(readlink -f -- "$candidate" 2>/dev/null || printf '%s' "$candidate")"
    case "$resolved" in
      "$shim_codex"|"$shim_codexr"|"$shim_codexfork"|"$shim_codexmv"|"$codex_wrapper_dir/codex_wrapper.sh")
        continue
        ;;
    esac
    if [ -x "$resolved" ]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  done < <(type -P -a codex 2>/dev/null || true)

  for candidate in "$HOME"/.nvm/versions/node/*/bin/codex "$HOME"/.local/bin/codex /usr/local/bin/codex /usr/bin/codex; do
    [ -x "$candidate" ] || continue
    resolved="$(readlink -f -- "$candidate" 2>/dev/null || printf '%s' "$candidate")"
    case "$resolved" in
      "$shim_codex"|"$shim_codexr"|"$shim_codexfork"|"$shim_codexmv") continue ;;
    esac
    printf '%s\n' "$resolved"
    return 0
  done
  return 1
}

CODEX_CLEAN_ARGS=()
codex_strip_enforced_mode_args() {
  CODEX_CLEAN_ARGS=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -s|-a|--sandbox|--sandbox-mode|--sandbox_mode|--ask-for-approval|--approval-policy|--approval_policy)
        if [ "$#" -lt 2 ]; then
          printf 'codex wrapper error: %s requires a value\n' "$1" >&2
          return 2
        fi
        shift 2
        ;;
      -s=*|-a=*|--sandbox=*|--sandbox-mode=*|--sandbox_mode=*|--ask-for-approval=*|--approval-policy=*|--approval_policy=*)
        shift
        ;;
      --full-auto|--approve-for-me|--dangerously-bypass-approvals-and-sandbox)
        shift
        ;;
      *)
        CODEX_CLEAN_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

codex_run_native() {
  local real_bin="$1"
  local startup_helper="${AGENT_SHELL_INSTALL_ROOT:-$HOME/.local/lib/agentshell}/codex-startup"
  shift
  local takeover_args=()
  if [ "$CODEX_WRAPPER_CLOSE_OTHER" -eq 1 ] || [ "$CODEX_WRAPPER_INSPECT" -eq 1 ]; then
    takeover_args=(--kill)
    if [ "$CODEX_WRAPPER_INSPECT" -eq 1 ]; then takeover_args=(--where); fi
    if [ ! -f "$startup_helper" ] || ! command -v python3 >/dev/null 2>&1; then
      printf 'codex wrapper: --close-other needs the AgentShell startup helper and Python 3.\n' >&2
      return 2
    fi
  fi
  # Replace this short-lived wrapper with Codex. Keeping Bash as a parent for
  # a multi-hour session leaves this script open and makes live wrapper updates
  # susceptible to mixed old/new input when Codex eventually exits.
  if [ -f "$startup_helper" ] && command -v python3 >/dev/null 2>&1; then
    exec python3 "$startup_helper" "$real_bin" "${takeover_args[@]}" -s danger-full-access -a never "$@"
  fi
  exec "$real_bin" -s danger-full-access -a never "$@"
}

CODEX_RESUME_NATIVE_ARGS=()
CODEX_RESUME_PASS_ARGS=()
CODEX_RESUME_SCOPE="exact"
CODEX_RESUME_TARGET_CWD=""
CODEX_RESUME_QUERY=""
CODEX_RESUME_INCLUDE_NON_INTERACTIVE=0
CODEX_RESUME_FORCE_NATIVE=0
CODEX_RESUME_EXPLICIT_CWD=0

codex_normalize_path() {
  realpath -m -- "$1"
}

codex_parse_resume_args() {
  local value
  CODEX_RESUME_NATIVE_ARGS=()
  CODEX_RESUME_PASS_ARGS=()
  CODEX_RESUME_SCOPE="exact"
  CODEX_RESUME_TARGET_CWD="$(pwd -P)"
  CODEX_RESUME_QUERY=""
  CODEX_RESUME_INCLUDE_NON_INTERACTIVE=0
  CODEX_RESUME_FORCE_NATIVE=0
  CODEX_RESUME_EXPLICIT_CWD=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --kill|--close-other|--as-close-other)
        [ "$CODEX_WRAPPER_INSPECT" -eq 0 ] || { printf 'Use --where or --kill separately.\n' >&2; return 2; }
        CODEX_WRAPPER_CLOSE_OTHER=1
        shift
        ;;
      --where)
        [ "$CODEX_WRAPPER_CLOSE_OTHER" -eq 0 ] || { printf 'Use --where or --kill separately.\n' >&2; return 2; }
        CODEX_WRAPPER_INSPECT=1
        shift
        ;;
      --native)
        CODEX_RESUME_FORCE_NATIVE=1
        shift
        ;;
      --non-strict)
        CODEX_RESUME_SCOPE="partial"
        shift
        if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then
          CODEX_RESUME_QUERY="$1"
          shift
        fi
        ;;
      --non-strict=*)
        CODEX_RESUME_SCOPE="partial"
        CODEX_RESUME_QUERY="${1#*=}"
        shift
        ;;
      --all)
        if [ "$CODEX_RESUME_SCOPE" != "partial" ]; then
          CODEX_RESUME_SCOPE="all"
        fi
        CODEX_RESUME_NATIVE_ARGS+=("$1")
        shift
        ;;
      --include-non-interactive)
        CODEX_RESUME_INCLUDE_NON_INTERACTIVE=1
        CODEX_RESUME_NATIVE_ARGS+=("$1")
        shift
        ;;
      -C|--cd|--cwd)
        if [ "$#" -lt 2 ]; then
          printf 'codex resume wrapper error: %s requires a directory\n' "$1" >&2
          return 2
        fi
        value="$(codex_normalize_path "$2")" || return 2
        CODEX_RESUME_TARGET_CWD="$value"
        CODEX_RESUME_EXPLICIT_CWD=1
        CODEX_RESUME_PASS_ARGS+=("--cd" "$value")
        CODEX_RESUME_NATIVE_ARGS+=("--cd" "$value")
        shift 2
        ;;
      -C=*|--cd=*|--cwd=*)
        value="$(codex_normalize_path "${1#*=}")" || return 2
        CODEX_RESUME_TARGET_CWD="$value"
        CODEX_RESUME_EXPLICIT_CWD=1
        CODEX_RESUME_PASS_ARGS+=("--cd" "$value")
        CODEX_RESUME_NATIVE_ARGS+=("--cd" "$value")
        shift
        ;;
      -c|--config|--enable|--disable|--remote|--remote-auth-token-env|-m|--model|--local-provider|-p|--profile|--add-dir|-i|--image)
        if [ "$#" -lt 2 ]; then
          printf 'codex resume wrapper error: %s requires a value\n' "$1" >&2
          return 2
        fi
        CODEX_RESUME_PASS_ARGS+=("$1" "$2")
        CODEX_RESUME_NATIVE_ARGS+=("$1" "$2")
        shift 2
        ;;
      --config=*|--enable=*|--disable=*|--remote=*|--remote-auth-token-env=*|--model=*|--local-provider=*|--profile=*|--add-dir=*|--image=*)
        CODEX_RESUME_PASS_ARGS+=("$1")
        CODEX_RESUME_NATIVE_ARGS+=("$1")
        shift
        ;;
      --strict-config|--oss|--dangerously-bypass-hook-trust|--search|--no-alt-screen)
        CODEX_RESUME_PASS_ARGS+=("$1")
        CODEX_RESUME_NATIVE_ARGS+=("$1")
        shift
        ;;
      --last|-h|--help|-V|--version)
        CODEX_RESUME_FORCE_NATIVE=1
        CODEX_RESUME_NATIVE_ARGS+=("$1")
        shift
        ;;
      --)
        CODEX_RESUME_FORCE_NATIVE=1
        CODEX_RESUME_NATIVE_ARGS+=("$1")
        shift
        while [ "$#" -gt 0 ]; do
          CODEX_RESUME_NATIVE_ARGS+=("$1")
          shift
        done
        ;;
      -*)
        # Preserve forward compatibility: unknown Codex options go to native Codex.
        CODEX_RESUME_FORCE_NATIVE=1
        CODEX_RESUME_NATIVE_ARGS+=("$1")
        shift
        ;;
      *)
        # Native Codex accepts either a UUID or a /rename session name here.
        CODEX_RESUME_FORCE_NATIVE=1
        CODEX_RESUME_NATIVE_ARGS+=("$1")
        shift
        while [ "$#" -gt 0 ]; do
          CODEX_RESUME_NATIVE_ARGS+=("$1")
          shift
        done
        ;;
    esac
  done

  if [ "$CODEX_RESUME_SCOPE" = "partial" ] && [ -z "$CODEX_RESUME_QUERY" ]; then
    CODEX_RESUME_QUERY="$CODEX_RESUME_TARGET_CWD"
  fi
}

codex_fast_picker() {
  local real_bin="$1"
  local db_path db_dir output_path status index_path resolved_index existing_index duplicate
  local picker_command selection=() session_indexes=()
  shift

  db_path="${CODEX_SQLITE_HOME:-${CODEX_HOME:-$HOME/.codex}}/state_5.sqlite"
  if [ ! -f "$db_path" ]; then
    printf 'No indexed Codex history at %s; opening the native picker.\n' "$db_path" >&2
    codex_run_native "$real_bin" resume "${CODEX_RESUME_NATIVE_ARGS[@]}"
    return $?
  fi
  if [ ! -x "$codex_session_tool" ]; then
    printf 'codex resume picker error: helper is not executable: %s\n' "$codex_session_tool" >&2
    return 1
  fi

  output_path="$(mktemp "${TMPDIR:-/tmp}/codex-session-selection.XXXXXX")" || return 1
  picker_command=(
    python3 "$codex_session_tool" pick
    --db "$db_path"
    --scope "$CODEX_RESUME_SCOPE"
    --cwd "$CODEX_RESUME_TARGET_CWD"
    --query "$CODEX_RESUME_QUERY"
    --limit "$CODEX_RESUME_PICKER_LIMIT"
    --output "$output_path"
  )

  # /rename values are append-only records in session_index.jsonl. Include the
  # shared SQLite home's index, the active account profile, and every local
  # AgentShell profile so renamed chats remain visible in the shared picker.
  db_dir="$(dirname -- "$db_path")"
  for index_path in \
    "$db_dir/session_index.jsonl" \
    "${CODEX_HOME:-$HOME/.codex}/session_index.jsonl" \
    "$HOME"/.local/share/agentshell/profiles/*/codex-home/session_index.jsonl
  do
    [ -f "$index_path" ] || continue
    resolved_index="$(realpath -m -- "$index_path")" || continue
    duplicate=0
    for existing_index in "${session_indexes[@]}"; do
      if [ "$existing_index" = "$resolved_index" ]; then
        duplicate=1
        break
      fi
    done
    [ "$duplicate" -eq 1 ] || session_indexes+=("$resolved_index")
  done
  for index_path in "${session_indexes[@]}"; do
    picker_command+=(--session-index "$index_path")
  done
  if [ "$CODEX_RESUME_INCLUDE_NON_INTERACTIVE" -eq 1 ]; then
    picker_command+=(--include-non-interactive)
  fi
  if [ -n "${CODEX_PICKER_SELECT_INDEX:-}" ]; then
    picker_command+=(--select-index "$CODEX_PICKER_SELECT_INDEX")
  fi

  "${picker_command[@]}"
  status=$?
  if [ "$status" -ne 0 ]; then
    rm -f -- "$output_path"
    return "$status"
  fi
  mapfile -d '' -t selection < "$output_path"
  rm -f -- "$output_path"
  if [ "${#selection[@]}" -lt 3 ] || [ -z "${selection[0]}" ] || [ -z "${selection[2]}" ]; then
    printf 'codex resume picker error: helper returned no valid selection\n' >&2
    return 1
  fi

  # A shared AgentShell account uses the common rollout tree for new threads,
  # while a small number of pre-0.3 profiles still have legacy rollout trees.
  # Resolve a credential-isolated view over the selected rollout's actual tree
  # before native Codex follows paginated history lineage.
  codex_refresh_agentshell_home "${selection[2]}" || {
    printf 'codex resume picker error: could not prepare the selected history view\n' >&2
    return 1
  }

  if [ "$CODEX_RESUME_EXPLICIT_CWD" -eq 1 ]; then
    codex_run_native "$real_bin" resume "${CODEX_RESUME_PASS_ARGS[@]}" "${selection[0]}" "$@"
  else
    codex_run_native "$real_bin" resume "${CODEX_RESUME_PASS_ARGS[@]}" --cd "${selection[1]}" "${selection[0]}" "$@"
  fi
}

codex_handle_resume() {
  local real_bin="$1"
  shift
  codex_parse_resume_args "$@" || return $?
  if [ "$CODEX_RESUME_FORCE_NATIVE" -eq 1 ] || ! codex_picker_enabled; then
    codex_run_native "$real_bin" resume "${CODEX_RESUME_NATIVE_ARGS[@]}"
    return $?
  fi
  codex_fast_picker "$real_bin"
}

codex_handle_fork() {
  local session_id target_raw target_dir real_bin

  if [ "$#" -eq 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
    printf '%s\n' \
      'Usage: codexfork SESSION_ID FOLDER [PROMPT]' \
      'Fork SESSION_ID with native Codex and open the new session in FOLDER.' \
      'FOLDER must already exist. Quote PROMPT when it contains spaces.' \
      'Rename the opened fork with: /rename NAME'
    return 0
  fi

  if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    printf 'Usage: codexfork SESSION_ID FOLDER [PROMPT]\n' >&2
    return 2
  fi

  session_id="$1"
  target_raw="$2"
  if [[ ! "$session_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
    printf 'codexfork error: SESSION_ID must be a UUID: %s\n' "$session_id" >&2
    return 2
  fi
  if [ ! -d "$target_raw" ]; then
    printf 'codexfork error: folder does not exist: %s\n' "$target_raw" >&2
    return 1
  fi
  target_dir="$(realpath -- "$target_raw")" || return 1
  real_bin="$(codex_find_real_bin)" || { printf 'codexfork error: real Codex binary not found\n' >&2; return 127; }

  printf 'codexfork: forking %s into %s\n' "$session_id" "$target_dir"
  if [ "$#" -eq 3 ]; then
    codex_run_native "$real_bin" fork --cd "$target_dir" "$session_id" "$3"
  else
    codex_run_native "$real_bin" fork --cd "$target_dir" "$session_id"
  fi
}

codex_handle_move() {
  local latest=0 no_resume=0 native_picker=0
  local old_raw="" new_raw="." real_bin db_path output_path status
  local move_result=() positional=()
  local takeover_session="" takeover_helper="${AGENT_SHELL_INSTALL_ROOT:-$HOME/.local/lib/agentshell}/codex_takeover.py"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -l|--latest) latest=1; shift ;;
      --no-resume) no_resume=1; shift ;;
      --native) native_picker=1; shift ;;
      -h|--help)
        printf '%s\n' \
          'Usage: codexmv [--latest|-l] [--no-resume] [--native] <oldpath> [newpath]' \
          'Default: migrate cwd metadata, save a rollback journal, then open the fast picker.' \
          '  --latest, -l  Resume the newest migrated session directly.' \
          '  --kill        Before --latest, close only its verified owner; refuse other active migration targets.' \
          '  --no-resume   Migrate only.' \
          '  --native      Use the official Codex picker after migration.'
        return 0
        ;;
      --)
        shift
        while [ "$#" -gt 0 ]; do positional+=("$1"); shift; done
        ;;
      -*)
        printf 'codexmv error: unknown option %s\n' "$1" >&2
        return 2
        ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  if [ "${#positional[@]}" -lt 1 ] || [ "${#positional[@]}" -gt 2 ]; then
    printf 'Usage: codexmv [--latest|-l] [--no-resume] [--native] <oldpath> [newpath]\n' >&2
    return 2
  fi
  old_raw="${positional[0]}"
  if [ "${#positional[@]}" -eq 2 ]; then
    new_raw="${positional[1]}"
  fi

  if [ "$CODEX_WRAPPER_CLOSE_OTHER" -eq 1 ] && { [ "$latest" -ne 1 ] || [ "$no_resume" -eq 1 ] || [ "$native_picker" -eq 1 ]; }; then
    printf 'codexmv --kill requires --latest and cannot combine with --native or --no-resume. Nothing changed.\n' >&2
    return 2
  fi

  db_path="${CODEX_SQLITE_HOME:-${CODEX_HOME:-$HOME/.codex}}/state_5.sqlite"
  [ -f "$db_path" ] || { printf 'codexmv error: state database not found at %s\n' "$db_path" >&2; return 1; }
  [ -x "$codex_session_tool" ] || { printf 'codexmv error: helper is not executable: %s\n' "$codex_session_tool" >&2; return 1; }
  if [ "$CODEX_WRAPPER_CLOSE_OTHER" -eq 1 ]; then
    [ "$(codex_normalize_path "$old_raw")" != "$(codex_normalize_path "$new_raw")" ] || { printf 'codexmv: paths are identical; nothing changed.\n' >&2; return 2; }
    takeover_session="$(python3 "$takeover_helper" prepare-move "$db_path" "$old_raw")" || return $?
    # Do not close a second owner if one appears during the migration.
    CODEX_WRAPPER_CLOSE_OTHER=0
  fi
  output_path="$(mktemp "${TMPDIR:-/tmp}/codexmv-result.XXXXXX")" || return 1

  python3 "$codex_session_tool" move \
    --db "$db_path" \
    --old "$old_raw" \
    --new "$new_raw" \
    --output "$output_path"
  status=$?
  if [ "$status" -ne 0 ]; then
    rm -f -- "$output_path"
    return "$status"
  fi
  mapfile -d '' -t move_result < "$output_path"
  rm -f -- "$output_path"
  if [ "${#move_result[@]}" -lt 4 ]; then
    printf 'codexmv error: helper returned an incomplete result\n' >&2
    return 1
  fi
  if [ -n "$takeover_session" ] && [ "${move_result[1]}" != "$takeover_session" ]; then
    printf 'codexmv: newest session changed during migration; nothing else was stopped. Resume the desired UUID explicitly.\n' >&2
    return 2
  fi
  if [ "$no_resume" -eq 1 ]; then
    return 0
  fi

  real_bin="$(codex_find_real_bin)" || { printf 'codexmv error: real Codex binary not found\n' >&2; return 127; }
  if [ "$latest" -eq 1 ]; then
    codex_run_native "$real_bin" resume --cd "${move_result[2]}" "${move_result[1]}"
  elif [ "$native_picker" -eq 1 ] || ! codex_picker_enabled; then
    codex_run_native "$real_bin" resume --cd "${move_result[2]}"
  else
    CODEX_RESUME_SCOPE="exact"
    CODEX_RESUME_TARGET_CWD="${move_result[2]}"
    CODEX_RESUME_QUERY=""
    CODEX_RESUME_INCLUDE_NON_INTERACTIVE=0
    CODEX_RESUME_EXPLICIT_CWD=1
    CODEX_RESUME_PASS_ARGS=(--cd "${move_result[2]}")
    codex_fast_picker "$real_bin"
  fi
}

# Existing interactive AgentShell terminals may predate an AgentShell upgrade.
# Refresh the effective shared-history view on every wrapper invocation so the
# fix does not require closing those terminals or re-sourcing their shell.
codex_refresh_agentshell_home || {
  printf 'codex wrapper error: could not prepare AgentShell shared history\n' >&2
  exit 1
}

case "$codex_wrapper_mode" in
  codex)
    codex_strip_enforced_mode_args "$@" || exit $?
    codex_real_bin="$(codex_find_real_bin)" || { printf 'codex wrapper error: real Codex binary not found\n' >&2; exit 127; }
    if [ "${#CODEX_CLEAN_ARGS[@]}" -gt 0 ] && [ "${CODEX_CLEAN_ARGS[0]}" = "resume" ]; then
      codex_handle_resume "$codex_real_bin" "${CODEX_CLEAN_ARGS[@]:1}"
      exit $?
    fi
    codex_run_native "$codex_real_bin" "${CODEX_CLEAN_ARGS[@]}"
    ;;
  codexr)
    codex_strip_enforced_mode_args "$@" || exit $?
    if [ "${#CODEX_CLEAN_ARGS[@]}" -gt 0 ] && [ "${CODEX_CLEAN_ARGS[0]}" = "resume" ]; then
      CODEX_CLEAN_ARGS=("${CODEX_CLEAN_ARGS[@]:1}")
    fi
    codex_real_bin="$(codex_find_real_bin)" || { printf 'codexr wrapper error: real Codex binary not found\n' >&2; exit 127; }
    codex_handle_resume "$codex_real_bin" "${CODEX_CLEAN_ARGS[@]}"
    ;;
  codexfork)
    codex_handle_fork "$@"
    ;;
  codexmv)
    codex_handle_move "$@"
    ;;
  *)
    printf 'Usage: %s {codex|codexr|codexfork|codexmv} [arguments...]\n' "$0" >&2
    exit 2
    ;;
esac
