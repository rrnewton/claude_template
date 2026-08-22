#!/usr/bin/env bash
# devcontainer-provision.sh — bring a freshly created container to a FULLY
# USABLE state with no manual step and nothing for anyone to remember.
#
# Installed into the image at /usr/local/bin/devcontainer-provision.sh and run
# automatically by the image ENTRYPOINT (entrypoint.sh) on every container
# start, and again by devcontainer.json's postStartCommand.  Idempotent and
# safe to re-run at any time.
#
#
# WHAT SURVIVES A CONTAINER RECREATION, AND WHAT DOES NOT
# =========================================================================
# PERSISTENT  $HOME only.  It is a bind mount of .devcontainer/home/ on the
#             host (see the Makefile `root`/`run` targets), so everything
#             under $HOME — including $HOME/bin, $HOME/local/node, the
#             crontab's *contents* if you save them there, credentials and
#             agent state — outlives any number of rebuilds.
#
# BAKED       Anything installed by the Dockerfile fragments.  `/` is an
#             overlay whose upper layer is discarded on recreation, but the
#             image layers underneath are re-applied, so /usr, /usr/local and
#             /opt come back EXACTLY as the image built them.  Baking is
#             therefore durable, and is the preferred home for static tools.
#
# EPHEMERAL   Anything written into `/` AFTER the container started: an
#             `apt-get install` you ran by hand, an `npm install -g` into
#             /usr, a `pip install` into /opt/venv, the live crontab in
#             /var/spool/cron, and — because there is NO INIT SYSTEM here
#             (PID 1 is a plain bash) — every running process.  All of it is
#             gone on the next recreation, silently.
#
# The rule that follows: if a tool is static, BAKE IT into a Dockerfile
# fragment.  Use this script only for what genuinely cannot be baked —
# starting a daemon, anything that must live on the persistent volume, and
# anything needing secrets or the mounted workspace.
#
#
# WHY THIS EXISTS (ds-3ij3j4)
# =========================================================================
# This container was recreated on 2026-07-21.  That recreation silently
# destroyed cron, wrangler, PyYAML, pytest, mypy, rsync, mdbook and a current
# minibeads build.  Nobody noticed for a month, and the production Cloudflare
# D1 user database went un-backed-up the whole time.  Every one of those
# failures returned a plausible-looking success to whoever last looked.
#
# Usage:
#   devcontainer-provision.sh            # provision / repair, then report
#   devcontainer-provision.sh --check    # report only; exit 1 if not fully provisioned
#   devcontainer-provision.sh --quiet    # only print on failure

# NOTE: deliberately NOT `set -e`.  This script's job is to report EVERY
# problem it finds, not to die on the first one.
set -uo pipefail

# /run is ephemeral, which is exactly right: the status must never survive a
# container recreation and claim a fresh container is already provisioned.
# Overridable only so the state can be redirected when testing.
STATE_DIR="${DEVCONTAINER_STATE_DIR:-/run/devcontainer}"
STATUS_FILE="$STATE_DIR/status"
REPORT_FILE="$STATE_DIR/report"
PERSISTENT_LOG="${HOME:-/root}/.devcontainer/provision.log"
HOOK_TIMEOUT="${DEVCONTAINER_HOOK_TIMEOUT:-600}"

CHECK_ONLY=0
QUIET=0
while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1; shift ;;
        --quiet) QUIET=1; shift ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "devcontainer-provision.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
done

# Ask the PATH question the way cron and plain login shells ask it, never the
# way a richer agent shell asks it.
# shellcheck source=container-paths.sh
[ -r /usr/local/lib/devcontainer/paths.sh ] && . /usr/local/lib/devcontainer/paths.sh

FAILURES=()
NOTES=()
REPORT=()

