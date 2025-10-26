

[2025-10-25] Set up container for beads dev
===========================================

TODO[beads] bd show multiple issues
----------------------------------------

`bd show ID1 ID2` should just show both. Commit this change as one standalone commit.

Also, add a flag `bd show --all-issues` to show all issues. You can warn in the help that this may be an expensive operation. Commit this as a second commit.

Finally, add another flag `bd show --priority 0` to show all issues at a priority (-p for short), which shows all the issues at a given priority, and can be provided multiple times. Commit this as a third commit.

TODO[beads] provide `bd edit ID` subcommand
----------------------------------------

As a human, it's annoying to have to edit beads issues using `bd
update`.  Instead, provide a `bd edit` command that opens $EDITOR to
edit the issue.  `bd edit --description` should be the default, but
add other options like `--title` to match the format of `bd update`.



Ambitious new feature `bd --no-db` mode
-------------------------------------

Especially when I have the same directory mounted inside a container and
accessed on the host, it's VERY easy to get corruption, duplication, and get out
of sync between different `bd` instances accessing the same `.beads` directory.

To avoid this, I want a much simple `bd --no-db` global option which affects all
subcommands. 

The idea with this alternate mode is to do all operations DIRECTLY on the
`issues.jsonl` file, with no SQLlite database. 

The `bd` code already contains the logic to load and export the json file. This
change will require each command to load the DB into memory from the json and
output it again. 

`bd init -p prefix` is not actually needed in `--no-db` mode. Instead, it will
use the simple heuristic of, once it has read the .jsonl file, continuing to use
the prefix of issues in that file, if all issues share the same prefix. If we do
run `bd --no-db init -p prefix` we can also generate a file nodb_prefix.txt and
use that if it exists. 

This will be a big change to make, so let's plan it out step by step. First port
the `bd --no-db create` subcommand so that we can create an issue this way, and
then we can take the other subcommands one by one. 

It gave me an initial version
----------------------------------------

I will probably fold in some subsequent changes

    commit a3d842211ffb946df56b815d27175a63815fb3c5 (HEAD -> no-db, origin/no-db)
    Author: Claude Code <claude@anthropic.com>
    Date:   Sat Oct 25 14:48:51 2025 +0000

        Add --no-db mode: JSONL-only operation without SQLite

        Implement --no-db mode to avoid SQLite database corruption in scenarios
        where the same .beads directory is accessed from multiple processes
        (e.g., host + container, multiple containers).

I pushed it as tag 'no-db-01' just because I don't have magic commit cloud
backup.

After I fold in the change from dedup:

    commit 056bf1b9d1cbe22381ae6f3c502e393fc7bfdfd8
    Author: Claude Code <claude@anthropic.com>
    Date:   Sat Oct 25 14:48:51 2025 +0000
        Add --no-db mode: JSONL-only operation without SQLite

Ok, I rebased on upstream main and currently b0b9c37 (current upstream)
passes all tests and race detection. The tests are not using much CPU so I don't
know what's happening. IT's USPER fast if it runs a second time (caching).
IT looks like the rpc test takes 63 seconds..

Wow killing the race tests in NOT responsive. It just ignores Ctrl-C.
It's STILL not using much cpu. 

7d7ca1c is my new commit, but while the prev commit passes tests (and race
detection), this FAILS. 7d7ca1cd857f586c5938d8a0172b636a668fa0eb

-----

There's more work to do `go test ./...` shows test failures. Please debug and 
amend this commit.

The partly-fixed version is 10ce3cfd39733a1e9ed19f07c7b8fc507c981f06
- fixed a couple file paths, and added two missing methods.

Crazy how it wants to declare this a pre-existing failure when it is DIRECTLY
caused be the functionality we changed.  I guess it was confused because I did
the rebase without telling it.

  - ✗ github.com/steveyegge/beads/cmd/bd: 1 pre-existing failure (TestAutoFlushErrorHandling)

Now the fixed commit is e370aae1fafb11ff5a71dd420c0be76e3099b47d

git diff -r 10ce3cfd39733a1e9ed19f07c7b8fc507c981f06 -r e370aae1fafb11ff5a71dd420c0be76e3099b47d

UH dunno if this is good.

TODO: Make writing the file more atomic
----------------------------------------


We can make file writing more atomic than simply naively openning the output
file for writing.

We don't have an atomic "compare and swap" (renameat2) on every file system. We
can have a fallback that is almost as good.

### If renameat2 with RENAME_EXCHANGE is available

This is easy, we note the contents hash of the database when we read it from
disk, and store that along with our in-memory DB. Then:

 - We write our output to a temp file under the .beads/ directory, say
   'tmp34_issues.jsonl'.
 - We perform a hash check of the output file to ensure that it has NOT changed
   since we read it, and we bail with an error otherwise.
 - We atomically exchange our tmp file with `issues.jsonl`.
 - If it is successful, we verify one more time that the old file (now exchanged
   to our location `tmp34_issues.jsonl`) contains the same contents that match
   the hash. If so, success.
 - If not, we attempt roll back our change with another swap.
   We exit with an error for the CURRENT `bd` operation, trying hard not 
   to clobber someone else's modification of the .jsonl.

### If we only have atomic rename

All file systems should support at least an atomic move/rename.

The protocol is similar to above, except instead of a single swap, we must:

- move issues.jsonl out of the way, to a fresh temp location
- move our `tmp34_issues.jsonl` into `issues.jsonl`

All our checking of the contents (hash) of the file remains the same.

----------------------------------------

In that commit, you've added `writeIssuesToJSONL` to write out the file. But I
don't know how bd currently writes out the `issues.jsonl` file before our
changes. Describe that for me.  Why not use one common code path for writing out
the file as safely as possible?

----
It's annoying that we almost always have a single issue prefix, but I still must
type `bd show prefix-3` rather than `bd show 3`.  Add a fallback where if the
issue id doesn't resolve, and it is a bare number, try adding the prefix.
Implement this for `bd show` but suggest whether there are any other places to
use it.


---

How does beads store configurations? Is there a configuration file in the
`.beads` directory or somewhere else? I would like to make `--no-db` a
configuration option that I can set for a repository which will be respected by
all `bd` invocations and the mcp-beads service.


Note: force pushed no-db
------

After having AI handle the merge conflicts.

 + ba27221...c47a139 no-db -> no-db (forced update)



TODO: Upgrade rename to consolidate and repair
-----------------------------------------------------

I've addad an example of a corrupted beads repo here. It has four different
issue prefixes. Rename will not work to fix it:

```
/workspace/corruption_test (beads) $ ../beads/bd --no-db rename-prefix mtg-
Error: new prefix is the same as current prefix: mtg
```

Let's upgrade the rename command so that it:

1. detects when the issues db has multiple prefixes.
2. aborts with a descriptive error unless `--repair` is passed
3. if `--repair` is passed, it consecutively renames using the following algorithm

The algorithm is to LEAVE ALONE all issues that already have the correct prefix.
If `correct-99` is the highest index with the correct prefix, we sort our issues
first by lexiographic order on their prefix, then by number `bad-1, bad-2, ...
realbad-1, ...`, and we process them in that order. Each badly named issue gets
renamed to the next available correct prefixed ID: `correct-100, correct-101`
etc.

Just like the existing rename command, we respect all inter-issue references and
rename globally. Hopefully that logic can be reused and we can make the minimal
change to the existing code to add the `--repair` functionality.

After tests pass, `git restore .beads/beads.jsonl` and commit.


TODO: Annoying that tests trash .beads/beads.jsonl
-------------
It's sloppy that the `./go test ./...` tests leave `.beads/beads.jsonl` dirty in
the working copy. Is there a way to clean this up from within the go tests?



Build me a new script for updating my feature branches.
-----------

Under the devbeads/ root here we have a `feature_branches.txt` file.



Describe for me the interface to the backend
---------------

How does beads interact with its sqllite backend? What atomicity assumptions are
made? Where in the code does it assume it can atomically update MULTIPLE issues
with one transaction?

=> Resulting AI summary
-----------------------------------------------------

● Looking at the code I've analyzed, let me describe the SQLite backend interface and atomicity guarantees:

  Backend Interface

  The backend is defined by the storage.Storage interface in /workspace/beads/internal/storage/storage.go. Key methods include:

  - Single operations: CreateIssue, UpdateIssue, DeleteIssue
  - Batch operations: CreateIssues (multiple issues atomically), DeleteIssues
  - Query operations: GetIssue, ListIssues, various filters
  - Relationship operations: CreateDependency, DeleteDependency
  - Configuration: GetConfig, SetConfig, GetMetadata, SetMetadata

  Atomicity Assumptions

  The SQLite backend uses these patterns for atomicity:

  1. BEGIN IMMEDIATE transactions - Acquires write lock early to prevent conflicts:
  if _, err := conn.ExecContext(ctx, "BEGIN IMMEDIATE"); err != nil {
      return fmt.Errorf("failed to begin immediate transaction: %w", err)
  }

  2. Deferred ROLLBACK - Ensures cleanup on errors:
  committed := false
  defer func() {
      if !committed {
          _, _ = conn.ExecContext(context.Background(), "ROLLBACK")
      }
  }()

  3. WAL mode - Configured at initialization in sqlite.go:143 for better concurrency
  4. Busy timeout - 30 seconds to handle lock contention

  Multiple Issues Updated Atomically

  Here are the key locations where beads updates MULTIPLE issues in one transaction:

  1. CreateIssues (sqlite.go:885-939)

  Creates multiple issues atomically in a single transaction. This is the primary batch operation:

  - Reserves ID range atomically
  - Bulk inserts all issues
  - Records all creation events
  - Marks all as dirty for export
  - All-or-nothing: if any step fails, entire batch rolls back

  2. Import Process (import_phases.go)

  Uses CreateIssues for batch importing:
  - Phase 4 (upsertIssues) collects new issues and creates them in one batch
  - Significantly faster than sequential creates (5-15x speedup mentioned in comments)

  3. DeleteIssues (sqlite.go:632-673)

  Deletes multiple issues in single transaction:
  - All deletions atomic
  - Cascading deletes for dependencies, events, labels handled automatically by foreign keys
  - Bulk records deletion events

  4. UpdateIssueID (sqlite.go:393-482)

  When renaming an issue ID, atomically updates:
  - The issue itself
  - All dependencies referencing it (blocks/blocked_by)
  - All comments referencing it
  - Ensures referential integrity maintained

  5. Implicit Multi-Issue Updates via Foreign Keys

  Operations like updating dependencies can affect multiple issues through CASCADE constraints:
  - Deleting an issue cascades to its dependencies
  - Deleting a dependency updates both issues' relationship counts

  The transaction boundary ensures these multi-issue operations are atomic - either all succeed or none do, maintaining database consistency even under concurrent access.




TODO: ambitious new backend for exploded markdown representation
========================================
This will reqire some planning.

### overall goal

The SQLlite backend introduces lots of potential desynchronization and
corruption issues, and the issues.jsonl representation is also terrible for
merge conflict resolving. An "exploded" format where the issues are all separate
text (markdown) files would be easier to deal with merge conflicts for humans
and AI agents.

Thus our goal is to present a second storage backend, configured by a
.beads/config.yaml setting `backend=sqlite | markdown`. It must present the same
interface as the current sqllite backend and be interchangeable.

### Mapping of beads issues to markdown.

We define a bidirectional mapping between the logical contents of the bead and a
markdown file on disk. The name of the file will simply be based on the issue
ID, which always has the form `prefix-XYZ`, e.g. : `.beads/markdown.db/prefix-XYZ.md`.

```
      --acceptance string     Acceptance criteria
  -a, --assignee string       New assignee
  -d, --description string    Issue description
      --design string         Design notes
      --external-ref string   External reference (e.g., 'gh-9', 'jira-ABC')
  -h, --help                  help for update
      --notes string          Additional notes
  -p, --priority int          New priority
  -s, --status string         New status
      --title string          New title
