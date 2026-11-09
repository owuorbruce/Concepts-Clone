# aMaze — Repository Agent Rules

This file contains technical guardrails only. Private product plans, roadmaps,
strategy and owner decisions are not stored or reproduced in this repository.
Do not publish them in commits, PR descriptions, issues or generated docs
without explicit owner permission.

## Authority and scope

- Work only on the task explicitly assigned by the owner or architect.
- Do not infer follow-up milestones or change unrelated code.
- Use the base branch and file limits specified in each work order.
- Do not merge, open a PR or publish project plans without authorization.
- Report each actual action, changed file, validation result and limitation.

## Technical requirements

- aMaze is independent software built from Butterfly. Replacing upstream code
  is permitted when necessary; compatibility with Butterfly is not required.
- Existing aMaze drawing files must continue to open. Model changes require
  defaults, migration coverage and round-trip tests.
- Android, Windows and Linux are equal targets; do not design or validate for
  one platform alone.
- Preserve applicable licenses and attributions. Use original assets.
- Keep one canonical document state, undo/redo history and save path.
- Changes to drawings must go through the document bloc, not direct mutation.
- Keep changes reviewable and include relevant regression tests.
- Never hand-edit generated files; run code generation when models change.
- Localize user-visible strings via `app/lib/l10n/app_en.arb`.

## Verification

From `app/` when the work order permits:

```sh
dart format lib test
flutter analyze --fatal-infos
flutter test
```

Run any required API tests, code generation and target-platform builds when
applicable. Report exact commands and results. Never claim unavailable checks
passed. Review before the owner authorizes a merge.

`CLAUDE.md` imports this file. There are no other repository-wide plans
or execution orders.
