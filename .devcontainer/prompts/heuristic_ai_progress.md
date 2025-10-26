
Work on expanding the heuristic AI towards parity with the Java version.

The testing strategy will be similar to test_royal_assassin_with_log_capture (or the shell script e2e tests/*.sh), we need to set up specific scenarios and verify the actions. Continue to use a greater variety of cards up to 4ED with more triggered and keyword abilities. Activate until we are running tests with real board states with the real cards loaded from the card database.

But before we do let's make sure we start in a clean state, as
described in CLAUDE.md.

Review the context:

- CLAUDE.md
- PROJECT_VISION.md

Make forward progress on the task and commit it after `make validate`
passes. Update the task to reflect the progress or close it if it is
complete.

If you become completely stuck, write the problem to "error.txt" before you exit.

If you are successful, and `make validate` passes, then commit the
changes. Finally, push the changes (`git push origin main`). If there
are any upstream commits, pull those and merge them (fixing any merge
conflicts and revalidating) before pushing the merged results.
