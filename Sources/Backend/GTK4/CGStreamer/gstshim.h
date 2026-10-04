#ifndef SWIFT_OPENUI_GSTSHIM_H
#define SWIFT_OPENUI_GSTSHIM_H

#include <gst/app/gstappsink.h>
#include <gst/gst.h>

typedef void (*SwiftOpenUIGStreamerFrameCallback)(gpointer data);

typedef struct {
    GstElement *playbin;
    GstElement *video_bin;
    GstElement *normal_appsink;
    GstElement *split_pipeline;
    GstElement *pipeline;
    GstElement *appsink;
    GstSample *pending_sample;
    SwiftOpenUIGStreamerFrameCallback frame_callback;
    gpointer frame_callback_data;
    guint frame_source;
    gulong sample_handler;
    GMutex frame_source_mutex;
} SwiftOpenUIGStreamerPlayer;

static inline GstFlowReturn swift_openui_gst_player_new_sample(GstAppSink *sink, gpointer data);

static inline void swift_openui_gst_player_connect_sink(SwiftOpenUIGStreamerPlayer *player,
                                                         GstElement *appsink) {
    player->appsink = appsink;
    g_object_set(appsink, "sync", TRUE, "max-buffers", 2, "drop", TRUE,
        "emit-signals", TRUE, NULL);
    player->sample_handler = g_signal_connect(appsink, "new-sample",
        G_CALLBACK(swift_openui_gst_player_new_sample), player);
}

static inline void swift_openui_gst_player_disconnect_sink(SwiftOpenUIGStreamerPlayer *player) {
    if (player->sample_handler != 0 && player->appsink)
        g_signal_handler_disconnect(player->appsink, player->sample_handler);
    player->sample_handler = 0;
    player->appsink = NULL;
}

static inline gboolean swift_openui_gst_player_dispatch_frame(gpointer data) {
    SwiftOpenUIGStreamerPlayer *player = data;
    g_mutex_lock(&player->frame_source_mutex);
    player->frame_source = 0;
    SwiftOpenUIGStreamerFrameCallback callback = player->frame_callback;
    gpointer callback_data = player->frame_callback_data;
    g_mutex_unlock(&player->frame_source_mutex);
    if (callback) callback(callback_data);
    return G_SOURCE_REMOVE;
}

static inline GstFlowReturn swift_openui_gst_player_new_sample(GstAppSink *sink, gpointer data) {
    (void)sink;
    SwiftOpenUIGStreamerPlayer *player = data;
    g_mutex_lock(&player->frame_source_mutex);
    if (player->frame_callback && player->frame_source == 0)
        player->frame_source = g_idle_add(swift_openui_gst_player_dispatch_frame, player);
    g_mutex_unlock(&player->frame_source_mutex);
    return GST_FLOW_OK;
}

static inline void swift_openui_gst_player_clear_pending_sample(SwiftOpenUIGStreamerPlayer *player) {
    if (player && player->pending_sample) {
        gst_sample_unref(player->pending_sample);
        player->pending_sample = NULL;
    }
}

static inline SwiftOpenUIGStreamerPlayer *swift_openui_gst_player_new(void) {
    static gsize initialized = 0;
    if (g_once_init_enter(&initialized)) {
        gst_init(NULL, NULL);
        g_once_init_leave(&initialized, 1);
    }
    SwiftOpenUIGStreamerPlayer *player = g_new0(SwiftOpenUIGStreamerPlayer, 1);
    g_mutex_init(&player->frame_source_mutex);
    player->playbin = gst_element_factory_make("playbin3", NULL);
    player->video_bin = gst_parse_bin_from_description(
        "videoconvert ! video/x-raw,format=RGBA ! appsink name=swiftappsink",
        TRUE, NULL);
    player->normal_appsink = player->video_bin ? gst_bin_get_by_name(GST_BIN(player->video_bin), "swiftappsink") : NULL;
    if (!player->playbin || !player->normal_appsink || !player->video_bin) {
        if (player->playbin) gst_object_unref(player->playbin);
        if (player->normal_appsink) gst_object_unref(player->normal_appsink);
        if (player->video_bin) gst_object_unref(player->video_bin);
        g_mutex_clear(&player->frame_source_mutex);
        g_free(player);
        return NULL;
    }
    // Let the sink wait for the pipeline clock. Without synchronization the
    // polling loop drains decoded video as fast as the CPU can produce it,
    // racing several seconds ahead of clocked audio before stalling at EOS.
    player->pipeline = player->playbin;
    swift_openui_gst_player_connect_sink(player, player->normal_appsink);
    g_object_set(player->playbin, "video-sink", player->video_bin, NULL);
    return player;
}

