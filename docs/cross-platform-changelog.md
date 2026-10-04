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

## 2026-10-04 — GTK4 — continuous Slider bindings

- **Shared surface:** GTK `Slider` now updates its binding continuously as the
  thumb moves, while model-driven value reconciliation is excluded from the
  control callback.
- **Impact:** interactive scrubbers cannot be overwritten during the former
  150 ms debounce window, and programmatic updates do not feed back as input.
- **Ping:** GTK4 integrators.
- **Refs:** `GTKRenderer.swift`, `GTK4DescriptorTree.swift`.

## 2026-10-04 — GTK4 — accurate media seeking

- **Shared surface:** GStreamer-backed `AVPlayer.seek(to:)` now requests an
  accurate timestamp instead of restricting seeks to keyframes.
- **Impact:** scrubbers and relative seek controls reach the requested playback
  time even when a source has sparse keyframes.
- **Ping:** GTK4 integrators.
- **Refs:** `gstshim.h`.

## 2026-10-04 — GTK4 — fullscreen control symbol mappings

- **Shared surface:** mapped the SF Symbols for entering and exiting fullscreen
  to the bundled Material fullscreen glyphs.
- **Impact:** non-Apple custom player controls render both fullscreen actions.
- **Ping:** GTK4 integrators.
- **Refs:** `SFSymbolCompatibility.swift`.

## 2026-10-04 — GTK4 — media-control symbol mappings

- **Shared surface:** mapped the SF Symbols used by custom video controls for
  ten-second seek, play, pause and picture-in-picture to bundled Material glyphs.
- **Impact:** all non-Apple renderers resolve these controls instead of showing
  the missing-symbol placeholder.
- **Ping:** GTK4 integrators.
- **Refs:** `SFSymbolCompatibility.swift`, `GTK4SymbolMappingTests.swift`.

## 2026-10-04 — GTK4 — backend playback duration

- **Shared surface:** the backend-only `_AVPlayerDriver` SPI now reports media
  duration, exposed to backend consumers through `_swiftOpenUIDuration`.
- **Impact:** GTK applications can build their own AVKit-style scrubber without
  adding application-specific public API to SwiftOpenUI.
- **Ping:** GTK4 media integrators.
- **Refs:** `MediaPlayer.swift`, `GTKMedia.swift`, `MediaPlayerTests.swift`.

## 2026-10-04 — GTK4 — navigation chrome in sheets

- **Shared surface:** sheets containing a `NavigationStack` now install its
  attached header bar on the transient GTK window.
- **Impact:** sheet titles and toolbar actions such as Close remain visible.
- **Layout:** expanding frames retain explicit minimum width and height requests,
  allowing content-sized sheets to honor form minimums.
- **Ping:** GTK4 integrators.
- **Refs:** `GTK4Backend.swift`, `GTKRenderer.swift`.

## 2026-10-04 — GTK4 — explicit aspect ratios in vertical layouts

- **Shared surface:** an explicit `.aspectRatio` no longer inherits vertical
  expansion from its content; its height is derived from the available width.
- **Impact:** video surfaces in scrolling detail pages scale to their intended
  ratio instead of being squeezed to the viewport remainder.
- **Ping:** GTK4 integrators.
- **Refs:** `GTKRenderer.swift`, `GTK4PlayerSizingTests.swift`.

## 2026-10-04 — GTK4 — full-width custom navigation labels

- **Shared surface:** GTK4 `NavigationLink` now propagates horizontal expansion
  from a custom label through its native button wrapper.
- **Impact:** full-width list rows keep their allocated width, so wrapped titles
  no longer collapse to a few characters.
- **Ping:** GTK4 integrators.
- **Refs:** `GTKNavigation.swift`, `GTK4NavigationTitleTests.swift`.

## 2026-10-04 — GTK4 — sample-driven video presentation

- **Shared surface:** GStreamer signals when a clock-eligible appsink sample is
  available and coalesces presentation onto GTK's main context.
- **Impact:** GTK invalidates the video surface only when a new stream frame is
  available. Low-frame-rate media no longer keeps a high-refresh-rate
  compositor callback active, while 60 fps media can still present at full
  rate without blocking GTK's event loop.
