// Build with cc -I Sources/Backend/GTK4/CGStreamer this-file.c \
//   $(pkg-config --cflags --libs gstreamer-app-1.0) -o /tmp/gst-playback-test
// Runs entirely against generated video and a WAV filesink, with no audio device.
#include "gstshim.h"
#include <math.h>

typedef struct {
    SwiftOpenUIGStreamerPlayer *player;
    guint frames, events;
    gint audio_buffers;
    gint64 first_frame, last_frame;
    guint8 last_pixel;
} Probe;

static void frame(gpointer data) {
    Probe *probe = data;
    guint8 *bytes = NULL;
    gsize length;
    gint width, height, stride;
    if (swift_openui_gst_player_pull_frame(probe->player, &bytes, &length, &width, &height, &stride)) {
        g_assert_cmpint(width, ==, 64);
        g_assert_cmpint(height, ==, 36);
        g_assert_cmpuint(length, >=, (gsize)stride * height);
        if (!probe->frames) probe->first_frame = g_get_monotonic_time();
        probe->last_frame = g_get_monotonic_time();
        probe->frames++;
        probe->last_pixel = bytes[0];
        swift_openui_gst_player_free_frame(bytes);
    }
}

static void event(gpointer data) { ((Probe *)data)->events++; }
static GstPadProbeReturn audio_buffer(GstPad *pad, GstPadProbeInfo *info, gpointer data) {
    (void)pad; (void)info;
    g_atomic_int_inc(&((Probe *)data)->audio_buffers);
    return GST_PAD_PROBE_OK;
}

static void pump_until(Probe *probe, guint events, gint64 timeout) {
    gint64 deadline = g_get_monotonic_time() + timeout;
    while (probe->events < events && g_get_monotonic_time() < deadline) {
        while (g_main_context_iteration(NULL, FALSE));
        g_usleep(1000);
    }
    g_assert_cmpuint(probe->events, ==, events);
}

