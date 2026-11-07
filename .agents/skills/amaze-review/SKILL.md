---
name: amaze-review
description: Review changes to Concepts Clone (aMaze, a Flutter fork of Butterfly) for bugs, aMaze conventions and Flutter pitfalls. Use after finishing a feature or fix, before committing or opening a PR. Reports findings only; does not edit code.
---

You review code in the aMaze repo. Read `AGENTS.md` at the repo root first; its
conventions are the rules. You report problems, you do not fix them.

## 1. Find what changed

Run `git diff --staged` and `git diff`. If both are empty, review the branch
against its base: `git diff amaze/develop...HEAD` (or the last few commits with
`git log --oneline -5`). Read every changed Dart file in full, plus the callers
of anything whose behavior changed.

## 2. Check, most important first

**Correctness and data (CRITICAL)**
- Canvas edits must go through document bloc events (`ElementsChanged` etc.) so
  undo/redo works. Direct mutation of document or element state is a bug.
- A gesture must only commit elements it actually changed (see the Nudge handler:
  "commit only moved strokes"). Committing untouched elements bloats undo history.
- Cancelled gestures (second finger, pointer cancel, tool switch) must leave the
  document unchanged and clear any preview.
- Geometry: guard against NaN/infinite values, zero radius/length, empty or
  one-point strokes. Pressure must be interpolated, not dropped.
- Saved-file compatibility: a new `Tool` variant or changed model in `api/`
  changes the file format. Flag it unless it is clearly intended. New tools
  should reuse an existing `Tool` type and be identified by `displayIcon`
  (`amaze.<name>`).
- The classic editor (`classicEditor` flag) must still work.

**Lifecycle and performance (HIGH)**
- `StreamSubscription`, `Timer`, `AnimationController`, `TextEditingController`,
  `FocusNode`, listeners: created in `initState`, released in `dispose`.
- No `.listen()`, sorting, hit-testing loops or I/O inside `build()`.
- Pointer-move handlers run on every event: no allocations of whole stroke lists
  per event when a preview update would do; no full-document scans per move.
- `BlocBuilder`/`BlocSelector` scope: rebuild only what depends on the change;
  add a `buildWhen`/selector when watching a large state.
- Use `MediaQuery.sizeOf(context)` and friends, not `MediaQuery.of(context)`.
- `const` constructors where all fields are final.
- Stable keys for reorderable lists (tool slots, library tiles).

**aMaze conventions (HIGH)**
- New shell UI lives in `app/lib/views/amaze/`; changes to upstream files are
  small hooks. Flag large rewrites of upstream code.
- Colors and sizes come from `AmazeStyle` / `AmazeStyle.instrumentTheme`, not
  hard-coded `Color(...)` in widgets.
- User-facing text comes from `AppLocalizations`; new keys only in `app_en.arb`.
- No hand edits to `*.g.dart`, `*.freezed.dart` or `lib/src/generated/**`.
- No Butterfly/Linwood branding in user-facing UI.
- New tools and shell behaviors have tests in `app/test/`.

**Accessibility (MEDIUM)**
- Wheel, dock and slot buttons have tooltips or `Semantics` labels.
- Touch targets at least 40x40 logical pixels on tablet layouts.

Do **not** flag: `_buildX()` helper methods (upstream style), `BuildContext`
use after `await` (lint disabled on purpose), or style the formatter and
`flutter analyze --fatal-infos` already enforce.

## 3. Report

Only report issues you are more than 80% sure are real. Group repeats ("4
widgets missing const"). For each finding:

```
[SEVERITY] path/to/file.dart:LINE — one-line problem
  Why: what goes wrong, with a concrete case (input/gesture → result)
  Fix: the smallest change that fixes it
```

End with one line: `Verdict: ready to commit` or `Verdict: fix CRITICAL/HIGH first`.
If you found nothing, say so plainly; don't invent findings.
