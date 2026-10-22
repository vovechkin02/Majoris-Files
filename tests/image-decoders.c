#include "src/preview/image-decoders.h"
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <libheif/heif.h>
#include <lcms2.h>
#include <tiffio.h>
#include <math.h>
#include <json-glib/json-glib.h>
#if LIBHEIF_HAVE_VERSION(1,23,0)
#include <libheif/heif_sequences.h>
#endif

static char *folder;
static void icc(void) {
    char *path = g_build_filename(folder, "linear.png", NULL); GError *error = NULL;
    GdkPixbuf *input = gdk_pixbuf_new(GDK_COLORSPACE_RGB, TRUE, 8, 8, 8); gdk_pixbuf_fill(input, 0x80808080);
    cmsCIExyY white = {0.3127,0.329,1}; cmsCIExyYTRIPLE colors = {{0.64,0.33,1},{0.30,0.60,1},{0.15,0.06,1}};
    cmsToneCurve *curve = cmsBuildGamma(NULL, 1); cmsToneCurve *curves[] = {curve,curve,curve};
    cmsHPROFILE profile = cmsCreateRGBProfile(&white, &colors, curves); cmsUInt32Number length = 0; cmsSaveProfileToMem(profile,NULL,&length);
    void *bytes = g_malloc(length); cmsSaveProfileToMem(profile,bytes,&length); char *encoded = g_base64_encode(bytes,length);
    g_assert_true(gdk_pixbuf_save(input,path,"png",&error,"icc-profile",encoded,NULL)); g_assert_no_error(error);
    GdkPixbuf *output = majoris_decode_image(path,128,FALSE,&error); g_assert_no_error(error); g_assert_nonnull(output);
    const guchar *pixels = gdk_pixbuf_get_pixels(output);
    g_assert_cmpint(pixels[0], >, 175); g_assert_cmpint(pixels[0], <, 200); g_assert_cmpint(pixels[3], ==, 128);
    g_assert_nonnull(gdk_pixbuf_get_option(output,"icc-profile"));
    g_object_unref(output); g_object_unref(input); cmsCloseProfile(profile); cmsFreeToneCurve(curve); g_free(encoded);g_free(bytes);g_unlink(path);g_free(path);
}
static void raw(void) {
    char *path = g_build_filename(folder,"fixture.dng",NULL); TIFF *file = TIFFOpen(path,"w"); g_assert_nonnull(file);
    uint8_t version[] = {1,4,0,0}, pattern[] = {0,1,1,2}; uint16_t repeat[] = {2,2}; uint32_t white[] = {65535};
    float matrix[] = {1,0,0,0,1,0,0,0,1};
    TIFFSetField(file,TIFFTAG_IMAGEWIDTH,128); TIFFSetField(file,TIFFTAG_IMAGELENGTH,128);
    TIFFSetField(file,TIFFTAG_BITSPERSAMPLE,16); TIFFSetField(file,TIFFTAG_SAMPLESPERPIXEL,1);
    TIFFSetField(file,TIFFTAG_PHOTOMETRIC,32803); TIFFSetField(file,TIFFTAG_PLANARCONFIG,PLANARCONFIG_CONTIG);
    TIFFSetField(file,TIFFTAG_COMPRESSION,COMPRESSION_NONE); TIFFSetField(file,TIFFTAG_ROWSPERSTRIP,128);
    TIFFSetField(file,TIFFTAG_DNGVERSION,version); TIFFSetField(file,TIFFTAG_CFAREPEATPATTERNDIM,repeat);
    TIFFSetField(file,TIFFTAG_CFAPATTERN,4,pattern); TIFFSetField(file,TIFFTAG_WHITELEVEL,1,white);
    TIFFSetField(file,TIFFTAG_COLORMATRIX1,9,matrix); TIFFSetField(file,TIFFTAG_CALIBRATIONILLUMINANT1,21);
    TIFFSetField(file,TIFFTAG_UNIQUECAMERAMODEL,"Majoris DNG fixture"); TIFFSetField(file,TIFFTAG_MAKE,"Majoris"); TIFFSetField(file,TIFFTAG_MODEL,"DNG fixture");
    uint16_t row[128]; for(int y=0;y<128;y++){for(int x=0;x<128;x++)row[x]=12000+(x+y)*30;g_assert_cmpint(TIFFWriteScanline(file,row,y,0),>=,0);} TIFFClose(file);
    GError *error = NULL; GdkPixbuf *image = majoris_decode_image(path,128,FALSE,&error);
    g_assert_no_error(error); g_assert_nonnull(image); g_assert_cmpint(gdk_pixbuf_get_width(image),>,1); g_assert_cmpint(gdk_pixbuf_get_width(image),<=,128); g_object_unref(image);
    image = majoris_decode_image(path,128,TRUE,&error); g_assert_null(image); g_assert_error(error,G_IO_ERROR,G_IO_ERROR_NOT_SUPPORTED);g_clear_error(&error);
    g_unlink(path);g_free(path);
}
static void heif_case(gconstpointer data) {
    int transfer = GPOINTER_TO_INT(data);
    enum heif_compression_format format = transfer == 0 ? heif_compression_HEVC : heif_compression_AV1;
    struct heif_context *context = heif_context_alloc(); struct heif_encoder *encoder = NULL;
    if (heif_context_get_encoder_for_format(context,format,&encoder).code != heif_error_Ok) { heif_context_free(context);g_test_skip("Installed HEIF encoder plugin is unavailable");return; }
    struct heif_image *input = NULL; gboolean hdr = transfer != 0;
    g_assert_cmpint(heif_image_create(16,16,heif_colorspace_RGB,hdr ? heif_chroma_interleaved_RRGGBB_LE : heif_chroma_interleaved_RGB,&input).code,==,heif_error_Ok);
    g_assert_cmpint(heif_image_add_plane(input,heif_channel_interleaved,16,16,hdr ? 10 : 8).code,==,heif_error_Ok);
    int stride;uint8_t *pixels = heif_image_get_plane(input,heif_channel_interleaved,&stride);
    for(int y=0;y<16;y++)for(int x=0;x<16;x++)for(int c=0;c<3;c++){if(hdr){pixels[y*stride+x*6+c*2]=0;pixels[y*stride+x*6+c*2+1]=2;}else pixels[y*stride+x*3+c]=128;}
    struct heif_color_profile_nclx *nclx = heif_nclx_color_profile_alloc();
    nclx->color_primaries = hdr ? 9 : 1;nclx->transfer_characteristics = hdr ? transfer : 13;nclx->matrix_coefficients=hdr ? 9 : 1;nclx->full_range_flag=1;
    heif_image_set_nclx_color_profile(input,nclx); heif_encoder_set_lossy_quality(encoder,100);
    struct heif_image_handle *handle = NULL;
    struct heif_encoding_options *options=heif_encoding_options_alloc();options->output_nclx_profile=nclx;
    g_assert_cmpint(heif_context_encode_image(context,input,encoder,options,&handle).code,==,heif_error_Ok);
    heif_encoding_options_free(options);
    struct heif_color_profile_nclx *saved=NULL;g_assert_cmpint(heif_image_handle_get_nclx_color_profile(handle,&saved).code,==,heif_error_Ok);
    g_assert_cmpint(saved->transfer_characteristics,==,hdr ? transfer : 13);heif_nclx_color_profile_free(saved);
    char *path = g_build_filename(folder, hdr ? "fixture.avif" : "fixture.heic",NULL);
    g_assert_cmpint(heif_context_write_to_file(context,path).code,==,heif_error_Ok);
    GError *error=NULL;GdkPixbuf *output = majoris_decode_image(path,128,FALSE,&error);g_assert_no_error(error);g_assert_nonnull(output);
    int value = gdk_pixbuf_get_pixels(output)[0];g_test_message("Transfer %d rendered midpoint %d",transfer,value);
    if(transfer==16){g_assert_cmpint(value,>,135);g_assert_cmpint(value,<,190);} else {g_assert_cmpint(value,>,90);g_assert_cmpint(value,<,160);}
    g_object_unref(output);heif_image_handle_release(handle);heif_image_release(input);heif_encoder_release(encoder);heif_context_free(context);heif_nclx_color_profile_free(nclx);g_unlink(path);g_free(path);
}
static void corrupt(void) {
    char *path=g_build_filename(folder,"corrupt.avif",NULL);GError *error=NULL;
    g_file_set_contents(path,"invalid image fixture",-1,&error);g_assert_no_error(error);
    GdkPixbuf *image=majoris_decode_image(path,128,FALSE,&error);g_assert_null(image);g_assert_nonnull(error);g_clear_error(&error);g_unlink(path);g_free(path);
    g_assert_cmpfloat_with_epsilon(majoris_hdr_to_linear(0.5080784215,16),100,0.01);
    g_assert_cmpfloat_with_epsilon(majoris_hdr_to_linear(1,18),1000,0.01);
}
static void avif_sequence(void){
#if LIBHEIF_HAVE_VERSION(1,23,0)
    struct heif_context *context=heif_context_alloc();struct heif_encoder *encoder=NULL;
    if(heif_context_get_encoder_for_format(context,heif_compression_AV1,&encoder).code!=heif_error_Ok){g_test_skip("AV1 encoder unavailable");heif_context_free(context);return;}
    struct heif_track_options *options=heif_track_options_alloc();heif_track_options_set_timescale(options,1000);
    struct heif_track *track=NULL;g_assert_cmpint(heif_context_add_visual_sequence_track(context,32,16,heif_track_type_image_sequence,options,NULL,&track).code,==,heif_error_Ok);heif_track_options_release(options);
    struct heif_color_profile_nclx *profile=heif_nclx_color_profile_alloc();profile->color_primaries=1;profile->transfer_characteristics=13;profile->matrix_coefficients=1;profile->full_range_flag=1;
    for(int frame=0;frame<2;frame++){
        struct heif_image *image=NULL;g_assert_cmpint(heif_image_create(32,16,heif_colorspace_RGB,heif_chroma_interleaved_RGB,&image).code,==,heif_error_Ok);heif_image_add_plane(image,heif_channel_interleaved,32,16,8);
        int stride=0;guint8 *pixels=heif_image_get_plane(image,heif_channel_interleaved,&stride);
        for(int y=0;y<16;y++)for(int x=0;x<32;x++){pixels[y*stride+x*3]=frame?0:240;pixels[y*stride+x*3+1]=10;pixels[y*stride+x*3+2]=frame?240:0;}
        heif_image_set_nclx_color_profile(image,profile);heif_image_set_duration(image,100);
        g_assert_cmpint(heif_track_encode_sequence_image(track,image,encoder,NULL).code,==,heif_error_Ok);heif_image_release(image);
    }
    g_assert_cmpint(heif_track_encode_end_of_sequence(track,encoder).code,==,heif_error_Ok);
    char *path=g_build_filename(folder,"sequence.avif",NULL);g_assert_cmpint(heif_context_write_to_file(context,path).code,==,heif_error_Ok);
    heif_track_release(track);heif_encoder_release(encoder);heif_context_free(context);heif_nclx_color_profile_free(profile);
    GError *error=NULL;char *json=majoris_decode_avif_animation(path,&error);g_assert_no_error(error);g_assert_nonnull(json);
    JsonParser *parser=json_parser_new();g_assert_true(json_parser_load_from_data(parser,json,-1,&error));g_assert_no_error(error);JsonArray *frames=json_node_get_array(json_parser_get_root(parser));g_assert_cmpuint(json_array_get_length(frames),==,2);
    g_assert_cmpint(json_object_get_int_member(json_array_get_object_element(frames,0),"delay"),==,100);g_assert_cmpint(json_object_get_int_member(json_array_get_object_element(frames,1),"delay"),==,100);
    g_assert_cmpstr(json_object_get_string_member(json_array_get_object_element(frames,0),"png"),!=,json_object_get_string_member(json_array_get_object_element(frames,1),"png"));
    GdkPixbuf *thumbnail=majoris_decode_image(path,128,TRUE,&error);g_assert_no_error(error);g_assert_nonnull(thumbnail);g_object_unref(thumbnail);
    g_object_unref(parser);g_free(json);g_unlink(path);g_free(path);
#else
    g_test_skip("Timed AVIF APIs unavailable in this libheif version");
#endif
}
int main(int argc,char **argv){
    g_test_init(&argc,&argv,NULL);folder=g_dir_make_tmp("majoris-image-formats-XXXXXX",NULL);g_assert_nonnull(folder);
    g_test_add_func("/image/icc-alpha",icc);g_test_add_func("/image/dng",raw);g_test_add_func("/image/corrupt-and-transfer-functions",corrupt);
    g_test_add_data_func("/image/heic",GINT_TO_POINTER(0),heif_case);g_test_add_data_func("/image/avif-pq",GINT_TO_POINTER(16),heif_case);g_test_add_data_func("/image/avif-hlg",GINT_TO_POINTER(18),heif_case);
    g_test_add_func("/image/animated-avif",avif_sequence);
    int result=g_test_run();g_rmdir(folder);g_free(folder);return result;
}
