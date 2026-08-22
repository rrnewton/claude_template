
USER=ubuntu
CACHEBUST=0

TAG := $(shell cat project_name.txt)

ifeq ($(strip $(TAG)),)
    $(error TAG must be set (from project_name.txt) and not empty!)
endif

# Get or create workspace name.
#
# REPONAME must be DETERMINISTIC and cannot go stale: derive it from the
# PROJECT git remote URL (the enclosing repo that is NOT claude_template),
# lowercased. github.com/rrnewton/DeepScry.git -> "deepscry". This is robust
# to the directory being renamed and to a stale home/workspace_name.txt cache.
#
# We still cache the result into home/workspace_name.txt (gitignored), but we
# OVERWRITE the cache whenever it disagrees with the freshly-derived name, so a
# stale cache (e.g. an old "mtg-forge-rs" from before the repo was renamed) can
# never win. The cache is only TRUSTED as-is when git can't be queried (e.g.
# inside a container with no .git), so behaviour degrades gracefully.
#
# Walk UP from .. until we find a git remote that is NOT claude_template; that
# is the project repo. (.. is the .claude_template submodule itself.)
REPONAME := $(shell \
	REPO_NAME=""; \
	for d in .. ../.. ../../..; do \
		R=$$(cd "$$d" 2>/dev/null && git remote get-url origin 2>/dev/null); \
		[ -z "$$R" ] && continue; \
		echo "$$R" | grep -iq "claude_template" && continue; \
		REPO_NAME=$$(echo "$$R" | sed -E 's|.*[/:]([^/]+)(\.git)?/?$$|\1|; s|\.git$$||' | tr 'A-Z' 'a-z'); \
		break; \
	done; \
	if [ -n "$$REPO_NAME" ]; then \
		if [ ! -f ./home/workspace_name.txt ] || [ "$$(cat ./home/workspace_name.txt 2>/dev/null)" != "$$REPO_NAME" ]; then \
			mkdir -p ./home; echo "$$REPO_NAME" > ./home/workspace_name.txt; \
		fi; \
		echo "$$REPO_NAME"; \
	elif [ -f ./home/workspace_name.txt ]; then \
		cat ./home/workspace_name.txt; \
	else \
		echo "workspace"; \
	fi)


# Get or create realhostname
REALHOSTNAME := $(shell if [ -f ./home/realhostname.txt ]; then cat ./home/realhostname.txt; else hostname | tee ./home/realhostname.txt; fi)

# Reserve a unique, per-repo container index (N) on this host. 
SLOT := $(shell \
	if [ -f slot.txt ]; then \
		cat slot.txt; \
	else \
		rep="$(REPONAME)"; n=1; \
		while true; do \
		   f="/tmp/container-$$rep-$$n.token"; \
		   if ( set -o noclobber; : > "$$f" ) 2>/dev/null; \
		     then echo $$n; break; \
			 else n=$$((n+1)); \
		   fi; \
		done; \
		echo $$n > slot.txt; \
	fi)

CONTAINER_HOSTNAME := $(REALHOSTNAME)-$(SLOT)

FULLTAG := $(TAG)-$(SLOT)

# A STABLE container name, so "which container am I in / how do I get back to
# it / how do I replace it" all have obvious answers. Without a name podman
# invents a random one and rebuild-and-relaunch becomes a scavenger hunt.
CONTAINER_NAME ?= $(FULLTAG)

# Podman's default pids limit is often 2048, which leaves high-core validation
# runs mostly idle (`make validate` auto-throttles when /sys/fs/cgroup/pids.max
# is tight). Use a high finite default so root containers can exercise large
# machines; override with `make PIDS_LIMIT=... root` if a host needs less/more.
PIDS_LIMIT ?= 65536
PIDS_FLAG = --pids-limit=$(PIDS_LIMIT)

# Keep the primary development container below the host's memory-pressure
# threshold. Restart it after crashes/OOM kills, but not after an intentional
# shell exit.
ROOT_MEMORY_LIMIT ?= 80g
ROOT_LIFECYCLE_FLAGS = --memory=$(ROOT_MEMORY_LIMIT) \
	--cgroup-conf=memory.swap.max=0 --restart=on-failure

