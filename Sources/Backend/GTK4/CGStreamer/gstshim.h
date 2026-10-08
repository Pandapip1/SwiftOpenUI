#ifndef SWIFT_OPENUI_GSTSHIM_H
#define SWIFT_OPENUI_GSTSHIM_H

#include <gst/app/gstappsink.h>
#include <gst/gst.h>

typedef void (*SwiftOpenUIGStreamerFrameCallback)(gpointer data);

typedef struct {
    GstElement *playbin;
    GstElement *video_bin;
    GstElement *normal_appsink;
    GObject *normal_paintable;
    GObject *split_paintable;
    GObject *active_paintable;
    GstPad *paintable_sink_pad;
    gulong segment_probe;
    guint32 seek_seqnum;
    gint segment_seqnum;
    gboolean prefer_paintable;
    GstElement *split_pipeline;
    GstElement *pipeline;
    GstElement *appsink;
    GstSample *pending_sample;
    SwiftOpenUIGStreamerFrameCallback frame_callback;
    gpointer frame_callback_data;
    guint frame_source;
    guint bus_source;
    SwiftOpenUIGStreamerFrameCallback event_callback;
    gpointer event_callback_data;
    gchar *error_message;
    gboolean ended;
    gboolean failed;
    gboolean audio_sink_available;
    gboolean is_live;
    gint buffering_percent;
    GstState target_state;
    gulong sample_handler;
    GMutex frame_source_mutex;
    GHashTable *video_headers;
    GHashTable *audio_headers;
    GstStreamCollection *stream_collection;
    gint selected_track_indices[3];
    gint requested_track_indices[3];
    guint64 stream_collection_generation;
    // Integration tests can force the parser failure path without changing
    // the process-wide GStreamer registry.
    const gchar *test_audio_sink_description;
} SwiftOpenUIGStreamerPlayer;

static inline void swift_openui_gst_player_apply_pending_track_selection(SwiftOpenUIGStreamerPlayer *player);

static inline void swift_openui_gst_player_watch_bus(SwiftOpenUIGStreamerPlayer *player);

static inline GstFlowReturn swift_openui_gst_player_new_sample(GstAppSink *sink, gpointer data);

static inline gboolean swift_openui_gst_uses_fake_audio(void) {
    return g_strcmp0(g_getenv("SWIFT_OPENUI_GST_FAKE_AUDIO"), "1") == 0;
}

// Prefer Pulse when its plugin is present. PipeWire exposes the Pulse protocol,
// and constructing this sink directly avoids autoaudiosink's timing-dependent
// probe/fakesink fallback during application startup. Keep autoaudiosink for
// systems whose GStreamer installation has no Pulse plugin.
static inline const gchar *swift_openui_gst_audio_sink_description(void) {
    if (swift_openui_gst_uses_fake_audio()) return "fakesink sync=true";
    GstElementFactory *pulse = gst_element_factory_find("pulsesink");
    if (pulse) {
        gst_object_unref(pulse);
        return "pulsesink sync=true client-name=SwiftOpenUI";
    }
    return "autoaudiosink sync=true";
}

static inline GstElement *swift_openui_gst_player_make_audio_sink(void) {
    const gchar *factory = "autoaudiosink";
    if (swift_openui_gst_uses_fake_audio()) factory = "fakesink";
    else {
        GstElementFactory *pulse = gst_element_factory_find("pulsesink");
        if (pulse) {
            factory = "pulsesink";
            gst_object_unref(pulse);
        }
    }
    GstElement *sink = gst_element_factory_make(factory, NULL);
    if (!sink) return NULL;
    g_object_set(sink, "sync", TRUE, NULL);
    if (g_strcmp0(factory, "pulsesink") == 0)
        g_object_set(sink, "client-name", "SwiftOpenUI", NULL);
    return sink;
}

static inline gboolean swift_openui_gst_message_is_missing_audio_output(GstMessage *message) {
    if (!message || GST_MESSAGE_TYPE(message) != GST_MESSAGE_WARNING
        || !GST_IS_ELEMENT(GST_MESSAGE_SRC(message))) return FALSE;
    GstElementFactory *factory = gst_element_get_factory(GST_ELEMENT(GST_MESSAGE_SRC(message)));
    return factory && g_strcmp0(gst_plugin_feature_get_name(GST_PLUGIN_FEATURE(factory)),
                                "autoaudiosink") == 0;
}

static inline void swift_openui_gst_player_fail(SwiftOpenUIGStreamerPlayer *player,
                                                const gchar *message) {
    if (!player) return;
    g_free(player->error_message);
    player->error_message = g_strdup(message);
    player->failed = TRUE;
    if (player->event_callback) player->event_callback(player->event_callback_data);
}

