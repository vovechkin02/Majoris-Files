#include <gst/gst.h>
#include <gst/pbutils/pbutils.h>
#include <gst/app/gstappsink.h>
#include <gst/video/video.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <json-glib/json-glib.h>
#include <stdio.h>

static void field(JsonBuilder *b, const char *key, const char *value) {
    if (!value || !*value) return;
    char *safe = g_utf8_make_valid(value, -1);
    if (strlen(safe) <= 16384) {
        json_builder_set_member_name(b, key);
        json_builder_add_string_value(b, safe);
    }
    g_free(safe);
}
static void number(JsonBuilder *b, const char *key, guint64 value) {
    char *text = g_strdup_printf("%" G_GUINT64_FORMAT, value);
    field(b, key, text); g_free(text);
}
static void tags(JsonBuilder *b, const GstTagList *list) {
    if (!list) return;
    const char *keys[] = {GST_TAG_TITLE, GST_TAG_ARTIST, GST_TAG_ALBUM, GST_TAG_COPYRIGHT, GST_TAG_COMMENT};
    const char *names[] = {"Title", "Artist", "Album", "Copyright", "Description"};
    for (guint i = 0; i < G_N_ELEMENTS(keys); i++) {
        char *text = NULL;
        if (gst_tag_list_get_string(list, keys[i], &text)) { field(b, names[i], text); g_free(text); }
    }
    guint track;
    if (gst_tag_list_get_uint(list, GST_TAG_TRACK_NUMBER, &track)) number(b, "Track", track);
    if (gst_tag_list_get_uint(list, GST_TAG_SHOW_SEASON_NUMBER, &track)) number(b, "Season", track);
    if (gst_tag_list_get_uint(list, GST_TAG_SHOW_EPISODE_NUMBER, &track)) number(b, "Episode", track);
    GstDateTime *date = NULL;
    if (gst_tag_list_get_date_time(list, GST_TAG_DATE_TIME, &date)) {
        char *text = gst_date_time_to_iso8601_string(date);
        field(b, "Date", text); g_free(text); gst_date_time_unref(date);
    }
    GstSample *sample = NULL;
    if (gst_tag_list_get_sample(list, GST_TAG_IMAGE, &sample) || gst_tag_list_get_sample(list, GST_TAG_PREVIEW_IMAGE, &sample)) {
        GstMapInfo mapped;
        GstBuffer *buffer = gst_sample_get_buffer(sample);
        if (buffer && gst_buffer_get_size(buffer) <= 8 * 1024 * 1024 && gst_buffer_map(buffer, &mapped, GST_MAP_READ)) {
            GdkPixbufLoader *loader = gdk_pixbuf_loader_new();
            if (gdk_pixbuf_loader_write(loader, mapped.data, mapped.size, NULL) && gdk_pixbuf_loader_close(loader, NULL)) {
                GdkPixbuf *image = gdk_pixbuf_loader_get_pixbuf(loader);
                if (image) {
                    double scale = MIN(1.0, 384.0 / MAX(gdk_pixbuf_get_width(image), gdk_pixbuf_get_height(image)));
                    GdkPixbuf *small = gdk_pixbuf_scale_simple(image, MAX(1, (int)(gdk_pixbuf_get_width(image) * scale)), MAX(1, (int)(gdk_pixbuf_get_height(image) * scale)), GDK_INTERP_BILINEAR);
                    char *png = NULL; gsize size = 0;
                    if (small && gdk_pixbuf_save_to_buffer(small, &png, &size, "png", NULL, NULL) && size <= 256 * 1024) {
                        char *encoded = g_base64_encode((guchar *)png, size);
                        json_builder_set_member_name(b, "Artwork PNG"); json_builder_add_string_value(b, encoded); g_free(encoded);
                    }
                    g_free(png); if (small) g_object_unref(small);
                }
            }
            g_object_unref(loader); gst_buffer_unmap(buffer, &mapped);
        }
        gst_sample_unref(sample);
    }
}
gboolean majoris_media_info(const char *path) {
    gst_init(NULL, NULL);
    GError *error = NULL;
    GstDiscoverer *discoverer = gst_discoverer_new(5 * GST_SECOND, &error);
    if (!discoverer) { g_clear_error(&error); return FALSE; }
    char *uri = g_filename_to_uri(path, NULL, NULL);
    GstDiscovererInfo *info = gst_discoverer_discover_uri(discoverer, uri, &error);
    g_free(uri);
    if (!info || gst_discoverer_info_get_result(info) != GST_DISCOVERER_OK) {
        if (info) gst_discoverer_info_unref(info);
        g_clear_error(&error); g_object_unref(discoverer); return FALSE;
    }
    JsonBuilder *b = json_builder_new(); json_builder_begin_object(b);
    number(b, "Duration (seconds)", gst_discoverer_info_get_duration(info) / GST_SECOND);
    tags(b, gst_discoverer_info_get_tags(info));
    GList *streams = gst_discoverer_info_get_stream_list(info);
    guint count = 0;
    for (GList *l = streams; l && count++ < 64; l = l->next) {
        GstDiscovererStreamInfo *stream = l->data;
        GstCaps *caps = gst_discoverer_stream_info_get_caps(stream);
        char *codec = caps ? gst_pb_utils_get_codec_description(caps) : NULL;
        if (GST_IS_DISCOVERER_VIDEO_INFO(stream)) {
            GstDiscovererVideoInfo *video = GST_DISCOVERER_VIDEO_INFO(stream);
            field(b, "Video Codec", codec);
            char *dimensions = g_strdup_printf("%u × %u", gst_discoverer_video_info_get_width(video), gst_discoverer_video_info_get_height(video));
            field(b, "Resolution", dimensions); g_free(dimensions);
            guint denominator = gst_discoverer_video_info_get_framerate_denom(video);
            if (denominator) {
                char *rate = g_strdup_printf("%.3f", (double)gst_discoverer_video_info_get_framerate_num(video) / denominator);
                field(b, "Frame Rate", rate); g_free(rate);
            }
            number(b, "Video Bitrate", gst_discoverer_video_info_get_bitrate(video));
        } else if (GST_IS_DISCOVERER_AUDIO_INFO(stream)) {
            GstDiscovererAudioInfo *audio = GST_DISCOVERER_AUDIO_INFO(stream);
            field(b, "Audio Codec", codec);
            number(b, "Sample Rate", gst_discoverer_audio_info_get_sample_rate(audio));
            number(b, "Channels", gst_discoverer_audio_info_get_channels(audio));
            number(b, "Audio Bitrate", gst_discoverer_audio_info_get_bitrate(audio));
        } else field(b, "Container", codec);
        tags(b, gst_discoverer_stream_info_get_tags(stream));
        if (caps) gst_caps_unref(caps);
        g_free(codec);
    }
    gst_discoverer_stream_info_list_free(streams);
    json_builder_end_object(b);
    JsonNode *root = json_builder_get_root(b); JsonGenerator *generator = json_generator_new();
    json_generator_set_root(generator, root); char *text = json_generator_to_data(generator, NULL);
    fputs(text, stdout); g_free(text); json_node_free(root); g_object_unref(generator); g_object_unref(b);
    gst_discoverer_info_unref(info); g_object_unref(discoverer); return TRUE;
}

