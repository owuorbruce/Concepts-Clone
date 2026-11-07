# Handoff — aMaze status (2026-11-07)

Read `AGENTS.md` first for rules and commands. This file says where the project
stands and what to do next. Update it when you finish a task.

## Where things are

- Active branch: `feature/amaze-editor-shell`. Open PR #3 into `amaze/develop`.
- CI on the branch is fully green (Dart quality, Flutter build, connector tests,
  web preview).
- Merged into this branch on 2026-11-07: `feature/smart-connectors` and
  `feature/palette-import`. Those branches are now done.
- Done and working: aMaze shell (default on every platform), tool wheel, dock,
  8 tool slots, brush library, Nudge tool, Slice tool, smart connectors,
  palette import (.gpl/.ase etc.).
- Test-only switch `debugAmazeShellIsDefault` (in `views/amaze/shell.dart`) keeps
  the classic-editor tests in `project_page_lifecycle_test.dart` on the classic
  layout. Don't remove it.

## Next tasks, in order

Use the `amaze-new-tool` skill for each brush, then `amaze-check`, then
`amaze-review`. One brush per commit.

1. **Easy brushes** (pen presets, no new rendering) in
   `app/lib/views/amaze/library.dart` `_build()`:
   `fountain`, `softPencil`, `hardPencil`, `marker`, `dotted`.
2. **Simple navigation entries**: `rotate`, `zoom` (reuse existing camera/hand
   behavior).
3. **Hard tools** (need new rendering or a handler): `hardMask`, `softMask`,
   `watercolor`, `airbrush`.
4. **Texture/pattern brushes**: `tilingPatterns`, `waterful`, `crosshatching`,
   `inkBlot`.
5. When the list is done and CI is green, merge PR #3 into `amaze/develop`.

## Cleanup

- Delete the leftover branch `tmp/format-diff` on GitHub (throwaway CI file).

## Notes

- No local Flutter in the cloud sessions used so far; CI is the source of truth.
  Locally on Windows, run the `amaze-check` steps before pushing.
- Skills have twin copies in `.claude/skills/` and `.agents/skills/`; change both.
