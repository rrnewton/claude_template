Your goal right now is to identify and fix a missing feature in MTG compatibility from considering the `/workspace/forge-java` reference implementation or the MTG rules. MTG is a huge game with a lot of mechanics to cover. To find something broken to fix:

- Pick a random `.dck` file in `/workspace/decks/old_school` or `/workspcae/forge-java`
- Attempt to play it with the `mtg tui`
- Look for errors, problems, or illegal behavior by MTG rules.
- Fix the problem, expanding our game engine to cover more of MTG.

Workflow Reminder
-----------------

Keep progressing the task in question until it looks ready to
close. If it's already closed, select something else to do from the
issue tracker.

But before we begin work let's make sure we start in a clean state, as
described in CLAUDE.md. If validate doesn't pass to start with then
fixing that is your first task.

Review the context:

- CLAUDE.md
- PROJECT_VISION.md
- docs/HOWTO_AGENT_PLAY+REPRODUCERS.md

Make forward progress on the task and commit it after `make validate`
passes. Update the task to reflect the progress or close it if it is
complete.

If you become completely stuck, write the problem to "error.txt"
before you exit.

If you are successful, and `make validate` passes, then commit the
changes. Finally, push the changes on the current branch. If there
are any upstream commits, pull those and merge them (fixing any merge
conflicts and revalidating) before pushing the merged results.