# Compute dynamic workspace directory name
WORKDIR := /$(REPONAME)-$(REALHOSTNAME)

OS := $(shell uname)

ifeq ($(OS),Darwin)
    CONTAINER=docker
else ifeq ($(OS),Linux)
    CONTAINER=podman
else
    CONTAINER= echo Unsupported_OS && exit 1
endif

# Make the bind-mounted home WRITABLE for the run user.
#
# Under podman ROOTLESS the host uid (e.g. 1000) does NOT map to the in-container
# `ubuntu` uid by default, so `-v pwd/home:/home/ubuntu` lands owned by a foreign
# uid and the run user cannot mkdir ~/.codex etc.
#
# We do NOT use `--userns=keep-id` to fix this: on some crun versions keep-id
# makes the container fail to LAUNCH AT ALL, because crun cannot apply podman's
# default `net.ipv4.ping_group_range` sysctl inside a keep-id user namespace
# ("write to /proc/sys/net/ipv4/ping_group_range: Invalid argument"). Instead the
# image ENTRYPOINT (entrypoint.sh) starts as root in podman's NORMAL rootless
# namespace — the same namespace `make root` already uses successfully, where the
# default sysctls apply cleanly — chowns the run user's home so it is writable,
# then drops privileges to that user. The target user is passed via RUN_AS_USER.
RUN_AS_FLAG = -e RUN_AS_USER=$(USER)

# Locate the whole parent dev-deepscry harness so the ENTIRE workspace (the
# deepscry/ project checkout AND worktrees/, ops/, validate_perf/, ai_docs/, ...)
# is mounted into the container as $(WORKDIR) — not just the deepscry/ project.
#
# Layout note: this .devcontainer lives at <project>/.claude_template/.devcontainer,
# so .. is the claude_template submodule, ../.. is the PROJECT checkout (which has
# NO worktrees/), and ../../.. is the PARENT harness (which DOES have worktrees/).
# The $HOME/work/dev-deepscry path is commonly a SYMLINK to the real harness, so
# every candidate is passed through `readlink -f` to give podman/docker the REAL
# absolute path (a bind-mount source must be a real path, not a symlink).
DEVDEEPSCRY := $(shell for d in ../../.. ../.. "$$HOME/work/dev-deepscry" /mnt/wsl/BWSLDatabtrfsvolumevhdx/deepscry; do \
		[ -d "$$d" ] || continue; \
		real=$$(readlink -f "$$d" 2>/dev/null); \
		[ -n "$$real" ] || continue; \
		if [ -d "$$real/worktrees" ]; then echo "$$real"; break; fi; \
	done)

# Source dir bind-mounted at $(WORKDIR): the parent harness when found, else fall
# back to the project checkout (`pwd/..`) so the container still works on a bare
# project clone with no surrounding harness. The parent IS the deepscry workspace,
# so mounting it at /$(REPONAME)-$(REALHOSTNAME) is the natural home.
WORKDIR_MOUNT_SRC := $(if $(DEVDEEPSCRY),$(DEVDEEPSCRY),$$(readlink -f ..))

GOCLAUDE= claude --dangerously-skip-permissions --continue

# Always invoke claude from the same space so we don't confuse our claude.json workspace config.
# Now uses the dynamically computed WORKDIR instead of hardcoded /workspace
CLAUDEWORK= $(WORKDIR)

# `make CACHEBUST="$(date +%s)" build` to force rebuild.
build: Dockerfile
	$(CONTAINER) build -t $(FULLTAG) --build-arg CACHEBUST=$(CACHEBUST) --build-arg WORKDIR=$(WORKDIR) .

# Ensure the bind-mounted home exists before any run target. We only CREATE it if
# missing; we do NOT hard-fail on chmod. After a `make run`, the entrypoint has
# chowned ./home to the container user's host SUBUID (inherent to rootless podman
# without keep-id), so the invoking host user can no longer chmod it — and that is
# FINE (it is already writable by the container). A failed chmod must not block
# the next `make run`, so this is best-effort.
ensure-home:
	@mkdir -p ./home; chmod u+rwx ./home 2>/dev/null || true

