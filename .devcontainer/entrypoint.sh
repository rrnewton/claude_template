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
    # Drop to the unprivileged user, preserving a login-ish environment.
    exec setpriv --reuid "$uid" --regid "$gid" --init-groups \
        env HOME="$home" USER="$RUN_AS_USER" LOGNAME="$RUN_AS_USER" "$@"
fi

if [ "${HERDR_INSTALL_INTEGRATIONS:-1}" != "0" ]; then
    install_herdr_integrations "${HOME:-/root}"
fi
warn_if_herdr_socket_unreachable

exec "$@"