gboolean majoris_video_thumbnail(const char *path) {
    gst_init(NULL, NULL);
    GstElement *player = gst_element_factory_make("playbin", NULL);
    GstElement *sink = gst_element_factory_make("appsink", NULL);
    GstElement *audio = gst_element_factory_make("fakesink", NULL);
    if (!player || !sink || !audio) {
        if (player) gst_object_unref(player);
        if (sink) gst_object_unref(sink);
        if (audio) gst_object_unref(audio);
        return FALSE;
    }
    GstCaps *caps = gst_caps_new_simple("video/x-raw", "format", G_TYPE_STRING, "RGB", NULL);
    gst_app_sink_set_caps(GST_APP_SINK(sink), caps); gst_caps_unref(caps);
    g_object_set(sink, "max-buffers", 1u, "drop", TRUE, "sync", FALSE, NULL);
    char *uri = g_filename_to_uri(path, NULL, NULL);
    g_object_set(player, "uri", uri, "video-sink", sink, "audio-sink", audio, NULL); g_free(uri);
    gboolean ok = FALSE;
    if (gst_element_set_state(player, GST_STATE_PAUSED) == GST_STATE_CHANGE_FAILURE) goto done;
    if (gst_element_get_state(player, NULL, NULL, 5 * GST_SECOND) == GST_STATE_CHANGE_FAILURE) goto done;
    gint64 duration = 0;
    if (gst_element_query_duration(player, GST_FORMAT_TIME, &duration) && duration > GST_SECOND)
        gst_element_seek_simple(player, GST_FORMAT_TIME, GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_KEY_UNIT, MIN(duration / 10, 30 * GST_SECOND));
    GstSample *sample = gst_app_sink_try_pull_preroll(GST_APP_SINK(sink), 5 * GST_SECOND);
    if (!sample) goto done;
    GstVideoInfo info;
    GstVideoFrame frame;
    if (gst_video_info_from_caps(&info, gst_sample_get_caps(sample)) &&
        info.width > 0 && info.height > 0 && info.width <= 16384 && info.height <= 16384 &&
        gst_video_frame_map(&frame, &info, gst_sample_get_buffer(sample), GST_MAP_READ)) {
        GdkPixbuf *image = gdk_pixbuf_new_from_data(GST_VIDEO_FRAME_PLANE_DATA(&frame, 0), GDK_COLORSPACE_RGB, FALSE, 8, info.width, info.height, GST_VIDEO_FRAME_PLANE_STRIDE(&frame, 0), NULL, NULL);
        double scale = MIN(1.0, 128.0 / MAX(info.width, info.height));
        GdkPixbuf *small = gdk_pixbuf_scale_simple(image, MAX(1, (int)(info.width * scale)), MAX(1, (int)(info.height * scale)), GDK_INTERP_BILINEAR);
        char *png = NULL; gsize size = 0;
        if (small && gdk_pixbuf_save_to_buffer(small, &png, &size, "png", NULL, NULL)) {
            ok = fwrite(png, 1, size, stdout) == size; g_free(png);
        }
        if (small) g_object_unref(small);
        g_object_unref(image); gst_video_frame_unmap(&frame);
    }
    gst_sample_unref(sample);
done:
    gst_element_set_state(player, GST_STATE_NULL);
    gst_object_unref(player);
    return ok;
}
