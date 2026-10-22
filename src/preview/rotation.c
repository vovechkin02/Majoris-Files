#include <gio/gio.h>
#include <glib/gstdio.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <gexiv2/gexiv2.h>
#include <turbojpeg.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>

gboolean majoris_rotate_file(const char *path, int angle, const char *format, gboolean lossy) {
    if ((angle != 90 && angle != 270) || (strcmp(format,"png") && strcmp(format,"jpeg"))) return FALSE;
    GError *error = NULL; GExiv2Metadata *metadata = gexiv2_metadata_new();
    if (!gexiv2_metadata_open_path(metadata,path,&error)) goto failed;
    int orientation = gexiv2_metadata_try_get_orientation(metadata,&error);
    if (error) goto failed;
    if (orientation < 1 || orientation > 8) orientation = 1;
    const int clockwise[] = {0,6,7,8,5,2,3,4,1}, counterclockwise[] = {0,8,5,6,7,4,1,2,3};
    int transform = angle == 90 ? clockwise[orientation] : counterclockwise[orientation];
    char *temporary = NULL; int fd = g_file_open_tmp("majoris-rotate-XXXXXX",&temporary,&error);
    if (fd < 0) goto failed;
    close(fd);
    gboolean rendered = FALSE;
    if (!strcmp(format,"jpeg") && !lossy) {
        char *input = NULL; gsize input_length = 0;
        if (!g_file_get_contents(path,&input,&input_length,&error) || input_length > 256*1024*1024) { g_free(input); goto cleanup; }
        tjhandle handle = tjInitTransform();
        unsigned char *output = NULL; unsigned long output_length = 0;
        int width,height,subsampling,colorspace;
        int operations[] = {TJXOP_NONE,TJXOP_NONE,TJXOP_HFLIP,TJXOP_ROT180,TJXOP_VFLIP,TJXOP_TRANSPOSE,TJXOP_ROT90,TJXOP_TRANSVERSE,TJXOP_ROT270};
        tjtransform operation; memset(&operation,0,sizeof(operation)); operation.op=operations[transform]; operation.options=TJXOPT_PERFECT;
        if (handle && tjDecompressHeader3(handle,(unsigned char*)input,input_length,&width,&height,&subsampling,&colorspace)==0 && width>0 && height>0 && (guint64)width*height<=64*1024*1024 &&
            tjTransform(handle,(unsigned char*)input,input_length,1,&output,&output_length,&operation,0)==0 && output_length<=80*1024*1024)
            rendered=g_file_set_contents(temporary,(char*)output,output_length,&error);
        if (output) tjFree(output); if(handle)tjDestroy(handle);g_free(input);
    } else {
        if (!strcmp(format,"png")) {
            FILE *file = fopen(path,"rb"); unsigned char header[25];
            gboolean allowed = file && fread(header,1,25,file)==25 && !memcmp(header,"\x89PNG\r\n\x1a\n",8) && header[24]<=8;
            if(file)fclose(file);
            if(!allowed)goto cleanup; // Never silently reduce a 16-bit PNG.
        }
        int width=0,height=0;
        if(!gdk_pixbuf_get_file_info(path,&width,&height)||width<=0||height<=0||(guint64)width*height>64*1024*1024)goto cleanup;
        GdkPixbuf *input=gdk_pixbuf_new_from_file(path,&error),*output=NULL;
        if(!input)goto cleanup;
        if(transform==2||transform==4)output=gdk_pixbuf_flip(input,transform==2);
        else if(transform==5||transform==7){GdkPixbuf *flipped=gdk_pixbuf_flip(input,transform==7);output=gdk_pixbuf_rotate_simple(flipped,GDK_PIXBUF_ROTATE_CLOCKWISE);g_object_unref(flipped);}
        else output=gdk_pixbuf_rotate_simple(input,transform==3?GDK_PIXBUF_ROTATE_UPSIDEDOWN:transform==6?GDK_PIXBUF_ROTATE_CLOCKWISE:transform==8?GDK_PIXBUF_ROTATE_COUNTERCLOCKWISE:GDK_PIXBUF_ROTATE_NONE);
        const char *profile=gdk_pixbuf_get_option(input,"icc-profile");
        if(!strcmp(format,"jpeg"))rendered=profile?gdk_pixbuf_save(output,temporary,format,&error,"quality","95","icc-profile",profile,NULL):gdk_pixbuf_save(output,temporary,format,&error,"quality","95",NULL);
        else rendered=profile?gdk_pixbuf_save(output,temporary,format,&error,"icc-profile",profile,NULL):gdk_pixbuf_save(output,temporary,format,&error,NULL);
        g_object_unref(output);g_object_unref(input);
    }
    if(rendered){
        int width=0,height=0;gdk_pixbuf_get_file_info(temporary,&width,&height);
        gexiv2_metadata_try_set_orientation(metadata,GEXIV2_ORIENTATION_NORMAL,&error);
        if(!error)gexiv2_metadata_try_erase_exif_thumbnail(metadata,&error);
        if(!error)gexiv2_metadata_try_set_tag_long(metadata,"Exif.Photo.PixelXDimension",width,&error);
        if(!error)gexiv2_metadata_try_set_tag_long(metadata,"Exif.Photo.PixelYDimension",height,&error);
        if(!error&&gexiv2_metadata_has_tag(metadata,"Xmp.tiff.Orientation"))gexiv2_metadata_try_set_tag_long(metadata,"Xmp.tiff.Orientation",1,&error);
        if(!error)rendered=gexiv2_metadata_save_file(metadata,temporary,&error);else rendered=FALSE;
    }
    if(rendered){
        char *bytes=NULL;gsize length=0;
        rendered=g_file_get_contents(temporary,&bytes,&length,&error)&&length<=80*1024*1024;
        if(rendered)rendered=fwrite(bytes,1,length,stdout)==length;g_free(bytes);
    }
cleanup:
    g_unlink(temporary);g_free(temporary);g_clear_error(&error);g_object_unref(metadata);return rendered;
failed:
    g_clear_error(&error);g_object_unref(metadata);return FALSE;
}
