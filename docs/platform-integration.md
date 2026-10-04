# Majoris platform integration

Build on Debian with a current GTK4/libadwaita toolchain:

```sh
apt install build-essential meson ninja-build valac libgtk-4-dev \
  libadwaita-1-dev libgee-0.8-dev libsqlite3-dev libjson-glib-dev \
  libpoppler-glib-dev libarchive-dev libpolkit-gobject-1-dev libx11-dev
meson setup build --prefix=/usr
meson compile -C build
meson test -C build --print-errorlogs
sudo meson install -C build
```

GTK >= 4.12 and libadwaita >= 1.5 are required. WSL is a development environment,
not a substitute for Majoris system integration tests.

The Majoris image must include GVfs/FUSE and network backends, Samba, smbclient,
libsmbclient, cifs-utils, Avahi, a secret-service keyring, UDisks, a graphical
Polkit agent, xdg-desktop-portal, the document portal, the GTK GStreamer media
backend, suitable GStreamer codecs and image codecs. Poppler and libarchive are
linked system libraries. Install `xdg-terminal-exec` and register the Majoris
terminal as the configured terminal provider. Runtime UI does not install packages.

## File chooser

Meson installs:

* `/usr/share/xdg-desktop-portal/portals/majoris.portal`
* `/usr/share/xdg-desktop-portal/majoris-portals.conf`
* the session D-Bus activation service for the Majoris portal backend

The desktop session should set `XDG_CURRENT_DESKTOP=Majoris`. The installed
desktop-specific configuration selects `majoris` for FileChooser only. The ISO
must retain appropriate preferred backends for other portal interfaces in its
complete desktop portal configuration. Do not replace those with Files.

For unsandboxed GTK applications, export `GTK_USE_PORTAL=1` in the desktop
session environment when needed to route native file-dialog calls through the
portal. Applications should use normal GtkFileDialog APIs:

```vala
var dialog = new Gtk.FileDialog();
dialog.title = "Open Document";
var filter = new Gtk.FileFilter();
filter.name = "Text Documents";
filter.add_pattern("*.txt");
var filters = new GLib.ListStore(typeof(Gtk.FileFilter));
filters.append(filter);
dialog.filters = filters;
var file = yield dialog.open(window, cancellable);
```

Use `open_multiple`, `select_folder`, and `save` for the other modes. Handle
GtkDialogError.DISMISSED as cancellation. The application writes content after
Save returns; the chooser itself does not overwrite or create the selected file.
Do not import private MajorisFiles classes into client applications.

Portal API and backend configuration were checked against the current upstream
[FileChooser backend specification](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.impl.portal.FileChooser.html)
and [portals.conf documentation](https://flatpak.github.io/xdg-desktop-portal/docs/portals.conf.html).

## Sharing foundation

The ISO must configure Samba usershares and the usershare directory/group,
`usershare owner only = yes`, an appropriate usershare limit, and guest policy.
The GUI does not rewrite smb.conf. Users require normal usershare group access.
Polkit action and system D-Bus service files are installed by Meson. Do not run
the GUI as root. Starting Samba is authorized graphically; passwords are passed
over the local system bus and Samba's stdin, never process arguments or logs.

The service does not yet manage an owned local-network firewall rule. Until
implemented, the ISO must provide its standard Samba LAN firewall policy.
The service must be tested with the actual Majoris firewall and Samba packages
before default installation. WS-Discovery remains an ISO component.

## Hardware and sandbox acceptance

Validate USB arrival/removal and eject, SMB discovery/authentication/read/write,
SFTP/WebDAV mounts, Flatpak document access to only selected files, portal parent
modality on X11 and Wayland, native GtkFileDialog routing, Samba ACLs and Polkit
denial, and media codecs on a disposable Majoris VM. Do not run acceptance tests
against personal data or modify the developer host's Samba configuration.
