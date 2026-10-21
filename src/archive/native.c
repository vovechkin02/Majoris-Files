#include "native.h"
#include <archive.h>
#include <archive_entry.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
static gboolean failure(struct archive *a, GError **error) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED, "%s", archive_error_string(a) ?: "Archive operation failed");
    return FALSE;
}
static gboolean safe_name(const char *name) {
    if (!name || !*name || strlen(name) > 4096 || g_path_is_absolute(name) || strchr(name,'\\')) return FALSE;
    char **parts = g_strsplit(name,"/",-1); gboolean safe = TRUE;
    for (int i=0;parts[i];i++) if (!strcmp(parts[i],"..")) safe = FALSE;
    g_strfreev(parts); return safe;
}
static int open_reader(struct archive *reader, const char *source, size_t block, char ***volumes, GError **error) {
    if (!g_str_has_suffix(source, ".7z.001")) return archive_read_open_filename(reader, source, block);
    char *stem = g_strndup(source, strlen(source) - 3);
    char *folder = g_path_get_dirname(source);
    char *base = g_path_get_basename(stem);
    GDir *dir = g_dir_open(folder, 0, error);
    guint maximum = 0;
    if (!dir) { g_free(stem); g_free(folder); g_free(base); return ARCHIVE_FATAL; }
    const char *name;
    while ((name = g_dir_read_name(dir))) {
        if (!g_str_has_prefix(name, base)) continue;
        const char *suffix = name + strlen(base);
        if (!*suffix) continue;
        gboolean digits = TRUE;
        for (const char *p = suffix; *p; p++) if (!g_ascii_isdigit(*p)) { digits = FALSE; break; }
        if (digits) {
            guint64 part = g_ascii_strtoull(suffix, NULL, 10);
            if (part <= 10000) maximum = MAX(maximum, part);
        }
    }
    g_dir_close(dir); g_free(folder); g_free(base);
    GPtrArray *files = g_ptr_array_new_with_free_func(g_free);
    for (guint i = 1; i <= maximum; i++) {
        char *part = g_strdup_printf("%s%03u", stem, i);
        struct stat st;
        if (lstat(part, &st) || !S_ISREG(st.st_mode)) {
            g_set_error(error, G_IO_ERROR, G_IO_ERROR_INVALID_DATA, "Missing or non-regular archive volume: %s", part);
            g_free(part); g_ptr_array_unref(files); g_free(stem); return ARCHIVE_FATAL;
        }
        g_ptr_array_add(files, part);
    }
    g_free(stem); g_ptr_array_add(files, NULL);
    *volumes = (char **)g_ptr_array_free(files, FALSE);
    return archive_read_open_filenames(reader, (const char **)*volumes, block);
}
char *majoris_archive_list(const char *source, GCancellable *cancel, GError **error) {
    struct archive *reader = archive_read_new();
    char **volumes = NULL;
    GString *text = g_string_new(NULL);
    archive_read_support_filter_all(reader); archive_read_support_format_all(reader);
    if(open_reader(reader, source, 65536, &volumes, error) != ARCHIVE_OK) { if (!error || !*error) failure(reader, error); goto fail; }
    struct archive_entry *entry; int result; guint count = 0;
    while((result = archive_read_next_header(reader, &entry)) != ARCHIVE_EOF) {
        if(g_cancellable_set_error_if_cancelled(cancel, error)) goto fail;
        if(result < ARCHIVE_OK) { failure(reader, error); goto fail; }
        const char *name = archive_entry_pathname(entry);
        char *valid = g_utf8_make_valid(name ? name : "Unnamed entry", -1);
        g_string_append_printf(text, "%s%s · %" G_GINT64_FORMAT " bytes\n", valid, archive_entry_filetype(entry) == AE_IFDIR ? "/" : "", (gint64)archive_entry_size(entry));
        g_free(valid);
        if(++count >= 2000 || text->len > 1024 * 1024) { g_string_append(text, "\n[Entry preview limit reached]\n"); break; }
        if(archive_read_data_skip(reader) < ARCHIVE_OK) { failure(reader, error); goto fail; }
    }
    archive_read_free(reader); g_strfreev(volumes); return g_string_free(text, FALSE);
fail:
    archive_read_free(reader); g_strfreev(volumes); g_string_free(text, TRUE); return NULL;
}
gboolean majoris_archive_extract(const char *source, const char *destination, const char *password, GCancellable *cancel, GError **error) {
    struct archive *reader = archive_read_new(), *writer = archive_write_disk_new(); gboolean ok = FALSE;
    char **volumes = NULL;
    archive_read_support_filter_all(reader); archive_read_support_format_all(reader);
    if(password && archive_read_add_passphrase(reader, password) != ARCHIVE_OK) { failure(reader, error); goto out; }
    archive_write_disk_set_options(writer, ARCHIVE_EXTRACT_SECURE_SYMLINKS | ARCHIVE_EXTRACT_SECURE_NODOTDOT | ARCHIVE_EXTRACT_NO_OVERWRITE | ARCHIVE_EXTRACT_SAFE_WRITES);
    if (open_reader(reader,source,1024*1024,&volumes,error) != ARCHIVE_OK) { if (!error || !*error) failure(reader,error); goto out; }
    struct archive_entry *entry; int result; guint count=0; guint64 bytes=0;
    while ((result=archive_read_next_header(reader,&entry)) != ARCHIVE_EOF) {
        if (g_cancellable_set_error_if_cancelled(cancel,error)) goto out;
        if (result < ARCHIVE_OK) { failure(reader,error); goto out; }
        const char *name=archive_entry_pathname(entry); mode_t type=archive_entry_filetype(entry);
        if (!safe_name(name) || archive_entry_symlink(entry) || archive_entry_hardlink(entry) || (type!=AE_IFREG && type!=AE_IFDIR) || ++count>100000) {
            g_set_error_literal(error,G_IO_ERROR,G_IO_ERROR_INVALID_DATA,"Archive contains an unsafe path, link, special file, or too many entries"); goto out;
        }
        char *path=g_build_filename(destination,name,NULL); archive_entry_set_pathname(entry,path); g_free(path);
        archive_entry_set_perm(entry,type==AE_IFDIR ? 0700 : 0600);
        if (archive_write_header(writer,entry) < ARCHIVE_OK) { failure(writer,error); goto out; }
        const void *buffer; size_t length; la_int64_t offset;
        while ((result=archive_read_data_block(reader,&buffer,&length,&offset)) == ARCHIVE_OK) {
            if (g_cancellable_set_error_if_cancelled(cancel,error)) goto out;
            bytes+=length;
            if (bytes>(((guint64)1)<<40)) { g_set_error_literal(error,G_IO_ERROR,G_IO_ERROR_NO_SPACE,"Archive exceeds the 1 TiB extraction safety limit"); goto out; }
            if (archive_write_data_block(writer,buffer,length,offset) < ARCHIVE_OK) { failure(writer,error); goto out; }
        }
        if (result != ARCHIVE_EOF) { failure(reader,error); goto out; }
        if (archive_write_finish_entry(writer)<ARCHIVE_OK) { failure(writer,error); goto out; }
    }
    ok=TRUE;
out:
    archive_read_free(reader); g_strfreev(volumes); archive_write_free(writer); return ok;
}
static gboolean add_path(struct archive *writer,const char *source,const char *name,GCancellable *cancel,GError **error) {
    if (g_cancellable_set_error_if_cancelled(cancel,error)) return FALSE;
    struct stat st;
    if (lstat(source,&st)) { g_set_error(error,G_IO_ERROR,g_io_error_from_errno(errno),"Cannot read %s: %s",source,g_strerror(errno)); return FALSE; }
    if (!S_ISREG(st.st_mode) && !S_ISDIR(st.st_mode)) { g_set_error_literal(error,G_IO_ERROR,G_IO_ERROR_NOT_SUPPORTED,"Archive creation only supports regular files and directories"); return FALSE; }
    struct archive_entry *entry=archive_entry_new(); archive_entry_set_pathname(entry,name); archive_entry_set_filetype(entry,S_ISDIR(st.st_mode)?AE_IFDIR:AE_IFREG); archive_entry_set_perm(entry,st.st_mode & 0777); archive_entry_set_size(entry,S_ISREG(st.st_mode)?st.st_size:0); archive_entry_set_mtime(entry,st.st_mtime,0);
    int result=archive_write_header(writer,entry); archive_entry_free(entry); if (result<ARCHIVE_OK) return failure(writer,error);
    if (S_ISREG(st.st_mode)) {
        int fd=open(source,O_RDONLY|O_NOFOLLOW); if (fd<0) { g_set_error(error,G_IO_ERROR,g_io_error_from_errno(errno),"Cannot open source: %s",g_strerror(errno)); return FALSE; }
        guint8 *buffer=g_malloc(1024*1024); ssize_t count; gboolean ok=TRUE;
        while ((count=read(fd,buffer,1024*1024))>0) { if (g_cancellable_set_error_if_cancelled(cancel,error)) { ok=FALSE; break; } if (archive_write_data(writer,buffer,count)!=count) { failure(writer,error); ok=FALSE; break; } }
        if (count<0 && ok) { g_set_error(error,G_IO_ERROR,g_io_error_from_errno(errno),"Cannot read source: %s",g_strerror(errno)); ok=FALSE; }
        g_free(buffer); close(fd); if (!ok) return FALSE;
    } else {
        GDir *dir=g_dir_open(source,0,error); if (!dir) return FALSE; const char *child;
        while ((child=g_dir_read_name(dir))) { char *path=g_build_filename(source,child,NULL); char *relative=g_build_filename(name,child,NULL); gboolean ok=add_path(writer,path,relative,cancel,error); g_free(path); g_free(relative); if (!ok) { g_dir_close(dir); return FALSE; } }
        g_dir_close(dir);
    }
    return archive_write_finish_entry(writer)>=ARCHIVE_OK || failure(writer,error);
}
gboolean majoris_archive_create(const char *destination,const char *format,char **sources,const char *password,GCancellable *cancel,GError **error) {
    int fd=open(destination,O_WRONLY|O_CREAT|O_EXCL,0600);
    if (fd<0) { g_set_error(error,G_IO_ERROR,g_io_error_from_errno(errno),"Cannot create archive: %s",g_strerror(errno)); return FALSE; }
    struct archive *writer=archive_write_new(); gboolean ok=FALSE; int result;
    if (!strcmp(format,"zip")) result=archive_write_set_format_zip(writer);
    else if (!strcmp(format,"7z")) result=archive_write_set_format_7zip(writer);
    else { result=archive_write_set_format_pax_restricted(writer); if (!strcmp(format,"tar.gz")) archive_write_add_filter_gzip(writer); else if (!strcmp(format,"tar.bz2")) archive_write_add_filter_bzip2(writer); else if (!strcmp(format,"tar.xz")) archive_write_add_filter_xz(writer); else if (!strcmp(format,"tar.zst")) archive_write_add_filter_zstd(writer); }
    if(password) {
        if(strcmp(format, "zip")) { g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED, "Encrypted creation supports ZIP only"); goto out; }
        if(archive_write_set_passphrase(writer, password) != ARCHIVE_OK || archive_write_set_options(writer, "zip:encryption=aes256") != ARCHIVE_OK) { failure(writer, error); goto out; }
    }
    if (result<ARCHIVE_OK || archive_write_open_fd(writer,fd)<ARCHIVE_OK) { failure(writer,error); goto out; }
    for (int i=0;sources[i];i++) { char *name=g_path_get_basename(sources[i]); gboolean added=add_path(writer,sources[i],name,cancel,error); g_free(name); if (!added) goto out; }
    ok=archive_write_close(writer)>=ARCHIVE_OK; if (!ok) failure(writer,error);
out:
    archive_write_free(writer); close(fd); if (!ok) unlink(destination); return ok;
}
