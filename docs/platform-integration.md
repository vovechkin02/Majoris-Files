# Majoris platform integration

Build on Debian 13 or a compatible stable Majoris toolchain. Required development
packages are listed in `debian/control`, including GtkSourceView 5, TinySPARQL 3.8,
GStreamer base development libraries and GExiv2. GTK >= 4.12, libadwaita >= 1.5,
libportal >= 0.7 and Meson >= 1.6 are required. Do not mix development GNOME packages
into an otherwise unsupported distribution.

```sh
meson setup build --prefix=/usr
meson compile -C build
meson test -C build --print-errorlogs
DESTDIR="$PWD/build/staging" meson install -C build
```

The image needs GVfs/FUSE/network backends, Samba/smbclient/cifs-utils, Avahi,
UDisks, a graphical Polkit agent, a secret-service keyring, xdg-desktop-portal
including the document portal, bubblewrap and suitable codecs. 7-Zip provides
native encrypted/multipart creation. Formatted Office rendering additionally
requires LibreOffice Writer/Calc/Impress and python3-uno. System content indexing
uses LocalSearch/Tracker's FileSystem and Documents endpoints; no indexer is started
or its private database accessed directly. Without an index service, recursive GIO
search remains available. Install `acl` for advanced POSIX ACL editing and register
the intended terminal with `xdg-terminal-exec`.

## Chooser and document access

Meson installs `majoris.portal`, `majoris-portals.conf` and the D-Bus backend service.
The desktop must select Majoris for `org.freedesktop.impl.portal.FileChooser`, while
retaining its other portal providers. The application exports the backend interface,
not the public portal API. Only the current public portal owner can invoke it.
xdg-desktop-portal and its document service register/grant returned files.

Native and usable GVfs/FUSE paths are returned through that mediation. Unsupported
remote regular Open files can be explicitly imported into retained application
storage. The default limit is 10 GiB with a 30-minute timeout; preferences configure
1–1024 GiB and 1–1440 minutes. Free space and source stability are checked. Pending
transfers are private and abandoned transfers are cleaned; successful imports are
retained so a receiving app does not lose its backing file on chooser closure.
Imports do not write back. Remote Save/folders without usable filesystem mediation
are refused; no local-only save is reported as a remote success. SaveFiles returns
ordered available destination names, not reservations.

See [the release matrix](release-matrix.md) for actual public portal and Gtk.FileDialog
Flatpak fixture commands. Local X11 Flatpak success does not verify real remote
backends, Wayland/X11 external parent focus, device removal or concurrent callers.

## Preview isolation and optional formats

Allow bubblewrap's unprivileged namespaces under the image security policy.
`majoris-files-preview-helper` has read-only input, trusted system libraries/fonts,
private temporary storage and no home or network. Ordinary helpers have 768 MiB
address space, 10-second CPU and 15-second parent timeout budgets. At most four run
concurrently. Office conversion uses 2 GiB, 30-second CPU, 60-second parent timeout,
private output and an explicit no-macros/no-update UNO load. Its installed trusted
script is `majoris-files-office-render.py`; output is bounded to 64 MiB.

Unavailable sandbox/decoder/converter capability reports an unavailable preview or
an explicitly labeled extracted-text fallback. Animated WebP and less common image
formats require appropriate installed system decoders. HDR/color-managed RAW paths
are not complete. GtkMediaFile playback still needs decoder isolation; existing
thumbnail-cache PNG decoding and archive worker parsing also need their remaining
security/acceptance audits. Remote preview defaults to explicit download and has
separate configurable size/policy controls.

## Graphical Samba and firewall

The ISO must provision the usershare directory/group, `usershare owner only = yes`,
an appropriate usershare limit, guest policy and normal usershare group access.
The GUI does not rewrite smb.conf or install packages. System-wide administrator
shares remain administrator managed. The Polkit service starts only fixed smbd.service,
provisions only the calling account's SMB password through stdin, and exposes
bounded caller-owned-share client status. Never run the GUI as root.

Per-account R/F/D access is separate from filesystem ownership/mode/ACL restrictions.
Mixed ACLs are preserved and external changes require reload before editing. True
per-share non-browseable policy is still missing. Windows effective permissions
and user/guest combinations must be verified on a disposable server.

The optional firewalld integration does not enable the daemon. It only changes the
bundled `majoris-files-sharing` policy after validating its exact ownership marker,
services, target, priority and allowed zones. It enables Samba ingress only from
home/work and egress to HOST. It never opens public zones or rewrites administrator
policies. Last-share removal attempts to clear the owned ingress; failures are
reported. Other firewall backends display an unsupported result. The ISO must not
silently classify an untrusted network as home/work. WS-Discovery is a separate
image component. Real firewalld/Polkit behavior remains an acceptance gate.

## Desktop and release acceptance

SearchProvider2 registration is installed under GNOME Shell search-providers and
uses the Majoris application bus name. FileManager1, desktop wallpaper/email portals,
UDisks and Nearby provider interfaces remain available. User extensions are opt-in;
see [the external protocol](extensions.md). Build with `-Dexample_extension=true`
only when the checksum example is wanted; it additionally needs python3-gi.

Validate in a disposable Majoris VM: Windows SMB access/enforcement, real firewall
rule lifecycle and denial, large SMB Open, remote writable Save and disconnect,
parent modality/focus on X11 and Wayland, USB removal in every chooser state,
real MP4 audio, formatted DOCX/XLSX/PPTX, cloud materialization, shell activation,
100 GB split/join/checksum, full keyboard/screen reader and large view workloads.
See [the completion matrix](release-matrix.md) for exact incomplete code paths as
well as verification gaps. This tree is not yet approved as the production default.

For an unsigned binary package build, run `python3 tools/build-debian.py` from a
Linux/WSL environment after installing build dependencies. It builds and tests a
private temporary Linux copy, preserves logs and `.deb` artifacts under `build/`,
and installs nothing. This avoids DrvFs permission emulation preventing dpkg from
validating its control directories. Debian files and scripts retain LF via
`.gitattributes`.