# `run` starts as ROOT (the default image user) so the ENTRYPOINT can chown the
# bind-mounted home, then drops to $(USER) via RUN_AS_USER. This avoids the
# keep-id launch failure (see RUN_AS_FLAG comment above) while still landing the
# user in a writable home as the unprivileged `ubuntu` user.
run: ensure-home
	$(CONTAINER) run -it --rm --hostname $(CONTAINER_HOSTNAME) $(RUN_AS_FLAG) \
		-v `pwd`/home:/home/$(USER) \
		-v $(WORKDIR_MOUNT_SRC):$(WORKDIR) \
		$(FULLTAG) bash

# NOTE: the root-style targets run `-u root` and want to STAY root (so they keep
# the home mounted at /root), so they bypass the entrypoint's drop-to-user by not
# setting RUN_AS_USER. Under rootless podman container-root already maps to the
# invoking host user, so their bind-mounted home stays writable.
root: ensure-home check-name-free
	$(CONTAINER) run -it -u root --name $(CONTAINER_NAME) --hostname $(CONTAINER_HOSTNAME) \
		$(PIDS_FLAG) \
		$(ROOT_LIFECYCLE_FLAGS) \
		-v `pwd`/home:/root --cap-add PERFMON --cap-add SYS_ADMIN \
		-v $(WORKDIR_MOUNT_SRC):$(WORKDIR) \
		$(FULLTAG) bash

# ===========================================================================
# Rebuild / relaunch / verify  (ds-3ij3j4)
# ===========================================================================
# `make cycle` is the one command: rebuild the image, replace the running
# container with a fresh one, and land in a shell that is already fully
# provisioned (cron daemon started, project data-plane hook run).
#
# Why the ceremony matters: only $HOME survives a recreation. Everything under
# `/` comes back exactly as the IMAGE built it, and anything installed by hand
# into a running container is thrown away. See README.md -> "What survives a
# container recreation".

# Refuse to silently collide with an existing container of the same name --
# that container might have live agents in it.
check-name-free:
	@if $(CONTAINER) ps -a --format '{{.Names}}' 2>/dev/null | grep -qx '$(CONTAINER_NAME)'; then \
		echo "error: a container named '$(CONTAINER_NAME)' already exists:"; \
		$(CONTAINER) ps -a --filter 'name=$(CONTAINER_NAME)' \
			--format '         {{.Names}}   {{.Status}}   {{.Image}}' 2>/dev/null; \
		echo ""; \
		echo "  get a shell in it :  make attach"; \
		echo "  REPLACE it        :  make relaunch      (stops and DELETES it)"; \
		exit 1; \
	fi

# Open another shell in the already-running container (does NOT re-run the
# entrypoint, so it does not re-provision -- use `make provision` for that).
attach:
	$(CONTAINER) exec -it $(CONTAINER_NAME) bash

# Rebuild the image from the current Dockerfile fragments.
rebuild:
	rm -f Dockerfile
	$(MAKE) build

# Same, ignoring the layer cache (use when an `apt-get`/`npm`/`cargo` layer
# needs to re-resolve to current upstream versions).
rebuild-nocache:
	rm -f Dockerfile
	$(MAKE) Dockerfile
	$(CONTAINER) build --no-cache -t $(FULLTAG) --build-arg WORKDIR=$(WORKDIR) .

# Stop and DELETE the named container, then start a fresh one from the current
# image. Destructive by design: anything installed by hand into the old
# container is lost (it was never durable in the first place).
relaunch: ensure-home
	@echo "==> replacing container '$(CONTAINER_NAME)' (anything not in \$$HOME or the image is discarded)"
	-$(CONTAINER) rm -f -t 10 $(CONTAINER_NAME)
	$(MAKE) root

# The whole cycle in one command.
cycle: rebuild relaunch