static inline void swift_openui_gst_apply_headers(GstElement *source, GHashTable *headers) {
    if (!source || !headers || g_hash_table_size(headers) == 0 ||
        !g_object_class_find_property(G_OBJECT_GET_CLASS(source), "extra-headers")) return;
    GstStructure *structure = gst_structure_new_empty("headers");
    GHashTableIter iterator;
    gpointer key, value;
    g_hash_table_iter_init(&iterator, headers);
    while (g_hash_table_iter_next(&iterator, &key, &value))
        gst_structure_set(structure, (const gchar *)key, G_TYPE_STRING, (const gchar *)value, NULL);
    g_object_set(source, "extra-headers", structure, NULL);
    gst_structure_free(structure);
}

static inline void swift_openui_gst_video_source_setup(GstElement *element, GstElement *source,
                                                        gpointer data) {
    (void)element;
    swift_openui_gst_apply_headers(source, ((SwiftOpenUIGStreamerPlayer *)data)->video_headers);
}

static inline void swift_openui_gst_audio_source_setup(GstElement *element, GstElement *source,
                                                        gpointer data) {
    (void)element;
    swift_openui_gst_apply_headers(source, ((SwiftOpenUIGStreamerPlayer *)data)->audio_headers);
}

static inline void swift_openui_gst_player_connect_sink(SwiftOpenUIGStreamerPlayer *player,
                                                         GstElement *appsink) {
    player->appsink = appsink;
    g_object_set(appsink, "sync", TRUE, "max-buffers", 2, "drop", TRUE,
        "emit-signals", TRUE, "wait-on-eos", FALSE, NULL);
    player->sample_handler = g_signal_connect(appsink, "new-sample",
        G_CALLBACK(swift_openui_gst_player_new_sample), player);
}

