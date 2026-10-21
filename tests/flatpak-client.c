#include <gio/gio.h>
#include <string.h>
#include <stdio.h>
#ifdef MAJORIS_GTK_CLIENT
#include <gtk/gtk.h>
#endif

static GMainLoop *loop;
static const char *mode, *secret;
static int status = 1;
static void response(GDBusConnection *bus, const char *sender, const char *path, const char *interface, const char *signal, GVariant *parameters, void *data) {
    (void)bus; (void)sender; (void)path; (void)interface; (void)signal; (void)data;
    guint code; GVariant *result;
    g_variant_get(parameters, "(u@a{sv})", &code, &result);
    GFile *private = g_file_new_for_path(secret);
    GError *error = NULL;
    GFileInputStream *leak = g_file_read(private, NULL, &error);
    if (leak) { g_object_unref(leak); goto done; }
    g_clear_error(&error);
    if (!strcmp(mode, "cancel")) { status = code == 1 ? 0 : 1; goto done; }
    if (code != 0) goto done;
    GVariant *uris = g_variant_lookup_value(result, "uris", G_VARIANT_TYPE_STRING_ARRAY);
    guint expected = (!strcmp(mode, "multiple") || !strcmp(mode, "savefiles")) ? 2 : 1;
    if (!uris || g_variant_n_children(uris) != expected) { if (uris) g_variant_unref(uris); goto done; }
    for (guint i = 0; i < expected; i++) {
        GVariant *value = g_variant_get_child_value(uris, i);
        const char *uri = g_variant_get_string(value, NULL);
        GFile *file = g_file_new_for_uri(uri);
        if (!strcmp(mode, "save") || !strcmp(mode, "savefiles")) {
            if (!g_file_replace_contents(file, "saved-through-portal", 20, NULL, FALSE, G_FILE_CREATE_NONE, NULL, NULL, &error)) { g_object_unref(file); g_variant_unref(value); g_variant_unref(uris); goto done; }
        } else {
            if (!strcmp(mode, "folder")) { GFile *child = g_file_get_child(file, "allowed.txt"); g_object_unref(file); file = child; }
            char *contents = NULL; gsize length = 0;
            if (!g_file_load_contents(file, NULL, &contents, &length, NULL, &error) || length == 0) { g_free(contents); g_object_unref(file); g_variant_unref(value); g_variant_unref(uris); goto done; }
            g_free(contents);
        }
        g_object_unref(file); g_variant_unref(value);
    }
    g_variant_unref(uris); status = 0;
done:
    if (error) { fprintf(stderr, "%s\n", error->message); g_error_free(error); }
    g_object_unref(private); g_variant_unref(result); g_main_loop_quit(loop);
}
static gboolean timeout(void *data) { (void)data; g_main_loop_quit(loop); return G_SOURCE_REMOVE; }
#ifdef MAJORIS_GTK_CLIENT
static void gtk_done(GObject *object, GAsyncResult *result, void *data) {
    (void)data;
    GError *error = NULL; GFile *file = NULL; GListModel *files = NULL;
    GtkFileDialog *dialog = GTK_FILE_DIALOG(object);
    if (!strcmp(mode, "multiple")) files = gtk_file_dialog_open_multiple_finish(dialog, result, &error);
    else if (!strcmp(mode, "save")) file = gtk_file_dialog_save_finish(dialog, result, &error);
    else if (!strcmp(mode, "folder")) file = gtk_file_dialog_select_folder_finish(dialog, result, &error);
    else file = gtk_file_dialog_open_finish(dialog, result, &error);
    guint code = 0;
    if (error) {
        code = 1;
        if (strcmp(mode, "cancel")) { fprintf(stderr, "%s\n", error->message); g_error_free(error); g_main_loop_quit(loop); return; }
        g_error_free(error);
    }
    GVariantBuilder values, uris; g_variant_builder_init(&values, G_VARIANT_TYPE_VARDICT); g_variant_builder_init(&uris, G_VARIANT_TYPE_STRING_ARRAY);
    if (file) { char *uri = g_file_get_uri(file); g_variant_builder_add(&uris, "s", uri); g_free(uri); g_object_unref(file); }
    if (files) {
        for (guint i = 0; i < g_list_model_get_n_items(files); i++) { GFile *item = g_list_model_get_item(files, i); char *uri = g_file_get_uri(item); g_variant_builder_add(&uris, "s", uri); g_free(uri); g_object_unref(item); }
        g_object_unref(files);
    }
    g_variant_builder_add(&values, "{sv}", "uris", g_variant_builder_end(&uris));
    GVariant *parameters = g_variant_ref_sink(g_variant_new("(u@a{sv})", code, g_variant_builder_end(&values)));
    response(NULL, NULL, NULL, NULL, NULL, parameters, NULL); g_variant_unref(parameters);
}
#endif
int main(int argc, char **argv) {
    if (argc != 4 || !g_file_test("/.flatpak-info", G_FILE_TEST_EXISTS)) return 2;
    mode = argv[1]; secret = argv[3];
#ifdef MAJORIS_GTK_CLIENT
    g_unsetenv("GDK_DEBUG"); g_setenv("GTK_USE_PORTAL", "1", TRUE); g_setenv("GDK_BACKEND", "x11", TRUE);
    gtk_init(); loop = g_main_loop_new(NULL, FALSE);
    GtkFileDialog *dialog = gtk_file_dialog_new(); gtk_file_dialog_set_title(dialog, mode);
    GFile *folder = g_file_new_for_path(argv[2]); gtk_file_dialog_set_initial_folder(dialog, folder); g_object_unref(folder);
    if (!strcmp(mode, "save")) { gtk_file_dialog_set_initial_name(dialog, "gtk-saved.txt"); gtk_file_dialog_save(dialog, NULL, NULL, gtk_done, NULL); }
    else if (!strcmp(mode, "multiple")) gtk_file_dialog_open_multiple(dialog, NULL, NULL, gtk_done, NULL);
    else if (!strcmp(mode, "folder")) gtk_file_dialog_select_folder(dialog, NULL, NULL, gtk_done, NULL);
    else gtk_file_dialog_open(dialog, NULL, NULL, gtk_done, NULL);
    guint timer = g_timeout_add_seconds(20, timeout, NULL); g_main_loop_run(loop);
    if (status == 0) g_source_remove(timer);
    g_object_unref(dialog); g_main_loop_unref(loop); return status;
#else
    GError *error = NULL;
    GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!bus) return 3;
    loop = g_main_loop_new(NULL, FALSE);
    guint subscription = g_dbus_connection_signal_subscribe(bus, "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request", "Response", NULL, NULL, G_DBUS_SIGNAL_FLAGS_NONE, response, NULL, NULL);
    GVariantBuilder options; g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&options, "{sv}", "handle_token", g_variant_new_string("majoristest"));
    g_variant_builder_add(&options, "{sv}", "current_folder", g_variant_new_bytestring(argv[2]));
    if (!strcmp(mode, "multiple")) g_variant_builder_add(&options, "{sv}", "multiple", g_variant_new_boolean(TRUE));
    if (!strcmp(mode, "folder")) g_variant_builder_add(&options, "{sv}", "directory", g_variant_new_boolean(TRUE));
    if (!strcmp(mode, "save")) g_variant_builder_add(&options, "{sv}", "current_name", g_variant_new_string("saved.txt"));
    if (!strcmp(mode, "savefiles")) {
        GVariantBuilder names; g_variant_builder_init(&names, G_VARIANT_TYPE("aay"));
        g_variant_builder_add_value(&names, g_variant_new_bytestring("partA.txt"));
        g_variant_builder_add_value(&names, g_variant_new_bytestring("partB.txt"));
        g_variant_builder_add(&options, "{sv}", "files", g_variant_builder_end(&names));
    }
    const char *method = !strcmp(mode, "save") ? "SaveFile" : !strcmp(mode, "savefiles") ? "SaveFiles" : "OpenFile";
    GVariant *request = g_dbus_connection_call_sync(bus, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.FileChooser", method, g_variant_new("(ss@a{sv})", "", mode, g_variant_builder_end(&options)), G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, 15000, NULL, &error);
    if (!request) { if (error) fprintf(stderr, "%s\n", error->message); return 4; }
    g_variant_unref(request);
    guint timer = g_timeout_add_seconds(20, timeout, NULL);
    g_main_loop_run(loop);
    if (status == 0) g_source_remove(timer);
    g_dbus_connection_signal_unsubscribe(bus, subscription);
    g_main_loop_unref(loop); g_object_unref(bus);
    return status;
#endif
}