int main(void) {
    // No environment override or autoaudiosink is used: this test verifies
    // actual decoded audio buffers reaching a file, independently of devices.
    g_unsetenv("SWIFT_OPENUI_GST_FAKE_AUDIO");
    Probe probe = {0};
    probe.player = swift_openui_gst_player_new();
    g_assert_nonnull(probe.player);
    SwiftOpenUIGStreamerPlayer *p = probe.player;
    g_source_remove(p->bus_source); p->bus_source = 0;
    swift_openui_gst_player_disconnect_sink(p);
    // White video makes losing/clearing the final frame observable. A short
    // independently clocked audio branch must run through EOS too.
    GError *error = NULL;
    p->split_pipeline = gst_parse_launch(
        "videotestsrc pattern=white num-buffers=24 ! "
        "video/x-raw,format=RGBA,width=64,height=36,framerate=24/1 ! appsink name=video "
        "audiotestsrc num-buffers=48 samplesperbuffer=1000 ! "
        "audio/x-raw,rate=48000,format=S16LE ! identity name=audio ! wavenc ! "
        "filesink location=/dev/null sync=true", &error);
    g_assert_no_error(error);
    gst_object_ref_sink(p->split_pipeline);
    p->pipeline = p->split_pipeline;
    GstElement *sink = gst_bin_get_by_name(GST_BIN(p->pipeline), "video");
    swift_openui_gst_player_connect_sink(p, sink); gst_object_unref(sink);
    GstElement *audio = gst_bin_get_by_name(GST_BIN(p->pipeline), "audio");
    GstPad *pad = gst_element_get_static_pad(audio, "src");
    gst_pad_add_probe(pad, GST_PAD_PROBE_TYPE_BUFFER, audio_buffer, &probe, NULL);
    gst_object_unref(pad); gst_object_unref(audio);
    swift_openui_gst_player_watch_bus(p);
    swift_openui_gst_player_set_frame_callback(p, frame, &probe);
    swift_openui_gst_player_set_event_callback(p, event, &probe);
    swift_openui_gst_player_play(p);
    gint64 first_deadline = g_get_monotonic_time() + G_USEC_PER_SEC;
    while (probe.frames < 3 && g_get_monotonic_time() < first_deadline) {
        while (g_main_context_iteration(NULL, FALSE));
        g_usleep(1000);
    }
    g_assert_cmpuint(probe.frames, >=, 3);
    gst_element_post_message(p->pipeline, gst_message_new_buffering(GST_OBJECT(p->pipeline), 25));
    while (g_main_context_iteration(NULL, FALSE));
    g_assert_cmpint(swift_openui_gst_player_buffering_percent(p), ==, 25);
    g_assert_true(swift_openui_gst_player_is_playing(p));
    GstState state;
    gst_element_get_state(p->pipeline, &state, NULL, GST_SECOND);
    g_assert_cmpint(state, ==, GST_STATE_PAUSED);
    gint64 paused_position = swift_openui_gst_player_position(p);
    gint64 pause_deadline = g_get_monotonic_time() + 200000;
    while (g_get_monotonic_time() < pause_deadline) {
        while (g_main_context_iteration(NULL, FALSE));
        g_usleep(1000);
    }
    g_assert_cmpint(llabs(swift_openui_gst_player_position(p) - paused_position), <, 50 * GST_MSECOND);
    g_assert_cmpuint(probe.last_pixel, ==, 255);
    g_assert_cmpuint(probe.events, ==, 0);
    gst_element_post_message(p->pipeline, gst_message_new_buffering(GST_OBJECT(p->pipeline), 100));
    while (g_main_context_iteration(NULL, FALSE));
    gst_element_get_state(p->pipeline, &state, NULL, GST_SECOND);
    g_assert_cmpint(state, ==, GST_STATE_PLAYING);
    gst_element_post_message(p->pipeline, gst_message_new_buffering(GST_OBJECT(p->pipeline), 25));
    while (g_main_context_iteration(NULL, FALSE));
    // Buffer recovery must not override a pause the user requested meanwhile.
    swift_openui_gst_player_pause(p);
    gst_element_post_message(p->pipeline, gst_message_new_buffering(GST_OBJECT(p->pipeline), 100));
    while (g_main_context_iteration(NULL, FALSE));
    g_assert_false(swift_openui_gst_player_is_playing(p));
    gst_element_get_state(p->pipeline, &state, NULL, GST_SECOND);
    g_assert_cmpint(state, ==, GST_STATE_PAUSED);
    swift_openui_gst_player_play(p);
    pump_until(&probe, 1, 4 * G_USEC_PER_SEC);
    frame(&probe); // Present a coalesced final frame on EOS, just as GTK does.
    g_assert_true(swift_openui_gst_player_has_ended(p));
    g_assert_false(swift_openui_gst_player_is_playing(p));
    g_assert_cmpuint(probe.frames, >=, 22);
    g_assert_cmpint(probe.last_frame - probe.first_frame, >=, 850000);
    g_assert_cmpint(probe.last_frame - probe.first_frame, <, 1500000);
    g_assert_cmpint(g_atomic_int_get(&probe.audio_buffers), ==, 48);
    g_assert_cmpuint(probe.last_pixel, ==, 255);
    g_print("cadence: %u frames / %.3f s; audio: %d buffers; EOS: once; final frame: white; buffering: clock paused and user pause respected\n",
        probe.frames, (probe.last_frame - probe.first_frame) / 1e6, probe.audio_buffers);

    // Source errors before the first frame must reach the event callback,
    // including when a caller repeatedly asks about stream collections.
    swift_openui_gst_player_set_uris(p, "file:///swift-openui-no-such-media-file", NULL);
    swift_openui_gst_player_play(p);
    gint64 deadline = g_get_monotonic_time() + G_USEC_PER_SEC;
    while (!p->failed && g_get_monotonic_time() < deadline) {
        swift_openui_gst_player_stream_collection_generation(p);
        while (g_main_context_iteration(NULL, FALSE));
        g_usleep(1000);
    }
    g_assert_true(p->failed);
    g_assert_false(swift_openui_gst_player_is_playing(p));
    gchar *message = swift_openui_gst_player_take_error(p);
    g_assert_nonnull(message); g_free(message);
    g_assert_null(swift_openui_gst_player_take_error(p));
    g_assert_cmpuint(probe.events, >, 1);
    swift_openui_gst_player_free(p);
    g_print("pre-frame source error: delivered despite collection polling\n");

    p = swift_openui_gst_player_new();
    probe = (Probe){ .player = p };
    g_source_remove(p->bus_source); p->bus_source = 0;
    swift_openui_gst_player_disconnect_sink(p);
    p->split_pipeline = gst_parse_launch(
        "videotestsrc is-live=true pattern=white ! "
        "video/x-raw,format=RGBA,width=64,height=36,framerate=24/1 ! appsink name=video", NULL);
    gst_object_ref_sink(p->split_pipeline); p->pipeline = p->split_pipeline;
    sink = gst_bin_get_by_name(GST_BIN(p->pipeline), "video");
    swift_openui_gst_player_connect_sink(p, sink); gst_object_unref(sink);
    swift_openui_gst_player_watch_bus(p);
    swift_openui_gst_player_set_frame_callback(p, frame, &probe);
    swift_openui_gst_player_play(p);
    first_deadline = g_get_monotonic_time() + G_USEC_PER_SEC;
    while (probe.frames < 3 && g_get_monotonic_time() < first_deadline) {
        while (g_main_context_iteration(NULL, FALSE));
        g_usleep(1000);
    }
    gst_element_post_message(p->pipeline, gst_message_new_buffering(GST_OBJECT(p->pipeline), 25));
    while (g_main_context_iteration(NULL, FALSE));
    guint before_live = probe.frames;
    pause_deadline = g_get_monotonic_time() + 200000;
    while (g_get_monotonic_time() < pause_deadline) {
        while (g_main_context_iteration(NULL, FALSE));
        g_usleep(1000);
    }
    g_assert_true(p->is_live);
    g_assert_cmpuint(probe.frames, >, before_live);
    g_assert_true(swift_openui_gst_player_is_playing(p));
    swift_openui_gst_player_free(p);
    g_print("live buffering notification: playback continues\n");
    return 0;
}
