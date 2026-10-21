#include <gexiv2/gexiv2.h>
#include <json-glib/json-glib.h>
#include <stdio.h>
#include <string.h>

gboolean majoris_image_metadata(const char *path) {
    GExiv2Metadata *metadata = gexiv2_metadata_new(); GError *error = NULL;
    if (!gexiv2_metadata_open_path(metadata, path, &error)) { g_clear_error(&error); g_object_unref(metadata); return FALSE; }
    JsonBuilder *b = json_builder_new(); json_builder_begin_object(b);
    const char *tags[] = {"Exif.Image.Make", "Exif.Image.Model", "Exif.Photo.LensModel", "Exif.Photo.ExposureTime", "Exif.Photo.FNumber", "Exif.Photo.ISOSpeedRatings", "Exif.Photo.FocalLength", "Exif.Photo.DateTimeOriginal", "Exif.Image.Orientation", "Exif.GPSInfo.GPSLatitude", "Exif.GPSInfo.GPSLongitude", "Exif.Image.Copyright", "Exif.Image.Artist", "Exif.Image.ImageDescription", "Xmp.xmp.Rating"};
    const char *labels[] = {"Camera Make", "Camera Model", "Lens", "Exposure", "Aperture", "ISO", "Focal Length", "Capture Date", "Orientation", "GPS Latitude", "GPS Longitude", "Copyright", "Creator", "Description", "Rating"};
    for (guint i = 0; i < G_N_ELEMENTS(tags); i++) {
        char *text = gexiv2_metadata_try_get_tag_interpreted_string(metadata, tags[i], &error);
        g_clear_error(&error);
        if (text && g_utf8_validate(text, -1, NULL) && strlen(text) <= 16384 && *text) { json_builder_set_member_name(b, labels[i]); json_builder_add_string_value(b, text); }
        g_free(text);
    }
    gint width = gexiv2_metadata_get_pixel_width(metadata), height = gexiv2_metadata_get_pixel_height(metadata);
    if (width > 0 && height > 0) {
        char *dimensions = g_strdup_printf("%d × %d", width, height);
        json_builder_set_member_name(b, "Dimensions"); json_builder_add_string_value(b, dimensions); g_free(dimensions);
    }
    json_builder_end_object(b); JsonGenerator *generator = json_generator_new(); JsonNode *root = json_builder_get_root(b);
    json_generator_set_root(generator, root); char *text = json_generator_to_data(generator, NULL); fputs(text, stdout);
    g_free(text); json_node_free(root); g_object_unref(generator); g_object_unref(b); g_object_unref(metadata); return TRUE;
}