```

Short strings (store in YAML front matter)
 - title
 - status
 - priority
 - assignee
 - external-ref
 - labels (yaml list of strings)

These keys are only present in the front-matter if a non-empty value is set.

Long strings:
 - description
 - design
 - notes
 - acceptance

These are top-level sections in the main body of the note.
Their headers are only present if they are set to non-empty strings.
In addition to the string passed in, we store one extra newline before the
section heading line:

```

# Description
<STRING>

# Notes
<STRING>
```

If there's every any reason no privilege one of these sections, Description 
is the main one we expect every issue to have. The other long sections are
not expected to be used.

### Concurrency issues

This is the crux of the difference between files on disk and the SQLite database.
HOWEVER the expected level of contention on the DB is QUITE LOW in practice.
And atomic file moves across all file systems we care about will give us the
building block that we need.

Issue "locking" protocol:
 - Whenever we want to operate on issue-xzy.md, we lock it by moving the file
   to `issue-xyz.md.lock.<ourpid>`
 - We perform operations out-of-place on a new tempory copy of the file.
 - IF `renameat2` is available on our platform, we can rename two files at once:
    - `issue-xyz.md.tmp.<ourpid>` => `issue-xyz`
    - `issue-xyz.md.lock.<ourpid>` => `issue-xyz.md.trash.<ourpid>`
   Which would atomically "commit our change" for a single issue. After that 
   transaction succeeds we can freely delete `issue-xyz.md.trash.<ourpid>`.
 - If we only have single-file atomic move, that's ok, we can perform the two
   moves in order. The only minor issue is that another process may think we 
   still have the files locked for a  moment when we've already committed.

 - If we need to lock mulitple files, we follow lock-ordering based protocol.
   The process with the lower PID gets higher priority. If we see that another
   process that supercedes us holds a lock we want, we back off release all our
   locks, and wait to retry.

 - The multi-file write to the file system will not be atomic, but it will be
   atomic per-issue which should be sufficient for our use cases together with
   the lock-ordering protocol.

 - Concurrent writers attempting to create issues must recognize that any
   `issue-xyz.md*` files mean the issue is "busy/taken" and not try to clobber it.


--------

I cannot get a simple e2e test to work:

```
$ cd beads; go build -o bd ./cmd/bd
$ cd ../fresh_test
$ ../beads/bd init --backend=markdown # succeeds
$ ../beads/bd list
Error: failed to open database: failed to ping database: unable to open database file: out of memory (14)
# Couldn't attempt `../beads/bd create "test issue"`
```

We should probably have an e2e test to this effect.

----

It works for me but listing issues is remarkably slow. Even running repeatedly.
What are we doing?  Running find on this mostly empty directory takes 2ms.

```
$ time ../beads/bd list
Found 0 issues:
real	0m5.019s
user	0m0.012s
sys	0m0.027s