say()  { REPORT+=("$*"); [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
ok()   { say "  ok      $*"; }
fail() { FAILURES+=("$*"); say "  FAIL    $*"; }
note() { NOTES+=("$*");    say "  note    $*"; }

# -- 1. Baked prerequisites ------------------------------------------------
#
# Each entry is "command:what installs it".  Anything listed here MUST come
# from a Dockerfile fragment; if it is missing, the running image is older
# than this script and the honest answer is "rebuild the image", not "let me
# quietly apt-get it for you" (that install would evaporate on the next
# recreation and we would be back to a month of silent failure).
#
# Keep in sync with Dockerfile.prefix / Dockerfile.rust / Dockerfile.project.
# tests/test_provisioning_static.sh enforces that.
REQUIRED_COMMANDS=(
    "crontab:cron (Dockerfile.prefix)"
    "rsync:rsync (Dockerfile.prefix)"
    "git:git (Dockerfile.prefix)"
    "tmux:tmux (Dockerfile.prefix)"
    "jq:jq (Dockerfile.prefix)"
    "node:nodejs (Dockerfile.prefix)"
    "npm:nodejs (Dockerfile.prefix)"
    "wrangler:npm -g wrangler (Dockerfile.prefix)"
    "cargo:rustup (Dockerfile.rust)"
    "mb:minibeads (Dockerfile.rust)"
    "mdbook:cargo install mdbook (Dockerfile.rust)"
)

# Python packages that must be importable from the shared virtualenv.
# Keep in sync with Dockerfile.prefix's `/opt/venv/bin/python3 -m pip install`.
VENV_PYTHON=/opt/venv/bin/python3
REQUIRED_PYTHON_MODULES=(yaml pytest mypy pandas)

say "== baked prerequisites =="
for entry in "${REQUIRED_COMMANDS[@]}"; do
    cmd="${entry%%:*}"; src="${entry#*:}"
    if resolved="$(command -v "$cmd" 2>/dev/null)"; then
        ok "$cmd -> $resolved"
    else
        fail "$cmd is NOT on PATH; it should be baked by $src. REBUILD THE IMAGE (make cycle) rather than installing it by hand -- a hand install is discarded on the next container recreation."
    fi
done

if [ -x "$VENV_PYTHON" ]; then
    for mod in "${REQUIRED_PYTHON_MODULES[@]}"; do
        if "$VENV_PYTHON" -c "import $mod" >/dev/null 2>&1; then
            ok "python module $mod (in /opt/venv)"
        else
            fail "python module '$mod' missing from /opt/venv; it should be baked by Dockerfile.prefix. REBUILD THE IMAGE (make cycle)."
        fi
    done
else
    fail "/opt/venv/bin/python3 does not exist; the shared virtualenv was not baked (Dockerfile.prefix)."
fi

# -- 2. The cron daemon (cannot be baked: there is no init system) ---------
say "== cron daemon =="
cron_running() { pgrep -x cron >/dev/null 2>&1 || pgrep -x crond >/dev/null 2>&1; }
if cron_running; then
    ok "cron daemon running (pid $(pgrep -x cron 2>/dev/null || pgrep -x crond 2>/dev/null))"
elif [ "$CHECK_ONLY" = 1 ]; then
    fail "cron daemon is NOT running; nothing scheduled will execute. Run devcontainer-provision.sh."
else
    # The package postinst cannot start it ("invoke-rc.d: policy-rc.d denied
    # execution of start") because PID 1 is a plain bash, so start it directly.
    # It is NOT supervised: if it dies, nothing restarts it. --check notices.
    if [ -x /usr/sbin/cron ]; then /usr/sbin/cron
    elif [ -x /usr/sbin/crond ]; then /usr/sbin/crond
    fi
    sleep 1
    if cron_running; then
        ok "cron daemon started (pid $(pgrep -x cron 2>/dev/null || pgrep -x crond 2>/dev/null))"
    else
        fail "could not start a cron daemon (looked for /usr/sbin/cron and /usr/sbin/crond); nothing scheduled will execute."
    fi
fi

# -- 3. Persistent tool prefix --------------------------------------------
# $HOME survives recreation, so anything a hook installs at runtime belongs
# here rather than in /usr.  Creating it up front means the PATH entry from
# container-paths.sh actually resolves.
say "== persistent prefix =="
PERSISTENT_NODE_PREFIX="${DEEPSCRY_NODE_PREFIX:-${HOME:-/root}/local/node}"
if [ "$CHECK_ONLY" = 1 ]; then
    [ -d "$PERSISTENT_NODE_PREFIX/bin" ] \
        && ok "$PERSISTENT_NODE_PREFIX/bin exists" \
        || note "$PERSISTENT_NODE_PREFIX/bin does not exist yet (created on the next provisioning run)"
else
    mkdir -p "$PERSISTENT_NODE_PREFIX/bin" 2>/dev/null \
        && ok "$PERSISTENT_NODE_PREFIX/bin ready" \
        || note "could not create $PERSISTENT_NODE_PREFIX/bin"
fi

# -- 4. Project provisioning hook -----------------------------------------
# The image knows nothing about any particular project.  If the mounted
# workspace ships a hook, run it; that is where project-specific data-plane
# setup lives (for DeepScry: ops/bootstrap-container.sh, which installs the
# managed crontab block that drives the D1 user-database backup).
say "== project hook =="
find_hook() {
    local c
    for c in \
        "${DEVCONTAINER_PROJECT_HOOK:-}" \
        "${DEVCONTAINER_WORKDIR:-}/ops/bootstrap-container.sh" \
        "${DEVCONTAINER_WORKDIR:-}/.devcontainer-provision" \
        /workspace/ops/bootstrap-container.sh \
        /workspace/.devcontainer-provision ; do
        [ -n "$c" ] && [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
    done
    return 1
}

if hook="$(find_hook)"; then
    if [ "$CHECK_ONLY" = 1 ]; then
        if "$hook" --check >/dev/null 2>&1; then
            ok "project hook $hook reports everything in place"
        else
            fail "project hook $hook reports it still needs to run (\`$hook --check\` exited nonzero)"
        fi
    else
        say "  running $hook (timeout ${HOOK_TIMEOUT}s)"
        if timeout "$HOOK_TIMEOUT" "$hook" >>"$PERSISTENT_LOG" 2>&1; then
            ok "project hook $hook completed (output appended to $PERSISTENT_LOG)"
        else
            hook_rc=$?
            if [ "$hook_rc" = 124 ]; then
                fail "project hook $hook TIMED OUT after ${HOOK_TIMEOUT}s; see $PERSISTENT_LOG"
            else
                fail "project hook $hook exited $hook_rc; see $PERSISTENT_LOG"
            fi
        fi
    fi
else
    # A standalone clone legitimately has no hook.  Visible, not silent.
    note "no project provisioning hook found (looked for \$DEVCONTAINER_WORKDIR/ops/bootstrap-container.sh and .devcontainer-provision); nothing project-specific was set up"
fi

# -- 5. Verdict ------------------------------------------------------------
say ""
if [ "${#FAILURES[@]}" -eq 0 ]; then
    verdict="ok"
    say "PROVISIONING OK  (${#NOTES[@]} note(s))"
else
    verdict="failed"
    say "PROVISIONING FAILED  (${#FAILURES[@]} problem(s)):"
    for f in "${FAILURES[@]}"; do say "  - $f"; done
fi

if [ "$CHECK_ONLY" = 0 ]; then
    mkdir -p "$STATE_DIR" 2>/dev/null
    printf '%s\n' "$verdict" > "$STATUS_FILE" 2>/dev/null
    printf '%s\n' "${REPORT[@]}" > "$REPORT_FILE" 2>/dev/null
    mkdir -p "$(dirname "$PERSISTENT_LOG")" 2>/dev/null
    { printf '\n===== devcontainer-provision %s =====\n' "$(date -Is)"
      printf '%s\n' "${REPORT[@]}"; } >> "$PERSISTENT_LOG" 2>/dev/null
fi

if [ "${#FAILURES[@]}" -eq 0 ]; then
    exit 0
fi
# On failure ALWAYS print, even under --quiet: silence here is the exact bug
# this whole change exists to kill.
if [ "$QUIET" = 1 ]; then printf '%s\n' "${REPORT[@]}" >&2; fi
exit 1
