---
name: amaze-new-tool
description: Add a new canvas tool or brush to Concepts Clone (aMaze) — brush library entry, icon, handler, strings and tests — the same way Nudge and Slice were built. Use when the user asks for a new tool, brush or library entry, or to make an "unavailable" library entry work.
---

# Adding an aMaze tool

aMaze tools reuse an existing Butterfly `Tool` type and are told apart by
`displayIcon` = `amaze.<entryName>`. This keeps saved files readable by classic
Butterfly. Follow Nudge (`HandTool` + `app/lib/handlers/nudge.dart`) and Slice
(`EraserTool` + `app/lib/handlers/slice.dart`) as references; read both before
starting.

## 0. Decide the shape

- **Pure preset** (different settings of an existing tool, e.g. a new pen):
  only steps 1–3 and 6.
- **New behavior** (new gesture or editing logic): all steps.
- Only add a new `Tool` variant in `api/lib/src/models/tool.dart` if no existing
  type can carry the tool's settings. That changes the file format, so confirm
  with the user first.

## 1. Library entry — `app/lib/views/amaze/library.dart`

- If the entry already exists as unavailable (e.g. `hardMask`, `airbrush`),
  reuse it. Otherwise add a `LibraryEntry` value with its `LibrarySection`
  and glyph.
- In `_build()`, return the base tool (e.g. `Tool.eraser(mode: ...)`).
  `createTool()` adds `displayIcon: 'amaze.<name>'` for you.
- Add the case to `getLocalizedName`.

## 2. Icon — `app/lib/views/amaze/icons.dart`

Add an `AmazeGlyph` value and its painter method next to `_nudge()` /
`_slice()`, using the same stroke weight and grid as the other glyphs. Or use a
`PhosphorAmazeIcon` in `LibraryEntry.icon` if a Phosphor icon fits.

## 3. Strings — `app/lib/l10n/app_en.arb`

Add the name (and any hint text) to `app_en.arb` only, then run
`flutter gen-l10n` in `app/`.

## 4. Handler — `app/lib/handlers/<name>.dart`

- `part of 'handler.dart';` and add `part '<name>.dart';` in `handler.dart`.
- Declare `const k<Name>DisplayIcon = 'amaze.<name>';` and, if useful,
  `bool is<Name>Tool(Tool tool)`.
- In `Handler.fromTool`, add a `when` branch **above** the base case:
  `EraserTool() when tool.displayIcon == kXDisplayIcon => XHandler(tool),`.
- Put the math in top-level `@visibleForTesting` functions (like
  `nudgePenPoints`, `splitPenPointsAtCut`) so it can be unit-tested without
  widgets. Guard NaN/infinite input and degenerate strokes; interpolate pressure.
- Show the in-progress result as a preview (foreground renderer), and commit
  **once** at gesture end through the document bloc
  (`context.getDocumentBloc().add(ElementsChanged(changes, pageName: ...))`),
  with only the elements that changed. Commit nothing if nothing changed.
- Handle cancel (second pointer, pointer cancel, tool switch): drop the preview,
  commit nothing.
- If the tool has settings, reuse the base tool's property fields.

## 5. Tests — `app/test/`

- `test/handlers/<name>_handler_test.dart`: unit tests for the geometry
  functions, including edge cases (empty stroke, one point, NaN, no change).
- If the wheel/library shows it, extend `test/views/amaze_icons_test.dart` and
  `amaze_shell_test.dart` (entry is available, icon renders, tool can be put in
  a slot).

## 6. Finish

Run the `amaze-check` skill, then review the
change with the `amaze-reviewer` agent (Claude Code) or the `amaze-review`
skill (Codex). Commit with a message like `Add <Name> tool`, on a feature branch off
`amaze/develop` (or the branch the user is working on).
