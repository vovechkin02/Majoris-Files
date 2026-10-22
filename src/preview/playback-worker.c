#include <gst/gst.h>
#include <gst/app/gstappsink.h>
#include <gst/video/video.h>
#include <gst/pbutils/pbutils.h>
#include <glib-unix.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

static GMutex output_lock;
static GstElement *player;
static GMainLoop *loop;
static gboolean prepared, seeking;
static gint64 discovered_duration;
static gboolean write_bytes(const void *data,gsize size){
    const char *p=data;while(size){ssize_t n=write(STDOUT_FILENO,p,size);if(n<0&&errno==EINTR)continue;if(n<=0)return FALSE;p+=n;size-=n;}return TRUE;
}
static void packet(guint32 kind,const void *data,guint32 length){
    guint32 header[]={GUINT32_TO_LE(kind),GUINT32_TO_LE(length)};
    g_mutex_lock(&output_lock);gboolean ok=write_bytes(header,sizeof(header))&&write_bytes(data,length);g_mutex_unlock(&output_lock);
    if(!ok)_exit(3);
}
static GstFlowReturn video_sample(GstAppSink *sink,gpointer preroll){
    GstSample *sample=preroll?gst_app_sink_pull_preroll(sink):gst_app_sink_pull_sample(sink);
    if(!sample)return GST_FLOW_EOS;
    GstVideoInfo info;GstVideoFrame frame;
    if(!gst_video_info_from_caps(&info,gst_sample_get_caps(sample))||GST_VIDEO_INFO_FORMAT(&info)!=GST_VIDEO_FORMAT_RGBA||info.width<1||info.height<1||info.width>1920||info.height>1080||!gst_video_frame_map(&frame,&info,gst_sample_get_buffer(sample),GST_MAP_READ)){gst_sample_unref(sample);return GST_FLOW_ERROR;}
    guint32 size=8+info.width*info.height*4;guint8 *data=g_malloc(size);
    guint32 dimensions[]={GUINT32_TO_LE(info.width),GUINT32_TO_LE(info.height)};memcpy(data,dimensions,8);
    for(gint row=0;row<info.height;row++)memcpy(data+8+row*info.width*4,(guint8*)GST_VIDEO_FRAME_PLANE_DATA(&frame,0)+row*GST_VIDEO_FRAME_PLANE_STRIDE(&frame,0),info.width*4);
    packet('V',data,size);g_free(data);gst_video_frame_unmap(&frame);gst_sample_unref(sample);return GST_FLOW_OK;
}
static GstFlowReturn audio_sample(GstAppSink *sink,gpointer unused){
    GstSample *sample=gst_app_sink_pull_sample(sink);if(!sample)return GST_FLOW_EOS;
    GstMapInfo map;GstBuffer *buffer=gst_sample_get_buffer(sample);
    if(gst_buffer_map(buffer,&map,GST_MAP_READ)){
        if(map.size>192000||map.size%8){gst_buffer_unmap(buffer,&map);gst_sample_unref(sample);return GST_FLOW_ERROR;}
        packet('A',map.data,map.size);gst_buffer_unmap(buffer,&map);
    }
    gst_sample_unref(sample);return GST_FLOW_OK;
}
static gboolean status(gpointer unused){
    if(!prepared)return G_SOURCE_CONTINUE;
    gint64 position=0,duration=0;gint audio=0,video=0;
    gst_element_query_position(player,GST_FORMAT_TIME,&position);gst_element_query_duration(player,GST_FORMAT_TIME,&duration);
    if(duration<=0)duration=discovered_duration;
    g_object_get(player,"n-audio",&audio,"n-video",&video,NULL);
    GstQuery *query=gst_query_new_seeking(GST_FORMAT_TIME);gboolean seekable=FALSE;
    if(gst_element_query(player,query))gst_query_parse_seeking(query,NULL,&seekable,NULL,NULL);gst_query_unref(query);
    guint8 data[20];guint32 flags=GUINT32_TO_LE(8|(audio>0?1:0)|(video>0?2:0)|(seekable?4:0));guint64 p=GUINT64_TO_LE(MAX(position,0)/1000),d=GUINT64_TO_LE(MAX(duration,0)/1000);
    memcpy(data,&flags,4);memcpy(data+4,&p,8);memcpy(data+12,&d,8);packet('S',data,sizeof(data));return G_SOURCE_CONTINUE;
}
static gboolean message(GstBus *bus,GstMessage *event,gpointer unused){
    switch(GST_MESSAGE_TYPE(event)){
    case GST_MESSAGE_ERROR:{GError *error=NULL;char *detail=NULL;gst_message_parse_error(event,&error,&detail);char *text=g_strdup_printf("%s%s%s",error?error->message:"Media decoder failed",detail?"\n":"",detail?detail:"");packet('E',text,MIN(strlen(text),2048));g_free(text);g_free(detail);g_clear_error(&error);g_main_loop_quit(loop);break;}
    case GST_MESSAGE_ASYNC_DONE:prepared=TRUE;if(seeking){seeking=FALSE;packet('K',NULL,0);}status(NULL);break;
    case GST_MESSAGE_EOS:packet('D',NULL,0);break;
    default:break;
    }return G_SOURCE_CONTINUE;
}
static gboolean commands(gint fd,GIOCondition condition,gpointer unused){
    static char pending[256];static gsize used;
    if(condition&(G_IO_HUP|G_IO_ERR)){g_main_loop_quit(loop);return G_SOURCE_REMOVE;}
    ssize_t count=read(fd,pending+used,sizeof(pending)-used-1);if(count<=0){g_main_loop_quit(loop);return G_SOURCE_REMOVE;}used+=count;pending[used]=0;
    char *line=pending,*newline;
    while((newline=strchr(line,'\n'))){*newline=0;
        if(!strcmp(line,"P"))gst_element_set_state(player,GST_STATE_PLAYING);
        else if(!strcmp(line,"p"))gst_element_set_state(player,GST_STATE_PAUSED);
        else if(line[0]=='S'&&line[1]==' '){char *end=NULL;guint64 timestamp=g_ascii_strtoull(line+2,&end,10);if(!end||*end||timestamp>G_MAXINT64/1000||!gst_element_seek_simple(player,GST_FORMAT_TIME,GST_SEEK_FLAG_FLUSH|GST_SEEK_FLAG_ACCURATE,timestamp*1000))packet('F',NULL,0);else seeking=TRUE;}
        else if(!strcmp(line,"Q")){g_main_loop_quit(loop);return G_SOURCE_REMOVE;}
        else{g_main_loop_quit(loop);return G_SOURCE_REMOVE;}
        line=newline+1;
    }
    used-=line-pending;memmove(pending,line,used);if(used==sizeof(pending)-1){g_main_loop_quit(loop);return G_SOURCE_REMOVE;}return G_SOURCE_CONTINUE;
}
gboolean majoris_playback_worker(const char *path){
    gst_init(NULL,NULL);GError *error=NULL;
    char *uri=g_filename_to_uri(path,NULL,NULL);
    GstDiscoverer *discoverer=gst_discoverer_new(5*GST_SECOND,NULL);
    if(discoverer){GstDiscovererInfo *info=gst_discoverer_discover_uri(discoverer,uri,NULL);if(info){GstClockTime duration=gst_discoverer_info_get_duration(info);if(GST_CLOCK_TIME_IS_VALID(duration)&&duration<=G_MAXINT64)discovered_duration=duration;gst_discoverer_info_unref(info);}g_object_unref(discoverer);}
    GstElement *video=gst_parse_bin_from_description("videoconvert ! videoscale ! video/x-raw,format=RGBA,width=[1,1920],height=[1,1080],pixel-aspect-ratio=1/1 ! appsink name=frames emit-signals=true sync=true max-buffers=2 drop=true",TRUE,&error);
    GstElement *audio=gst_parse_bin_from_description("audioconvert ! audioresample ! audio/x-raw,format=F32LE,rate=48000,channels=2,layout=interleaved ! appsink name=sound emit-signals=true sync=true max-buffers=4 drop=true",TRUE,&error);
    player=gst_element_factory_make("playbin",NULL);
    if(error||!video||!audio||!player){const char *text=error?error->message:"GStreamer playback elements unavailable";packet('E',text,MIN(strlen(text),2048));g_clear_error(&error);return FALSE;}
    GstElement *frames=gst_bin_get_by_name(GST_BIN(video),"frames"),*sound=gst_bin_get_by_name(GST_BIN(audio),"sound");
    g_signal_connect(frames,"new-sample",G_CALLBACK(video_sample),NULL);g_signal_connect(frames,"new-preroll",G_CALLBACK(video_sample),GINT_TO_POINTER(1));g_signal_connect(sound,"new-sample",G_CALLBACK(audio_sample),NULL);
    g_object_set(player,"uri",uri,"video-sink",video,"audio-sink",audio,NULL);g_free(uri);gst_object_unref(frames);gst_object_unref(sound);
    loop=g_main_loop_new(NULL,FALSE);GstBus *bus=gst_element_get_bus(player);guint watch=gst_bus_add_watch(bus,message,NULL);gst_object_unref(bus);
    guint input=g_unix_fd_add(STDIN_FILENO,G_IO_IN|G_IO_HUP|G_IO_ERR,commands,NULL),timer=g_timeout_add(100,status,NULL);
    gst_element_set_state(player,GST_STATE_PAUSED);g_main_loop_run(loop);
    if(g_main_context_find_source_by_id(NULL,input))g_source_remove(input);g_source_remove(timer);g_source_remove(watch);
    gst_element_set_state(player,GST_STATE_NULL);gst_object_unref(player);g_main_loop_unref(loop);return TRUE;
}
