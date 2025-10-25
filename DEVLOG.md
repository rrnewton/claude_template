

[2025-10-25] Set up container for beads dev
===========================================


Ambitious new feature `bd --no-db` mode
-------------------------------------

Especially when I have the same directory mounted inside a container and accessed on the host, it's VERY easy to get corruption, duplication, and get out of sync between different `bd` instances accessing the same `.beads` directory.

To avoid this, I want a much simple `bd --no-db` global option which affects all subcommands.

The idea with this alternate mode is to do all operations DIRECTLY on the `issues.jsonl` file, with no SQLlite database.

The `bd` code already contains the logic to load and export the json file. This change will require each command to load the DB into memory from the json and output it again.

`bd init -p prefix` is not actually needed in `--no-db` mode. Instead, it will use the simple heuristic of, once it has read the .jsonl file, continuing to use the prefix of issues in that file, if all issues share the same prefix. If we do run `bd --no-db init -p prefix` we can also generate a file nodb_prefix.txt and use that if it exists.

This will be a big change to make, so let's plan it out step by step. First port the `bd --no-db create` subcommand so that we can create an issue this way, and then we can take the other subcommands one by one.

