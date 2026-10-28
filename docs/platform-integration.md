# Majoris platform integration

Use a stable Debian 13-compatible toolchain. `debian/control` is authoritative for
build/runtime dependencies. GTK >=4.18, libadwaita >=1.5, TinySPARQL >=3.8,
libportal >=0.7 and libheif >=1.19 are supported; timed AVIF additionally requires
libheif >=1.23. No experimental GNOME library is required. The supplied Majoris Theme universal
Toolbar revision (27 October 2026, 23:55:59 snapshot or later) must provide the
installed `majoris-ui-gtk4` 0.1.0+ package, including SONAME 0, VAPI/header and
pkg-config metadata. See [Toolbar integration](toolbar-integration.md).

```sh
meson setup build --prefix=/usr
meson compile -C build
meson test -C build --print-errorlogs
DESTDIR="$PWD/build/staging" meson install -C build
python3 tools/build-debian.py
```

The package builder uses a private Linux copy, runs the package tests, normalizes
DrvFs modes and returns unsigned artifacts/logs under `build/`. It installs nothing.

## ISO defaults

Install the package plus working GVfs/FUSE/network backends, document portal,
bubblewrap, UDisks, Avahi, graphical Polkit agent and keyring. Install appropriate
GStreamer codecs; base plugins are required, good/bad/libav recommended. Formatted
Office previews require LibreOffice and python3-uno. POSIX ACL editing needs `acl`;
register a terminal through `xdg-terminal-exec`. Search uses supported LocalSearch/
Tracker endpoints without opening private databases or starting an indexer.
Unknown coverage falls back to recursive GIO search.

Set the desktop identity to Majoris and select the installed `majoris-portals.conf`
FileChooser backend while retaining the desktop's other portal providers. The
public portal alone invokes the backend; the document service grants access.
Install `majoris-mimeapps.list` for inode/directory defaults. The ISO must avoid
competing `org.freedesktop.FileManager1` activation registrations when selecting
Majoris as its file manager. Omit Nautilus's application/default registration from
the target image as appropriate; do not indiscriminately remove GNOME libraries
or overwrite existing user MIME preferences. SearchProvider2 and Majoris desktop,
D-Bus, icon, policy and service registrations are packaged.

## Remote chooser contract

Usable GVfs/FUSE paths are returned as native filesystem URIs through document
portal mediation. Without that bridge, regular Open files may be explicitly
imported into retained storage. Default limit: 10 GiB / 30 minutes, configurable.
Imports check source stability, free space and cancellation; they never write back.
Remote Save/folder access without usable filesystem mediation is refused. SaveFiles
names are available names, not reservations. Real SMB/SFTP/WebDAV and Flatpak
fixtures are recorded in [status.md](status.md).

## Preview capability and isolation

Permit bubblewrap unprivileged namespaces. Image/document/metadata helpers receive
read-only input, trusted system libraries/fonts, private temporary storage, no home
or network, and resource/deadline limits. Office uses a private profile with macros
and updates disabled. Unavailable converters show capability errors or explicitly
label extracted-text fallback. RAW uses LibRaw; HEIF/AVIF uses libheif; ICC uses
LittleCMS. PQ/HLG is tone-mapped to SDR; no HDR display-output claim is made.

Playback decoders run in the sandbox worker. The GUI receives bounded raw RGBA/PCM,
with play/pause/seek, cancellation, startup/stall deadlines and child error handling.
The GUI audio sink renders raw PCM and does not demux/decode the input. Actual
speaker/GPU synchronization remains a hardware acceptance gate.

Cloud per-file and Nearby actions need explicit external providers. Account-only
libcloudproviders cannot establish file capabilities. See [cloud-files.md](cloud-files.md)
and [extensions.md](extensions.md); do not infer support from an account listing.

## Samba foundation and firewall

Provision `/var/lib/samba/usershares` with the intended usershare group, group write
and sticky bit (commonly root:sambashare mode 1770). Add intended users to that group
in the image/account provisioning workflow. Include the packaged
`/usr/share/majoris-files/majoris-samba-foundation.conf` inside Samba's global
configuration; review guest policy for the image. It enables registry shares,
owner-only usershares and a bounded count. Validate `testparm` before service start.
The GUI never rewrites administrator smb.conf or installs packages.

The service uses `/var/lib/majoris-files/share-visibility` mode 0700 to record owned
visibility overlays. Hidden means omitted from browsing, not access control. R/F/D
policies remain constrained by POSIX ownership/mode/ACLs. External changes refuse
blind overwrite. Never run the GUI as root. The installed Polkit policy requires
normal authorization for privileged changes.

Firewalld is optional and never automatically enabled. Only the exact owned
`majoris-files-sharing` policy may be changed; ingress is home/work only. Do not
silently classify untrusted networks into those zones. Administrator policies,
public zones and unmanaged nftables remain untouched. Last-share removal closes
the owned ingress or reports failure. WS-Discovery is an independent ISO component.
Real firewalld/Polkit runtime/permanent behavior requires the disposable VM gate.

## Reproducible service checks

Run these only inside the disposable namespaces required by the scripts:

```sh
# Requires root, iproute2, actual GVfs/FUSE and python3-paramiko.
unshare --net --mount --propagation private sh -c \
  'ip link set lo up; python3 tests/remote-services.py build/remote-check'
unshare --net --mount --propagation private sh -c \
  'ip link set lo up; python3 tests/remote-services.py build/remote-check --without-fuse'
# Extracted Samba package tree; script rejects host namespace/config paths.
unshare --net --mount --propagation private env MAJORIS_TEST_UID=1000 \
  MAJORIS_REMOTE_CHECK=build/remote-check \
  MAJORIS_FLATPAK_CLIENT=build/flatpak-client \
  MAJORIS_FLATPAK_HOST=build/flatpak-host \
  python3 tests/samba-visibility.py build/samba-tools/root build/visibility-check --server
unshare --mount --propagation private \
  python3 tests/disk-full.py build/replacement-crash-tests
```

These are controlled real-service checks, not a substitute for
[Majoris VM acceptance](vm-acceptance.md). See [release-matrix.md](release-matrix.md).
