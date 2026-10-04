#pragma once
#include <gio/gio.h>
gboolean majoris_archive_extract(const char *source, const char *destination, GCancellable *cancel, GError **error);
gboolean majoris_archive_create(const char *destination, const char *format, char **sources, GCancellable *cancel, GError **error);
