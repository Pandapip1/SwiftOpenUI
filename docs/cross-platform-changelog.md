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

## 2026-10-04 — GTK4 — direct GStreamer media surface

- **Shared surface:** GTK4 playback now uses a `playbin3` pipeline with an
  `appsink` RGBA surface, replacing `GtkVideo` for embedded playback.
- **Impact:** GTK can decode through the configured GStreamer plugin set while
  SwiftUI owns the rendered surface. The Nix development and packaging inputs
  now include GStreamer development headers and linker libraries.
- **Ping:** Hummingbird media owner.
- **Refs:** `GTKMedia.swift`, `CGStreamer/gstshim.h`.

## 2026-10-04 — GTK4 — repaint video frames through DrawingArea

- **Shared surface:** the GTK media surface now copies decoded RGBA frames into
  a Cairo-backed `GtkDrawingArea` and repaints it on every frame.
- **Impact:** avoids stale or black `GtkPicture` paintable snapshots when a
  running GStreamer stream replaces its texture.
- **Ping:** Hummingbird media owner.
- **Refs:** `CGTK/shim.h`, `GTKMedia.swift`.

The sink chain uses a parsed `videoconvert`/RGBA/appsink bin and disables
appsink clock synchronization so frame pulls do not wait on a UI-thread clock.
The video bin is explicitly synchronized to PLAYING before `playbin3` starts.

## 2026-10-04 — Media — external subtitle routing

- **Shared surface:** `MediaPlayerDriver` and `MediaPlayer` expose an optional
  external subtitle URL without exposing platform media types.
- **Impact:** GTK forwards the URL to GStreamer `playbin3`'s `suburi` property;
  existing custom subtitle parsing remains available for styled overlays.
- **Ping:** Hummingbird media owner.
- **Refs:** `Compat/MediaPlayer.swift`, `GTKMedia.swift`.

## 2026-10-04 — Media — backend-neutral track and PiP capabilities

- **Shared surface:** `MediaPlayerDriver` and `MediaPlayer` now expose
  selectable `MediaTrack` values plus picture-in-picture capability/actions.
  Apple platforms include an `AVMediaPlayerDriver` adapter that maps AVFoundation
  audible, visual, and legible media-selection groups and AVKit PiP.
- **Impact:** applications can build one custom player surface without importing
  AVFoundation or AVKit. GTK retains safe no-op capability defaults until its
  direct GStreamer backend supplies stream selection and desktop PiP.
- **Ping:** Hummingbird media owner.
- **Refs:** `Compat/MediaPlayer.swift`, `Compat/AVMediaPlayerDriver.swift`.

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
