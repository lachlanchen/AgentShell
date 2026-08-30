#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/agentshell-test.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

export HOME="$test_root/home"
export AGENT_SHELL_HOME="$test_root/state"
export AGENT_SHELL_BIN_DIR="$test_root/bin"
export AGENT_SHELL_CODEX_WRAPPER="$test_root/missing-wrapper"
export AGENT_SHELL_USE_CODEX_WRAPPER=0
export AGENT_TEST_OUTPUT="$test_root/invocation.txt"
unset AGENT_SHELL_ACCOUNT AGENT_SHELL_PROFILE_ROOT AGENT_SHELL_PROFILE_ENV \
  AGENT_SHELL_CODEX_HISTORY_MODE AGENT_SHELL_CODEX_SQLITE_HOME \
  AGENT_SHELL_CODEX_HOME CODEX_HOME CODEX_SQLITE_HOME || true
mkdir -p "$HOME/.codex/skills" "$AGENT_SHELL_BIN_DIR" "$test_root/native" "$test_root/work/tree"

cat > "$HOME/.codex/config.toml" <<'EOF'
model = "test-model"
sqlite_home = "/must/not/be/inherited"
EOF
printf 'must-not-copy\n' > "$HOME/.codex/auth.json"
printf 'shared skill\n' > "$HOME/.codex/skills/example.md"

cat > "$test_root/native/codex" <<'EOF'
#!/usr/bin/env bash
{
  printf 'tool=%s\n' "$(basename -- "$0")"
  printf 'cwd=%s\n' "$(pwd -P)"
  printf 'codex_home=%s\n' "${CODEX_HOME:-}"
  printf 'sqlite_home=%s\n' "${CODEX_SQLITE_HOME:-}"
  printf 'account=%s\n' "${AGENT_SHELL_ACCOUNT:-}"
  printf 'openai_api_key=%s\n' "${OPENAI_API_KEY-unset}"
  for argument in "$@"; do printf 'arg=%s\n' "$argument"; done
} > "$AGENT_TEST_OUTPUT"
printf 'stub codex\n'
EOF
chmod 0755 "$test_root/native/codex"
ln -s codex "$test_root/native/codexmv"

for name in agentshell agent-run agent-profile agent-codex agent-codexr agent-codexmv agent-claude agent-gemini agent-copilot; do
  ln -s "$repo_root/bin/agentshell" "$AGENT_SHELL_BIN_DIR/$name"
done
export PATH="$AGENT_SHELL_BIN_DIR:$test_root/native:/usr/bin:/bin"
export OPENAI_API_KEY='inherited-key-must-be-cleared'

agent-profile create alpha >/dev/null
profile="$AGENT_SHELL_HOME/profiles/alpha"

test -d "$profile/codex-home"
test -d "$profile/gemini-home/.gemini"
test -L "$profile/codex-home/skills"
test ! -e "$profile/codex-home/auth.json"
grep -q 'model = "test-model"' "$profile/codex-home/config.toml"
! grep -q 'sqlite_home' "$profile/codex-home/config.toml"
test -L "$AGENT_SHELL_BIN_DIR/agent-alpha-codex"

cd "$test_root/work/tree"
agent-alpha-codex --model test-model 'hello world' >/dev/null
grep -q "^cwd=$test_root/work/tree$" "$AGENT_TEST_OUTPUT"
grep -q "^codex_home=$profile/codex-home$" "$AGENT_TEST_OUTPUT"
grep -q '^account=alpha$' "$AGENT_TEST_OUTPUT"
grep -q '^openai_api_key=unset$' "$AGENT_TEST_OUTPUT"
grep -q '^arg=--model$' "$AGENT_TEST_OUTPUT"
grep -q '^arg=hello world$' "$AGENT_TEST_OUTPUT"
grep -q "^sqlite_home=$profile/codex-home$" "$AGENT_TEST_OUTPUT"

