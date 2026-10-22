#pragma once
#include <gio/gio.h>
typedef void (*MajorisArchiveProgress)(guint64 bytes,guint files,gpointer data);
gboolean majoris_archive_extract(const char *source, const char *destination, const char *password, GCancellable *cancel, MajorisArchiveProgress progress,gpointer data,GError **error);
gboolean majoris_archive_create(const char *destination, const char *format, char **sources, const char *password, GCancellable *cancel,MajorisArchiveProgress progress,gpointer data,GError **error);
char *majoris_archive_list(const char *source, GCancellable *cancel, GError **error);
