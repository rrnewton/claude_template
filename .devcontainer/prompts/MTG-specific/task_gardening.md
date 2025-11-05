
We're going to work on an DOCUMENTATION task.

We want to make sure our tasks are up to date and match what's in the code.
Review the open tasks and other context:

 - Tracking issue(s) for performance: `bd show mtg-2`
 - CLAUDE.md
 - PROJECT_VISION.md
 - Game rules: rules/02_mtg_rules_condensed_medium_length_gemini.md 

Select a task that seems likely to be out of date, and work to bring it up-to-date.

 - Look for descriptions of system architecture and type names.  These
   must be validated to see if they match what the code is really
   doing.

 - Look for claims of performance or tests passing WITHOUT some kind
   of timestamp (either commit#XYZ(hash) or YYYY-MM-DD). You could
   update out-of-date numbers.

 - You can add a stamp at the bottom of the issue: "Checked up-to-date as of YYYY-MM-DD".

If you are successful, then commit the changes. Finally, push the
changes (`git push origin main`). If there are any upstream commits,
pull those and merge them (fixing any merge conflicts and
revalidating) before pushing the merged results.