static inline void swift_openui_gst_player_free(SwiftOpenUIGStreamerPlayer *player) {
    if (!player) return;
    g_mutex_lock(&player->frame_source_mutex);
    player->frame_callback = NULL;
    player->frame_callback_data = NULL;
    if (player->frame_source != 0) {
        g_source_remove(player->frame_source);
        player->frame_source = 0;
    }
    g_mutex_unlock(&player->frame_source_mutex);
    swift_openui_gst_player_disconnect_sink(player);
    gst_element_set_state(player->pipeline, GST_STATE_NULL);
    swift_openui_gst_player_clear_pending_sample(player);
    gst_object_unref(player->playbin);
    if (player->split_pipeline) gst_object_unref(player->split_pipeline);
    gst_object_unref(player->normal_appsink);
    g_mutex_clear(&player->frame_source_mutex);
    g_free(player);
}

static inline void swift_openui_gst_player_set_frame_callback(
    SwiftOpenUIGStreamerPlayer *player,
    SwiftOpenUIGStreamerFrameCallback callback,
    gpointer data) {
    if (!player) return;
    g_mutex_lock(&player->frame_source_mutex);
    player->frame_callback = callback;
    player->frame_callback_data = data;
    g_mutex_unlock(&player->frame_source_mutex);
}

static inline void swift_openui_gst_player_set_uri(SwiftOpenUIGStreamerPlayer *player, const char *uri) {
    if (player && player->playbin) {
        swift_openui_gst_player_clear_pending_sample(player);
        g_object_set(player->playbin, "uri", uri, NULL);
    }
}

static inline void swift_openui_gst_player_set_uris(SwiftOpenUIGStreamerPlayer *player,
                                                     const char *video_uri,
                                                     const char *audio_uri) {
    if (!player || !video_uri) return;
    gst_element_set_state(player->pipeline, GST_STATE_NULL);
    swift_openui_gst_player_clear_pending_sample(player);
    swift_openui_gst_player_disconnect_sink(player);
    if (player->split_pipeline) {
        gst_object_unref(player->split_pipeline);
        player->split_pipeline = NULL;
    }
    if (!audio_uri) {
        player->pipeline = player->playbin;
        swift_openui_gst_player_connect_sink(player, player->normal_appsink);
        g_object_set(player->playbin, "uri", video_uri, NULL);
        return;
    }

    gchar *video = g_strescape(video_uri, NULL);
    gchar *audio = g_strescape(audio_uri, NULL);
    // Headless integration tests opt into a fake sink so they never route
    // fixture audio to the user's sound server.
    const gchar *audio_sink = g_strcmp0(g_getenv("SWIFT_OPENUI_GST_FAKE_AUDIO"), "1") == 0
        ? "fakesink sync=true" : "autoaudiosink";
    gchar *description = g_strdup_printf(
        "uridecodebin uri=\"%s\" name=video_source "
        "video_source. ! queue ! videoconvert ! video/x-raw,format=RGBA ! "
        "appsink name=swiftappsink "
        "uridecodebin uri=\"%s\" name=audio_source "
        "audio_source. ! queue ! audioconvert ! audioresample ! %s",
        video, audio, audio_sink);
    GError *error = NULL;
    player->split_pipeline = gst_parse_launch(description, &error);
    g_free(description);
    g_free(video);
    g_free(audio);
    if (error) g_error_free(error);
    GstElement *sink = player->split_pipeline
        ? gst_bin_get_by_name(GST_BIN(player->split_pipeline), "swiftappsink") : NULL;
    if (!player->split_pipeline || !sink) {
        if (sink) gst_object_unref(sink);
        if (player->split_pipeline) {
            gst_object_unref(player->split_pipeline);
            player->split_pipeline = NULL;
        }
        player->pipeline = player->playbin;
        swift_openui_gst_player_connect_sink(player, player->normal_appsink);
        g_object_set(player->playbin, "uri", video_uri, NULL);
        return;
    }
    player->pipeline = player->split_pipeline;
    swift_openui_gst_player_connect_sink(player, sink);
    gst_object_unref(sink);
}

static inline void swift_openui_gst_player_set_subtitle_uri(SwiftOpenUIGStreamerPlayer *player, const char *uri) {
    if (player && player->playbin) g_object_set(player->playbin, "suburi", uri, NULL);
}

static inline void swift_openui_gst_player_play(SwiftOpenUIGStreamerPlayer *player) {
    if (player) gst_element_set_state(player->pipeline, GST_STATE_PLAYING);
}

static inline void swift_openui_gst_player_pause(SwiftOpenUIGStreamerPlayer *player) {
    if (player) gst_element_set_state(player->pipeline, GST_STATE_PAUSED);
}

