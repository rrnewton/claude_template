
Pick a task from the backlog and work on it.

Make sure we start in a clean state and follow the workflow in CLAUDE.md.

Now we're ready to select a task to make forward progress. Review the context:

 - Tracking issue(s): e.g. `bd show minibeads-1`
 - CLAUDE.md
 - PROJECT_VISION.md

Then select a task, make forward progress, and commit it after `make
validate` passes. Generally pick higher priority tasks first.

If you become completely stuck, write the problem to "error.txt" before you exit.

If you are successful, and `make validate` passes, then commit the
changes. Finally, push the changes on the current branch and use github CLI (`gh runs`)
to monitor the CI and look for problems.

If there are any upstream commits, pull those and merge them (fixing any merge
conflicts and revalidating) before pushing the merged results.
