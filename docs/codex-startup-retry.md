# Codex workspace-routing startup timeout

## Symptom and diagnosis

Codex CLI 0.156.1 can intermittently exit before either a new conversation or a resumed conversation opens:

```text
Error: account/read failed during TUI bootstrap: account/read failed: workspace routing discovery timed out (code -32603)
```

Manual retries may work. This error is not itself evidence of a broken session database, wrong account, expired login, or shared-history corruption.

In the [0.156.1 account processor](https://github.com/openai/codex/blob/rust-v0.156.1/codex-rs/app-server/src/request_processors/account_processor/workspace_routing.rs), `read_account` wraps configuration/authentication loading and workspace-routing discovery in a **15-second timeout**. Discovery calls `get_accounts_check`; results are cached within that app-server process. A separate successful preflight process cannot populate a later TUI process's cache.

On 2026-09-24, initial direct native app-server `account/read` probes under two separate selected accounts both succeeded: approximately 1.2 seconds cold and 0.01–0.03 seconds warm. A subsequent six-process sample **without AgentShell** reproduced four discovery timeouts at 15.006–15.013 seconds; two calls succeeded in approximately 2.3 seconds. This is not solely a wrapper/picker failure.

Independent HTTPS probes also observed intermittent TCP/TLS stalls to one of ChatGPT's two DNS-returned IPv4 addresses, while the other responded promptly. Both addresses later responded normally. Router DNS answers agreed with Google and Cloudflare DNS-over-HTTPS; this was not evidence of a wrong DNS record. An unauthenticated `401` from the accounts-check endpoint was expected for those transport probes and did not mean the saved Codex login failed.

This establishes a native discovery timeout plus intermittent transport trouble, but does not identify which router, upstream network or service caused every failed request. Both wired and Wi-Fi paths subsequently worked. No global DNS/route changes or permanent CDN-IP pinning were made. The guard is bounded recovery, not a claim that the underlying network/service fault has been permanently repaired.

A later three-round, interface-bound comparison strengthened the network evidence: Wi-Fi completed all six unauthenticated HTTPS probes in 0.30–0.49 seconds; wired completed four of six in 0.77–2.28 seconds and timed out connecting to both addresses in the third round. The default route used wired networking. This points to the wired upstream path rather than a permanent bad CDN IP, but the exact failing gateway/hop was not identified. Existing routes and active sessions were intentionally left untouched.

## Use it

Install/update AgentShell normally:

```bash
./install.sh
. "$HOME/.bashrc"
agentshell company
agentshell -v
codexr
```

Another terminal can independently use:

```bash
. "$HOME/.bashrc"
agentshell lab
codex
```

One-off account selection works too:

```bash
codex --account personal
codexr --account company --all
```

Keep using existing logins. `agentshell -v` shows the local account label, history mode and state paths; `/status` inside Codex verifies the authenticated identity. Shared history is still optional, and it is not an access-control boundary between people using the same Unix account.

## Exactly what is retried

The optional Python-standard-library helper, `bin/codex-startup`, is used by named-account native CLI dispatch on Linux/WSL when Python 3 is available. The native TUI keeps its original stdin and stdout TTYs. Only stderr is relayed, byte-for-byte, retaining at most 64 KiB **in memory**, not on disk.

All of these must hold:

1. This is an interactive local CLI invocation, not a pipe or redirected command.
2. The process exits with status `1` within 120 seconds.
3. Its final stderr line exactly matches the account-routing timeout during TUI bootstrap.
4. No interrupt/termination signal was received, and attempts remain.

Default: three total attempts, with 2-second and 4-second waits. Ctrl+C cancels. Credentials, environment, working directory, arguments, native executable and selected resume ID remain unchanged. The fast workstation picker is not rerun when its selection has already been passed to the native launcher. A native picker may reappear if its own selection happened inside the failed process.

There is no extra network check on a successful startup, no login/logout, no cross-account fallback and no workspace-policy bypass. The helper does not retry `exec`, reviews, queued work, login, updates, app-server, unknown options, remote-server connections or worktree creation. Other failures and ordinary session exits pass through. It does not attempt to recover a crashed working conversation.

The Linux guard is deliberately not enabled on macOS or Windows: native terminal handling differs there and needs platform-specific validation. Their existing account dispatch remains unchanged. Desktop GUI launches are also unchanged.

## Existing workstation wrappers

When AgentShell delegates to an external `codex_wrapper.sh`, that wrapper owns the final native launch. Add the guard at that point, **after** selecting a resume session and account-specific history view. Do not wrap `codexr`'s picker in a retry loop.

For the existing `codex_run_native` function:

```bash
codex_run_native() {
  local real_bin="$1"
  local startup_helper="${AGENT_SHELL_INSTALL_ROOT:-$HOME/.local/lib/agentshell}/codex-startup"
  shift
  if [ -f "$startup_helper" ] && command -v python3 >/dev/null 2>&1; then
    exec python3 "$startup_helper" "$real_bin" -s danger-full-access -a never "$@"
  fi
  exec "$real_bin" -s danger-full-access -a never "$@"
}
```

The permission flags here preserve that particular workstation's existing settings; the generic AgentShell launcher itself does not add permission flags. Keep your own policy if different. The Bash wrapper still `exec`s away, avoiding the old long-lived-Bash/live-edit EOF problem. Python loads its helper once when launched.

On the workstation this integration applies to ordinary `codex`, `codexr`, and the interactive launch following a completed `codexmv`; a migration itself is never repeated. Existing terminals that already invoke this wrapper pick up the installed helper on their next command. Already-running Codex sessions are not modified.

## Disable or limit it

Inside an AgentShell terminal:

```bash
CODEX_STARTUP_ATTEMPTS=1 codexr
```

For a one-off named account:

```bash
CODEX_STARTUP_ATTEMPTS=1 codex --account lab
```

Supported range: 1–5 total attempts; default 3. An invalid value disables retries rather than creating an unbounded loop. For a permanent opt-out, export `CODEX_STARTUP_ATTEMPTS=1` in the shell startup configuration. No account or session data needs restoration.

## Validation and troubleshooting

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
python3 -m unittest discover -s tests -p test_startup.py -v
git diff --check
```

Regression tests use fake Codex executables in isolated temporary profiles and pseudo-terminals. They cover argument/CWD/account preservation, real stdin/stdout TTYs, success, exact-error detection, bounded retries, Ctrl+C, noninteractive passthrough, unrelated errors and opt-out. They do not call a model or read real account credentials.

If three attempts still fail, the last native error is preserved. Check the service/network and the native client version rather than increasing retries indefinitely. A 401, missing workspace, residency restriction, or corrupted history is a different problem and must be investigated separately. Never fix this timeout by copying another account's `auth.json`, rewriting SQLite/JSONL, or disabling routing enforcement.
