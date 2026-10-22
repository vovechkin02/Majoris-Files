#pragma once
#include <gio/gio.h>
gboolean majoris_sync_tree(const char *, GCancellable *, gboolean, GError **);
gboolean majoris_exchange(const char *, const char *, GError **);
