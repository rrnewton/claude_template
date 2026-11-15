#!/bin/bash
# Devcontainer entrypoint: make the bind-mounted home writable for the run user,
# WITHOUT podman --userns=keep-id (which on stricter crun versions fails to launch
# at all, because crun cannot apply podman's default net.ipv4.ping_group_range
# sysctl inside a keep-id user namespace).
#
# Strategy: the container starts as ROOT in podman's NORMAL rootless namespace
# (where the default sysctls apply cleanly, exactly like `make root`). As root we
# chown the run user's bind-mounted home so it is writable, then drop privileges
# and exec the requested command as that user.
#
# Controlled by env:
#   RUN_AS_USER   target unprivileged user to drop to (e.g. "ubuntu").
#                 If unset/empty, we just exec the command as-is (root).
#
# If we are NOT uid 0 (e.g. someone still runs `-u ubuntu` directly), we cannot
# chown, so we simply exec the command — no failure, just best-effort.
set -e

# Start cron as root when the image has it (DeepScry's scheduled ops jobs).
# A daemon already running (a re-entered container) is left alone.
if [ "$(id -u)" = "0" ] && command -v cron >/dev/null 2>&1 && ! pgrep -x cron >/dev/null 2>&1; then
    cron || echo "warning: could not start cron; scheduled ops jobs will not run" >&2
fi

# ── Self-healing hook (DeepScry ds-owq2mpr, 2026-11-14) ──────────────────────
# A project may declare the goal state of its container and ship ONE idempotent
# healer for it. This entrypoint runs that healer on EVERY container start, so a
# restarted or recreated container converges back (cron, build tools, agent
# CLIs, Herdr, the agent team) without a person re-running bootstrap scripts.
#
#   DEVCONTAINER_HEAL=0              disable the hook entirely (stated loudly)
#   DEVCONTAINER_HEAL_HOOK=<path>    the healer (default: $PWD/ops/container-heal.sh,
#                                    i.e. the workspace mounted at the WORKDIR)
#   DEVCONTAINER_HEAL_FOREGROUND=1   wait for the start pass before running "$@"
#   DEVCONTAINER_HEAL_INTERVAL=<s>   tick period in `supervise` mode (default 600)
#
# The hook is called as `<hook> start` once and, in `supervise` mode, as
# `<hook> tick` periodically. Its logs go to ~/.local/state/devcontainer-heal/.
#
# `supervise` is the command for the DETACHED service container (`make service`):
# PID 1 then runs the start pass and a tick loop instead of an interactive shell,
# exits 0 on SIGTERM (podman stop), and is otherwise never expected to exit.
# Run the container with --init so zombie reaping is not PID 1's job.
heal_hook="${DEVCONTAINER_HEAL_HOOK:-$PWD/ops/container-heal.sh}"
heal_log_dir="${HOME:-/root}/.local/state/devcontainer-heal"

heal_hook_usable() {
    if [ "${DEVCONTAINER_HEAL:-1}" = "0" ]; then
        echo "devcontainer: DEVCONTAINER_HEAL=0; NOT running the self-heal hook" >&2
        return 1
    fi
    if [ ! -x "$heal_hook" ]; then
        echo "warning: no executable self-heal hook at $heal_hook; nothing will repair this container on start" >&2
        return 1
    fi
    mkdir -p "$heal_log_dir"
}

run_heal_start() { # foreground|background
    heal_hook_usable || return 0
    start_log="$heal_log_dir/start-$(date +%Y%m%dT%H%M%S).log"
    if [ "$1" = "foreground" ]; then
        echo "devcontainer: self-heal start pass (log $start_log)"
        "$heal_hook" start >"$start_log" 2>&1 \
            || echo "warning: self-heal start pass did not converge; see $start_log" >&2
        tail -n 3 "$start_log"
    else
        setsid "$heal_hook" start >"$start_log" 2>&1 </dev/null &
        echo "devcontainer: self-heal start pass running in the background (log $start_log)"
    fi
}

supervise() {
    sleep_pid=""
    trap 'echo "devcontainer supervisor: SIGTERM, exiting"; [ -n "$sleep_pid" ] && kill "$sleep_pid" 2>/dev/null; exit 0' TERM INT
    run_heal_start foreground
    tick_log="$heal_log_dir/tick.log"
    while :; do
        sleep "${DEVCONTAINER_HEAL_INTERVAL:-600}" &
        sleep_pid=$!
        wait "$sleep_pid"
        heal_hook_usable 2>/dev/null || continue
        if [ -f "$tick_log" ] && [ "$(stat -c %s "$tick_log")" -gt 5000000 ]; then
            mv -f "$tick_log" "$tick_log.1"
        fi
        "$heal_hook" tick >>"$tick_log" 2>&1 || true
    done
}

