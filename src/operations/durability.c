#define _GNU_SOURCE
#include <gio/gio.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <linux/fs.h>

static gboolean report(GError **error, const char *operation) {
    g_set_error(error, G_IO_ERROR, g_io_error_from_errno(errno), "%s: %s", operation, g_strerror(errno));
    return FALSE;
}
static gboolean sync_tree(const char *path, GCancellable *token, guint depth, GError **error) {
    if (g_cancellable_set_error_if_cancelled(token, error)) return FALSE;
    if (depth > 128) { g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_TOO_MANY_LINKS, "Durability traversal is too deep"); return FALSE; }
    struct stat st;
    if (lstat(path, &st)) return report(error, "Inspect staged content");
    if (S_ISLNK(st.st_mode)) return TRUE;
    if (!S_ISREG(st.st_mode) && !S_ISDIR(st.st_mode)) { g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED, "Special files cannot be staged durably"); return FALSE; }
    int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (S_ISDIR(st.st_mode) ? O_DIRECTORY : 0));
    if (fd < 0) return report(error, "Open staged content for synchronization");
    gboolean ok = TRUE;
    if (S_ISDIR(st.st_mode)) {
        GDir *directory = g_dir_open(path, 0, error);
        if (!directory) ok = FALSE;
        else {
            const char *name;
            while (ok && (name = g_dir_read_name(directory))) {
                char *child = g_build_filename(path, name, NULL);
                ok = sync_tree(child, token, depth + 1, error); g_free(child);
            }
            g_dir_close(directory);
        }
    }
    if (ok && fsync(fd)) ok = report(error, "Synchronize staged content");
    close(fd); return ok;
}
gboolean majoris_sync_tree(const char *path, GCancellable *token, gboolean recursive, GError **error) {
    if (recursive) return sync_tree(path, token, 0, error);
    if (g_cancellable_set_error_if_cancelled(token, error)) return FALSE;
    int fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return report(error, "Open parent directory for synchronization");
    gboolean ok = fsync(fd) == 0;
    if (!ok) report(error, "Synchronize parent directory");
    close(fd); return ok;
}
gboolean majoris_exchange(const char *target, const char *staging, GError **error) {
    if (syscall(SYS_renameat2, AT_FDCWD, target, AT_FDCWD, staging, RENAME_EXCHANGE) == 0) return TRUE;
    if (errno == ENOSYS || errno == EOPNOTSUPP || errno == EINVAL) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED, "Atomic exchange is unavailable on this filesystem");
        return FALSE;
    }
    return report(error, "Atomically publish replacement");
}
