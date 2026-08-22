
A reusable template for devcontainers with claude
==================================================

This is adapted from the reference dev container setup from Anthropic:

https://github.com/anthropics/claude-code/tree/main/.devcontainer

It includes various adaptations because the dev environment needs to be suited
for the project, not just for Claude. Ideally this should be moved to Nix or
docker compose, or something with a composable abstraction for combining two
different sets of dependencies.

The goal here is to support:

- a somewhat-locked down environment for Claude --dangerously-skip-permissions
- compilers/libs for a specific project

How the image is assembled
--------------------------

There is no checked-in `Dockerfile` (it is gitignored). The `Makefile` `cat`s a
set of fragments together into `Dockerfile`, then builds it (podman on Linux,
docker on macOS):

    Dockerfile.prefix   base image + shared dev tools (Ubuntu 26.04 LTS)
    $(AGENT_LAYERS)     Dockerfile.claude + Dockerfile.codex + Dockerfile.copilot
    Dockerfile.rust     rustup/nightly + minibeads (mb, latest) + profiling tools
    Dockerfile.project  project deps (maven, jdk, python plotting, perf)
    Dockerfile.postfix  WORKDIR / /workspace symlink

Build it with `make build` (or directly:
`podman build -t deepscry --build-arg WORKDIR=/workspace .`). The pinned image
tag is `deepscry` (from `project_name.txt`).

Revival note (2026-06-16, mtg-idscc6): base bumped 25.10 -> 26.04 LTS; the
`happy` (happy-cli) layer and the `gemini-cli` layer were REMOVED (commented out
in the Makefile so they are easy to restore); `codex` (`@openai/codex`) was added
alongside `claude`; `cargo-nextest` is now installed `--locked` (it refuses a
bare `cargo install`); minibeads is fetched from its `main` branch so `mb` is
always latest.

Rebuild and relaunch
--------------------

One command, run **from the host** (not from inside the container):

    make cycle          # rebuild the image, replace the container, drop into a shell

It is just `make rebuild` (regenerate `Dockerfile` from the fragments and build)
followed by `make relaunch` (stop and delete the named container, start a fresh
one). The pieces are separately useful:

    make rebuild          rebuild the image only
    make rebuild-nocache  rebuild ignoring the layer cache (re-resolve apt/npm/cargo versions)
    make relaunch         replace the container only, from the current image
    make attach           open another shell in the already-running container
    make provision-check  is the running container fully provisioned?  exit 0 = yes
    make provision        re-run provisioning by hand (idempotent; normally unnecessary)
    make info             image tag, container name, mount paths, and this list

The container now has a **stable name** (`CONTAINER_NAME`, defaulting to the
image tag, e.g. `deepscry-1`) so "which container am I in", "how do I get back
to it" and "how do I replace it" all have obvious answers. `make root` refuses
to start if that name is already taken, and tells you whether you wanted
`make attach` or `make relaunch` — it will never quietly stomp a container that
might have live agents in it. `make relaunch` is the explicit destructive one.

`make cycle` is safe to run repeatedly: the container is provisioned
automatically on every start (see below), so a rebuild leaves you in a working
box with no follow-up steps to remember.


What survives a container recreation
------------------------------------

This is the single most important thing to know before installing anything
here, and getting it wrong has already cost a month of silent production
breakage (see "Why provisioning is automatic" below).

| | Survives recreation? | What lives there |
|---|---|---|
| **`$HOME`** (`/root`, a bind mount of `.devcontainer/home/`) | **YES — persistent** | credentials, agent state, shell history, `$HOME/bin`, `$HOME/local/node` |
| **Everything the image builds** (`/usr`, `/usr/local`, `/opt`, …) | **YES — baked** | apt packages, `npm -g`, `/opt/venv`, `/opt/cargo`, everything from a `Dockerfile.*` fragment |
| **Anything written into `/` after the container started** | **NO — discarded** | a hand `apt-get install`, a hand `pip install` into `/opt/venv`, the live crontab in `/var/spool/cron` |
| **Running processes** | **NO** | there is no init system; PID 1 is a plain `bash`, so nothing is started or supervised at boot |

`/` is an overlay filesystem. Its *upper* layer is thrown away on recreation
while the *image* layers underneath are re-applied — which is why "baked" and
"persistent" are both durable but "installed by hand at runtime" is not.

