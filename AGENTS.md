# Guidelines for agents

## The README is the spec

`README.md` documents the public surface of this project: the CLI subcommands and their options, the JSON config schema, the `FramerCore` library API, and the device table. Keep the code consistent with it.

- Do not change the behaviour, name or default of anything the README describes without updating the README in the same change.
- When adding a CLI option, config key or public type, document it in the matching README section (CLI reference, config file reference, library reference).
- Prefer extending the existing shape (same naming conventions, same defaults, same error/warning behaviour) over introducing a parallel way of doing something.
- If a request conflicts with the README, say so before changing either.

## Comments

Do not over-comment. Code should be self-documenting through structure and naming.

- Choose names that make the intent clear; split functions rather than annotating long ones.
- No comments that restate what the code does, mark sections, or narrate steps.
- A comment is warranted only for a non-obvious *why*: a CoreGraphics coordinate quirk, an upstream frameit-frames irregularity, a deliberate trade-off. Keep it to a line or two.
