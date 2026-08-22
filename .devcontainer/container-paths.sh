#!/bin/sh
# Canonical PATH for this dev container.  Installed to
# /usr/local/lib/devcontainer/paths.sh and sourced by:
#
#   * /etc/profile.d/10-devcontainer-path.sh  -> every login shell
#   * cron jobs / other non-login contexts    -> `. /usr/local/lib/devcontainer/paths.sh`
#
# WHY THIS FILE EXISTS
# -------------------------------------------------------------------------
# Agent shells in this container historically carried PATH entries that a
# plain login shell and a cron job did NOT (/opt/cargo/bin, /opt/venv/bin,
# $HOME/bin).  A tool installed into $HOME/bin therefore looked present when
# checked from an agent shell and was completely invisible to cron and to
# scripts/deploy-cloud.sh.  That is how `mdbook` was "installed" and the
# deploy still could not find it.
#
# There is now exactly ONE definition of this container's PATH, and it is
# this file.  Verify a tool the way the rest of the system will see it:
#
#     env -i bash -lc 'command -v mdbook'
#
# POSIX sh on purpose: cron's /bin/sh is dash on Ubuntu.
# shellcheck shell=sh

devcontainer_path_prepend() {
    case ":${PATH}:" in
        *":$1:"*) ;;
        *) [ -d "$1" ] && PATH="$1:${PATH}" ;;
    esac
}

# Lowest priority first; each prepend wins over the previous one.
# $HOME/bin stays highest so a hand-placed override still beats the image.
# The Node toolchain lives at an image-internal path that only the image's
# `ENV PATH` advertises -- and cron does NOT inherit the image ENV, so without
# this glob `node`/`npm` are invisible to every scheduled job.
for _devcontainer_d in \
        /bin/versions/node/*/bin \
        /usr/bin/versions/node/*/bin \
        /usr/local/bin \
        /opt/local/bin \
        /opt/cargo/bin \
        /opt/venv/bin \
        "${HOME:-/root}/.local/bin" \
        "${HOME:-/root}/local/node/bin" \
        "${HOME:-/root}/bin" ; do
    devcontainer_path_prepend "$_devcontainer_d"
done
unset _devcontainer_d
export PATH