$ time find .beads/markdown.db/ > /dev/null
real	0m0.002s
user	0m0.001s
sys	0m0.001s
```

----

If I switch into a directory with an existing `.beads/issues.jsonl` (but no
database files in either backend), and I try to list the beads, I have this problem:

```
$ cd corruption_test
$ cat .beads/config.yaml
no-db: false
backend: markdown
issue-prefix: "mtg-"

$ ../beads/bd list
Error: failed to open storage: failed to create issues directory: mkdir /home/newton/work/beads-dev/devbeads/corruption_test/.beads/corruption_test.db: not a directory
```

It's trying to use the directory as the prefix rather than using the issue
prefix from the config.

-----

Ok, this is great, let's keep going. If I have a checkout that has an
`issues.jsonl` but no database, I am not able to auto-populate it the way we can
with the SQL lite database backend:

```
$ ../beads/bd list
Auto-import failed: import requires SQLite storage backend
```

Fix that code path.

----

The import code may work, but I cannot test it because even though the
issue-prefix is set in the config.yaml, in markdown mode we cannot find it:

```
$ cat .beads/config.yaml
# Beads Configuration
# no-db: true
no-db: false
backend: markdown
issue-prefix: "mtg-"
[newton@newton-fedora-MZ01GC9H ~/work/beads-dev/devbeads/corruption_test (markdown-init-flag)]
$ ../beads/bd list
Auto-import failed: failed to get configured prefix: key not found: issue_prefix

