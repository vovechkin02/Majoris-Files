#pragma once
#include <gdk-pixbuf/gdk-pixbuf.h>
GdkPixbuf *majoris_decode_image(const char *, int, gboolean, GError **);
double majoris_hdr_to_linear(double value, int transfer);
char *majoris_decode_avif_animation(const char *path,GError **error);
