# Give every login shell the same PATH that agent shells and cron jobs get.
# See /usr/local/lib/devcontainer/paths.sh for why this is centralized.
# shellcheck shell=sh
[ -r /usr/local/lib/devcontainer/paths.sh ] && . /usr/local/lib/devcontainer/paths.sh
