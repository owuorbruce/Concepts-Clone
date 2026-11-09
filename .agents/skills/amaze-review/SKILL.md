---
name: amaze-review
description: Review the explicitly assigned aMaze change for correctness, regressions, performance and cross-platform behavior. Report only; do not edit.
---

# aMaze code review

Read `AGENTS.md` and the assigned work order. Compare the changed files
against the **specified base**, not an assumed branch. Read relevant callers.
Review is scoped to the current change, not an opportunity to add features.

## Critical correctness

- Edits must pass through the document bloc and produce coherent undo/redo.
- Cancelled or interrupted gestures must leave no unintended changes.
- Geometry must reject NaN/infinity, degenerate paths and invalid dimensions.
- Preserve pressure/tilt/velocity semantics when editing supported strokes.
- Existing **aMaze** files must open; changes to models need defaults and tests.
- Butterfly compatibility is not required; replacement of upstream code is
  permitted when justified and reviewable.
- A tool/brush shown as working must implement the advertised behavior.

## High priority

- No leaks or unbounded work on pointer move/build; release subscriptions.
- Keep input handling consistent on Android, Windows and Linux.
- Prevent gesture conflicts between wheel, canvas, S Pen, touch and mouse.
- Keep focus, screen resizing, accessibility, pointer cancel and undo stable.
- No unrelated files, accidental generated changes, extra packages or assets.
- Original artwork and applicable license/attribution requirements.
- UI text comes from localization; test new or changed user interactions.

## Output

Report only issues supported by concrete evidence (path, line, reproduction,
consequence, smallest fix). Separate **verified** checks from **unrun** checks.
Do not infer completion, run work orders automatically, change code or merge.
Finish with `Verdict: ready for owner review` or
`Verdict: fix critical/high issues before review`.