agent-profile history alpha shared >/dev/null
agent-alpha-codex --version >/dev/null
grep -q "^sqlite_home=$HOME/.codex$" "$AGENT_TEST_OUTPUT"
grep -q "^codex_home=$profile/codex-shared-home$" "$AGENT_TEST_OUTPUT"
test -L "$profile/codex-shared-home/sessions"
test "$(realpath "$profile/codex-shared-home/sessions")" = "$(realpath "$HOME/.codex/sessions")"
test ! -e "$profile/codex-shared-home/auth.json"
test -f "$profile/codex-shared-home/.account-state-v1"
test -f "$profile/codex-shared-home/config.toml"
test ! -L "$profile/codex-shared-home/config.toml"
grep -q '^History mode:   shared$' <<<"$(agentshell status alpha)"
grep -q '^AgentShell 0.4.0$' <<<"$(agentshell --version)"

# Optional Bash interception changes only calls that explicitly name an account.
alias cr='printf existing-cr'
# shellcheck disable=SC1091
. "$repo_root/shell/agentshell.bash"
alias cr | grep -q 'printf existing-cr'

codex --version >/dev/null
grep -q '^tool=codex$' "$AGENT_TEST_OUTPUT"
grep -q '^account=$' "$AGENT_TEST_OUTPUT"
grep -q '^openai_api_key=inherited-key-must-be-cleared$' "$AGENT_TEST_OUTPUT"
grep -q '^arg=--version$' "$AGENT_TEST_OUTPUT"

codexr --all >/dev/null
grep -q '^tool=codex$' "$AGENT_TEST_OUTPUT"
grep -q '^account=$' "$AGENT_TEST_OUTPUT"
grep -q '^arg=resume$' "$AGENT_TEST_OUTPUT"
grep -q '^arg=--all$' "$AGENT_TEST_OUTPUT"

codexmv '/old project' '/new project' --no-resume >/dev/null
grep -q '^tool=codexmv$' "$AGENT_TEST_OUTPUT"
grep -q '^account=$' "$AGENT_TEST_OUTPUT"
grep -q '^arg=/old project$' "$AGENT_TEST_OUTPUT"
grep -q '^arg=/new project$' "$AGENT_TEST_OUTPUT"

codex -p native-profile --account beta >/dev/null
grep -q '^account=$' "$AGENT_TEST_OUTPUT"
grep -q '^arg=-p$' "$AGENT_TEST_OUTPUT"
grep -q '^arg=--account$' "$AGENT_TEST_OUTPUT"

codex --account beta --version >/dev/null
grep -q '^account=beta$' "$AGENT_TEST_OUTPUT"
grep -q '^arg=--version$' "$AGENT_TEST_OUTPUT"
grep -q "^sqlite_home=$AGENT_SHELL_HOME/profiles/beta/codex-home$" "$AGENT_TEST_OUTPUT"
test "$profile" != "$AGENT_SHELL_HOME/profiles/beta"

if agent-codex --account= --version >/dev/null 2>&1; then
  printf 'empty account value was unexpectedly accepted\n' >&2
  exit 1
fi

# Legacy rollout paths receive an account-isolated view over their original
# history tree. The selected account's credentials are never replaced by the
# source profile's credentials.
mkdir -p "$AGENT_SHELL_HOME/profiles/beta/codex-home/sessions/2026/08/30"
legacy_rollout="$AGENT_SHELL_HOME/profiles/beta/codex-home/sessions/2026/08/30/rollout-test.jsonl"
printf '{}\n' > "$legacy_rollout"
printf 'alpha auth\n' > "$profile/codex-shared-home/auth.json"
legacy_view="$(agent-profile codex-home alpha "$legacy_rollout")"
test "$legacy_view" = "$profile/codex-history-views/beta"
test "$(realpath "$legacy_view/sessions")" = "$(realpath "$AGENT_SHELL_HOME/profiles/beta/codex-home/sessions")"
test "$(readlink "$legacy_view/auth.json")" = "$profile/codex-shared-home/auth.json"

profile_list_output="$(agent-profile list)"
profile_show_output="$(agent-profile show alpha)"
grep -q alpha <<<"$profile_list_output"
grep -q "Working dir:   $test_root/work/tree (unchanged)" <<<"$profile_show_output"

if agent-profile create '../invalid' >/dev/null 2>&1; then
  printf 'invalid profile name was unexpectedly accepted\n' >&2
  exit 1
fi

printf 'AgentShell tests passed.\n'