static inline void swift_openui_gst_player_disconnect_sink(SwiftOpenUIGStreamerPlayer *player) {
    if (player->paintable_sink_pad) {
        gst_pad_remove_probe(player->paintable_sink_pad, player->segment_probe);
        gst_object_unref(player->paintable_sink_pad);
        player->paintable_sink_pad = NULL;
        player->segment_probe = 0;
    }
    player->seek_seqnum = GST_SEQNUM_INVALID;
    g_atomic_int_set(&player->segment_seqnum, GST_SEQNUM_INVALID);
    if (player->sample_handler != 0) {
        if (player->appsink) g_signal_handler_disconnect(player->appsink, player->sample_handler);
        else if (player->active_paintable) g_signal_handler_disconnect(player->active_paintable, player->sample_handler);
    }
    player->active_paintable = NULL;
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

static inline void swift_openui_gst_player_schedule_frame(SwiftOpenUIGStreamerPlayer *player) {
    g_mutex_lock(&player->frame_source_mutex);
    if (player->frame_callback && player->frame_source == 0)
        player->frame_source = g_idle_add(swift_openui_gst_player_dispatch_frame, player);
    g_mutex_unlock(&player->frame_source_mutex);
}

static inline GstFlowReturn swift_openui_gst_player_new_sample(GstAppSink *sink, gpointer data) {
    (void)sink;
    swift_openui_gst_player_schedule_frame(data);
    return GST_FLOW_OK;
}

static inline void swift_openui_gst_player_paintable_changed(GObject *paintable, gpointer data) {
    (void)paintable;
    // GTK's sink owns frame lifetime and texture presentation. Swift still
    // receives a coalesced notification to apply pending seeks/rate changes.
    swift_openui_gst_player_schedule_frame(data);
}

static inline GstPadProbeReturn swift_openui_gst_player_segment(GstPad *pad,
                                                                GstPadProbeInfo *info,
                                                                gpointer data) {
    (void)pad;
    SwiftOpenUIGStreamerPlayer *player = data;
    GstEvent *event = GST_PAD_PROBE_INFO_EVENT(info);
    if (GST_EVENT_TYPE(event) == GST_EVENT_SEGMENT)
        g_atomic_int_set(&player->segment_seqnum, gst_event_get_seqnum(event));
    return GST_PAD_PROBE_OK;
}

static inline void swift_openui_gst_player_connect_paintable(SwiftOpenUIGStreamerPlayer *player,
                                                               GObject *paintable,
                                                               GstElement *video_bin) {
    player->appsink = NULL;
    player->active_paintable = paintable;
    player->sample_handler = g_signal_connect(paintable, "invalidate-contents",
        G_CALLBACK(swift_openui_gst_player_paintable_changed), player);
    GstElement *sink = NULL;
    g_object_get(video_bin, "sink", &sink, NULL);
    player->paintable_sink_pad = gst_element_get_static_pad(sink, "sink");
    gst_object_unref(sink);
    player->segment_probe = gst_pad_add_probe(player->paintable_sink_pad,
        GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM, swift_openui_gst_player_segment, player, NULL);
}

static inline gboolean swift_openui_gst_player_native_seek_completed(SwiftOpenUIGStreamerPlayer *player) {
    if (!player || !player->active_paintable || player->seek_seqnum == GST_SEQNUM_INVALID
        || (guint32)g_atomic_int_get(&player->segment_seqnum) != player->seek_seqnum) return FALSE;
    // SEGMENT arrives before its first buffer. Wait for preroll as well, so
    // position queries no longer reflect the previous segment. Queued GTK
    // invalidations and old ASYNC_DONE messages alone cannot acknowledge a seek.
    return gst_element_get_state(player->pipeline, NULL, NULL, 0) == GST_STATE_CHANGE_SUCCESS;
}

// Follows gtk4paintablesink's upstream GL integration: glsinkbin negotiates
// uploads/color conversion on the GPU and shares the sink's GDK GL context.
// Do not insert videoconvert or force SystemMemory/RGBA before this bin.
// The caller must already have initialized GTK on its main thread.
static inline GstElement *swift_openui_gst_player_make_gl_sink(GObject **paintable_out) {
    *paintable_out = NULL;
    GstElement *sink = gst_element_factory_make("gtk4paintablesink", NULL);
    if (!sink) return NULL;
    gst_object_ref_sink(sink);
    GObject *paintable = NULL;
    GObject *context = NULL;
    g_object_get(sink, "paintable", &paintable, NULL);
    if (paintable && g_object_class_find_property(G_OBJECT_GET_CLASS(paintable), "gl-context"))
        g_object_get(paintable, "gl-context", &context, NULL);
    GstElement *bin = context ? gst_element_factory_make("glsinkbin", NULL) : NULL;
    if (context) g_object_unref(context);
    if (bin) {
        g_object_set(bin, "sink", sink, NULL);
        *paintable_out = paintable;
    } else if (paintable) g_object_unref(paintable);
    gst_object_unref(sink);
    return bin;
}

static inline gpointer swift_openui_gst_player_paintable(SwiftOpenUIGStreamerPlayer *player) {
    return player ? player->active_paintable : NULL;
}

static inline void swift_openui_gst_player_clear_pending_sample(SwiftOpenUIGStreamerPlayer *player) {
    if (player && player->pending_sample) {
        gst_sample_unref(player->pending_sample);
        player->pending_sample = NULL;
    }
}

static inline SwiftOpenUIGStreamerPlayer *swift_openui_gst_player_new_with_paintable(gboolean prefer_paintable) {
    static gsize initialized = 0;
    if (g_once_init_enter(&initialized)) {
        gst_init(NULL, NULL);
        g_once_init_leave(&initialized, 1);
    }
    SwiftOpenUIGStreamerPlayer *player = g_new0(SwiftOpenUIGStreamerPlayer, 1);
    for (gint kind = 0; kind < 3; kind++) player->selected_track_indices[kind] = -1;
    for (gint kind = 0; kind < 3; kind++) player->requested_track_indices[kind] = -2;
    player->video_headers = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);
    player->audio_headers = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);
    g_mutex_init(&player->frame_source_mutex);
    player->prefer_paintable = prefer_paintable;
    player->target_state = GST_STATE_NULL;
    player->buffering_percent = 100;
    player->playbin = gst_element_factory_make("playbin3", NULL);
    if (prefer_paintable) player->video_bin = swift_openui_gst_player_make_gl_sink(&player->normal_paintable);
    if (!player->video_bin) player->video_bin = gst_parse_bin_from_description(
        "videoconvert ! video/x-raw,format=RGBA ! appsink name=swiftappsink",
        TRUE, NULL);
    if (player->playbin) gst_object_ref_sink(player->playbin);
    if (player->video_bin) gst_object_ref_sink(player->video_bin);
    player->normal_appsink = player->video_bin && !player->normal_paintable ? gst_bin_get_by_name(GST_BIN(player->video_bin), "swiftappsink") : NULL;
    if (!player->playbin || (!player->normal_appsink && !player->normal_paintable) || !player->video_bin) {
        if (player->playbin) gst_object_unref(player->playbin);
        if (player->normal_appsink) gst_object_unref(player->normal_appsink);
        if (player->normal_paintable) g_object_unref(player->normal_paintable);
        if (player->video_bin) gst_object_unref(player->video_bin);
        g_hash_table_unref(player->video_headers);
        g_hash_table_unref(player->audio_headers);
        g_mutex_clear(&player->frame_source_mutex);
        g_free(player);
        return NULL;
    }
    // Let the sink wait for the pipeline clock. Without synchronization the
    // polling loop drains decoded video as fast as the CPU can produce it,
    // racing several seconds ahead of clocked audio before stalling at EOS.
    player->pipeline = player->playbin;
    g_signal_connect(player->playbin, "source-setup", G_CALLBACK(swift_openui_gst_video_source_setup), player);
    if (player->normal_paintable) swift_openui_gst_player_connect_paintable(player, player->normal_paintable, player->video_bin);
    else swift_openui_gst_player_connect_sink(player, player->normal_appsink);
    g_object_set(player->playbin, "video-sink", player->video_bin, NULL);
    // Tests can opt into fakesink; ordinary playback is given a concrete
    // desktop sink instead of autoaudiosink's silent fake-sink fallback.
    GstElement *audio_sink = swift_openui_gst_player_make_audio_sink();
    player->audio_sink_available = audio_sink != NULL;
    if (audio_sink) {
        gst_object_ref_sink(audio_sink);
        g_object_set(player->playbin, "audio-sink", audio_sink, NULL);
        gst_object_unref(audio_sink);
    }
    // Keep progressively downloaded files on disk. Besides avoiding repeated
    // network reads, queue2 can seek within media served by simple HTTP origins
    // that do not implement byte-range requests.
    gint flags = 0;
    g_object_get(player->playbin, "flags", &flags, NULL);
    flags |= (1 << 7); // GST_PLAY_FLAG_DOWNLOAD
    g_object_set(player->playbin, "flags", flags, NULL);
    swift_openui_gst_player_watch_bus(player);
    return player;
}

