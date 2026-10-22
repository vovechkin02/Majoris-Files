#include "image-decoders.h"
#include <json-glib/json-glib.h>
#include <libraw/libraw.h>
#include <libheif/heif.h>
#include <lcms2.h>
#include <math.h>
#include <string.h>
#include <gio/gio.h>

static GdkPixbuf *bounded(GdkPixbuf *input, int maximum) {
    double scale = fmin(1.0, (double)maximum / MAX(gdk_pixbuf_get_width(input), gdk_pixbuf_get_height(input)));
    if (scale == 1) return g_object_ref(input);
    return gdk_pixbuf_scale_simple(input, MAX(1, (int)(gdk_pixbuf_get_width(input) * scale)), MAX(1, (int)(gdk_pixbuf_get_height(input) * scale)), GDK_INTERP_BILINEAR);
}
static void srgb_profile(GdkPixbuf *image) {
    cmsHPROFILE profile = cmsCreate_sRGBProfile(); cmsUInt32Number length = 0;
    if (profile && cmsSaveProfileToMem(profile, NULL, &length) && length <= 65536) {
        void *bytes = g_malloc(length);
        if (cmsSaveProfileToMem(profile, bytes, &length)) {
            char *text = g_base64_encode(bytes, length); gdk_pixbuf_remove_option(image, "icc-profile");
            gdk_pixbuf_set_option(image, "icc-profile", text); g_free(text);
        }
        g_free(bytes);
    }
    if (profile) cmsCloseProfile(profile);
}
static gboolean icc_to_srgb(GdkPixbuf *image, const void *bytes, gsize length, GError **error) {
    if (!bytes || length == 0) { srgb_profile(image); return TRUE; }
    if (length > 4 * 1024 * 1024) { g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_DATA, "Image color profile exceeds the limit"); return FALSE; }
    cmsHPROFILE input = cmsOpenProfileFromMem(bytes, length), output = cmsCreate_sRGBProfile();
    cmsUInt32Number format = gdk_pixbuf_get_has_alpha(image) ? TYPE_RGBA_8 : TYPE_RGB_8;
    cmsHTRANSFORM transform = input && output && cmsGetColorSpace(input) == cmsSigRgbData ?
        cmsCreateTransform(input, format, output, format, INTENT_PERCEPTUAL, cmsFLAGS_COPY_ALPHA | cmsFLAGS_BLACKPOINTCOMPENSATION) : NULL;
    if (transform) {
        for (int y = 0; y < gdk_pixbuf_get_height(image); y++) {
            guchar *row = gdk_pixbuf_get_pixels(image) + y * gdk_pixbuf_get_rowstride(image);
            cmsDoTransform(transform, row, row, gdk_pixbuf_get_width(image));
        }
        cmsDeleteTransform(transform);
    }
    if (input) cmsCloseProfile(input); if (output) cmsCloseProfile(output);
    if (!transform) { g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_DATA, "Unsupported or invalid embedded RGB color profile"); return FALSE; }
    srgb_profile(image); return TRUE;
}
// ST 2084 gives absolute luminance up to 10,000 cd/m². HLG uses its
// inverse OETF with the reference 1,000 cd/m² display system gamma.
double majoris_hdr_to_linear(double value, int transfer) {
    value = CLAMP(value, 0, 1);
    if (transfer == 16) {
        double p = pow(value, 1.0 / 78.84375);
        return pow(fmax(p - 0.8359375, 0) / fmax(18.8515625 - 18.6875 * p, 1e-9), 1.0 / 0.1593017578125) * 10000.0;
    }
    double scene = value <= 0.5 ? value * value / 3.0 : (exp((value - 0.55991073) / 0.17883277) + 0.28466892) / 12.0;
    return pow(scene, 1.2) * 1000.0;
}
static double srgb(double value) { return value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1.0 / 2.4) - 0.055; }
static gboolean nclx_to_srgb(GdkPixbuf *image, int primaries, int transfer, GError **error) {
    cmsCIExyY white = {0.3127, 0.3290, 1};
    cmsCIExyYTRIPLE colors = {{0.64, 0.33, 1}, {0.30, 0.60, 1}, {0.15, 0.06, 1}};
    if (primaries == 9) colors = (cmsCIExyYTRIPLE){{0.708, 0.292, 1}, {0.170, 0.797, 1}, {0.131, 0.046, 1}};
    else if (primaries == 12) colors = (cmsCIExyYTRIPLE){{0.680, 0.320, 1}, {0.265, 0.690, 1}, {0.150, 0.060, 1}};
    else if (primaries != 1 && primaries != 2) goto unsupported;
    cmsUInt16Number table[4096];
    for (int i = 0; i < 4096; i++) {
        double value = i / 4095.0, linear;
        switch (transfer) {
            case 1: case 6: case 14: case 15: linear = value < 0.081 ? value/4.5 : pow((value+0.099)/1.099, 1.0/0.45); break;
            case 2: case 13: linear = value <= 0.04045 ? value/12.92 : pow((value+0.055)/1.055, 2.4); break;
            case 4: linear = pow(value, 2.2); break;
            case 5: linear = pow(value, 2.8); break;
            case 8: linear = value; break;
            default: goto unsupported;
        }
        table[i] = CLAMP((int)lrint(linear*65535), 0, 65535);
    }
    cmsToneCurve *curve = cmsBuildTabulatedToneCurve16(NULL, 4096, table);
    cmsToneCurve *curves[] = {curve, curve, curve};
    cmsHPROFILE profile = curve ? cmsCreateRGBProfile(&white, &colors, curves) : NULL;
    if (curve) cmsFreeToneCurve(curve);
    cmsUInt32Number size = 0; gboolean result = FALSE;
    if (profile && cmsSaveProfileToMem(profile, NULL, &size) && size < 1024*1024) {
        void *bytes = g_malloc(size);
        if (cmsSaveProfileToMem(profile, bytes, &size)) result = icc_to_srgb(image, bytes, size, error);
        g_free(bytes);
    }
    if (profile) cmsCloseProfile(profile);
    return result;
unsupported:
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED, "This NCLX color space is not supported by the SDR preview conversion"); return FALSE;
}
static void hdr_pixel(double rgb[3], int primaries, int transfer) {
    double r = majoris_hdr_to_linear(rgb[0], transfer) / 203.0;
    double g = majoris_hdr_to_linear(rgb[1], transfer) / 203.0;
    double b = majoris_hdr_to_linear(rgb[2], transfer) / 203.0;
    if (primaries == 9) {
        rgb[0] = 1.660491*r - 0.587641*g - 0.072850*b;
        rgb[1] = -0.124550*r + 1.132900*g - 0.008350*b;
        rgb[2] = -0.018151*r - 0.100579*g + 1.118730*b;
    } else if (primaries == 12) {
        rgb[0] = 1.224745*r - 0.224904*g;
        rgb[1] = -0.042058*r + 1.042081*g;
        rgb[2] = -0.019642*r - 0.078655*g + 1.098537*b;
    } else { rgb[0] = r; rgb[1] = g; rgb[2] = b; }
    double luminance = fmax(0, 0.2126*rgb[0] + 0.7152*rgb[1] + 0.0722*rgb[2]);
    // Luminance-preserving Reinhard mapping, 203-nit reference white.
    double scale = 1.0 / (1.0 + luminance);
    double maximum = fmax(rgb[0], fmax(rgb[1], rgb[2])) * scale;
    if (maximum > 1) scale /= maximum;
    for (int c = 0; c < 3; c++) rgb[c] = CLAMP(srgb(fmax(0, rgb[c] * scale)), 0, 1);
}
#if LIBHEIF_HAVE_VERSION(1,23,0)
#include <libheif/heif_sequences.h>
static GdkPixbuf *sequence_frame(struct heif_image *image,int maximum,GError **error){
    int w=heif_image_get_width(image,heif_channel_interleaved),h=heif_image_get_height(image,heif_channel_interleaved),stride=0,bits=heif_image_get_bits_per_pixel_range(image,heif_channel_interleaved);
    const guint8 *pixels=heif_image_get_plane_readonly(image,heif_channel_interleaved,&stride);
    if(w<1||h<1||(guint64)w*h>64*1024*1024||bits<1||bits>16||stride<w*8||!pixels)return NULL;
    struct heif_color_profile_nclx *profile=NULL;heif_image_get_nclx_color_profile(image,&profile);
    int transfer=profile?profile->transfer_characteristics:2,primaries=profile?profile->color_primaries:2;gboolean hdr=transfer==16||transfer==18;
    if(profile)heif_nclx_color_profile_free(profile);
    if(hdr&&primaries!=1&&primaries!=9&&primaries!=12)return NULL;
    double scale=fmin(1,(double)maximum/MAX(w,h));GdkPixbuf *result=gdk_pixbuf_new(GDK_COLORSPACE_RGB,TRUE,8,MAX(1,(int)(w*scale)),MAX(1,(int)(h*scale)));
    for(int y=0;y<gdk_pixbuf_get_height(result);y++){
        const guint8 *row=pixels+MIN(h-1,(int)(y/scale))*stride;guint8 *out=gdk_pixbuf_get_pixels(result)+y*gdk_pixbuf_get_rowstride(result);
        for(int x=0;x<gdk_pixbuf_get_width(result);x++){
            int sx=MIN(w-1,(int)(x/scale));double rgb[3];
            for(int c=0;c<3;c++)rgb[c]=(row[sx*8+c*2]|((guint)row[sx*8+c*2+1]<<8))/(double)((1u<<bits)-1);
            if(hdr)hdr_pixel(rgb,primaries,transfer);
            for(int c=0;c<3;c++)out[x*4+c]=CLAMP((int)lrint(rgb[c]*255),0,255);
            out[x*4+3]=(guint)(row[sx*8+6]|((guint)row[sx*8+7]<<8))*255/((1u<<bits)-1);
        }
    }
    gsize size=heif_image_get_raw_color_profile_size(image);
    if(size&&!hdr){void *icc=size<=4*1024*1024?g_malloc(size):NULL;gboolean ok=icc&&heif_image_get_raw_color_profile(image,icc).code==heif_error_Ok&&icc_to_srgb(result,icc,size,error);g_free(icc);if(!ok)g_clear_object(&result);}
    else if(hdr)srgb_profile(result);else if(!nclx_to_srgb(result,primaries,transfer,error))g_clear_object(&result);
    return result;
}
#endif
char *majoris_decode_avif_animation(const char *path,GError **error){
#if LIBHEIF_HAVE_VERSION(1,23,0)
    struct heif_context *context=heif_context_alloc();struct heif_track *track=NULL;struct heif_decoding_options *options=NULL;char *text=NULL;JsonBuilder *builder=NULL;
    if(heif_context_read_from_file(context,path,NULL).code!=heif_error_Ok||!heif_context_has_sequence(context))goto done;
    track=heif_context_get_track(context,0);if(!track)goto done;
    uint16_t width,height;if(heif_track_get_image_resolution(track,&width,&height).code!=heif_error_Ok||!width||!height||(guint64)width*height>64*1024*1024)goto done;
    uint32_t timescale=heif_track_get_timescale(track);if(!timescale)goto done;
    options=heif_decoding_options_alloc();options->convert_hdr_to_8bit=0;
    options->ignore_sequence_editlist=1;
    builder=json_builder_new();json_builder_begin_array(builder);guint64 pixels=0,encoded=0;guint count=0;
    for(;count<240;count++){
        struct heif_image *image=NULL;struct heif_error status=heif_track_decode_next_image(track,&image,heif_colorspace_RGB,heif_chroma_interleaved_RRGGBBAA_LE,options);
        if(status.code==heif_error_End_of_sequence)break;
        if(status.code!=heif_error_Ok)goto done;
        guint64 delay=(guint64)heif_image_get_duration(image)*1000/timescale;
        GdkPixbuf *frame=sequence_frame(image,800,error);heif_image_release(image);if(!frame)goto done;
        pixels+=(guint64)gdk_pixbuf_get_width(frame)*gdk_pixbuf_get_height(frame);
        char *png=NULL;gsize size=0;gboolean ok=pixels<=16*1024*1024&&gdk_pixbuf_save_to_buffer(frame,&png,&size,"png",error,NULL);g_object_unref(frame);encoded+=size;
        if(!ok||encoded>24*1024*1024){g_free(png);goto done;}
        char *base64=g_base64_encode((guchar*)png,size);g_free(png);
        json_builder_begin_object(builder);json_builder_set_member_name(builder,"delay");json_builder_add_int_value(builder,CLAMP(delay,20,10000));json_builder_set_member_name(builder,"png");json_builder_add_string_value(builder,base64);json_builder_end_object(builder);g_free(base64);
    }
    if(count<2)goto done;
    json_builder_end_array(builder);JsonNode *root=json_builder_get_root(builder);JsonGenerator *generator=json_generator_new();json_generator_set_root(generator,root);text=json_generator_to_data(generator,NULL);g_object_unref(generator);json_node_free(root);
done:
    if(builder)g_object_unref(builder);if(options)heif_decoding_options_free(options);if(track)heif_track_release(track);heif_context_free(context);
    if(!text&&error&&!*error)g_set_error_literal(error,G_IO_ERROR,G_IO_ERROR_NOT_SUPPORTED,"A timed AVIF sequence is unavailable or exceeds the animation limits");return text;
#else
    g_set_error_literal(error,G_IO_ERROR,G_IO_ERROR_NOT_SUPPORTED,"Timed AVIF previews require libheif 1.23 or newer");return NULL;
#endif
}
static GdkPixbuf *decode_heif(const char *path, int maximum, GError **error) {
    struct heif_context *context = heif_context_alloc();
    struct heif_image_handle *handle = NULL; struct heif_image *decoded = NULL;
    GdkPixbuf *result = NULL;
    gboolean recognized = FALSE;
    if (heif_context_read_from_file(context, path, NULL).code != heif_error_Ok)goto done;
    if(heif_context_get_primary_image_handle(context,&handle).code!=heif_error_Ok){
#if LIBHEIF_HAVE_VERSION(1,23,0)
        if(heif_context_has_sequence(context)){
            struct heif_track *track=heif_context_get_track(context,0);struct heif_decoding_options *options=heif_decoding_options_alloc();options->convert_hdr_to_8bit=0;
            if(track&&heif_track_decode_next_image(track,&decoded,heif_colorspace_RGB,heif_chroma_interleaved_RRGGBBAA_LE,options).code==heif_error_Ok)result=sequence_frame(decoded,maximum,error);
            heif_decoding_options_free(options);if(track)heif_track_release(track);
        }
#endif
        goto done;
    }
    recognized = TRUE;
    int width = heif_image_handle_get_width(handle), height = heif_image_handle_get_height(handle);
    if (width <= 0 || height <= 0 || (guint64)width * height > 64 * 1024 * 1024) goto done;
    struct heif_color_profile_nclx *profile = NULL;
    heif_image_handle_get_nclx_color_profile(handle, &profile);
    int transfer = profile ? profile->transfer_characteristics : 2;
    int primaries = profile ? profile->color_primaries : 2;
    gboolean hdr = transfer == 16 || transfer == 18;
    if (hdr && primaries != 1 && primaries != 9 && primaries != 12) { if (profile) heif_nclx_color_profile_free(profile); goto done; }
    struct heif_decoding_options *options = heif_decoding_options_alloc();
    options->ignore_transformations = 0; options->convert_hdr_to_8bit = 0;
    // Preserve the source transfer for explicit HDR interpretation. Older stable
    // libheif versions already leave RGB in the source transfer/color space.
#if LIBHEIF_HAVE_VERSION(1,21,0)
    if (options->version >= 8) options->output_image_nclx_profile = profile;
#endif
    gboolean alpha = heif_image_handle_has_alpha_channel(handle);
    int channels = alpha ? 4 : 3;
    struct heif_error status = heif_decode_image(handle, &decoded, heif_colorspace_RGB,
        hdr ? (alpha ? heif_chroma_interleaved_RRGGBBAA_LE : heif_chroma_interleaved_RRGGBB_LE) : (alpha ? heif_chroma_interleaved_RGBA : heif_chroma_interleaved_RGB), options);
    heif_decoding_options_free(options);
    if (profile) heif_nclx_color_profile_free(profile);
    if (status.code != heif_error_Ok) goto done;
    width = heif_image_get_width(decoded, heif_channel_interleaved); height = heif_image_get_height(decoded, heif_channel_interleaved);
    int stride, bits = heif_image_get_bits_per_pixel_range(decoded, heif_channel_interleaved);
    const uint8_t *pixels = heif_image_get_plane_readonly(decoded, heif_channel_interleaved, &stride);
    if (!pixels || width <= 0 || height <= 0 || bits < 1 || bits > 16) goto done;
    double scale = fmin(1, (double)maximum / MAX(width, height));
    result = gdk_pixbuf_new(GDK_COLORSPACE_RGB, alpha, 8, MAX(1, (int)(width*scale)), MAX(1, (int)(height*scale)));
    if (!result) goto done;
    for (int y = 0; y < gdk_pixbuf_get_height(result); y++) {
        const uint8_t *source = pixels + MIN(height - 1, (int)(y/scale)) * stride;
        uint8_t *out = gdk_pixbuf_get_pixels(result) + y * gdk_pixbuf_get_rowstride(result);
        for (int x = 0; x < gdk_pixbuf_get_width(result); x++) {
            int sx = MIN(width - 1, (int)(x/scale)); double rgb[3];
            for (int c = 0; c < 3; c++) rgb[c] = hdr ? (source[sx*channels*2+c*2] | ((guint)source[sx*channels*2+c*2+1] << 8)) / (double)((1u << bits)-1) : source[sx*channels+c] / 255.0;
            if (hdr) hdr_pixel(rgb, primaries, transfer);
            for (int c = 0; c < 3; c++) out[x*channels+c] = CLAMP((int)lrint(rgb[c]*255), 0, 255);
            if (alpha) out[x*channels+3] = hdr ? (guint)(source[sx*8+6] | ((guint)source[sx*8+7] << 8))*255/((1u<<bits)-1) : source[sx*4+3];
        }
    }
    gsize icc_size = heif_image_handle_get_raw_color_profile_size(handle);
    if (icc_size && !hdr) {
        void *icc = icc_size <= 4*1024*1024 ? g_malloc(icc_size) : NULL;
        gboolean ok = icc && heif_image_handle_get_raw_color_profile(handle, icc).code == heif_error_Ok && icc_to_srgb(result, icc, icc_size, error);
        g_free(icc); if (!ok) g_clear_object(&result);
    } else if (hdr) srgb_profile(result);
    else if (!nclx_to_srgb(result, primaries, transfer, error)) g_clear_object(&result);
done:
    if (decoded) heif_image_release(decoded); if (handle) heif_image_handle_release(handle);
    heif_context_free(context);
    if (recognized && !result && error && !*error) g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED, "The installed HEIF/AVIF decoder cannot render this color space or image within the resource limits");
    return result;
}
static GdkPixbuf *raw_pixels(libraw_processed_image_t *data) {
    if (!data || data->data_size > 64*1024*1024) return NULL;
    if (data->type == LIBRAW_IMAGE_JPEG) {
        GdkPixbufLoader *loader = gdk_pixbuf_loader_new(); GdkPixbuf *result = NULL;
        if (gdk_pixbuf_loader_write(loader, data->data, data->data_size, NULL) && gdk_pixbuf_loader_close(loader, NULL)) result = g_object_ref(gdk_pixbuf_loader_get_pixbuf(loader));
        g_object_unref(loader); return result;
    }
    if (data->type != LIBRAW_IMAGE_BITMAP || data->bits != 8 || data->colors != 3 || !data->width || !data->height || (guint64)data->width * data->height * 3 > data->data_size) return NULL;
    GdkPixbuf *image = gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8, data->width, data->height);
    if (image) for (int y=0; y<data->height; y++) memcpy(gdk_pixbuf_get_pixels(image)+y*gdk_pixbuf_get_rowstride(image), data->data+y*data->width*3, data->width*3);
    return image;
}
GdkPixbuf *majoris_decode_image(const char *path, int maximum, gboolean thumbnail, GError **error) {
    GdkPixbuf *image = NULL;
    libraw_data_t *raw = libraw_init(0);
    if (raw && libraw_open_file(raw, path) == LIBRAW_SUCCESS) {
        libraw_processed_image_t *pixels = NULL; int status;
        if (libraw_unpack_thumb(raw) == LIBRAW_SUCCESS) pixels = libraw_dcraw_make_mem_thumb(raw, &status);
        image = raw_pixels(pixels); if (pixels) libraw_dcraw_clear_mem(pixels);
        if (image) {
            const char *profile = gdk_pixbuf_get_option(image, "icc-profile");
            gsize length = 0; void *bytes = profile ? g_base64_decode(profile, &length) : NULL;
            gboolean converted = icc_to_srgb(image, bytes, length, error); g_free(bytes);
            if (!converted) { g_object_unref(image); libraw_close(raw); return NULL; }
            GdkPixbufRotation rotation = raw->sizes.flip == 3 ? GDK_PIXBUF_ROTATE_UPSIDEDOWN : raw->sizes.flip == 5 ? GDK_PIXBUF_ROTATE_COUNTERCLOCKWISE : raw->sizes.flip == 6 ? GDK_PIXBUF_ROTATE_CLOCKWISE : GDK_PIXBUF_ROTATE_NONE;
            GdkPixbuf *rotated = gdk_pixbuf_rotate_simple(image, rotation); g_object_unref(image); image = rotated;
        } else if (!thumbnail && (guint64)raw->sizes.raw_width * raw->sizes.raw_height <= 64*1024*1024) {
            raw->params.half_size = 1; raw->params.use_camera_wb = 1; raw->params.output_color = 1; raw->params.output_bps = 8;
            if (libraw_unpack(raw) == LIBRAW_SUCCESS && libraw_dcraw_process(raw) == LIBRAW_SUCCESS) {
                pixels = libraw_dcraw_make_mem_image(raw, &status); image = raw_pixels(pixels);
                if (pixels) libraw_dcraw_clear_mem(pixels);
            }
        }
        libraw_close(raw);
        if (!image) { g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED, thumbnail ? "This RAW file has no usable embedded thumbnail" : "The installed RAW backend cannot render this file within the limits"); return NULL; }
        GdkPixbuf *small = bounded(image, maximum); g_object_unref(image); srgb_profile(small); return small;
    }
    if (raw) libraw_close(raw);
    image = decode_heif(path, maximum, error);
    if (image || (error && *error)) return image;
    int width=0,height=0;
    if (!gdk_pixbuf_get_file_info(path,&width,&height) || width < 1 || height < 1 || (guint64)width*height > 64*1024*1024) {
        g_set_error_literal(error,G_IO_ERROR,G_IO_ERROR_NOT_SUPPORTED,"Image dimensions are unavailable or exceed the decoding limit"); return NULL;
    }
    double scale=fmin(1.0,(double)maximum/MAX(width,height));
    image = gdk_pixbuf_new_from_file_at_scale(path, MAX(1,(int)(width*scale)), MAX(1,(int)(height*scale)), TRUE, error);
    if (!image) return NULL;
    GdkPixbuf *oriented = gdk_pixbuf_apply_embedded_orientation(image); g_object_unref(image); image = oriented;
    const char *profile = gdk_pixbuf_get_option(image, "icc-profile");
    gsize size = 0; void *bytes = profile ? g_base64_decode(profile, &size) : NULL;
    gboolean ok = icc_to_srgb(image, bytes, size, error); g_free(bytes);
    if (!ok) g_clear_object(&image);
    return image;
}
