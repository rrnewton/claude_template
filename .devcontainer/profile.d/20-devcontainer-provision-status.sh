# Fail LOUDLY, not in a log nobody reads.
#
# If container provisioning did not complete (or never ran), say so on every
# interactive login until it is fixed.  Non-interactive shells stay silent so
# scripts and scp/rsync sessions are not polluted.
# shellcheck shell=sh
case "$-" in
    *i*)
        if [ ! -e /run/devcontainer/status ]; then
            printf '\n\033[1;31m!! CONTAINER PROVISIONING NEVER RAN !!\033[0m\n'
            printf '   Nothing scheduled (cron) is running and baked tools may be missing.\n'
            printf '   Run: sudo /usr/local/bin/devcontainer-provision.sh\n\n'
        elif [ "$(cat /run/devcontainer/status 2>/dev/null)" != "ok" ]; then
            printf '\n\033[1;31m!! CONTAINER PROVISIONING FAILED !!\033[0m\n'
            # Only the verdict + the failure list, not the whole report --
            # a 25-line dump on every shell teaches people to ignore it.
            sed -n '/^PROVISIONING FAILED/,$p' /run/devcontainer/report 2>/dev/null \
                | sed 's/^/   /'
            printf '   Full report: /run/devcontainer/report\n'
            printf '   Re-run: sudo /usr/local/bin/devcontainer-provision.sh\n\n'
        fi
        ;;
esac
