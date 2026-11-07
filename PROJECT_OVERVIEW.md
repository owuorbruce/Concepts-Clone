# aMaze (Concepts Clone): project overview

A plain-language summary of the project: what it is, what has been built, what
was done to set it up for AI helpers, and every feature still planned. For rules
and commands see `AGENTS.md`. For the next task see `HANDOFF.md`.

---

## 1. What aMaze is

- A **free, open-source drawing and note-taking app** in the style of the
  "Concepts" app.
- Made mainly for **Android tablets**, especially the **Samsung Galaxy Tab S10 FE**
  with the S Pen.
- **Infinite canvas** for drawing, handwriting, study notes, diagrams, mind maps
  and visual planning.
- Built on **Linwood Butterfly v2.6.2** (Flutter/Dart). Butterfly already has the
  canvas, pen strokes, layers, erasing, export and sync.
- Repo: `github.com/owuorbruce/Concepts-Clone`. Active branch:
  `feature/amaze-editor-shell` (PR #3 into `amaze/develop`).
- License: **AGPL-3.0**, inherited from Butterfly. The Butterfly name and logo
  can't be reused, so the app is branded **aMaze**.

## 2. The original goals (must-haves)

From the project brief:

- Works well on Android, especially the Tab S10 FE
- S Pen pressure sensitivity
- Reliable palm rejection (a resting hand doesn't draw)
- Smooth zooming, rotating and panning
- Drawings stay editable vectors, with selection and layers
- Free local saving, exporting and editing
- **No account, cloud service or subscription required**
- Optional AI connection (**MCP**) so AI tools can read and edit canvas objects
- Supports study notes, diagrams, mind maps, sketches and planning
- Opens old Butterfly files wherever possible
- Follows every license, including AGPL-3.0

Rules from the brief that still apply:

- Keep what Butterfly already does; only replace a part with proof it falls short.
- Don't rewrite Butterfly's drawing and rendering engine.
- Don't build two versions of the same feature.
- One document format, one undo history, one coordinate system, one save method.
- Small changes that can each be tested on their own.
- Don't claim something builds or runs fast unless it was actually tested.
- Don't copy code from **wenz_draw** (it has no license).
- Projects to study for ideas: **Infinite Canvas** (AI control via MCP),
  **PadNote** (Android handwriting, approving AI changes before they land),
  **xlinkote** (spatial notes, links between notes, Markdown).

## 3. What has been built so far

All on `feature/amaze-editor-shell`; CI passes for all of it.

**aMaze editor shell** (`app/lib/views/amaze/`)
- New editor layout, now the default on every platform. The `classicEditor`
  setting switches back to Butterfly's layout.
- **Tool wheel**: a movable radial wheel and the main control. High-contrast dark
  "instrument" look, readable numbers, undo/redo that stays legible when disabled.
- **Dock**: puts layers and pages first on tablets; tool properties sit beside it.
- **8 tool slots** with useful tablet defaults, and a menu to change each slot.
- **Brush library** sidebar with wide stroke previews, organized into sections,
  plus its own aMaze icon set.
- Compact, high-contrast surfaces and a lighter document header; extra Butterfly
  toolbars and zoom controls are folded away so the wheel isn't crowded.
- A **web preview** published to GitHub Pages on every push.

**New tools**
- **Nudge**: push strokes around with a soft brush. Only the strokes that moved
  are saved, so undo stays clean.
- **Slice**: cut strokes into pieces without destroying them, undoable.
- Both reuse Butterfly's existing tool types, so saved files still open in
  Butterfly.

**Other features**
- **Smart connectors**: lines that attach to shapes and follow them when moved,
  hardened after review (cache refresh, id collisions).
- **Palette import**: color palettes from GIMP, Adobe, Procreate and hex files.

**Working brushes in the library**: Pen, Dynamic pen, Fixed width, Wire, Fill,
Lasso, Nudge, Slice, Text, Pan.

## 4. What was done in the Nov 7 session

- Looked at **ECC** (`affaan-m/ECC`, a large add-on pack for AI coding tools)
  and decided against installing it. It's too big and generic for a solo
  Flutter project. Only a few ideas from its Flutter reviewer were worth keeping.
- Installed **Claude Code** on Windows and fixed its PATH.
- Wrote **project guides and skills** that work in Claude Code, Codex and ChatGPT:
  - `AGENTS.md`: the shared project guide (layout, branches, commands, rules).
  - `CLAUDE.md`: one line that imports `AGENTS.md` for Claude Code.
  - `amaze-check` skill: runs the same checks as CI and fixes failures.
  - `amaze-new-tool` skill: the recipe for adding a brush the way Nudge and
    Slice were built.
  - `amaze-review` skill / `amaze-reviewer` agent: reviews changes before
    committing.
  - Skills live in `.claude/skills/` (Claude Code) and `.agents/skills/`
    (Codex), as identical copies.
- **Merged** `feature/smart-connectors` and `feature/palette-import` into the
  editor branch.
- **Fixed CI**, which had been failing:
  - 26 classic-editor tests broke when aMaze became the default everywhere. A
    test-only switch (`debugAmazeShellIsDefault`) now runs them on the classic
    layout.
  - Formatting fixes in the palette-import code and tests.
- Wrote `HANDOFF.md` with the status and the ordered next tasks.

## 5. Features still to build

**Brushes in the library that show as unavailable (15)**

| Group | Entries | Difficulty |
|---|---|---|
| Pen presets | Fountain, Soft pencil, Hard pencil, Marker, Dotted | Easy: pen settings only |
| Navigation | Rotate, Zoom | Easy: reuse camera/hand behavior |
| New rendering | Hard mask, Soft mask, Watercolor, Airbrush | Hard: new drawing or handler code |
| Textures/patterns | Tiling patterns, Waterful, Crosshatching, Ink blot | Hard: texture rendering |

**Must-haves from the brief that aren't done or proven yet**

- **S Pen pressure and palm rejection**: Butterfly has stylus and pen-only
  input, but it hasn't been tested and tuned on a real Tab S10 FE.
- **Smooth zoom/rotate/pan on the tablet**: needs a real-device test.
- **MCP connection** so AI tools can read and edit canvas objects: not started.
  The natural place for it is the `api/` package (file format and models).
- **Mind maps and linked notes** (ideas from xlinkote): not started.
- **Approving AI changes before they apply** (idea from PadNote): not started,
  goes with MCP.
- **Architecture docs** planned in the brief (`docs/architecture/`
  `baseline-audit.md`, `integration-matrix.md`, `mcp-design.md`,
  `implementation-roadmap.md`): not written.

**Finishing up**

- Merge PR #3 into `amaze/develop` once the brushes are done and CI is green.
- Delete the leftover `tmp/format-diff` branch on GitHub.
- Build an Android release and test it on the Tab S10 FE.

## 6. How to work on it

- Read `AGENTS.md`, then `HANDOFF.md`.
- For each brush: `amaze-new-tool`, then `amaze-check`, then `amaze-review`.
  One brush per commit.
- GitHub CI is the final check (format, analyze, generated files, tests, builds).
