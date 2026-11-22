---
name: amaze-check
description: Run the same checks as Concepts Clone's CI (format, l10n, build_runner, analyze, tests) and fix any failures. Use before committing, before saying a change is done, when CI fails, or when the build or analyzer shows errors.
---

# amaze-check

Mirrors `.github/workflows/dart.yml` so problems are caught before pushing.

## Steps

Run from the repo root. Stop at the first failing step, fix it, then rerun
from that step.

1. **Dependencies**
   ```bash
   cd app && flutter pub get && cd ../api && dart pub get && cd ..
   ```
2. **Localizations** (only if `app/lib/l10n/app_en.arb` changed)
   ```bash
   cd app && flutter gen-l10n && dart format lib/src/generated && cd ..
   ```
3. **Code generation** (only if a `@freezed` / `@JsonSerializable` class or
   `part '*.g.dart'` file changed, in `app/` or `api/`)
   ```bash
   cd api && dart run build_runner build --delete-conflicting-outputs && dart format . && cd ..
   cd app && dart run build_runner build --delete-conflicting-outputs && dart format . && cd ..
   ```
4. **Format**
   ```bash
   cd app && dart format lib test && cd ../api && dart format lib test && cd ..
   ```
5. **Analyze** (infos count as failures, like CI)
   ```bash
   cd app && flutter analyze --fatal-infos && cd ../api && flutter analyze --fatal-infos && cd ..
   ```
6. **Tests**: the tests for what changed first, then the full suite.
   ```bash
   cd app && flutter test test/handlers/<file>_test.dart   # targeted
   cd app && flutter test                                   # full
   cd api && dart test                                      # if api/ changed
   ```
7. **Generated files committed?**: `git status`. Generated files changed by
   steps 2–3 must be committed with the change; CI fails on any diff.

## Fixing failures

- Fix the cause, not the symptom. Never add `// ignore:` or loosen
  `analysis_options.yaml` to get green, and never delete or skip a failing test,
  unless the user agrees.
- Errors mentioning `_$Something`, `.freezed.dart` or `.g.dart` → rerun step 3.
- `AppLocalizations` has no getter `x` → the key is missing in `app_en.arb` or
  step 2 wasn't run.
- `undefined name` inside a handler → handlers are `part of 'handler.dart'`;
  imports go in `handler.dart`, not the part file.
- Widget test times out or "pending timers" → autosave/debounce timers; flush
  them the way `amaze_shell_test.dart` does instead of adding long waits.
- Golden or layout overflow on tablet sizes → check the screenshots in
  `app/build/amaze_screenshots/`.
- Version mismatch errors → Flutter must match `environment.flutter` in
  `app/pubspec.yaml` (`flutter --version`).

## Report

Finish with a short table: step → pass/fail, plus what you fixed. If something
can't be fixed without a decision (e.g. a test that encodes old behavior), stop
and ask.
