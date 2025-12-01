
We're going to work on an OPTIMIZATION task. Review any outstanding issues about optimization and allocation rates.

But before we do let's make sure we start in a clean state, as described in CLAUDE.md.

If the starting state is clean, we're ready to select a task to make forward progress. Review the context:

 - Tracking issue(s) for performance: `bd show mtg-2`
 - OPTIMIZATION.md
 - CLAUDE.md
 - PROJECT_VISION.md

Then select an optimization-related task, make forward progress, and commit it after confirming:

- `make validate` passes (correctness testing)
- `make bench` reports improvements in our key metrics, e.g. reduced allocation if we eliminated allocation.

If you become completely stuck, write the problem to "error.txt" before you exit.

DO NOT commit an optimization change if it does not measurably speed up one of our key metrics (actions-per-second or byte-allocations-per-turn). But you may commit it on a branch `failed-optimization-XY` for later perusal.

If you are successful, then commit the changes. Finally, push the changes (`git push origin main`). If there are any upstream commits, pull those and merge them (fixing any merge conflicts and revalidating) before pushing the merged results.