- **Ping:** GTK4 media integrators.
- **Refs:** `GTKMedia.swift`, `CGStreamer/gstshim.h`.

## 2026-10-04 — GTK4 — present video by pipeline running time

- **Shared surface:** the custom GStreamer video bin now inherits state and
  clock timing from `playbin3`; appsink frames are additionally held until
  their segment-adjusted PTS reaches the pipeline's running time. GtkPicture
  uploads now preserve GStreamer's RGBA channel layout.
- **Impact:** video advances with clocked audio instead of decoding to the end
  immediately, including during the startup transition before the pipeline
  clock becomes available. Pending frames are discarded across seeks/source
  changes, and the displayed texture matches the decoded buffer.
- **Ping:** GTK4 media integrators.
- **Refs:** `CGStreamer/gstshim.h`, `CGTK/shim.h`.

## 2026-10-04 — GTK4 — synchronize appsink video to the pipeline clock

- **Shared surface:** GTK4's GStreamer appsink now honors the pipeline clock
  when delivering decoded video frames.
- **Impact:** video no longer decodes several seconds ahead of clocked audio
  and stalls near the end; bounded buffering still drops genuinely late frames.
- **Ping:** GTK4 media integrators.
- **Refs:** `CGStreamer/gstshim.h`.

## 2026-10-04 — GTK4 — direct GStreamer media surface

- **Shared surface:** GTK4 playback now uses a `playbin3` pipeline with an
  `appsink` RGBA surface, replacing `GtkVideo` for embedded playback.
- **Impact:** GTK can decode through the configured GStreamer plugin set while
  SwiftUI owns the rendered surface. The Nix development and packaging inputs
  now include GStreamer development headers and linker libraries.
- **Ping:** GTK4 media integrators.
- **Refs:** `GTKMedia.swift`, `CGStreamer/gstshim.h`.

## 2026-10-04 — GTK4 — repaint video frames through DrawingArea

- **Shared surface:** the GTK media surface now copies decoded RGBA frames into
  a Cairo-backed `GtkDrawingArea` and repaints it on every frame.
- **Impact:** avoids stale or black `GtkPicture` paintable snapshots when a
  running GStreamer stream replaces its texture.
- **Ping:** GTK4 media integrators.
- **Refs:** `CGTK/shim.h`, `GTKMedia.swift`.

The sink chain uses a parsed `videoconvert`/RGBA/appsink bin and disables
appsink clock synchronization so frame pulls do not wait on a UI-thread clock.
The video bin is explicitly synchronized to PLAYING before `playbin3` starts.

## 2026-10-04 — Media — external subtitle routing

- **Shared surface:** `MediaPlayerDriver` and `MediaPlayer` expose an optional
  external subtitle URL without exposing platform media types.
- **Impact:** GTK forwards the URL to GStreamer `playbin3`'s `suburi` property;
  existing custom subtitle parsing remains available for styled overlays.
- **Ping:** GTK4 media integrators.
- **Refs:** `Compat/MediaPlayer.swift`, `GTKMedia.swift`.

## 2026-10-04 — Media — backend-neutral track and PiP capabilities

- **Shared surface:** `MediaPlayerDriver` and `MediaPlayer` now expose
  selectable `MediaTrack` values plus picture-in-picture capability/actions.
  Apple platforms include an `AVMediaPlayerDriver` adapter that maps AVFoundation
  audible, visual, and legible media-selection groups and AVKit PiP.
- **Impact:** applications can build one custom player surface without importing
  AVFoundation or AVKit. GTK retains safe no-op capability defaults until its
  direct GStreamer backend supplies stream selection and desktop PiP.
- **Ping:** GTK4 media integrators.
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
- Ping: GTK4 maintainers.
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

## 2026-10-04 — GTK4 — Slider editing lifecycle

- **Shared surface:** `Slider` now includes SwiftUI's `onEditingChanged`
  initializer callback.
- **Impact:** GTK reports pointer press and release through a passive event
  controller while continuing to update the binding for every range change.
  The owning view host defers rebuilds for the life of that interaction, so
  state changes cannot replace the range and terminate its active drag.
- **Ping:** GTK4 integrators.
- **Refs:** `Slider.swift`, `GTKRenderer.swift`.