# THE single verifiable "is this container fully provisioned?" check.
# Exits nonzero and says exactly what is wrong if it is not.
# Works both from the host and from inside the container.
provision-check:
	@if [ -n "$$DEVCONTAINER" ]; then \
		/usr/local/bin/devcontainer-provision.sh --check; \
	else \
		$(CONTAINER) exec $(CONTAINER_NAME) /usr/local/bin/devcontainer-provision.sh --check; \
	fi

# Re-run provisioning by hand (idempotent). Normally unnecessary: the
# entrypoint does this on every container start.
provision:
	@if [ -n "$$DEVCONTAINER" ]; then \
		/usr/local/bin/devcontainer-provision.sh; \
	else \
		$(CONTAINER) exec $(CONTAINER_NAME) /usr/local/bin/devcontainer-provision.sh; \
	fi

root-with-port: ensure-home
	$(CONTAINER) run -it --rm -u root --name $(CONTAINER_NAME)-port --hostname $(CONTAINER_HOSTNAME) \
		$(PIDS_FLAG) \
		-v `pwd`/home:/root --cap-add PERFMON --cap-add SYS_ADMIN \
		-v $(WORKDIR_MOUNT_SRC):$(WORKDIR) -p 8080:8080 \
		$(FULLTAG) bash

privileged: ensure-home
	$(CONTAINER) run -it --rm -u root --name $(CONTAINER_NAME)-priv --hostname $(CONTAINER_HOSTNAME) \
		$(PIDS_FLAG) \
		-v `pwd`/home:/root \
		-v $(WORKDIR_MOUNT_SRC):$(WORKDIR) \
		--privileged --cap-add=ALL \
		$(FULLTAG) bash


# Active agent layers. Copilot and Gemini remain opt-in.
AGENT_LAYERS = Dockerfile.claude Dockerfile.codex Dockerfile.happier
# Dockerfile.copilot
# Dockerfile.gemini

# Historical source-build variants, retained for reference. The active
# Dockerfile.happier layer installs the published npm packages instead.
# HAPPY_LAYER = Dockerfile.happy-upstream
# HAPPY_LAYER = Dockerfile.happy-fork

# Remove Dockerfile.rust if we are not using rust or minibeads:
OPTIONAL_DOCKER_LAYERS = Dockerfile.rust
Dockerfile: Dockerfile.*
	cat Dockerfile.prefix $(AGENT_LAYERS) $(OPTIONAL_DOCKER_LAYERS) Dockerfile.project Dockerfile.postfix > Dockerfile

# TODO: need a way to pass this into happy on the CLI.
# It can take an MCP action to change it, but that's lame and wasteful.
.session_title.txt:
	echo $(TAG)-`hostname` > $@

claude:
	cd "$(CLAUDEWORK)" && $(GOCLAUDE)

# Use my tweaked version of happy if it's available
happy: .session_title.txt
	TITLE=`cat $^` && cd .. && \
	cd "$(CLAUDEWORK)" && happy $(GOCLAUDE)
#	hits=$$(happy -h | grep '\-\-name'); \
	cd "$(CLAUDEWORK)" && \
	if [ -z "$$hits" ]; then \
	  happy --name "$$TITLE" $(GOCLAUDE); else \
	  happy $(GOCLAUDE) "Tell happy to change the title to $$TITLE"; \
	fi

# Usually from outside the container, to pass it in:
install-pat: home/.github/PAT.txt
home/.github/PAT.txt:
	mkdir -p home/.github
	@if ! [ -z "$(GITHUB_PERSONAL_ACCESS_TOKEN)" ]; then \
		echo "$(GITHUB_PERSONAL_ACCESS_TOKEN)" > home/.github/PAT.txt; \
	elif [ -f ~/.github/PAT.txt ]; then \
		cp ~/.github/PAT.txt home/.github/PAT.txt; \
	else \
		echo "Error: GITHUB_PERSONAL_ACCESS_TOKEN not set and no ~/.github/PAT.txt file found." ; \
		exit 1; \
	fi

# Still need to manually add this key to GitHub as a deploy key for the repo.
install-ssh-deploy-key: home/.ssh/id_rsa.pub
home/.ssh/id_rsa.pub:
	ssh-keygen -t rsa -b 4096 -f home/.ssh/id_rsa -N "" -C "deploy-key-`hostname`"