static inline void swift_openui_gst_player_stop(SwiftOpenUIGStreamerPlayer *player) {
    if (player) {
        gst_element_set_state(player->pipeline, GST_STATE_NULL);
        swift_openui_gst_player_clear_pending_sample(player);
    }
}

static inline gboolean swift_openui_gst_player_seek(SwiftOpenUIGStreamerPlayer *player, gint64 nanoseconds) {
    if (!player) return FALSE;
    swift_openui_gst_player_clear_pending_sample(player);
    return gst_element_seek_simple(player->pipeline, GST_FORMAT_TIME,
        GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_ACCURATE, nanoseconds);
}

static inline gint64 swift_openui_gst_player_position(SwiftOpenUIGStreamerPlayer *player) {
    gint64 value = 0;
    return player && gst_element_query_position(player->pipeline, GST_FORMAT_TIME, &value) ? value : 0;
}

static inline gint64 swift_openui_gst_player_duration(SwiftOpenUIGStreamerPlayer *player) {
    gint64 value = 0;
    return player && gst_element_query_duration(player->pipeline, GST_FORMAT_TIME, &value) ? value : 0;
}

static inline gboolean swift_openui_gst_player_is_playing(SwiftOpenUIGStreamerPlayer *player) {
    GstState state = GST_STATE_NULL;
    return player && gst_element_get_state(player->pipeline, &state, NULL, 0) != GST_STATE_CHANGE_FAILURE && state == GST_STATE_PLAYING;
}

// Returns a newly allocated RGBA frame. The caller owns *data and must g_free it.
static inline gboolean swift_openui_gst_player_pull_frame(SwiftOpenUIGStreamerPlayer *player,
                                                            guint8 **data, gsize *length,
                                                            gint *width, gint *height, gint *stride) {
    if (!player || !data || !length || !width || !height || !stride) return FALSE;
    GstSample *sample = player->pending_sample;
    player->pending_sample = NULL;
    // This runs on GTK's main thread. Never wait here: blocking the UI loop
    // adds the timeout duration to every frame interval and produces uneven
    // playback even when GStreamer is decoding on time.
    if (!sample) sample = gst_app_sink_try_pull_sample(GST_APP_SINK(player->appsink), 0);
    if (!sample) return FALSE;
    GstCaps *caps = gst_sample_get_caps(sample);
    GstStructure *structure = caps ? gst_caps_get_structure(caps, 0) : NULL;
    gint w = 0, h = 0;
    if (!structure || !gst_structure_get_int(structure, "width", &w) || !gst_structure_get_int(structure, "height", &h)) {
        gst_sample_unref(sample);
        return FALSE;
    }
    GstBuffer *buffer = gst_sample_get_buffer(sample);
    GstClockTime pts = buffer ? GST_BUFFER_PTS(buffer) : GST_CLOCK_TIME_NONE;
    const GstSegment *segment = gst_sample_get_segment(sample);
    GstClockTime sample_running_time = segment && GST_CLOCK_TIME_IS_VALID(pts)
        ? gst_segment_to_running_time(segment, GST_FORMAT_TIME, pts)
        : GST_CLOCK_TIME_NONE;
    GstClock *clock = gst_element_get_clock(player->pipeline);
    GstClockTime pipeline_running_time = GST_CLOCK_TIME_NONE;
    if (clock) {
        GstClockTime now = gst_clock_get_time(clock);
        GstClockTime base = gst_element_get_base_time(player->pipeline);
        if (GST_CLOCK_TIME_IS_VALID(now) && GST_CLOCK_TIME_IS_VALID(base) && now >= base)
            pipeline_running_time = now - base;
        gst_object_unref(clock);
    }
    if (GST_CLOCK_TIME_IS_VALID(sample_running_time)) {
        gboolean clock_not_ready = !GST_CLOCK_TIME_IS_VALID(pipeline_running_time)
            && sample_running_time > 5 * GST_MSECOND;
        gboolean frame_is_early = GST_CLOCK_TIME_IS_VALID(pipeline_running_time)
            && sample_running_time > pipeline_running_time + 5 * GST_MSECOND;
        if (clock_not_ready || frame_is_early) {
            player->pending_sample = sample;
            return FALSE;
        }
    }
    GstMapInfo map;
    if (!buffer || !gst_buffer_map(buffer, &map, GST_MAP_READ)) {
        gst_sample_unref(sample);
        return FALSE;
    }
    guint8 *copy = g_malloc(map.size);
    memcpy(copy, map.data, map.size);
    gst_buffer_unmap(buffer, &map);
    gst_sample_unref(sample);
    *data = copy;
    *length = map.size;
    *width = w;
    *height = h;
    *stride = (gint)(map.size / (gsize)h);
    return TRUE;
}

static inline void swift_openui_gst_player_free_frame(guint8 *data) { g_free(data); }

#endif
