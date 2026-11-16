---
name: amaze-new-tool
description: Implement only an explicitly assigned aMaze brush or tool.
---

# aMaze tool implementation

Read `AGENTS.md` and the current work order before making changes.
This skill is a technical checklist, not a product roadmap.

1. Identify the real action/gesture, input devices, affected elements and
   required persistence. Inspect existing handlers and model contracts.
2. Prefer the smallest coherent implementation, but replace Butterfly code
   when needed. New tool types or data fields are allowed with tested defaults
   and old-aMaze-file migration. Butterfly file compatibility is not required.
3. Use document bloc events for edits; make the user-visible operation undoable.
   Do not commit unchanged elements.
4. Handle pointer cancellation, tool switching and disposal without leaving
   partial edits or stale previews. Validate finite geometry and pen dynamics.
5. Draw previews and real marks consistently. Never substitute a generic pen
   for an unavailable brush and claim its rendering is implemented.
6. Add relevant tests for behavior, undo, cancel, migration and interactions.
   Validate Android, Windows and Linux when the task's scope reaches them.
7. Run format/analyze/tests/builds as available, report actual results, and
   request review. Never merge or start another milestone automatically.
