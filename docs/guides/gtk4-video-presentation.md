# GTK4 video presentation

The GTK driver prefers `gtk4paintablesink` wrapped by `glsinkbin` when the
plugin can create a GDK GL context. `GtkPicture` displays the sink's paintable
directly. `glsinkbin` negotiates upload and color conversion; the backend does
not force CPU RGBA, map video buffers, or allocate a second texture per frame
on this path. Software-decoded YUV still requires an upload. Hardware decoder
availability is independent of the presentation path.

The implementation follows the GStreamer GTK sink's
[upstream integration](https://gstreamer.freedesktop.org/documentation/gtk4/index.html)
and `video/gtk4/examples/gtksink.py` in gst-plugins-rs. The plugin owns texture
lifetime and synchronization between GStreamer and GTK. The driver listens to
paintable invalidation only to advance pending player operations; it does not
copy those frames back to Swift.

If the plugin or its GL context is unavailable, the existing synchronized
RGBA appsink path remains available. Both muxed/adaptive playback and split
video/audio compositions use the same capability selection. Changing items
rebinds the native paintable without replacing the player widget.

Hummingbird's Nix runtime includes gst-plugins-rs. Other hosts need the
`gtk4paintablesink` plugin built with their GTK window-system GL support and
GStreamer's `glsinkbin`. GTK renderer selection remains with GTK/the host;
`GSK_RENDERER=gl` is useful when verifying the GL texture path. Explicitly
selecting Cairo or software GL cannot demonstrate hardware acceleration.

## Network buffering

The bus watch handles non-live BUFFERING notifications by pausing the pipeline
clock and retaining the current frame until the buffer reaches 100%. Recovery
resumes only when playback is still requested; a user pause remains a pause.
Live sources continue playing. Errors and EOS are delivered independently of
frame arrival, so a network error cannot disappear behind a stalled video
callback or be mistaken for ordinary completion. This follows GStreamer's
[buffering protocol](https://gstreamer.freedesktop.org/documentation/application-development/advanced/buffering.html).

## Verification

Run on an isolated display, with an isolated writable `XDG_CACHE_HOME`.
`Scripts/test-gstreamer-playback.sh` checks the display-independent fallback's
clocked frames, audio buffers into a WAV filesink, EOS, and source errors.
`Scripts/test-gstreamer-paintable.sh native` requires the GTK plugin and a
working GL context. It feeds I420 video into the real sink, verifies negotiated
`memory:GLMemory` or `memory:DMABuf` caps, direct GTK paintable identity, and
retention of the rendered white frame through EOS. Only the test reads back
that final texture to verify its pixels.
Frame notifications may be coalesced; they are not a buffer counter.

Run `Scripts/test-gstreamer-paintable.sh fallback` in a fresh process with
`GDK_DISABLE=gl`, or with the GTK plugin absent from the plugin search path and
a fresh GStreamer registry. This verifies capability fallback without asking
an application to change its media source.

## Measured validation

Explicit software-GL validation uses Xvfb, `LIBGL_ALWAYS_SOFTWARE=1`,
`GSK_RENDERER=gl` and `GDK_DISABLE=dmabuf` to exercise GLMemory even on a host
that also exposes DMA-BUF. The sink reports llvmpipe, negotiates GLMemory, and
passes the rendered-frame and EOS checks. This is functional validation, not
a hardware performance result.

Hardware validation used an isolated headless Weston compositor on Asahi AGX
(Apple M1 Pro, Mesa 26.2.3), a separate PulseAudio null sink, and real 1920×1014
24 fps HLS playback in Hummingbird. GStreamer selected `v4l2slh264dec` and the
native sink received NV12 DMA-BUF with subtitle overlay metadata. No CPU frame
pull or RGBA texture copy runs in the Swift driver on this path.

Two 45-second runs used the same compositor, renderer, video and starting
position. Samples from seconds 10–45 measured:

| Presentation | Mean process CPU | Median process CPU | Video cadence |
| --- | ---: | ---: | --- |
| Existing RGBA appsink | 139.7% | 141% | about 11–13 fps; clock about 0.5× wall time |
| Native paintable/DMA-BUF | 15.4% | 15% | 24 fps; clock tracks wall time |

The legacy path spent approximately one full CPU core in a video queue thread
and another 30–36% in a second video queue thread. Removing the CPU conversion
and frame-copy route resolves that bottleneck on this machine. Decoder,
renderer and driver availability determine results on other machines.

The existing Hummingbird HTTP playback suite (headers, split audio/video,
muxed track discovery, rate changes, seeks, download fallback) also runs on
both the llvmpipe GLMemory and AGX native paths. No test routes audio to a user's
physical devices.