The rules that follow:

* **If a tool is static, bake it into a `Dockerfile.*` fragment.** Do not
  install it into a running container and consider the job done.
* **If it must be created at runtime, put it under `$HOME`.** The persistent
  npm prefix is `$HOME/local/node` (`$HOME/local/node/bin` is on the PATH).
* **A daemon needs an explicit start.** `provision.sh` starts `cron` on every
  container start. It is *not* supervised — if it dies nothing restarts it, and
  `make provision-check` is what notices.

### One PATH, for everyone

`container-paths.sh` (installed at `/usr/local/lib/devcontainer/paths.sh`) is
the **single definition** of this container's PATH. `/etc/profile.d/` sources it
for every login shell, and anything else — a cron job, a deploy script — can
source it directly.

This exists because agent shells here used to carry PATH entries that plain
login shells and cron jobs did not. A tool dropped into `$HOME/bin` therefore
answered `command -v` happily from an agent shell and was completely invisible
to `scripts/deploy-cloud.sh` and to cron. **Verify a tool the way the rest of
the system will see it:**

    env -i bash -lc 'command -v <tool>'


Why provisioning is automatic
-----------------------------

This container was recreated on 2026-07-21. That recreation silently destroyed
`cron` (client *and* daemon), `wrangler`, PyYAML, `pytest`, `mypy`, `rsync`,
`mdbook`, and a current `minibeads` build. Nobody noticed for a month, and the
consequence was that the production Cloudflare D1 user database went
un-backed-up the entire time — in fact it had never once been backed up on this
host. Every one of those failures returned a plausible-looking success to
whoever last looked. (Tracked as issue `ds-3ij3j4`.)

The fix is that nothing depends on anyone remembering anything:

1. Static tools are **baked** into the image (`cron`, `rsync`, `mdbook`, PyYAML,
   `pytest`, `mypy`, `pandas`, `wrangler`, `mb`, …).
2. `provision.sh` — installed as `/usr/local/bin/devcontainer-provision.sh` and
   run by the image **ENTRYPOINT on every container start** (and again by
   `devcontainer.json`'s `postStartCommand`) — does the rest: verifies the baked
   tools are really there, starts the cron daemon, creates the persistent tool
   prefix, and runs the mounted project's own provisioning hook if it ships one
   (`$DEVCONTAINER_WORKDIR/ops/bootstrap-container.sh`, or
   `.devcontainer-provision`). It is idempotent.
3. It **fails loudly**, never silently: a banner at container start, a red
   banner on every interactive login until it is fixed, `/run/devcontainer/status`
   plus a report, an appended log at `$HOME/.devcontainer/provision.log`, and a
   nonzero exit from the one check anyone can run:

       make provision-check          # from the host
       devcontainer-provision.sh --check   # from inside

   If a baked tool is missing, the message says **rebuild the image**, not "let
   me apt-get that for you" — a hand install would evaporate on the next
   recreation and put us straight back into a month of silent failure.

`tests/test_provisioning_static.sh` guards the wiring without building or
starting anything: it cross-checks that every tool `provision.sh` demands is
actually installed by some `Dockerfile.*` fragment (ignoring mere mentions in
comments), that every `COPY` source exists, and that the provisioner really is
invoked from the entrypoint and `devcontainer.json`.


Standalone vs. multi-worktree
-----------------------------

This `.devcontainer` (it lives in the `.claude_template` submodule, symlinked in
as `.devcontainer`) is used in two shapes. To tell them apart RELIABLY, from the
`deepscry` checkout root:

    sup=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
    if [ -n "$sup" ] || [ -f ../worktrees/ACTIVE.md ]; then
      echo multi-worktree     # deepscry is a submodule of a dev-deepscry parent
    else
      echo standalone         # a plain deepscry clone
    fi

In the multi-worktree shape the parent "dev-deepscry" harness holds
`worktrees/` (+ `worktrees/ACTIVE.md`) and `experiments/`. Both `make run` (mounts
`..` as the dynamic WORKDIR) and `devcontainer.json` (mounts the parent at
`/dev-deepscry`) make that parent visible inside the container. See the header
comment in `devcontainer.json` for the mount details and how to drop the parent
mount for a strict standalone setup.
