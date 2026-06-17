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
    # Drop to the unprivileged user, preserving a login-ish environment.
    exec setpriv --reuid "$uid" --regid "$gid" --init-groups \
        env HOME="$home" USER="$RUN_AS_USER" LOGNAME="$RUN_AS_USER" "$@"
fi

exec "$@"
