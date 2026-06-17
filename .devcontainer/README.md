
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
`podman build -t mtg-rs --build-arg WORKDIR=/workspace .`). The pinned image tag
is `mtg-rs` (from `project_name.txt`).

Revival note (2026-06-16, mtg-idscc6): base bumped 25.10 -> 26.04 LTS; the
`happy` (happy-cli) layer and the `gemini-cli` layer were REMOVED (commented out
in the Makefile so they are easy to restore); `codex` (`@openai/codex`) was added
alongside `claude`; `cargo-nextest` is now installed `--locked` (it refuses a
bare `cargo install`); minibeads is fetched from its `main` branch so `mb` is
always latest.

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