// Display-independent users and tests explicitly retain the CPU fallback.
static inline SwiftOpenUIGStreamerPlayer *swift_openui_gst_player_new(void) {
    return swift_openui_gst_player_new_with_paintable(FALSE);
}

static inline void swift_openui_gst_player_free(SwiftOpenUIGStreamerPlayer *player) {
    if (!player) return;
    if (player->bus_source) g_source_remove(player->bus_source);
    g_free(player->error_message);
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
    if (player->stream_collection) gst_object_unref(player->stream_collection);
    if (player->normal_appsink) gst_object_unref(player->normal_appsink);
    if (player->normal_paintable) g_object_unref(player->normal_paintable);
    if (player->split_paintable) g_object_unref(player->split_paintable);
    gst_object_unref(player->video_bin);
    g_hash_table_unref(player->video_headers);
    g_hash_table_unref(player->audio_headers);
    g_mutex_clear(&player->frame_source_mutex);
    g_free(player);
}

static inline void swift_openui_gst_player_clear_headers(SwiftOpenUIGStreamerPlayer *player) {
    if (!player) return;
    g_hash_table_remove_all(player->video_headers);
    g_hash_table_remove_all(player->audio_headers);
}

static inline void swift_openui_gst_player_set_header(SwiftOpenUIGStreamerPlayer *player,
                                                       gboolean audio,
                                                       const char *name,
                                                       const char *value) {
    if (!player || !name || !value) return;
    g_hash_table_replace(audio ? player->audio_headers : player->video_headers,
                         g_strdup(name), g_strdup(value));
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

// Bus events must be delivered independently of video frames: an error can
// happen before preroll, and EOS arrives after the final new-sample signal.
static inline void swift_openui_gst_player_set_event_callback(
    SwiftOpenUIGStreamerPlayer *player, SwiftOpenUIGStreamerFrameCallback callback, gpointer data) {
    if (!player) return;
    player->event_callback = callback;
    player->event_callback_data = data;
}

static inline gchar *swift_openui_gst_player_take_error(SwiftOpenUIGStreamerPlayer *player) {
    if (!player) return NULL;
    gchar *message = player->error_message;
    player->error_message = NULL;
    return message;
}

static inline gboolean swift_openui_gst_player_has_ended(SwiftOpenUIGStreamerPlayer *player) {
    return player && player->ended;
}

static inline void swift_openui_gst_player_set_uri(SwiftOpenUIGStreamerPlayer *player, const char *uri) {
    if (player && player->playbin) {
        if (!player->audio_sink_available) {
            swift_openui_gst_player_fail(player,
                "Audio output is unavailable; playback cannot start");
            return;
        }
        swift_openui_gst_player_clear_pending_sample(player);
        g_object_set(player->playbin, "uri", uri, NULL);
    }
}

static inline void swift_openui_gst_player_set_uris(SwiftOpenUIGStreamerPlayer *player,
                                                     const char *video_uri,
                                                     const char *audio_uri) {
    if (!player || !video_uri) return;
    if (player->bus_source) { g_source_remove(player->bus_source); player->bus_source = 0; }
    g_clear_pointer(&player->error_message, g_free);
    player->ended = FALSE;
    player->failed = FALSE;
    player->is_live = FALSE;
    player->buffering_percent = 100;
    player->target_state = GST_STATE_NULL;
    if (player->stream_collection) {
        gst_object_unref(player->stream_collection);
        player->stream_collection = NULL;
    }
    for (gint kind = 0; kind < 3; kind++) player->selected_track_indices[kind] = -1;
    for (gint kind = 0; kind < 3; kind++) player->requested_track_indices[kind] = -2;
    if (!player->audio_sink_available) {
        swift_openui_gst_player_fail(player,
            "Audio output is unavailable; playback cannot start");
        return;
    }
    gst_element_set_state(player->pipeline, GST_STATE_NULL);
    swift_openui_gst_player_clear_pending_sample(player);
    swift_openui_gst_player_disconnect_sink(player);
    g_clear_object(&player->split_paintable);
    if (player->split_pipeline) {
        // A replacement may fail while parsing its new split A/V graph. Keep
        // pipeline pointing at the retained playbin before releasing the old
        // graph so stop/free never dereference the former split pipeline.
        player->pipeline = player->playbin;
        gst_object_unref(player->split_pipeline);
        player->split_pipeline = NULL;
    }
    if (!audio_uri) {
        player->pipeline = player->playbin;
        if (player->normal_paintable) swift_openui_gst_player_connect_paintable(player, player->normal_paintable, player->video_bin);
        else swift_openui_gst_player_connect_sink(player, player->normal_appsink);
        g_object_set(player->playbin, "uri", video_uri, NULL);
        swift_openui_gst_player_watch_bus(player);
        return;
    }

    gchar *video = g_strescape(video_uri, NULL);
    gchar *audio = g_strescape(audio_uri, NULL);
    // Headless integration tests opt into a fake sink so they never route
    // fixture audio to the user's sound server.
    const gchar *audio_sink = player->test_audio_sink_description
        ? player->test_audio_sink_description : swift_openui_gst_audio_sink_description();
    GstElement *native_video = player->prefer_paintable
        ? swift_openui_gst_player_make_gl_sink(&player->split_paintable) : NULL;
    const gchar *video_sink = native_video ? "queue name=video_queue" :
        "queue ! videoconvert ! video/x-raw,format=RGBA ! appsink name=swiftappsink";
    gchar *description = g_strdup_printf(
        "uridecodebin uri=\"%s\" name=video_source "
        "video_source. ! %s "
        "uridecodebin uri=\"%s\" name=audio_source "
        "audio_source. ! queue ! audioconvert ! audioresample ! %s",
        video, video_sink, audio, audio_sink);
    GError *error = NULL;
    player->split_pipeline = gst_parse_launch(description, &error);
    if (player->split_pipeline) gst_object_ref_sink(player->split_pipeline);
    g_free(description);
    g_free(video);
    g_free(audio);
    gchar *parse_error = error ? g_strdup(error->message) : NULL;
    if (error) g_error_free(error);
    // gst_parse_launch may return a partial bin alongside an error. A partial
    // split graph can still render video while silently dropping its audio
    // branch, so it is not a usable replacement.
    if (parse_error && player->split_pipeline) {
        gst_object_unref(player->split_pipeline);
        player->split_pipeline = NULL;
    }
    if (native_video) {
        gboolean linked = FALSE;
        if (player->split_pipeline) {
            GstElement *queue = gst_bin_get_by_name(GST_BIN(player->split_pipeline), "video_queue");
            if (gst_bin_add(GST_BIN(player->split_pipeline), native_video)) {
                linked = queue && gst_element_link(queue, native_video);
            } else gst_object_unref(native_video);
            if (queue) gst_object_unref(queue);
        } else gst_object_unref(native_video);
        if (!linked) {
            if (player->split_pipeline) gst_object_unref(player->split_pipeline);
            player->split_pipeline = NULL;
            g_clear_object(&player->split_paintable);
        }
    }
    GstElement *sink = player->split_pipeline
        ? gst_bin_get_by_name(GST_BIN(player->split_pipeline), "swiftappsink") : NULL;
    GstElement *video_source = player->split_pipeline
        ? gst_bin_get_by_name(GST_BIN(player->split_pipeline), "video_source") : NULL;
    GstElement *audio_source = player->split_pipeline
        ? gst_bin_get_by_name(GST_BIN(player->split_pipeline), "audio_source") : NULL;
    if (video_source) {
        g_signal_connect(video_source, "source-setup", G_CALLBACK(swift_openui_gst_video_source_setup), player);
        gst_object_unref(video_source);
    }
    if (audio_source) {
        g_signal_connect(audio_source, "source-setup", G_CALLBACK(swift_openui_gst_audio_source_setup), player);
        gst_object_unref(audio_source);
    }
    if (!player->split_pipeline || (!sink && !player->split_paintable)) {
        if (sink) gst_object_unref(sink);
        if (player->split_pipeline) {
            gst_object_unref(player->split_pipeline);
            player->split_pipeline = NULL;
        }
        gchar *message = g_strdup_printf(
            "Could not create the GStreamer audio playback pipeline%s%s",
            parse_error ? ": " : "", parse_error ? parse_error : "");
        g_free(parse_error);
        swift_openui_gst_player_fail(player, message);
        g_free(message);
        return;
    }
    g_free(parse_error);
    player->pipeline = player->split_pipeline;
    if (player->split_paintable) swift_openui_gst_player_connect_paintable(player, player->split_paintable, native_video);
    else swift_openui_gst_player_connect_sink(player, sink);
    if (sink) gst_object_unref(sink);
    swift_openui_gst_player_watch_bus(player);
}

static inline void swift_openui_gst_player_set_subtitle_uri(SwiftOpenUIGStreamerPlayer *player, const char *uri) {
    if (player && player->playbin) g_object_set(player->playbin, "suburi", uri, NULL);
}

static inline void swift_openui_gst_player_change_state(SwiftOpenUIGStreamerPlayer *player,
                                                           GstState state) {
    GstStateChangeReturn result = gst_element_set_state(player->pipeline, state);
    if (result == GST_STATE_CHANGE_NO_PREROLL) {
        player->is_live = TRUE;
        // Live sources must keep running; pausing cannot fill a live buffer.
        if (state == GST_STATE_PAUSED && player->target_state == GST_STATE_PLAYING)
            gst_element_set_state(player->pipeline, GST_STATE_PLAYING);
    }
}

static inline void swift_openui_gst_player_play(SwiftOpenUIGStreamerPlayer *player) {
    if (!player) return;
    player->target_state = GST_STATE_PLAYING;
    swift_openui_gst_player_change_state(player,
        !player->is_live && player->buffering_percent < 100 ? GST_STATE_PAUSED : GST_STATE_PLAYING);
}

static inline void swift_openui_gst_player_pause(SwiftOpenUIGStreamerPlayer *player) {
    if (!player) return;
    player->target_state = GST_STATE_PAUSED;
    swift_openui_gst_player_change_state(player, GST_STATE_PAUSED);
}

static inline gint swift_openui_gst_player_buffering_percent(SwiftOpenUIGStreamerPlayer *player) {
    return player ? player->buffering_percent : 100;
}

static inline gboolean swift_openui_gst_player_set_rate(SwiftOpenUIGStreamerPlayer *player,
                                                         gdouble rate,
                                                         gint64 requested_position) {
    if (!player || rate <= 0) return FALSE;
    gint64 position = requested_position;
    if (position < 0 && !gst_element_query_position(player->pipeline, GST_FORMAT_TIME, &position)) {
        return FALSE;
    }
    player->ended = FALSE;
    swift_openui_gst_player_clear_pending_sample(player);
    GstEvent *event = gst_event_new_seek(rate, GST_FORMAT_TIME,
        GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_ACCURATE,
        GST_SEEK_TYPE_SET, position, GST_SEEK_TYPE_NONE, GST_CLOCK_TIME_NONE);
    guint32 previous = player->seek_seqnum;
    player->seek_seqnum = gst_event_get_seqnum(event);
    gboolean accepted = gst_element_send_event(player->pipeline, event);
    if (!accepted) player->seek_seqnum = previous;
    return accepted;
}

static inline void swift_openui_gst_player_stop(SwiftOpenUIGStreamerPlayer *player) {
    if (player) {
        player->target_state = GST_STATE_NULL;
        player->buffering_percent = 100;
        gst_element_set_state(player->pipeline, GST_STATE_NULL);
        swift_openui_gst_player_clear_pending_sample(player);
    }
}

static inline gboolean swift_openui_gst_player_seek(SwiftOpenUIGStreamerPlayer *player,
                                                     gint64 nanoseconds,
                                                     gdouble rate) {
    return swift_openui_gst_player_set_rate(player, rate, nanoseconds);
}

static inline gboolean swift_openui_gst_player_is_seekable(SwiftOpenUIGStreamerPlayer *player) {
    if (!player) return FALSE;
    GstQuery *query = gst_query_new_seeking(GST_FORMAT_TIME);
    gboolean seekable = FALSE;
    if (gst_element_query(player->pipeline, query)) {
        GstFormat format;
        gint64 start, end;
        gst_query_parse_seeking(query, &format, &seekable, &start, &end);
    }
    gst_query_unref(query);
    return seekable;
}

static inline gint64 swift_openui_gst_player_position(SwiftOpenUIGStreamerPlayer *player) {
    gint64 value = 0;
    return player && gst_element_query_position(player->pipeline, GST_FORMAT_TIME, &value) ? value : 0;
}

static inline gint64 swift_openui_gst_player_duration(SwiftOpenUIGStreamerPlayer *player) {
    gint64 value = 0;
    return player && gst_element_query_duration(player->pipeline, GST_FORMAT_TIME, &value) ? value : 0;
}

static inline GstStreamType swift_openui_gst_track_type(gint kind) {
    return kind == 0 ? GST_STREAM_TYPE_VIDEO : kind == 1 ? GST_STREAM_TYPE_AUDIO : GST_STREAM_TYPE_TEXT;
}

static inline gboolean swift_openui_gst_player_bus_message(GstBus *bus, GstMessage *message,
                                                            gpointer data) {
    (void)bus;
    SwiftOpenUIGStreamerPlayer *player = data;
    // Unlike gst_bus_pop_filtered, a single bus watch never discards errors,
    // EOS or state changes while looking for stream-selection messages.
    if (GST_MESSAGE_TYPE(message) == GST_MESSAGE_STREAM_COLLECTION) {
        GstStreamCollection *collection = NULL;
        gst_message_parse_stream_collection(message, &collection);
        if (collection) {
            if (player->stream_collection) gst_object_unref(player->stream_collection);
            player->stream_collection = collection;
            player->stream_collection_generation++;
        }
    } else if (GST_MESSAGE_TYPE(message) == GST_MESSAGE_STREAMS_SELECTED
               && player->stream_collection) {
        for (gint kind = 0; kind < 3; kind++) player->selected_track_indices[kind] = -1;
        guint selected_count = gst_message_streams_selected_get_size(message);
        for (guint selected_index = 0; selected_index < selected_count; selected_index++) {
            GstStream *selected = gst_message_streams_selected_get_stream(message, selected_index);
            if (!selected) continue;
            GstStreamType selected_type = gst_stream_get_stream_type(selected);
            const gchar *selected_id = gst_stream_get_stream_id(selected);
            for (gint kind = 0; kind < 3; kind++) {
                GstStreamType type = swift_openui_gst_track_type(kind);
                if (!(selected_type & type)) continue;
                gint match = 0;
                guint size = gst_stream_collection_get_size(player->stream_collection);
                for (guint i = 0; i < size; i++) {
                    GstStream *candidate = gst_stream_collection_get_stream(player->stream_collection, i);
                    if (!candidate || !(gst_stream_get_stream_type(candidate) & type)) continue;
                    if (g_strcmp0(gst_stream_get_stream_id(candidate), selected_id) == 0) {
                        player->selected_track_indices[kind] = match;
                        break;
                    }
                    match++;
                }
            }
        }
    }
    if (swift_openui_gst_message_is_missing_audio_output(message)) {
        GError *warning = NULL;
        gst_message_parse_warning(message, &warning, NULL);
        gchar *description = g_strdup_printf("Audio output is unavailable%s%s",
            warning ? ": " : "", warning ? warning->message : "");
        if (warning) g_error_free(warning);
        swift_openui_gst_player_fail(player, description);
        g_free(description);
    } else if (GST_MESSAGE_TYPE(message) == GST_MESSAGE_BUFFERING) {
        gint percent = 100;
        gst_message_parse_buffering(message, &percent);
        gboolean was_buffering = player->buffering_percent < 100;
        player->buffering_percent = percent;
        if (!player->is_live && !player->failed && !player->ended
            && player->target_state == GST_STATE_PLAYING) {
            // Pause the clock without clearing the sink/paintable. Otherwise
            // recovery tries to catch up against time spent waiting for data.
            if (percent < 100 && !was_buffering)
                swift_openui_gst_player_change_state(player, GST_STATE_PAUSED);
            else if (percent == 100 && was_buffering)
                swift_openui_gst_player_change_state(player, GST_STATE_PLAYING);
        }
    } else if (GST_MESSAGE_TYPE(message) == GST_MESSAGE_ERROR) {
        GError *error = NULL;
        gst_message_parse_error(message, &error, NULL);
        g_free(player->error_message);
        player->error_message = g_strdup(error ? error->message : "Media playback failed");
        if (error) g_error_free(error);
        player->failed = TRUE;
    } else if (GST_MESSAGE_TYPE(message) == GST_MESSAGE_EOS) {
        player->ended = TRUE;
    }
    swift_openui_gst_player_apply_pending_track_selection(player);
    if ((GST_MESSAGE_TYPE(message) == GST_MESSAGE_ERROR || GST_MESSAGE_TYPE(message) == GST_MESSAGE_EOS)
        && player->event_callback) player->event_callback(player->event_callback_data);
    return G_SOURCE_CONTINUE;
}

static inline void swift_openui_gst_player_watch_bus(SwiftOpenUIGStreamerPlayer *player) {
    if (player->bus_source) g_source_remove(player->bus_source);
    GstBus *bus = gst_element_get_bus(player->pipeline);
    player->bus_source = bus ? gst_bus_add_watch(bus, swift_openui_gst_player_bus_message, player) : 0;
    if (bus) gst_object_unref(bus);
}

static inline void swift_openui_gst_player_refresh_stream_collection(SwiftOpenUIGStreamerPlayer *player) {
    // The main-context bus watch owns collection updates. Getters must not pop
    // filtered messages, which used to silently throw away errors and EOS.
    swift_openui_gst_player_apply_pending_track_selection(player);
}

static inline guint64 swift_openui_gst_player_stream_collection_generation(
    SwiftOpenUIGStreamerPlayer *player) {
    swift_openui_gst_player_refresh_stream_collection(player);
    return player ? player->stream_collection_generation : 0;
}

static inline gint swift_openui_gst_player_track_count(SwiftOpenUIGStreamerPlayer *player,
                                                        gint kind) {
    if (!player || player->pipeline != player->playbin) return 0;
    swift_openui_gst_player_refresh_stream_collection(player);
    if (!player->stream_collection) return 0;
    gint count = 0;
    GstStreamType type = swift_openui_gst_track_type(kind);
    guint size = gst_stream_collection_get_size(player->stream_collection);
    for (guint i = 0; i < size; i++) {
        GstStream *stream = gst_stream_collection_get_stream(player->stream_collection, i);
        if (stream && (gst_stream_get_stream_type(stream) & type)) count++;
    }
    return count;
}

static inline GstStream *swift_openui_gst_player_track(SwiftOpenUIGStreamerPlayer *player,
                                                        gint kind, gint index) {
    if (!player || !player->stream_collection || index < 0) return NULL;
    GstStreamType type = swift_openui_gst_track_type(kind);
    guint size = gst_stream_collection_get_size(player->stream_collection);
    gint match = 0;
    for (guint i = 0; i < size; i++) {
        GstStream *stream = gst_stream_collection_get_stream(player->stream_collection, i);
        if (stream && (gst_stream_get_stream_type(stream) & type)) {
            if (match == index) return stream;
            match++;
        }
    }
    return NULL;
}

static inline gchar *swift_openui_gst_player_track_label(SwiftOpenUIGStreamerPlayer *player,
                                                          gint kind, gint index) {
    swift_openui_gst_player_refresh_stream_collection(player);
    GstStream *stream = swift_openui_gst_player_track(player, kind, index);
    if (!stream) return NULL;
    GstTagList *tags = gst_stream_get_tags(stream);
    if (!tags) return NULL;
    gchar *title = NULL;
    gchar *language = NULL;
    gst_tag_list_get_string(tags, GST_TAG_TITLE, &title);
    gst_tag_list_get_string(tags, GST_TAG_LANGUAGE_CODE, &language);
    gchar *result = title ? g_strdup(title) : language ? g_strdup(language) : NULL;
    g_free(title);
    g_free(language);
    gst_tag_list_unref(tags);
    return result;
}

static inline void swift_openui_gst_player_apply_pending_track_selection(
    SwiftOpenUIGStreamerPlayer *player) {
    if (!player || !player->stream_collection) return;
    gboolean has_request = FALSE;
    for (gint kind = 0; kind < 3; kind++) {
        if (player->requested_track_indices[kind] != -2) has_request = TRUE;
    }
    if (!has_request) return;
    for (gint kind = 0; kind < 2; kind++) {
        if (player->selected_track_indices[kind] < 0
            && swift_openui_gst_player_track(player, kind, 0)) return;
    }
    GList *ids = NULL;
    for (gint candidate_kind = 0; candidate_kind < 3; candidate_kind++) {
        gint requested = player->requested_track_indices[candidate_kind];
        gint candidate_index = requested == -2
            ? player->selected_track_indices[candidate_kind] : requested;
        GstStream *stream = swift_openui_gst_player_track(player, candidate_kind, candidate_index);
        if (stream) ids = g_list_append(ids, g_strdup(gst_stream_get_stream_id(stream)));
    }
    if (ids && gst_element_send_event(player->pipeline, gst_event_new_select_streams(ids))) {
        for (gint kind = 0; kind < 3; kind++) {
            if (player->requested_track_indices[kind] != -2) {
                player->selected_track_indices[kind] = player->requested_track_indices[kind];
                player->requested_track_indices[kind] = -2;
            }
        }
    }
}

static inline void swift_openui_gst_player_select_track(SwiftOpenUIGStreamerPlayer *player,
                                                         gint kind, gint index) {
    if (!player || kind < 0 || kind > 2 || player->pipeline != player->playbin) return;
    player->requested_track_indices[kind] = index;
    swift_openui_gst_player_refresh_stream_collection(player);
}

static inline gboolean swift_openui_gst_player_is_playing(SwiftOpenUIGStreamerPlayer *player) {
    GstState state = GST_STATE_NULL;
    if (!player || player->ended || player->failed) return FALSE;
    // AVPlayer's requested playback rate remains nonzero while waiting for data.
    if (!player->is_live && player->buffering_percent < 100 && player->target_state == GST_STATE_PLAYING)
        return TRUE;
    return gst_element_get_state(player->pipeline, &state, NULL, 0) != GST_STATE_CHANGE_FAILURE
        && state == GST_STATE_PLAYING;
}

// Returns a newly allocated RGBA frame. The caller owns *data and must g_free it.
static inline gboolean swift_openui_gst_player_pull_frame(SwiftOpenUIGStreamerPlayer *player,
                                                            guint8 **data, gsize *length,
                                                            gint *width, gint *height, gint *stride) {
    if (!player || !player->appsink || !data || !length || !width || !height || !stride) return FALSE;
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