Found 0 issues:
```

---

What is the documentation around config.yaml in this project? Does it describe
it as a file configured by the human / checked into git, or as internal storage managed by the bd CLI?



done: bd init should respect config.yaml
----------------------------------------

Unless this contradicts some existing documentation in the project, I think if
bd init starts up and there is ALREADY a .beads/config.yaml, e.g. from version
control, it should be RESPECTED not CLOBBERED.

So, if we say `bd init` and we haven't provided flags for `--no-db` or
`--backend=`, what's in the config should take precedence.  In fact, if we
provide a flag and it contradicts what's in the config, we should ERROR instead
of picking a winner.


TODO: Manual testing shows issues with update
--------------------

You can use my `/workspace/corruption_test` directory for some manual testing.
When I attempt an update it goes through, but it also mentions a non-fatal error
failing to update:

```
$ ../beads/bd update mtg-64 --notes yayayayy
Auto-import failed: error updating issue mtg-58: failed to apply updates: invalid type for assignee: expected string
✓ Updated issue: mtg-64
```

Can you track this down?

----

```
$ ../beads/bd create foobar --description yayay
Auto-import failed: error updating issue mtg-58: failed to apply updates: invalid type for status: expected string
✓ Created issue: corrupt-1
  Title: foobar
  Priority: P2
  Status: open
