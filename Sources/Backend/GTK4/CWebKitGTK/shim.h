#pragma once
#include <webkit/webkit.h>

typedef void (*SwiftOpenUIWebKitLoadChanged)(WebKitWebView *, WebKitLoadEvent, void *);
typedef void (*SwiftOpenUIWebKitPropertyChanged)(WebKitWebView *, GParamSpec *, void *);

static inline gulong swift_openui_webkit_on_load_changed(
    WebKitWebView *view, SwiftOpenUIWebKitLoadChanged callback, void *context
) {
    return g_signal_connect(view, "load-changed", G_CALLBACK(callback), context);
}

static inline gulong swift_openui_webkit_on_title_changed(
    WebKitWebView *view, SwiftOpenUIWebKitPropertyChanged callback, void *context
) {
    return g_signal_connect(view, "notify::title", G_CALLBACK(callback), context);
}

static inline gulong swift_openui_webkit_on_progress_changed(
    WebKitWebView *view, SwiftOpenUIWebKitPropertyChanged callback, void *context
) {
    return g_signal_connect(view, "notify::estimated-load-progress", G_CALLBACK(callback), context);
}
