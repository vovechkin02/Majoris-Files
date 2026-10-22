#pragma once
#include <gtk/gtk.h>
GtkMediaStream *majoris_playback_new(GSubprocess *process,gboolean audio_output);
void majoris_playback_close(GtkMediaStream *stream);
guint64 majoris_playback_audio_bytes(GtkMediaStream *stream);
