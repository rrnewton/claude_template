
We're going to work on an OPTIMIZATION task. But before we do let's
make sure we start in a clean state, as described in CLAUDE.md. ALSO
check the github actions CI status for the most recent commit and make
sure it is green. If there's a CI failure, then fixing THAT becomes
our task.

If the starting state is clean, we're ready to select a task to make
forward progress. Review the context:

 - Tracking issue(s) for performance: `bd show mtg-2`
 - OPTIMIZATION.md
 - CLAUDE.md
 - Game rules: rules/02_mtg_rules_condensed_medium_length_gemini.md
 - PROJECT_VISION.md

Then select an optimization-related task, make forward progress, and
commit it after confirming:

- `make validate` passes (correctness testing)
- `make bench` reports improvements in our key metrics,
  e.g. reduced allocation if we eliminated allocation.

If you become completely stuck, write the problem to "error.txt" before you exit.

If you are successful, then commit the changes. Finally, push the
changes (`git push origin main`). If there are any upstream commits,
pull those and merge them (fixing any merge conflicts and
revalidating) before pushing the merged results.