```

TODO: Syncing markdown db => json not implemened
------

Since markdown is an alternate backend, we need, at least optionally, to be able
to maintain the same relationship to the issues.jsonl export of the data that
the sqllite backend does. So this should work:

```
../beads/bd sync --flush-only
Error exporting: failed to get dependencies: not yet implemented
```

After bidirectional updates from json <> markdown work,
we should also be expanding our test coverage so more of the standard e2e tests work
with both the sqllite and markdown backends.

AND THEN, when that's committed and we're in good shape, passing tests, we need
to recognize that it really makes NO SENSE to maintain both json and markdown,
because we would not get the benefits of better merge conflict resolution.

To support this use case, let's add a config parameter that completely turns
off any uses of the json export, making the backend the source-of-truth for
our issues always:

```config.yaml
no-json: true
```

This may be a substantial architecutural change, because it means everywhere
the json data store is referenced needs to be deactivated. But this will let us
run with our desired combination:

```config.yaml
no-json: true
backend: markdown
```

Note that if the user configures `no-db` and `no-json` we should error
immediately, because the data needs to go somewhere!

TODO: plan for daemon markdown mode
------------

Help me figure out what the policy on the daemon should be for the markdown
backend. First describe for me what the current logic is for the daemon
launching. Also, try to find the code for the mcp-beads MCP server and claude
plugin.  That is a prime use case for the daemon I believe, but tell me how/when/where it
invokes the actual bd binary.

We need to decide whether we want to keep the same daemon approach with
markdown, or just have it called on demand as a new bd command every time. There
may be some performance advantages to the daemon if it can keep things in
memory. But that's a tradeoff, because we want it to be careful about being
robust to external changes to the markdown files. So any assumptions it makes
about the state of disk should be validate when it touches the disk (e.g.
recording mod times and seeing if the markdown files have been externally
changed invalidating any cache).

This is a complex space, so let's gather intel and plan things first.

---

Ok great, no daemon for markdown. As long as the MCP server has a way to run
without the daemon, then let's definitely take backend=markdown to imply
BEADS_NO_DAEMON=1. That would also imply that we error on
`auto-start-daemon=true` in the config file combined with `backend=markdown`
because that is an unsupported combination.

I will test that the mcp server is still able to interact with beads even with a
markdown backend.




TODO: keep adding unsupported features in --no-db mode
========================================

I currently get this error when attempting repair.

```
$ bd rename-prefix mtg- --repair
✗ Multiple prefixes detected in database:
  - mtg: 71 issues
  - vc: 7 issues
  - workspace: 2 issues

Repairing database with multiple prefixes...
  Issues with correct prefix (mtg): 71 (highest: mtg-71)
  Issues to repair: 9

Error: failed to repair prefixes: failed to update issue vc-1 -> mtg-72: UpdateIssueID not supported in --no-db mode
```


TODO: add a way to change labels from bd update
========================================



