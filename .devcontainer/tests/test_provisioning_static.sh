#!/usr/bin/env bash
# Static checks on the container provisioning wiring (ds-3ij3j4).
#
# These run WITHOUT building or starting a container, so they can run anywhere
# -- including from inside the very container they describe, where a rebuild is
# impossible. They catch the drift that caused the original outage: a tool the
# provisioning check demands that no Dockerfile fragment actually bakes.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.." || exit 2

fails=0
pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; fails=$((fails+1)); }

echo "== shell syntax =="
for f in provision.sh entrypoint.sh container-paths.sh \
         profile.d/10-devcontainer-path.sh profile.d/20-devcontainer-provision-status.sh; do
    if bash -n "$f" 2>/dev/null; then pass "bash -n $f"; else fail "bash -n $f"; fi
done
# container-paths.sh and the profile.d snippets are sourced by dash (cron's
# /bin/sh) as well as bash, so they must be POSIX-clean too.
for f in container-paths.sh profile.d/10-devcontainer-path.sh \
         profile.d/20-devcontainer-provision-status.sh; do
    if sh -n "$f" 2>/dev/null; then pass "sh -n $f (POSIX / dash)"; else fail "sh -n $f (POSIX / dash)"; fi
done

echo "== Dockerfile assembly =="
# The Makefile cats the fragments together; every fragment it names must exist.
for f in Dockerfile.prefix Dockerfile.claude Dockerfile.codex Dockerfile.happier \
         Dockerfile.rust Dockerfile.project Dockerfile.postfix; do
    [ -f "$f" ] && pass "fragment $f present" || fail "fragment $f MISSING"
done
assembled="$(cat Dockerfile.prefix Dockerfile.claude Dockerfile.codex Dockerfile.happier \
                 Dockerfile.rust Dockerfile.project Dockerfile.postfix 2>/dev/null)"
# Comment lines stripped. Without this, a fragment that merely TALKS about
# mdbook in a comment satisfies "is mdbook baked?" -- which is precisely the
# false-confidence failure this whole change exists to prevent. (The first
# draft of this test had that bug; removing the real `cargo install mdbook`
# line left the test green because the comment above it still said "mdbook".)
assembled_code="$(grep -v '^[[:space:]]*#' <<< "$assembled")"

echo "== every file the image COPYs exists =="
# NOTE: a here-string, not a pipeline. `grep -q` exits at the first match, and
# under `set -o pipefail` that SIGPIPEs the writer and turns a SUCCESSFUL match
# into a nonzero pipeline status -- racily, depending on where in the input the
# match lands. This test caught that flake in its own first draft; every match
# below therefore feeds grep from a here-string.
while read -r _ src _; do
    [ -n "$src" ] || continue
    if [ -f "$src" ]; then pass "COPY $src"; else fail "COPY $src does not exist"; fi
done <<< "$(grep -E '^COPY ' <<< "$assembled_code")"

echo "== provisioning requirements are actually baked =="
# Each command provision.sh demands must be traceable to a Dockerfile line.
# This is the check that would have caught "mdbook is required but nothing
# installs it", i.e. the class of bug behind the month-long silent outage.
declare -A BAKED_BY=(
    [crontab]='cron'
    [rsync]='rsync'
    [git]='git'
    [tmux]='tmux'
    [jq]='jq'
    [node]='nvm install'
    [npm]='nvm install'
    [wrangler]='wrangler'
    [cargo]='rustup'
    [mb]='minibeads'
    [mdbook]='mdbook'
)
for cmd in "${!BAKED_BY[@]}"; do
    if grep -q -F -- "${BAKED_BY[$cmd]}" <<< "$assembled_code"; then
        pass "$cmd is baked (Dockerfile mentions '${BAKED_BY[$cmd]}')"
    else
        fail "provision.sh requires '$cmd' but no Dockerfile fragment installs it"
    fi
done
# ...and each one must actually be listed in provision.sh, so the two lists
# cannot drift apart in the other direction either.
for cmd in "${!BAKED_BY[@]}"; do
    if grep -q -F "\"$cmd:" provision.sh; then
        pass "provision.sh checks for $cmd"
    else
        fail "$cmd is baked but provision.sh never verifies it"
    fi
done

echo "== python packages required by provision.sh are baked =="
for mod in yaml pytest mypy pandas; do
    pipname="$mod"; [ "$mod" = yaml ] && pipname=PyYAML
    if grep -v '^[[:space:]]*#' Dockerfile.prefix | grep -q "pip install.*$pipname"; then
        pass "python '$mod' baked via $pipname"
    else
        fail "provision.sh requires python module '$mod' but Dockerfile.prefix does not install $pipname"
    fi
done

echo "== provisioning is actually WIRED IN =="
# Comment lines stripped here too -- a file that only MENTIONS the provisioner
# in a comment is exactly the false pass we are guarding against.
code_of() { grep -vE '^[[:space:]]*(#|//)' "$1"; }
have() { grep -q -F -- "$2" <<< "$(code_of "$1")"; }

# Must be INVOKED, not merely mentioned or `[ -x ]`-tested: the provisioner
# appearing in an existence guard proves nothing about it ever running.
invokes() {
    local code inv
    code="$(code_of "$1")"
    # A line that merely TESTS for the file (`[ -x ... ]`) or PRINTS its name
    # in an error message does not count as running it. Everything else that
    # names the absolute path does. (Both exclusions are here because the first
    # draft of this test passed against an entrypoint whose real invocation had
    # been removed -- the `[ -x ]` guard and the "Re-run: ..." banner were
    # enough to fool it.)
    inv="$(grep -F -- '/usr/local/bin/devcontainer-provision.sh' <<< "$code" \
           | grep -vE '\[[[:space:]]+-[a-zA-Z][[:space:]]' \
           | grep -vE '^[[:space:]]*(echo|printf)[[:space:]]')"
    [ -n "$inv" ]
}
invokes entrypoint.sh \
    && pass "entrypoint.sh INVOKES the provisioner on every container start" \
    || fail "entrypoint.sh does NOT invoke the provisioner -- nothing would make it run"
invokes devcontainer.json \
    && pass "devcontainer.json postStartCommand invokes the provisioner" \
    || fail "devcontainer.json does not invoke the provisioner"
have Dockerfile.postfix 'COPY provision.sh /usr/local/bin/devcontainer-provision.sh' \
    && pass "provision.sh is installed into the image" \
    || fail "provision.sh is never COPYed into the image"
have Dockerfile.postfix 'ENV DEVCONTAINER_WORKDIR' \
    && pass "DEVCONTAINER_WORKDIR is published at runtime (project hook discovery)" \
    || fail "DEVCONTAINER_WORKDIR is not exported; the project hook cannot be found"
have Dockerfile.postfix 'COPY container-paths.sh /usr/local/lib/devcontainer/paths.sh' \
    && pass "the single canonical PATH definition is installed into the image" \
    || fail "container-paths.sh is not installed; login shells and cron will see a different PATH than agent shells"

echo "== provision.sh --check is honest =="
# --check must never mutate anything.
grep -qE 'CHECK_ONLY.*=.*1.*\]; then$|if \[ "\$CHECK_ONLY" = 1 \]' provision.sh \
    && pass "provision.sh distinguishes --check from repair mode" \
    || fail "provision.sh has no --check guard"

echo ""
if [ "$fails" -eq 0 ]; then
    echo "ALL STATIC PROVISIONING CHECKS PASSED"
    exit 0
fi
echo "$fails STATIC PROVISIONING CHECK(S) FAILED"
exit 1
