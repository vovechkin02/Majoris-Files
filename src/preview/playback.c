#include "playback.h"
#include <gio/gunixoutputstream.h>
#include <gst/gst.h>
#include <gst/app/gstappsrc.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>
#include <string.h>
#include <signal.h>
#include <pthread.h>

typedef struct { GtkMediaStream parent;GSubprocess *process;GCancellable *cancel;GMutex lock;GBytes *frame;guint width,height;guint flags;guint64 timestamp,duration,audio_bytes;char *failure;gboolean ended,seek_ok,seek_failed,closed,prepared,audio_output,counted;gint64 started,last_packet,last_position;guint pump,audio_watch;GdkTexture *texture;GstElement *audio,*source,*volume; } MajorisPlayback;
static gint active_workers;
typedef GtkMediaStreamClass MajorisPlaybackClass;
static void paintable_init(GdkPaintableInterface *iface);
G_DEFINE_TYPE_WITH_CODE(MajorisPlayback,majoris_playback,GTK_TYPE_MEDIA_STREAM,G_IMPLEMENT_INTERFACE(GDK_TYPE_PAINTABLE,paintable_init))
static gboolean command(MajorisPlayback *self,const char *text){
    if(self->closed)return FALSE;
    GOutputStream *output=g_subprocess_get_stdin_pipe(self->process);
    int fd=g_unix_output_stream_get_fd(G_UNIX_OUTPUT_STREAM(output));
    // A decoder exit must produce an ordinary stream error, never SIGPIPE in
    // the GUI. Block/consume only this write's signal on the current thread.
    sigset_t blocked,previous,pending;sigemptyset(&blocked);sigaddset(&blocked,SIGPIPE);pthread_sigmask(SIG_BLOCK,&blocked,&previous);sigpending(&pending);gboolean existed=sigismember(&pending,SIGPIPE);
    ssize_t length=strlen(text),sent=write(fd,text,length);
    if(sent<0&&errno==EPIPE&&!existed){struct timespec zero={0,0};sigtimedwait(&blocked,NULL,&zero);}pthread_sigmask(SIG_SETMASK,&previous,NULL);
    if(sent!=length){gtk_media_stream_error(GTK_MEDIA_STREAM(self),G_IO_ERROR,G_IO_ERROR_BROKEN_PIPE,"The isolated media decoder stopped accepting controls");majoris_playback_close(GTK_MEDIA_STREAM(self));return FALSE;}return TRUE;
}
static gboolean play(GtkMediaStream *stream){MajorisPlayback *self=(MajorisPlayback*)stream;if(gtk_media_stream_get_ended(stream))command(self,"S 0\n");g_mutex_lock(&self->lock);self->last_position=g_get_monotonic_time();g_mutex_unlock(&self->lock);if(self->audio&&gtk_media_stream_has_audio(stream))gst_element_set_state(self->audio,GST_STATE_PLAYING);return command(self,"P\n");}
static void pause_media(GtkMediaStream *stream){MajorisPlayback *self=(MajorisPlayback*)stream;command(self,"p\n");if(self->audio)gst_element_set_state(self->audio,GST_STATE_PAUSED);}
static void seek_media(GtkMediaStream *stream,gint64 timestamp){MajorisPlayback *self=(MajorisPlayback*)stream;if(self->audio){gst_element_set_state(self->audio,GST_STATE_READY);gst_element_set_state(self->audio,gtk_media_stream_get_playing(stream)?GST_STATE_PLAYING:GST_STATE_PAUSED);}char text[64];g_snprintf(text,sizeof(text),"S %"G_GINT64_FORMAT"\n",MAX(timestamp,0));if(!command(self,text))gtk_media_stream_seek_failed(stream);}
static void update_audio(GtkMediaStream *stream,gboolean muted,double volume){MajorisPlayback *self=(MajorisPlayback*)stream;if(self->volume)g_object_set(self->volume,"mute",muted,"volume",volume,NULL);}
static void snapshot(GdkPaintable *paintable,GdkSnapshot *snapshot,double width,double height){MajorisPlayback *self=(MajorisPlayback*)paintable;if(self->texture)gdk_paintable_snapshot(GDK_PAINTABLE(self->texture),snapshot,width,height);}
static int intrinsic_width(GdkPaintable *paintable){MajorisPlayback *self=(MajorisPlayback*)paintable;return self->texture?gdk_texture_get_width(self->texture):0;}
static int intrinsic_height(GdkPaintable *paintable){MajorisPlayback *self=(MajorisPlayback*)paintable;return self->texture?gdk_texture_get_height(self->texture):0;}
static void paintable_init(GdkPaintableInterface *iface){iface->snapshot=snapshot;iface->get_intrinsic_width=intrinsic_width;iface->get_intrinsic_height=intrinsic_height;}
void majoris_playback_close(GtkMediaStream *stream){
    MajorisPlayback *self=(MajorisPlayback*)stream;if(self->closed)return;self->closed=TRUE;
    g_cancellable_cancel(self->cancel);if(self->process)g_subprocess_force_exit(self->process);
    if(self->pump){g_source_remove(self->pump);self->pump=0;}
    if(self->audio_watch){g_source_remove(self->audio_watch);self->audio_watch=0;}
    if(self->counted){g_atomic_int_add(&active_workers,-1);self->counted=FALSE;}
    g_mutex_lock(&self->lock);GstElement *audio=self->audio;self->audio=NULL;self->source=NULL;self->volume=NULL;g_mutex_unlock(&self->lock);
    if(audio){gst_element_set_state(audio,GST_STATE_NULL);gst_object_unref(audio);}
}
static void dispose(GObject *object){MajorisPlayback *self=(MajorisPlayback*)object;majoris_playback_close(GTK_MEDIA_STREAM(self));g_clear_object(&self->texture);g_clear_object(&self->process);g_clear_object(&self->cancel);G_OBJECT_CLASS(majoris_playback_parent_class)->dispose(object);}
static void finalize(GObject *object){MajorisPlayback *self=(MajorisPlayback*)object;g_clear_pointer(&self->frame,g_bytes_unref);g_free(self->failure);g_mutex_clear(&self->lock);G_OBJECT_CLASS(majoris_playback_parent_class)->finalize(object);}
static void majoris_playback_class_init(MajorisPlaybackClass *klass){GObjectClass *object=G_OBJECT_CLASS(klass);object->dispose=dispose;object->finalize=finalize;klass->play=play;klass->pause=pause_media;klass->seek=seek_media;klass->update_audio=update_audio;}
static void majoris_playback_init(MajorisPlayback *self){g_mutex_init(&self->lock);self->cancel=g_cancellable_new();self->started=self->last_packet=self->last_position=g_get_monotonic_time();}
static void fail(MajorisPlayback *self,const char *text){g_mutex_lock(&self->lock);if(!self->failure)self->failure=g_utf8_make_valid(text,-1);g_mutex_unlock(&self->lock);}
static gboolean audio_message(GstBus *bus,GstMessage *message,gpointer pointer){if(GST_MESSAGE_TYPE(message)==GST_MESSAGE_ERROR){MajorisPlayback *self=pointer;fail(self,"The system audio output could not play this preview");}return G_SOURCE_CONTINUE;}
static gboolean exact(GInputStream *input,void *data,gsize size,GCancellable *cancel){gsize count=0;return g_input_stream_read_all(input,data,size,&count,cancel,NULL)&&count==size;}
static gpointer read_packets(gpointer pointer){
    MajorisPlayback *self=pointer;GInputStream *input=g_subprocess_get_stdout_pipe(self->process);guint32 header[2];
    while(!g_cancellable_is_cancelled(self->cancel)&&exact(input,header,sizeof(header),self->cancel)){
        guint32 kind=GUINT32_FROM_LE(header[0]),length=GUINT32_FROM_LE(header[1]);
        if(length>8+1920*1080*4||!((kind=='V'&&length>=12)||(kind=='A'&&length<=192000&&length%8==0)||(kind=='S'&&length==20)||(kind=='E'&&length>0&&length<=2048)||((kind=='D'||kind=='K'||kind=='F')&&length==0))){fail(self,"Invalid isolated media output");break;}
        guint8 *data=g_malloc(length+1);data[length]=0;if(!exact(input,data,length,self->cancel)){g_free(data);break;}
        g_mutex_lock(&self->lock);self->last_packet=g_get_monotonic_time();
        if(kind=='V'){
            guint32 w,h;memcpy(&w,data,4);memcpy(&h,data+4,4);w=GUINT32_FROM_LE(w);h=GUINT32_FROM_LE(h);
            if(!w||!h||w>1920||h>1080||length!=8+w*h*4){g_mutex_unlock(&self->lock);g_free(data);fail(self,"Invalid isolated video dimensions");break;}
            g_clear_pointer(&self->frame,g_bytes_unref);self->frame=g_bytes_new(data+8,length-8);self->width=w;self->height=h;
        }else if(kind=='S'){
            guint32 flags;guint64 p,d;memcpy(&flags,data,4);memcpy(&p,data+4,8);memcpy(&d,data+12,8);
            flags=GUINT32_FROM_LE(flags);p=GUINT64_FROM_LE(p);d=GUINT64_FROM_LE(d);
            if(flags>15||p>G_MAXINT64||d>G_MAXINT64){g_mutex_unlock(&self->lock);g_free(data);fail(self,"Invalid isolated media timeline");break;}
            self->flags=flags;self->duration=d;if(p!=self->timestamp)self->last_position=g_get_monotonic_time();self->timestamp=p;
        }else if(kind=='E'){g_free(self->failure);self->failure=g_utf8_make_valid((char*)data,length);}
        else if(kind=='D')self->ended=TRUE;
        else if(kind=='K')self->seek_ok=TRUE;
        else if(kind=='F')self->seek_failed=TRUE;
        else if(kind=='A'){
            // Only fixed-format raw PCM crosses this boundary. No demuxer or
            // codec runs in the GTK process; audio device output stays here.
            for(guint32 i=0;i<length;i+=4){guint32 raw;float sample;memcpy(&raw,data+i,4);raw=GUINT32_FROM_LE(raw);memcpy(&sample,&raw,4);sample=isfinite(sample)?CLAMP(sample,-1.0f,1.0f):0.0f;memcpy(&raw,&sample,4);raw=GUINT32_TO_LE(raw);memcpy(data+i,&raw,4);}
            self->audio_bytes+=length;
            if(self->source){GstBuffer *buffer=gst_buffer_new_allocate(NULL,length,NULL);gst_buffer_fill(buffer,0,data,length);gst_app_src_push_buffer(GST_APP_SRC(self->source),buffer);}
        }
        g_mutex_unlock(&self->lock);g_free(data);
    }
    if(!g_cancellable_is_cancelled(self->cancel))fail(self,"The isolated media decoder exited or disconnected");
    g_object_unref(self);return NULL;
}
static gboolean pump(gpointer pointer){
    MajorisPlayback *self=pointer;GtkMediaStream *stream=GTK_MEDIA_STREAM(self);if(self->closed){self->pump=0;return G_SOURCE_REMOVE;}
    g_mutex_lock(&self->lock);
    GBytes *frame=g_steal_pointer(&self->frame);guint w=self->width,h=self->height,flags=self->flags;guint64 position=self->timestamp,duration=self->duration;gboolean ended=self->ended,seek_ok=self->seek_ok,seek_failed=self->seek_failed;self->ended=self->seek_ok=self->seek_failed=FALSE;
    char *failure=g_steal_pointer(&self->failure);gint64 last=self->last_packet,last_position=self->last_position;g_mutex_unlock(&self->lock);
    if(frame){GdkTexture *texture=gdk_memory_texture_new(w,h,GDK_MEMORY_R8G8B8A8,frame,w*4);gboolean resized=!self->texture||gdk_texture_get_width(self->texture)!=w||gdk_texture_get_height(self->texture)!=h;g_set_object(&self->texture,texture);g_object_unref(texture);g_bytes_unref(frame);if(resized)gdk_paintable_invalidate_size(GDK_PAINTABLE(self));gdk_paintable_invalidate_contents(GDK_PAINTABLE(self));}
    if(!self->prepared&&(flags&8)){self->prepared=TRUE;gtk_media_stream_stream_prepared(stream,!!(flags&1),!!(flags&2),!!(flags&4),duration);}
    if(self->prepared)gtk_media_stream_update(stream,position);
    if(seek_ok)gtk_media_stream_seek_success(stream);if(seek_failed)gtk_media_stream_seek_failed(stream);
    if(ended){if(gtk_media_stream_get_loop(stream)){command(self,"S 0\n");command(self,"P\n");}else gtk_media_stream_stream_ended(stream);}
    gint64 now=g_get_monotonic_time();
    if(!failure&&((!self->prepared&&now-self->started>15*G_USEC_PER_SEC)||now-last>15*G_USEC_PER_SEC||(gtk_media_stream_get_playing(stream)&&!ended&&now-last_position>20*G_USEC_PER_SEC)))failure=g_strdup("The isolated media decoder stopped responding");
    if(failure){gtk_media_stream_error(stream,G_IO_ERROR,G_IO_ERROR_FAILED,"%s",failure);g_free(failure);self->pump=0;majoris_playback_close(stream);return G_SOURCE_REMOVE;}
    return G_SOURCE_CONTINUE;
}
GtkMediaStream *majoris_playback_new(GSubprocess *process,gboolean audio_output){
    gst_init(NULL,NULL);MajorisPlayback *self=g_object_new(majoris_playback_get_type(),NULL);self->process=g_object_ref(process);self->audio_output=audio_output;
    self->counted=TRUE;if(g_atomic_int_add(&active_workers,1)>=4){gtk_media_stream_error(GTK_MEDIA_STREAM(self),G_IO_ERROR,G_IO_ERROR_BUSY,"Close another media preview before opening more than four decoders");majoris_playback_close(GTK_MEDIA_STREAM(self));return GTK_MEDIA_STREAM(self);}
    // Parent pipeline accepts PCM only. A bounded leaky queue prevents an
    // unavailable/slow audio device from blocking decoder supervision.
    GError *error=NULL;self->audio=gst_parse_launch(audio_output?"appsrc name=pcm is-live=true format=time do-timestamp=true max-bytes=262144 leaky-type=downstream caps=audio/x-raw,format=F32LE,rate=48000,channels=2,layout=interleaved ! queue max-size-bytes=262144 leaky=downstream ! volume name=level ! audioconvert ! audioresample ! autoaudiosink":"appsrc name=pcm is-live=true format=time do-timestamp=true max-bytes=262144 leaky-type=downstream caps=audio/x-raw,format=F32LE,rate=48000,channels=2,layout=interleaved ! volume name=level ! fakesink sync=false",&error);
    if(error||!self->audio){gtk_media_stream_error(GTK_MEDIA_STREAM(self),G_IO_ERROR,G_IO_ERROR_NOT_SUPPORTED,"Raw audio output is unavailable");g_clear_error(&error);majoris_playback_close(GTK_MEDIA_STREAM(self));return GTK_MEDIA_STREAM(self);}
    self->source=gst_bin_get_by_name(GST_BIN(self->audio),"pcm");self->volume=gst_bin_get_by_name(GST_BIN(self->audio),"level");gst_object_unref(self->source);gst_object_unref(self->volume);
    GstBus *bus=gst_element_get_bus(self->audio);self->audio_watch=gst_bus_add_watch(bus,audio_message,self);gst_object_unref(bus);
    int fd=g_unix_output_stream_get_fd(G_UNIX_OUTPUT_STREAM(g_subprocess_get_stdin_pipe(process)));fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK);
    self->pump=g_timeout_add(33,pump,self);GThread *thread=g_thread_new("isolated-media-output",read_packets,g_object_ref(self));g_thread_unref(thread);return GTK_MEDIA_STREAM(self);
}
guint64 majoris_playback_audio_bytes(GtkMediaStream *stream){MajorisPlayback *self=(MajorisPlayback*)stream;g_mutex_lock(&self->lock);guint64 count=self->audio_bytes;g_mutex_unlock(&self->lock);return count;}
