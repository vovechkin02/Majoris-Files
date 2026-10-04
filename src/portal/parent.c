#include "parent.h"
#include <gdk/wayland/gdkwayland.h>
#include <gdk/x11/gdkx.h>
#include <X11/Xutil.h>
#include <errno.h>
gboolean majoris_set_parent(GtkWindow *window, const char *identifier) {
    if (!identifier || !*identifier) return TRUE;
    gtk_widget_realize(GTK_WIDGET(window));
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    if (g_str_has_prefix(identifier, "wayland:") && GDK_IS_WAYLAND_TOPLEVEL(surface))
        return gdk_wayland_toplevel_set_transient_for_exported(GDK_TOPLEVEL(surface), identifier + 8);
    if (g_str_has_prefix(identifier, "x11:") && GDK_IS_X11_SURFACE(surface)) {
        char *end; errno = 0;
        unsigned long parent = strtoul(identifier + 4, &end, 16);
        if (errno || *end || !parent) return FALSE;
        GdkDisplay *display = gdk_surface_get_display(surface);
        gdk_x11_display_error_trap_push(display);
        XSetTransientForHint(gdk_x11_display_get_xdisplay(display), gdk_x11_surface_get_xid(surface), parent);
        XSync(gdk_x11_display_get_xdisplay(display), False);
        return gdk_x11_display_error_trap_pop(display) == 0;
    }
    return FALSE;
}
