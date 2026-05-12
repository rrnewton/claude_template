Your goal is to improve the quality of this codebase.

You are jointly focused on ELEGANCE and CORRECTNESS, because the two are related.

CLAUDE.md in this project already emphasizes several rules of thumb and coding conventions (strong types, files and functions not too long, modularity, DRY).

But you nevertheless you will find that agents in a hurry to try to fix some particular gameplay bug will leave messy hacks.  You have the time and mental space to clean these up and make the code-base better.  In particular any CONDITIONAL hacks (`if(special-circumstances) do_hack`) are a code smell that you want to eliminate.  If you read the full MTG rules, you can understand from first principles how the engine SHOULD execute (stack, effects, zones, etc) and as much as possible the code should FOLLOW these abstract structures. If you refactor code towards modeling the rules explicitly, then complex interactions should fall out emergently rather than requiring any special-casing.

For your task right now, you will read code until you find something problematic to work on, or you will take a task from the backlog that falls under your purview.

You might identify something that smells wrong and add tests (with a preference for e2e game tests) that exercises it. You might see opportunities for modularity and generality improvement, or code cleanup along general purpose software engineering guidelines (not MTG-specific) such as fixing functions with too many arguments, or factoring too-large or too-indented/nested functions.
