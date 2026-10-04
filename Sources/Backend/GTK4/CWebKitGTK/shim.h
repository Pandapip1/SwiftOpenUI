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

static inline GtkWidget *swift_openui_webkit_new(gboolean persistent) {
    if (persistent)
        return webkit_web_view_new();
    WebKitNetworkSession *session = webkit_network_session_new_ephemeral();
    GtkWidget *view = GTK_WIDGET(g_object_new(WEBKIT_TYPE_WEB_VIEW, "network-session", session, NULL));
    g_object_unref(session);
    return view;
}

static inline void swift_openui_webkit_add_user_script(
    WebKitWebView *view, const char *source,
    WebKitUserScriptInjectionTime time, gboolean main_frame_only
) {
    WebKitUserScript *script = webkit_user_script_new(
        source,
        main_frame_only ? WEBKIT_USER_CONTENT_INJECT_TOP_FRAME : WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
        time, NULL, NULL
    );
    webkit_user_content_manager_add_script(webkit_web_view_get_user_content_manager(view), script);
    webkit_user_script_unref(script);
}

typedef void (*SwiftOpenUIWebKitJavaScriptResult)(const char *, const char *, void *);
static inline void swift_openui_webkit_evaluate_finished(GObject *object, GAsyncResult *result, gpointer data) {
    gpointer *items = data;
    GError *error = NULL;
    JSCValue *value = webkit_web_view_call_async_javascript_function_finish(WEBKIT_WEB_VIEW(object), result, &error);
    char *json = value ? jsc_value_to_json(value, 0) : NULL;
    ((SwiftOpenUIWebKitJavaScriptResult)items[0])(json, error ? error->message : NULL, items[1]);
    g_free(json);
    if (value) g_object_unref(value);
    if (error) g_error_free(error);
    g_free(items);
}

static inline void swift_openui_webkit_evaluate(
    WebKitWebView *view, const char *source, SwiftOpenUIWebKitJavaScriptResult callback, void *context
) {
    gpointer *items = g_new(gpointer, 2); items[0] = (gpointer)callback; items[1] = context;
    char *body = g_strdup_printf("return await (%s);", source);
    webkit_web_view_call_async_javascript_function(view, body, -1, NULL, NULL, NULL, NULL,
                                                    swift_openui_webkit_evaluate_finished, items);
    g_free(body);
}

typedef void (*SwiftOpenUIWebKitCookieResult)(const char *, const char *, const char *, gboolean, void *);
static inline void swift_openui_webkit_cookies_finished(GObject *object, GAsyncResult *result, gpointer data) {
    gpointer *items = data;
    GError *error = NULL;
    GList *cookies = webkit_cookie_manager_get_all_cookies_finish(WEBKIT_COOKIE_MANAGER(object), result, &error);
    for (GList *item = cookies; item; item = item->next) {
        SoupCookie *cookie = item->data;
        ((SwiftOpenUIWebKitCookieResult)items[0])(
            soup_cookie_get_name(cookie), soup_cookie_get_value(cookie), soup_cookie_get_domain(cookie), FALSE, items[1]);
    }
    ((SwiftOpenUIWebKitCookieResult)items[0])(NULL, NULL, NULL, TRUE, items[1]);
    g_list_free_full(cookies, (GDestroyNotify)soup_cookie_free);
    if (error) g_error_free(error);
    g_free(items);
}

static inline void swift_openui_webkit_get_cookies(
    WebKitWebView *view, SwiftOpenUIWebKitCookieResult callback, void *context
) {
    gpointer *items = g_new(gpointer, 2); items[0] = (gpointer)callback; items[1] = context;
    WebKitCookieManager *manager = webkit_network_session_get_cookie_manager(webkit_web_view_get_network_session(view));
    webkit_cookie_manager_get_all_cookies(manager, NULL, swift_openui_webkit_cookies_finished, items);
}
