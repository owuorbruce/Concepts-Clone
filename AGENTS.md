# AGENTS.md — Concepts Clone (aMaze)

aMaze is a Concepts-style infinite-canvas sketching app, built as a fork of
[Linwood Butterfly](https://github.com/LinwoodDev/butterfly) (Flutter/Dart).
The upstream code still uses the `butterfly` package names; aMaze is the
product name and UI layer on top.

**Current status and next tasks: see `HANDOFF.md`.**

## Repo layout

- `app/` — the Flutter app (package `butterfly`). Almost all work happens here.
  - `app/lib/views/amaze/` — **the aMaze editor shell** (our code): `shell.dart`
    (flags), `layout.dart`, `tool_wheel.dart` (radial wheel), `dock.dart`,
    `tool_slots.dart` (8 slots), `slot_menu.dart`, `brush_library.dart`,
    `library.dart`, `icons.dart`, `style.dart` (design tokens), `wheel_prefs.dart`.
  - `app/lib/handlers/` — one handler per tool, all `part` files of `handler.dart`.
    Our tools: `nudge.dart`, `slice.dart`.
  - `app/lib/l10n/app_en.arb` — UI strings.
  - `app/test/` — widget and handler tests (`views/amaze_*_test.dart`,
    `handlers/*_handler_test.dart`).
- `api/` — `butterfly_api`: file format and data models (freezed + json_serializable).
  Tool types live in `api/lib/src/models/tool.dart`.
- `tools/` — build/release scripts (upstream). Rarely touched.
- `docs/` — upstream docs site.

## Branches

- `amaze/develop` — base branch for aMaze work.
- `feature/amaze-editor-shell` — main active branch (wheel, dock, brush library,
  Nudge and Slice tools). Pushes here also publish a web preview to `gh-pages`
  via `.github/workflows/amaze-preview.yml`.
- `feature/smart-connectors`, `feature/palette-import` — other aMaze features.
- `develop` — tracks upstream Butterfly. Don't commit aMaze work to it.

## Commands (run inside `app/` unless noted)

Flutter version is pinned in `app/pubspec.yaml` (`environment.flutter`).

```bash
flutter pub get
flutter gen-l10n                     # after editing app_en.arb
dart run build_runner build --delete-conflicting-outputs   # after changing freezed/json models (app or api)
dart format lib test
flutter analyze --fatal-infos
flutter test                         # app tests
flutter test test/views/amaze_shell_test.dart   # one file
flutter run -d windows               # or -d chrome
```

For `api/`: `dart pub get`, `dart test`.

CI (`.github/workflows/dart.yml`) runs exactly this: format check, analyze with
`--fatal-infos`, build_runner, then **fails if generated files differ from what's
committed**, then tests. Before saying a change is done, run format, analyze and
the relevant tests locally.

Widget tests write review screenshots to `app/build/amaze_screenshots/`
(uploaded as a CI artifact). Look at them when changing the shell UI.

## Conventions

- **Keep aMaze changes isolated** so upstream Butterfly can still be merged:
  new UI goes in `app/lib/views/amaze/`; edits to upstream files should be small
  hooks (e.g. a `when` branch in `Handler.fromTool`, a check of `usesAmazeShell`).
- **New tools reuse existing `Tool` types** instead of adding to the file format.
  A tool is told apart by its `displayIcon` (e.g. `amaze.nudge` on a `HandTool`,
  `amaze.slice` on an `EraserTool`), dispatched in `Handler.fromTool`. Only add a
  new `Tool` variant in `api/` if that's truly impossible, because it changes
  saved files.
- **Edits must be non-destructive and undoable**: go through document events
  (the bloc) so undo/redo works, and only commit the elements a gesture actually
  changed.
- The aMaze shell is the default on every platform (`amazeShellIsDefault`);
  the `classicEditor` flag switches back. Don't break the classic editor.
- Colors and sizes come from `AmazeStyle` (`style.dart`); the wheel and dock use
  `AmazeStyle.instrumentTheme` (dark, high-contrast). No hard-coded colors in widgets.
- Strings: add to `app_en.arb` only. Other `app_*.arb` files come from Crowdin.
- Never hand-edit generated files (`*.g.dart`, `*.freezed.dart`,
  `lib/src/generated/**`); regenerate them.
- Style: single quotes, super parameters, `flutter_lints` (see `analysis_options.yaml`).
- Every new tool or shell behavior gets a test in `app/test/`.

## Environment

- Developed on Windows (PowerShell). Prefer commands that work there.
- License: AGPL-3.0 (keep it). Butterfly's name and logo are under
  `BRANDING_LICENSE`, which is why the app is rebranded as aMaze. Don't
  reintroduce Butterfly/Linwood branding in user-facing UI.

## AI tooling (Claude Code and Codex)

This file is the shared project guide. `CLAUDE.md` only imports it, so edit
rules here, not there.

Skills exist in two copies with identical content:

- `.claude/skills/<name>/SKILL.md` — read by Claude Code
- `.agents/skills/<name>/SKILL.md` — read by Codex

**When you change a skill, make the same change in its twin in the same commit.**
The reviewer is a Claude Code subagent (`.claude/agents/amaze-reviewer.md`) and a
Codex skill (`.agents/skills/amaze-review/SKILL.md`); keep their checklists in sync.

| Skill | Use it to |
|---|---|
| `amaze-check` | run CI's checks locally and fix failures |
| `amaze-new-tool` | add a tool or brush the way Nudge and Slice were built |
| `amaze-review` / `amaze-reviewer` | review a change before committing |
