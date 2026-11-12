# Claude memory export (2026-11-12)

A copy of Claude Code's per-project memory from the first project Mac, taken before development
moved to the Mac Studio. The same rules are in `CLAUDE.md` ("Owner rules copied from Claude's
memory"), which Claude loads in every session; `CLAUDE.md` wins if the two ever differ.

Claude keeps its memory outside the repository, in
`~/.claude/projects/<the checkout's absolute path with every "/" and "." replaced by "-">/memory/`.
`python3 scripts/setup_mac.py` copies these files there on a new Mac and never overwrites a file
that already exists. `MEMORY.md` is the index; each other file holds one memory.

This folder is a snapshot. Memories Claude saves later live only on the Mac that saved them, so
copy the rule into `CLAUDE.md` whenever a new one matters to the project.
