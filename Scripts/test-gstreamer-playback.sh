#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
"${CC:-cc}" -I "$root/Sources/Backend/GTK4/CGStreamer" \
    "$root/Tests/Integration/GStreamerPlayback.c" \
    $(pkg-config --cflags --libs gstreamer-app-1.0) -o "$work/playback"
"$work/playback"
