
Workflow Reminder
-----------------

Keep progressing the task in question until it looks ready to
close. If it's already closed, select something else to do from the
issue tracker.

But before we begin work let's make sure we start in a clean state, as
described in CLAUDE.md. Review the context:

- CLAUDE.md
- PROJECT_VISION.md

Make forward progress on the task and commit it after `make validate`
passes. Update the task to reflect the progress or close it if it is
complete.

If you become completely stuck, write the problem to "error.txt"
before you exit.

If you are successful, and `make validate` passes, then commit the
changes. Finally, push the changes on the current branch. If there
are any upstream commits, pull those and merge them (fixing any merge
conflicts and revalidating) before pushing the merged results.