# From inside the container:
claude-github:
	cd "$(CLAUDEWORK)" && \
	claude mcp remove github || \
	claude mcp add --transport http github https://api.githubcopilot.com/mcp \
          -H "Authorization: Bearer $(GITHUB_PERSONAL_ACCESS_TOKEN)"

gh-auth:
	cat "$(HOME)/.github/PAT.txt" |  gh auth login --with-token

# From inside the container:
claude-beads:
	cd "$(CLAUDEWORK)" && claude plugin marketplace add steveyegge/beads
	cd "$(CLAUDEWORK)" && claude plugin install beads

outside-setup: install-pat

inside-setup: claude-github claude-beads install-ssh-deploy-key gh-auth

# Pull and rebase any upstream changes to the central config on the main branch.
pull-main:
	git diff --exit-code || \
	(echo "Please commit or stash your changes before pulling." && exit 1) && \
	BRANCH=`git branch --show-current` && \
	git checkout main && \
	git pull origin main && \
	git checkout $$BRANCH && \
	git merge main

commit-to-main:
	./commit_to_main.sh

# Get out of the way so work in this repo doesn't mess with the scripts we're
# running to drive Claude.
#
# Copy .devcontainer to $HOME if we're under /workspace, then switch to it
rsync:
	@if echo "$(PWD)" | grep -q "^/workspace"; then \
		echo "Detected /workspace directory, copying to $$HOME/devcontainer_clone..."; \
		mkdir -p "$$HOME/devcontainer_clone"; \
		rsync -av --no-owner --no-group --exclude='home/' "$(PWD)/" "$$HOME/devcontainer_clone/"; \
		echo "Switching to $$HOME/devcontainer_clone"; \
		cd "$$HOME/devcontainer_clone" && exec bash; \
	else \
		echo "Not under /workspace directory, no action taken."; \
		echo "Current directory: $(PWD)"; \
	fi

# Bidirectional sync using unison
sync:
	@if echo "$(PWD)" | grep -q "^/workspace"; then \
		echo "Detected /workspace directory, syncing with $$HOME/devcontainer_clone..."; \
		mkdir -p "$$HOME/devcontainer_clone"; \
		unison "$(PWD)" "$$HOME/devcontainer_clone" \
			-ignore 'Path home' \
			-auto -batch -prefer "$(PWD)"; \
		echo "Switching to $$HOME/devcontainer_clone"; \
		cd "$$HOME/devcontainer_clone" && exec bash; \
	else \
		echo "Not under /workspace directory, no action taken."; \
		echo "Current directory: $(PWD)"; \
	fi

# Smart side-step: use unison if available, otherwise rsync
side-step:
	@if command -v unison >/dev/null 2>&1; then \
		echo "Using unison for bidirectional sync..."; \
		$(MAKE) sync; \
	else \
		echo "Unison not found, falling back to rsync..."; \
		$(MAKE) rsync; \
	fi

info:
	@echo Workdir should be $(WORKDIR)
	@echo   REALHOSTNAME=$(REALHOSTNAME)
	@echo   CONTAINER_HOSTNAME=$(CONTAINER_HOSTNAME)
	@echo   IMAGE=$(FULLTAG)
	@echo   CONTAINER_NAME=$(CONTAINER_NAME)
	@echo   MOUNTED AT $(WORKDIR): $(WORKDIR_MOUNT_SRC)
	@echo ""
	@echo "  make cycle            rebuild the image + replace the container (the usual command)"
	@echo "  make rebuild          rebuild the image only"
	@echo "  make relaunch         replace the container only"
	@echo "  make attach           another shell in the running container"
	@echo "  make provision-check  is the running container fully provisioned? (exit 0 = yes)"


.PHONY: claude-beads claude-github setup-claude happy run build root pull-main \
   inside-setup outside-setup install-pat install-ssh-deploy-key side-step rsync sync gh-auth \
   ensure-home root-with-port privileged \
   check-name-free attach rebuild rebuild-nocache relaunch cycle provision provision-check info
