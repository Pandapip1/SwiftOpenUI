// Run through Scripts/test-gstreamer-paintable.sh on an isolated GTK display.
#include <gtk/gtk.h>
#include <epoxy/gl.h>
#include "gstshim.h"

typedef struct { guint frames, ends; SwiftOpenUIGStreamerPlayer *player; gboolean seek_acknowledged; } Probe;
static void frame(gpointer data) {
    Probe *probe = data;
    probe->frames++;
    if (swift_openui_gst_player_native_seek_completed(probe->player)) probe->seek_acknowledged = TRUE;
}
static void event(gpointer data) { ((Probe *)data)->ends++; }
static GstPadProbeReturn hold_buffer(GstPad *pad, GstPadProbeInfo *info, gpointer data) {
    (void)pad; (void)info; (void)data;
    return GST_PAD_PROBE_OK; // BLOCK probe holds the first post-seek buffer until removed.
}

int main(int argc, char **argv) {
    g_assert_cmpint(argc, ==, 2);
    gboolean expect_native = g_strcmp0(argv[1], "native") == 0;
    gtk_init();
    SwiftOpenUIGStreamerPlayer *p = swift_openui_gst_player_new_with_paintable(TRUE);
    g_assert_nonnull(p);
    g_assert_cmpint(swift_openui_gst_player_paintable(p) != NULL, ==, expect_native);
    g_assert_cmpint(p->appsink == NULL, ==, expect_native);
    if (!expect_native) {
        swift_openui_gst_player_free(p);
        g_print("unavailable GTK GL sink: selected appsink fallback\n");
        return 0;
    }
    g_assert_null(p->normal_appsink);
    GdkGLContext *context = NULL;
    g_object_get(p->active_paintable, "gl-context", &context, NULL);
    g_assert_nonnull(context);
    GdkGLContext *previous = gdk_gl_context_get_current();
    if (previous) g_object_ref(previous);
    gdk_gl_context_make_current(context);
    g_print("GTK sink GL renderer: %s\n", glGetString(GL_RENDERER));
    if (previous) { gdk_gl_context_make_current(previous); g_object_unref(previous); }
    else gdk_gl_context_clear_current();
    g_object_unref(context);
    guint8 *pixels = NULL; gsize length = 0; gint width = 0, height = 0, stride = 0;
    g_assert_false(swift_openui_gst_player_pull_frame(p, &pixels, &length, &width, &height, &stride));
    g_assert_null(pixels);
    g_assert_cmpstr(gst_plugin_feature_get_name(GST_PLUGIN_FEATURE(
        gst_element_get_factory(p->video_bin))), ==, "glsinkbin");
    GtkWidget *picture = gtk_picture_new_for_paintable(GDK_PAINTABLE(p->active_paintable));
    GtkWidget *window = gtk_window_new();
    gtk_window_set_child(GTK_WINDOW(window), picture);
    gtk_window_present(GTK_WINDOW(window));
    g_print("GTK renderer: %s\n", G_OBJECT_TYPE_NAME(gtk_native_get_renderer(GTK_NATIVE(window))));

    // Exercise the real sink with YUV input. The sink, not a CPU videoconvert
    // upstream, must negotiate GL upload/color conversion and own the texture.
    GError *parse_error = NULL;
    GstElement *source = gst_parse_bin_from_description(
        "videotestsrc pattern=white num-buffers=24 ! capsfilter "
        "caps=\"video/x-raw,format=I420,width=320,height=180,framerate=24/1\"", TRUE, &parse_error);
    g_assert_no_error(parse_error);
    p->split_pipeline = gst_pipeline_new(NULL);
    gst_object_ref_sink(p->split_pipeline);
    p->pipeline = p->split_pipeline;
    gst_bin_add_many(GST_BIN(p->pipeline), source, p->video_bin, NULL);
    g_assert_true(gst_element_link(source, p->video_bin));
    swift_openui_gst_player_watch_bus(p);
    Probe probe = { .player = p };
    swift_openui_gst_player_set_frame_callback(p, frame, &probe);
    swift_openui_gst_player_set_event_callback(p, event, &probe);
    // Allow first-use GL shader/context setup to preroll before timing playback.
    swift_openui_gst_player_pause(p);
    gint64 preroll = g_get_monotonic_time() + G_USEC_PER_SEC;
    while (g_get_monotonic_time() < preroll) {
        while (g_main_context_iteration(NULL, FALSE));
        g_usleep(1000);
    }
    // Queue a paintable notification from the old segment, then flush-seek
    // while preventing the replacement frame from completing sink preroll.
    gulong hold = gst_pad_add_probe(p->paintable_sink_pad,
        GST_PAD_PROBE_TYPE_BLOCK | GST_PAD_PROBE_TYPE_BUFFER, hold_buffer, NULL, NULL);
    guint before_seek = probe.frames;
    g_signal_emit_by_name(p->active_paintable, "invalidate-contents");
    g_assert_true(swift_openui_gst_player_seek(p, GST_SECOND / 2, 1.0));
    gint64 seek_deadline = g_get_monotonic_time() + 100000;
    while (g_get_monotonic_time() < seek_deadline) {
        while (g_main_context_iteration(NULL, FALSE));
        g_usleep(1000);
    }
    g_assert_cmpuint(probe.frames, >, before_seek);
    g_assert_false(probe.seek_acknowledged);
    g_assert_false(swift_openui_gst_player_native_seek_completed(p));
    gst_pad_remove_probe(p->paintable_sink_pad, hold);
    seek_deadline = g_get_monotonic_time() + G_USEC_PER_SEC;
    while (!swift_openui_gst_player_native_seek_completed(p) && g_get_monotonic_time() < seek_deadline) {
        while (g_main_context_iteration(NULL, FALSE));
        g_usleep(1000);
    }
    g_assert_true(swift_openui_gst_player_native_seek_completed(p));
    g_assert_cmpint(swift_openui_gst_player_position(p), >=, GST_SECOND / 2);
    g_print("native seek: queued pre-seek invalidation ignored until matching segment prerolls\n");
    swift_openui_gst_player_play(p);
    gint64 deadline = g_get_monotonic_time() + 5 * G_USEC_PER_SEC;
    while (!probe.ends && g_get_monotonic_time() < deadline) {
        while (g_main_context_iteration(NULL, FALSE));
        g_usleep(1000);
    }
    g_assert_false(p->failed);
    g_assert_true(p->ended);
    // Notifications are deliberately coalesced and need not match buffer count.
    g_assert_cmpuint(probe.frames, >, 0);
    g_assert_true(gtk_picture_get_paintable(GTK_PICTURE(picture)) == GDK_PAINTABLE(p->active_paintable));
    g_assert_cmpint(gdk_paintable_get_intrinsic_width(GDK_PAINTABLE(p->active_paintable)), ==, 320);
    GstElement *sink = NULL;
    g_object_get(p->video_bin, "sink", &sink, NULL);
    g_assert_nonnull(sink);
    GstPad *pad = gst_element_get_static_pad(sink, "sink");
    GstCaps *caps = gst_pad_get_current_caps(pad);
    g_assert_nonnull(caps);
    gchar *caps_text = gst_caps_to_string(caps); g_print("native negotiated caps: %s\n", caps_text); g_free(caps_text);
    GstCapsFeatures *features = gst_caps_get_features(caps, 0);
    gboolean gl_memory = gst_caps_features_contains(features, "memory:GLMemory");
    gboolean dma_buf = gst_caps_features_contains(features, "memory:DMABuf");
    g_assert_true(gl_memory || dma_buf);
    g_assert_cmpint(gdk_paintable_get_intrinsic_height(GDK_PAINTABLE(p->active_paintable)), ==, 180);
    GstPad *source_pad = gst_element_get_static_pad(source, "src");
    GstCaps *source_caps = gst_pad_get_current_caps(source_pad);
    g_assert_cmpstr(gst_structure_get_string(gst_caps_get_structure(source_caps, 0), "format"), ==, "I420");
    gst_caps_unref(source_caps); gst_object_unref(source_pad);
    g_print("native sink: %u frame notifications, %s input, direct persistent GTK paintable, EOS\n",
        probe.frames, gl_memory ? "GLMemory" : "DMA-BUF");
    // Read back only in the test to prove GTK actually presents the retained
    // white final frame. Production never downloads this texture to the CPU.
    GtkSnapshot *snapshot = gtk_snapshot_new();
    gdk_paintable_snapshot(GDK_PAINTABLE(p->active_paintable), GDK_SNAPSHOT(snapshot), 320, 180);
    GskRenderNode *node = gtk_snapshot_free_to_node(snapshot);
    g_assert_nonnull(node);
    graphene_rect_t viewport = GRAPHENE_RECT_INIT(0, 0, 320, 180);
    GdkTexture *texture = gsk_renderer_render_texture(gtk_native_get_renderer(GTK_NATIVE(window)), node, &viewport);
    g_assert_nonnull(texture);
    guint8 *download = g_malloc(320 * 180 * 4);
    gdk_texture_download(texture, download, 320 * 4);
    guint8 *center = download + (90 * 320 + 160) * 4;
    g_assert_cmpint(center[0], >, 240);
    g_assert_cmpint(center[1], >, 240);
    g_assert_cmpint(center[2], >, 240);
    g_free(download); g_object_unref(texture); gsk_render_node_unref(node);
    gst_caps_unref(caps); gst_object_unref(pad); gst_object_unref(sink);
    swift_openui_gst_player_free(p);
    gtk_window_destroy(GTK_WINDOW(window));
    while (g_main_context_iteration(NULL, FALSE));
    return 0;
}
