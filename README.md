# Majoris Files

Vala / GTK4 / libadwaita file manager and shared system file chooser for Majoris.

Majoris Theme is installed and activated by GNOME for both light and dark
appearances. Files loads only its own layout CSS and uses the installed theme’s
shared location-bar classes and the installed `majoris-ui-gtk4` Toolbar library; it does not bundle or select a GTK theme.

Build prerequisites include GTK4 **4.18+** and the Majoris Theme **0.1.0+**
`majoris-ui-gtk4` package (SONAME 0, public VAPI/header and pkg-config metadata).
Toolbar appearance belongs to the activated Theme; Files owns actions and overflow.
See [Toolbar integration](docs/toolbar-integration.md) for the migration and checks.

```sh
meson setup build --prefix=/usr
meson compile -C build
meson test -C build --print-errorlogs
./build/majoris-files
```

See [platform integration](docs/platform-integration.md) for dependencies, portal
routing and Samba provisioning; [architecture](docs/architecture.md) for service
and security boundaries; and [implementation status](docs/status.md) for changes,
executed checks, dependencies and remaining limitations.

The implemented feature set has automated regression and isolated real-service
coverage. [Majoris VM acceptance](docs/vm-acceptance.md) and hardware/provider
verification remain production release gates. Build an unsigned Debian package
without installing it using `python3 tools/build-debian.py`.

The shared GTK component requirements, measured dimensions and native validation evidence are documented in [Theme integration](docs/theme-integration.md).

The remaining Details section, metadata and focus investigations are documented in [Details corrections](docs/details-corrections.md).
