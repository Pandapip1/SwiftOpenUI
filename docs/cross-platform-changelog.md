# Cross-platform changelog

Append-only log of **shared-surface** changes — anything in a backend or the
shared core that *another* backend/platform consumes and could be affected by
(the shared symbol map, core `View`/`Layout` types, the view-host, cross-cutting
behavior). Backend-only internals that can't regress another platform don't
belong here — keep those in the backend's own docs/issues.

Every SwiftOpenUI backend agent clones this repo, so this is the discovery
point for "did someone change something under me?" **Newest entries on top.**
One entry per shared change; always say who to ping if it regresses your
backend.

```
## YYYY-MM-DD — <platform/agent> — <summary>
- Shared surface: <what shared/core file or type changed>
- Impact: <who consumes it / could regress; verification if known>
- Ping: <owner/agent>
- Refs: <commits / issue docs>
```

---

## 2026-10-03 — GTK4 — scope observation to each composite body

- Shared surface: `Bindable` now reads a projected property during projection,
  registering the dependency when the owning body evaluates. Its returned
  binding still reads and writes the live property.
- Impact: GTK4 ends body observation before rendering descendants, preventing a
  child's observable reads from rebuilding ancestors and resetting navigation.
  Other backends retain their rendering paths; binding projection now performs
  one additional getter read. GTK regressions cover external binding updates and
  repeated child changes without ancestor rebuilds.
- Ping: Pandapip1 / Hummingbird GTK maintainer.
- Refs: `GTK4ObservationIsolationTests`.

## 2026-07-10 — Windows (Win32) — shared symbol map entry + child-@State convergence

- **Shared surface:** `SwiftOpenUISymbols/SFSymbolCompatibility.swift` +
  `MaterialSymbolsCodepoints.swift` — added `circle.dotted →
  radio_button_unchecked` (0xE836). Additive; no existing mapping changed.
- **Impact:** every backend resolves `circle.dotted` now (macOS uses native SF
  Symbols → no-op). Verified benign on macOS; **net positive on GTK4** (the
  `SyncAction.ignore` badge now resolves to a real Material glyph instead of a
  missing symbol).
- **Awareness (not a shared-code change):** the Win32 child-`@State`
  reconciliation gap (`docs/issues/win32-conditional-view-rebuild.md`) is a
  **shared view-host problem** — GTK4 independently hits the same
  OutlineGroup-expansion-resets-on-ancestor-rebuild failure. Likely **one fix
  at the shared view-host layer** (ID-keyed child-state persistence) retires
  the workarounds on *both* Win32 and GTK4. Reconcile the two designs before
  either backend invests further.
- **Ping:** Win32 agent (symbol map); Win32 + Linux agents (reconciliation).
- **Refs:** SwiftOpenUI `629323a`;
  `docs/issues/win32-outlinegroup-dropdown-followups.md`.
