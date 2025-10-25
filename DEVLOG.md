

[2025-10-25] Set up container for beads dev
===========================================


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





