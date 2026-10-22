#include <gio/gio.h>
#include <poppler.h>
#include <cairo.h>
#include <pango/pangocairo.h>
#include <pango/pangofc-fontmap.h>
#include <fontconfig/fontconfig.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <sys/resource.h>
#include <sys/prctl.h>
#include <stdio.h>
#include <math.h>
#include <cmark.h>
#include <json-glib/json-glib.h>
#include "../archive/native.h"
#include "image-decoders.h"
#include <archive.h>
#include <archive_entry.h>
gboolean majoris_media_info(const char *path);
gboolean majoris_video_thumbnail(const char *path);
gboolean majoris_image_metadata(const char *path);
gboolean majoris_rotate_file(const char *path, int angle, const char *format, gboolean lossy);

typedef struct { GString *text; guint depth; } OfficeText;
static void office_start(GMarkupParseContext *context, const gchar *name, const gchar **keys, const gchar **values, gpointer data, GError **error) {
    (void)context; (void)name; (void)keys; (void)values;
    OfficeText *out = data;
    if(++out->depth > 128) g_set_error_literal(error, G_MARKUP_ERROR, G_MARKUP_ERROR_INVALID_CONTENT, "Office XML nesting limit");
}
static void office_end(GMarkupParseContext *context, const gchar *name, gpointer data, GError **error) {
    (void)context; (void)error; OfficeText *out = data; out->depth--;
    if(out->text->len < 512 * 1024 && (g_str_has_suffix(name, ":p") || g_str_has_suffix(name, ":tr") || g_str_equal(name, "row"))) g_string_append_c(out->text, '\n');
    else if(out->text->len < 512 * 1024 && (g_str_has_suffix(name, ":tc") || g_str_equal(name, "c") || g_str_equal(name, "si"))) g_string_append_c(out->text, '\t');
}
static void office_text(GMarkupParseContext *context, const gchar *text, gsize length, gpointer data, GError **error) {
    (void)context; (void)error; OfficeText *out = data;
    if(out->text->len < 512 * 1024) g_string_append_len(out->text, text, MIN(length, 512 * 1024 - out->text->len));
}
static void office_passthrough(GMarkupParseContext *context, const gchar *text, gsize length, gpointer data, GError **error) {
    (void)context; (void)length; (void)data;
    if(g_str_has_prefix(text, "<!DOCTYPE") || g_str_has_prefix(text, "<!ENTITY")) g_set_error_literal(error, G_MARKUP_ERROR, G_MARKUP_ERROR_INVALID_CONTENT, "Document declarations are not supported");
}
static gboolean office_preview(const char *path) {
    struct archive *archive = archive_read_new(); archive_read_support_format_zip(archive);
    if(archive_read_open_filename(archive, path, 65536) != ARCHIVE_OK) { archive_read_free(archive); return FALSE; }
    struct archive_entry *entry; guint entries = 0, documents = 0; gsize total = 0;
    OfficeText out = {g_string_new(NULL), 0}; gboolean ok = TRUE;
    const GMarkupParser parser = {office_start, office_end, office_text, office_passthrough, NULL};
    int status;
    while((status = archive_read_next_header(archive, &entry)) == ARCHIVE_OK) {
        if(++entries > 4096) { ok = FALSE; break; }
        const char *name = archive_entry_pathname(entry);
        gboolean selected = name && (g_str_equal(name, "content.xml") || g_str_equal(name, "word/document.xml") || g_str_equal(name, "xl/sharedStrings.xml") || (g_str_has_prefix(name, "xl/worksheets/sheet") && g_str_has_suffix(name, ".xml")) || (g_str_has_prefix(name, "ppt/slides/slide") && g_str_has_suffix(name, ".xml")));
        if(!selected) { archive_read_data_skip(archive); continue; }
        if(archive_entry_filetype(entry) != AE_IFREG || archive_entry_size(entry) > 4 * 1024 * 1024) { ok = FALSE; break; }
        GString *xml = g_string_new(NULL); char buffer[16384]; la_ssize_t count;
        while((count = archive_read_data(archive, buffer, sizeof(buffer))) > 0) {
            total += count;
            if(xml->len + count > 4 * 1024 * 1024 || total > 16 * 1024 * 1024) { ok = FALSE; break; }
            g_string_append_len(xml, buffer, count);
        }
        if(count < 0) ok = FALSE;
        if(ok) {
            out.depth = 0; GMarkupParseContext *context = g_markup_parse_context_new(&parser, 0, &out, NULL);
            ok = g_markup_parse_context_parse(context, xml->str, xml->len, NULL) && g_markup_parse_context_end_parse(context, NULL);
            g_markup_parse_context_free(context); documents++; g_string_append_c(out.text, '\n');
        }
        g_string_free(xml, TRUE);
        if(!ok || out.text->len >= 512 * 1024) break;
    }
    if(status != ARCHIVE_EOF && status != ARCHIVE_OK) ok = FALSE;
    archive_read_free(archive);
    if(ok && documents > 0) { char *valid = g_utf8_make_valid(out.text->str, out.text->len); fputs(valid, stdout); g_free(valid); if(out.text->len >= 512 * 1024) fputs("\n[Text preview truncated]\n", stdout); }
    else ok = FALSE;
    g_string_free(out.text, TRUE); return ok;
}