start_pass_or_supervise() {
    # Root only: the healer installs packages and starts daemons.
    [ "$(id -u)" = "0" ] || return 0
    if [ "${1:-}" = "supervise" ]; then
        supervise
    elif [ "${DEVCONTAINER_HEAL_FOREGROUND:-0}" = "1" ]; then
        run_heal_start foreground
    else
        run_heal_start background
    fi
}

if [ "${1:-}" = "supervise" ] && [ "$(id -u)" != "0" ]; then
    echo "error: supervise mode must run as root (it installs packages and starts daemons)" >&2
    exit 1
fi

warn_if_herdr_socket_unreachable() {
    if [ "${HERDR_ENV:-}" != "1" ] || [ -z "${HERDR_SOCKET_PATH:-}" ]; then
        return
    fi
    if [ ! -S "$HERDR_SOCKET_PATH" ]; then
        echo "warning: Herdr socket is not visible at $HERDR_SOCKET_PATH; session hooks cannot report to the host" >&2
    elif [ ! -w "$HERDR_SOCKET_PATH" ]; then
        echo "warning: uid $(id -u) cannot connect to Herdr socket $HERDR_SOCKET_PATH; use a root container or configure a socket proxy/user mapping" >&2
    fi
}

install_herdr_integrations() {
    runtime_home="$1"
    mkdir -p "$runtime_home/.claude" "$runtime_home/.codex"
    HOME="$runtime_home" CLAUDE_CONFIG_DIR="$runtime_home/.claude" \
        herdr integration install claude
    HOME="$runtime_home" CODEX_HOME="$runtime_home/.codex" \
        herdr integration install codex
}

if [ -n "$RUN_AS_USER" ] && [ "$(id -u)" = "0" ]; then
    home="$(getent passwd "$RUN_AS_USER" | cut -d: -f6)"
    uid="$(id -u "$RUN_AS_USER")"
    gid="$(id -g "$RUN_AS_USER")"
    if [ -n "$home" ] && [ -d "$home" ]; then
        # Only chown the top level + create-able state; a full -R could be slow on
        # a large mounted home, and ownership of the mount root is what gates
        # `mkdir ~/.codex`. Chown recursively only if the root is not already ours.
        if [ "$(stat -c %u "$home")" != "$uid" ]; then
            chown -R "$uid:$gid" "$home" 2>/dev/null || chown "$uid:$gid" "$home"
        fi
    fi
    if [ "${HERDR_INSTALL_INTEGRATIONS:-1}" != "0" ]; then
        setpriv --reuid "$uid" --regid "$gid" --init-groups \
            env HOME="$home" PATH="$PATH" \
            bash -c 'mkdir -p "$HOME/.claude" "$HOME/.codex" && \
                CLAUDE_CONFIG_DIR="$HOME/.claude" herdr integration install claude && \
                CODEX_HOME="$HOME/.codex" herdr integration install codex'
    fi
    if [ "${HERDR_ENV:-}" = "1" ] && [ -n "${HERDR_SOCKET_PATH:-}" ]; then
        setpriv --reuid "$uid" --regid "$gid" --init-groups \
            env HERDR_ENV="$HERDR_ENV" HERDR_SOCKET_PATH="$HERDR_SOCKET_PATH" \
            PATH="$PATH" bash -c '
                if [ ! -S "$HERDR_SOCKET_PATH" ]; then
                    echo "warning: Herdr socket is not visible at $HERDR_SOCKET_PATH; session hooks cannot report to the host" >&2
                elif [ ! -w "$HERDR_SOCKET_PATH" ]; then
                    echo "warning: uid $(id -u) cannot connect to Herdr socket $HERDR_SOCKET_PATH; use a root container or configure a socket proxy/user mapping" >&2
                fi'
    fi
    start_pass_or_supervise "$@"
    # Drop to the unprivileged user, preserving a login-ish environment.
    exec setpriv --reuid "$uid" --regid "$gid" --init-groups \
        env HOME="$home" USER="$RUN_AS_USER" LOGNAME="$RUN_AS_USER" "$@"
fi

if [ "${HERDR_INSTALL_INTEGRATIONS:-1}" != "0" ]; then
    install_herdr_integrations "${HOME:-/root}" \
        || echo "warning: herdr integration install failed; Claude/Codex session hooks may not report to Herdr" >&2
fi
warn_if_herdr_socket_unreachable

start_pass_or_supervise "$@"
exec "$@"
