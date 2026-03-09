
We're going to audit our tests, and in particular ignored tests. But before we do let's make sure we start in a clean state, as described in CLAUDE.md.

Sometimes an agent will hackily disable a test, making some excuse for marking it as ignored rather than backing up and trying to understand from first principles what SHOULD happen and how the test should work.  Sometimes they will be disabled during a major refactor, but then forget to reenable/update them.

Whatever the reason, look at our inventory of ignored tests.  Update a tracking issue (with minibeads, `mb` cli) with a clear title that tracks all ignored tests and their current status. Pick an ignored test and figure out why it was disabled and what it was testing. As long as that is still relevant in principle, work hard on knocking down obstacles to reenabling the test.

Remember our core principles re: coding style (CLAUDE.md), code optimization, and the deterministic engine and networked, replicated state machine (./docs/NETWORK_ARCHITECTURE.md). 
