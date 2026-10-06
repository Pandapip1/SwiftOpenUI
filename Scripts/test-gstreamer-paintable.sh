#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
"${CC:-cc}" -I "$root/Sources/Backend/GTK4/CGStreamer" \
    "$root/Tests/Integration/GStreamerPaintable.c" \
    $(pkg-config --cflags --libs gstreamer-app-1.0 gtk4 epoxy) -o "$work/paintable"
"$work/paintable" "${1:-native}"
