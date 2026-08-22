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

# ---------------------------------------------------------------------------
# Provision the container before handing control to the requested command
# (ds-3ij3j4).
#
# Only $HOME is persistent on these hosts and there is no init system, so a
# freshly recreated container starts with no cron daemon and none of the
# runtime state the project's data plane needs. devcontainer-provision.sh is
# idempotent and does the pieces that genuinely cannot be baked into the image.
#
# Deliberately NON-FATAL: a provisioning failure must never leave the user
# unable to get a shell and debug it. It fails LOUDLY instead --
#   * a banner here,
#   * /run/devcontainer/status set to "failed" plus a report,
#   * a red banner on every interactive login until it is fixed
#     (/etc/profile.d/20-devcontainer-provision-status.sh),
#   * `devcontainer-provision.sh --check` exits nonzero.
#
# HOME is passed explicitly because it decides where the PERSISTENT tool
# prefix ($HOME/local/node) is created, and that differs between the two run
# shapes: `make root` keeps root's home, `make run` drops to $RUN_AS_USER.
# ---------------------------------------------------------------------------
provision_container() {
    target_home="$1"
    [ "$(id -u)" = "0" ] || return 0
    [ -x /usr/local/bin/devcontainer-provision.sh ] || return 0
    if ! HOME="$target_home" /usr/local/bin/devcontainer-provision.sh --quiet; then
        echo "" >&2
        echo "############################################################" >&2
        echo "## CONTAINER PROVISIONING FAILED -- see the report above.  ##" >&2
        echo "## Scheduled jobs and/or baked tools are NOT usable.       ##" >&2
        echo "## Re-run: devcontainer-provision.sh                       ##" >&2
        echo "############################################################" >&2
        echo "" >&2
    fi
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
    provision_container "${home:-$HOME}"
    # Drop to the unprivileged user, preserving a login-ish environment.
    exec setpriv --reuid "$uid" --regid "$gid" --init-groups \
        env HOME="$home" USER="$RUN_AS_USER" LOGNAME="$RUN_AS_USER" "$@"
fi

provision_container "$HOME"

exec "$@"