static cairo_status_t write_png(void *closure, const unsigned char *data, unsigned int length) {
    (void)closure;
    return fwrite(data, 1, length, stdout) == length ? CAIRO_STATUS_SUCCESS : CAIRO_STATUS_WRITE_ERROR;
}
static gboolean number(const char *text, double minimum, double maximum, double *value) {
    char *end = NULL;
    *value = g_ascii_strtod(text, &end);
    return end && end != text && *end == 0 && isfinite(*value) && *value >= minimum && *value <= maximum;
}
typedef struct { JsonBuilder *builder; gsize bytes; guint segments; gboolean valid; } MarkdownOutput;
static void markdown_text(MarkdownOutput *out, const char *text, guint style) {
    if(!text || !out->valid) return;
    char *valid = g_utf8_make_valid(text, -1);
    out->bytes += strlen(valid);
    if(out->bytes > 2 * 1024 * 1024 || ++out->segments > 20000) { out->valid = FALSE; g_free(valid); return; }
    json_builder_begin_object(out->builder);
    json_builder_set_member_name(out->builder, "text"); json_builder_add_string_value(out->builder, valid);
    json_builder_set_member_name(out->builder, "style"); json_builder_add_int_value(out->builder, style);
    json_builder_end_object(out->builder); g_free(valid);
}
static void markdown_node(MarkdownOutput *out, cmark_node *node, guint style, guint depth) {
    if(depth > 256 || !out->valid) { out->valid = FALSE; return; }
    cmark_node_type type = cmark_node_get_type(node);
    if(type == CMARK_NODE_TEXT || type == CMARK_NODE_HTML_INLINE || type == CMARK_NODE_HTML_BLOCK) { markdown_text(out, cmark_node_get_literal(node), style); return; }
    if(type == CMARK_NODE_CODE || type == CMARK_NODE_CODE_BLOCK) { markdown_text(out, cmark_node_get_literal(node), style | 4); if(type == CMARK_NODE_CODE_BLOCK) markdown_text(out, "\n\n", 0); return; }
    if(type == CMARK_NODE_SOFTBREAK || type == CMARK_NODE_LINEBREAK) { markdown_text(out, type == CMARK_NODE_SOFTBREAK ? " " : "\n", style); return; }
    if(type == CMARK_NODE_THEMATIC_BREAK) { markdown_text(out, "────────────\n\n", 0); return; }
    if(type == CMARK_NODE_STRONG) style |= 1;
    if(type == CMARK_NODE_EMPH) style |= 2;
    if(type == CMARK_NODE_HEADING) style |= 9;
    if(type == CMARK_NODE_BLOCK_QUOTE) { style |= 16; markdown_text(out, "│ ", style); }
    if(type == CMARK_NODE_LINK || type == CMARK_NODE_IMAGE) style |= 32;
    if(type == CMARK_NODE_IMAGE) markdown_text(out, "[Image: ", style);
    int number = type == CMARK_NODE_LIST ? cmark_node_get_list_start(node) : 0;
    for(cmark_node *child = cmark_node_first_child(node); child; child = cmark_node_next(child)) {
        if(type == CMARK_NODE_LIST) {
            if(cmark_node_get_list_type(node) == CMARK_ORDERED_LIST) { char *prefix = g_strdup_printf("%d. ", number++); markdown_text(out, prefix, 0); g_free(prefix); }
            else markdown_text(out, "• ", 0);
        }
        markdown_node(out, child, style, depth + 1);
    }
    if(type == CMARK_NODE_LINK || type == CMARK_NODE_IMAGE) { markdown_text(out, " (", style); markdown_text(out, cmark_node_get_url(node), style); markdown_text(out, type == CMARK_NODE_IMAGE ? ")]" : ")", style); }
    if(type == CMARK_NODE_PARAGRAPH || type == CMARK_NODE_HEADING || type == CMARK_NODE_BLOCK_QUOTE) markdown_text(out, "\n\n", 0);
}
extern gboolean majoris_playback_worker(const char *path);
int main(int argc, char **argv) {
    struct rlimit memory = {768 * 1024 * 1024, 768 * 1024 * 1024}, cpu = {10, 10}, files = {64, 64}, core = {0, 0};
    if (argc >= 3 && g_str_equal(argv[1], "office-pdf")) {
        memory.rlim_cur = memory.rlim_max = 2UL * 1024 * 1024 * 1024;
        cpu.rlim_cur = cpu.rlim_max = 30;
        files.rlim_cur = files.rlim_max = 128;
    }
    if(argc==3&&g_str_equal(argv[1],"media-play")){
        memory.rlim_cur=memory.rlim_max=2UL*1024*1024*1024;
        cpu.rlim_cur=cpu.rlim_max=1800;
        files.rlim_cur=files.rlim_max=128;
    }
    struct rlimit output_limit = {128 * 1024 * 1024, 128 * 1024 * 1024};
    if (setrlimit(RLIMIT_FSIZE, &output_limit)) return 2;
    if(setrlimit(RLIMIT_AS, &memory) || setrlimit(RLIMIT_CPU, &cpu) || setrlimit(RLIMIT_NOFILE, &files) || setrlimit(RLIMIT_CORE, &core)) return 2;
    if(prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0 || argc < 3) return 2;
    GError *error = NULL;
    if(argc==3&&g_str_equal(argv[1],"media-play"))return majoris_playback_worker(argv[2])?0:2;
    if (g_str_equal(argv[1], "image-rotate")) {
        if (argc != 6 || !(g_str_equal(argv[3], "90") || g_str_equal(argv[3], "270"))) return 2;
        return majoris_rotate_file(argv[2], atoi(argv[3]), argv[4], g_str_equal(argv[5], "lossy")) ? 0 : 2;
    }
    if (g_str_equal(argv[1], "office-pdf")) {
        if (argc != 4) return 2;
        const char *arguments[] = {"/usr/bin/python3", "/office-render.py", argv[3], NULL};
        GSubprocess *renderer = g_subprocess_newv(arguments, G_SUBPROCESS_FLAGS_NONE, &error);
        if (!renderer) { g_clear_error(&error); return 2; }
        gboolean ok = g_subprocess_wait_check(renderer, NULL, &error);
        g_object_unref(renderer); g_clear_error(&error); return ok ? 0 : 2;
    }
    if(g_str_equal(argv[1], "media-info")) return majoris_media_info(argv[2]) ? 0 : 2;
    if(g_str_equal(argv[1], "image-info")) return majoris_image_metadata(argv[2]) ? 0 : 2;
    if(g_str_equal(argv[1], "video-thumbnail")) return majoris_video_thumbnail(argv[2]) ? 0 : 2;
    if(g_str_equal(argv[1], "office")) return office_preview(argv[2]) ? 0 : 2;
    if (g_str_equal(argv[1], "image-animation")) {
        char *sequence=majoris_decode_avif_animation(argv[2],NULL);if(sequence){fputs(sequence,stdout);g_free(sequence);return 0;}
        GdkPixbufAnimation *animation = gdk_pixbuf_animation_new_from_file(argv[2], &error);
        if (!animation) goto fail;
        if (gdk_pixbuf_animation_is_static_image(animation)) { g_object_unref(animation); return 3; }
        GTimeVal now = {1, 0};
        GdkPixbufAnimationIter *iterator = gdk_pixbuf_animation_get_iter(animation, &now);
        JsonBuilder *builder = json_builder_new(); json_builder_begin_array(builder);
        gsize total = 0, pixels = 0;
        char *first_hash = NULL;
        for (guint frame = 0; frame < 240; frame++) {
            GdkPixbuf *original = gdk_pixbuf_animation_iter_get_pixbuf(iterator);
            GdkPixbuf *oriented = gdk_pixbuf_apply_embedded_orientation(original);
            double scale = MIN(1.0, 800.0 / MAX(gdk_pixbuf_get_width(oriented), gdk_pixbuf_get_height(oriented)));
            GdkPixbuf *image = gdk_pixbuf_scale_simple(oriented, MAX(1, (int)(gdk_pixbuf_get_width(oriented) * scale)), MAX(1, (int)(gdk_pixbuf_get_height(oriented) * scale)), GDK_INTERP_BILINEAR);
            g_object_unref(oriented);
            pixels += (gsize)gdk_pixbuf_get_width(image) * gdk_pixbuf_get_height(image);
            if (pixels > 16 * 1024 * 1024) { g_object_unref(image); break; }
            char *png = NULL; gsize size = 0;
            if (!gdk_pixbuf_save_to_buffer(image, &png, &size, "png", &error, NULL)) { g_object_unref(image); break; }
            g_object_unref(image);
            char *hash = g_compute_checksum_for_data(G_CHECKSUM_SHA256, (guchar *)png, size);
            if (frame > 0 && g_str_equal(first_hash, hash)) { g_free(hash); g_free(png); break; }
            if (frame == 0) first_hash = g_strdup(hash);
            g_free(hash);
            if (total + size > 24 * 1024 * 1024) { g_free(png); break; }
            total += size;
            int delay = gdk_pixbuf_animation_iter_get_delay_time(iterator);
            delay = CLAMP(delay, 20, 10000);
            char *encoded = g_base64_encode((guchar *)png, size); g_free(png);
            json_builder_begin_object(builder);
            json_builder_set_member_name(builder, "png"); json_builder_add_string_value(builder, encoded); g_free(encoded);
            json_builder_set_member_name(builder, "delay"); json_builder_add_int_value(builder, delay);
            json_builder_end_object(builder);
            now.tv_usec += delay * 1000;
            now.tv_sec += now.tv_usec / 1000000;
            now.tv_usec %= 1000000;
            if (!gdk_pixbuf_animation_iter_advance(iterator, &now)) break;
        }
        g_free(first_hash);
        json_builder_end_array(builder);
        JsonGenerator *generator = json_generator_new(); JsonNode *root = json_builder_get_root(builder);
        json_generator_set_root(generator, root); char *text = json_generator_to_data(generator, NULL); fputs(text, stdout);
        g_free(text); json_node_free(root); g_object_unref(generator); g_object_unref(builder); g_object_unref(iterator); g_object_unref(animation);
        return 0;
    }
    if(g_str_equal(argv[1], "thumbnail-cache")) {
        if(argc != 5) return 2;
        int width, height;
        if(!gdk_pixbuf_get_file_info(argv[2], &width, &height) || width < 1 || height < 1 || width > 128 || height > 128) return 2;
        GdkPixbuf *image = gdk_pixbuf_new_from_file(argv[2], &error);
        if(!image) goto fail;
        gboolean valid = g_strcmp0(gdk_pixbuf_get_option(image, "tEXt::Thumb::URI"), argv[3]) == 0 && g_strcmp0(gdk_pixbuf_get_option(image, "tEXt::Thumb::MTime"), argv[4]) == 0;
        char *buffer = NULL; gsize size = 0;
        gboolean saved = valid && gdk_pixbuf_save_to_buffer(image, &buffer, &size, "png", &error, NULL);
        g_object_unref(image);
        if(!saved) goto fail;
        gboolean written = fwrite(buffer, 1, size, stdout) == size; g_free(buffer); return written ? 0 : 2;
    }
    if(g_str_equal(argv[1], "markdown")) {
        FILE *input = fopen(argv[2], "rb"); if(!input) return 2;
        char *contents = g_malloc(256 * 1024); size_t length = fread(contents, 1, 256 * 1024, input);
        gboolean read_ok = !ferror(input); fclose(input); if(!read_ok) { g_free(contents); return 2; }
        cmark_node *document = cmark_parse_document(contents, length, CMARK_OPT_VALIDATE_UTF8); g_free(contents); if(!document) return 2;
        MarkdownOutput output = {json_builder_new(), 0, 0, TRUE}; json_builder_begin_array(output.builder);
        markdown_node(&output, document, 0, 0); json_builder_end_array(output.builder); cmark_node_free(document);
        if(!output.valid) { g_object_unref(output.builder); return 2; }
        JsonGenerator *generator = json_generator_new(); JsonNode *root = json_builder_get_root(output.builder); json_generator_set_root(generator, root);
        char *text = json_generator_to_data(generator, NULL); fputs(text, stdout); g_free(text); json_node_free(root); g_object_unref(generator); g_object_unref(output.builder); return 0;
    }
    if(g_str_equal(argv[1], "archive")) {
        GCancellable *token = g_cancellable_new();
        char *text = majoris_archive_list(argv[2], token, &error);
        g_object_unref(token);
        if(!text) goto fail;
        fputs(text, stdout); g_free(text); return 0;
    }
    if(g_str_equal(argv[1], "pdf-info") || g_str_equal(argv[1], "pdf-page") || g_str_equal(argv[1], "pdf-thumbnail")) {
        char *uri = g_filename_to_uri(argv[2], NULL, &error);
        if(!uri) goto fail;
        PopplerDocument *document = poppler_document_new_from_file(uri, NULL, &error);
        g_free(uri);
        if(!document) goto fail;
        int count = poppler_document_get_n_pages(document);
        if(count < 1 || count > 100000) { g_object_unref(document); return 2; }
        if(g_str_equal(argv[1], "pdf-info")) { printf("%d", count); g_object_unref(document); return 0; }
        double index = 0, zoom = 1;
        gboolean thumbnail = g_str_equal(argv[1], "pdf-thumbnail");
        if(!thumbnail && (argc != 5 || !number(argv[3], 0, count - 1, &index) || floor(index) != index || !number(argv[4], 0.25, 3, &zoom))) { g_object_unref(document); return 2; }
        PopplerPage *page = poppler_document_get_page(document, (int)index);
        double width, height; poppler_page_get_size(page, &width, &height);
        if(!isfinite(width) || !isfinite(height) || width <= 0 || height <= 0) { g_object_unref(page); g_object_unref(document); return 2; }
        double scale = fmin(zoom, (thumbnail ? 128 : 4096) / fmax(width, height));
        cairo_surface_t *image = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, MAX(1, (int)(width * scale)), MAX(1, (int)(height * scale)));
        cairo_t *cr = cairo_create(image); cairo_set_source_rgb(cr, 1, 1, 1); cairo_paint(cr); cairo_scale(cr, scale, scale); poppler_page_render(page, cr);
        cairo_status_t status = cairo_surface_write_to_png_stream(image, write_png, NULL);
        cairo_destroy(cr); cairo_surface_destroy(image); g_object_unref(page); g_object_unref(document);
        return status == CAIRO_STATUS_SUCCESS ? 0 : 2;
    }
    if(g_str_equal(argv[1], "image") || g_str_equal(argv[1], "image-thumbnail")) {
        double angle = 0;
        gboolean thumbnail = g_str_equal(argv[1], "image-thumbnail");
        if(!thumbnail && (argc != 4 || !number(argv[3], 0, 270, &angle) || floor(angle) != angle || ((int)angle % 90) != 0)) return 2;
        GdkPixbuf *decoded = majoris_decode_image(argv[2], thumbnail ? 128 : 1800, thumbnail, &error);
        if(!decoded) goto fail;
        GdkPixbufRotation rotation = angle == 90 ? GDK_PIXBUF_ROTATE_CLOCKWISE : angle == 180 ? GDK_PIXBUF_ROTATE_UPSIDEDOWN : angle == 270 ? GDK_PIXBUF_ROTATE_COUNTERCLOCKWISE : GDK_PIXBUF_ROTATE_NONE;
        GdkPixbuf *image = gdk_pixbuf_rotate_simple(decoded, rotation);
        char *buffer = NULL; gsize size = 0;
        const char *profile = gdk_pixbuf_get_option(decoded, "icc-profile");
        gboolean saved = profile ? gdk_pixbuf_save_to_buffer(image, &buffer, &size, "png", &error, "icc-profile", profile, NULL) : gdk_pixbuf_save_to_buffer(image, &buffer, &size, "png", &error, NULL);
        g_object_unref(image); g_object_unref(decoded);
        if(!saved) goto fail;
        gboolean written = fwrite(buffer, 1, size, stdout) == size; g_free(buffer); return written ? 0 : 2;
    }
    if(g_str_equal(argv[1], "font")) {
        FcConfig *config = FcInitLoadConfigAndFonts();
        if(!config || !FcConfigAppFontAddFile(config, (const FcChar8 *)argv[2])) { if(config) FcConfigDestroy(config); return 2; }
        FcFontSet *fonts = FcConfigGetFonts(config, FcSetApplication);
        if(!fonts || fonts->nfont < 1) { FcConfigDestroy(config); return 2; }
        FcChar8 *family = NULL, *style = NULL;
        FcPatternGetString(fonts->fonts[0], FC_FAMILY, 0, &family); FcPatternGetString(fonts->fonts[0], FC_STYLE, 0, &style);
        if(!family) { FcConfigDestroy(config); return 2; }
        PangoFontMap *map = pango_cairo_font_map_new(); pango_fc_font_map_set_config(PANGO_FC_FONT_MAP(map), config);
        PangoContext *context = pango_font_map_create_context(map); PangoLayout *layout = pango_layout_new(context);
        PangoFontDescription *description = pango_fc_font_description_from_pattern(fonts->fonts[0], TRUE);
        pango_font_description_set_absolute_size(description, 30 * PANGO_SCALE);
        pango_layout_set_font_description(layout, description); pango_layout_set_width(layout, 1120 * PANGO_SCALE); pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR);
        char *sample = g_strdup_printf("%s — %s\n\nABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789 !?@#$%%&()\n\nThe quick brown fox jumps over the lazy dog.", family, style ? (const char *)style : "Regular");
        pango_layout_set_text(layout, sample, -1);
        cairo_surface_t *image = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1200, 480); cairo_t *cr = cairo_create(image);
        cairo_set_source_rgb(cr, 1, 1, 1); cairo_paint(cr); cairo_set_source_rgb(cr, .1, .1, .1); cairo_move_to(cr, 40, 30); pango_cairo_show_layout(cr, layout);
        cairo_status_t status = cairo_surface_write_to_png_stream(image, write_png, NULL);
        cairo_destroy(cr); cairo_surface_destroy(image); g_free(sample); pango_font_description_free(description); g_object_unref(layout); g_object_unref(context); g_object_unref(map); FcConfigDestroy(config);
        return status == CAIRO_STATUS_SUCCESS ? 0 : 2;
    }
    return 2;
fail:
    if(error) { fputs(error->message, stderr); g_error_free(error); }
    return 1;
}
