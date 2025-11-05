
We're going to work on a task.

But before we do let's make sure we start in a clean state, as
described in CLAUDE.md.

Check the github actions CI status for the most recent commit and make
sure it not red (if it's still pending, ignore and proceed). If
there's a CI failure, then fixing THAT becomes our task. Finally,
check that `make validate` passes locally in our starting state.

Now we're ready to select a task to make forward progress. Review the context:

 - Tracking issue(s): `bd show mtg-1`
 - CLAUDE.md
 - Game rules: rules/02_mtg_rules_condensed_medium_length_gemini.md
 - PROJECT_VISION.md
 - Relevent feature of the source material, Java implementation: ./forge-java

Then select a task, make forward progress, and commit it after `make
validate` passes. Generally pick higher priority tasks first.

As described in the project vision, the goal is to keep expanding the
implementation until the full game of MTG is playable, including all
cards and arbitrary decks, including the 6690 .dck files in
forge-java/.

If you become completely stuck, write the problem to "error.txt" before you exit.

If you are successful, and `make validate` passes, then commit the
changes. Finally, push the changes (`git push origin main`). If there
are any upstream commits, pull those and merge them (fixing any merge
conflicts and revalidating) before pushing the merged results.
