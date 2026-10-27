# Majoris Files

Vala / GTK4 / libadwaita file manager and shared system file chooser for Majoris.

Majoris Theme is installed and activated by GNOME for both light and dark
appearances. Files loads only its own layout CSS and uses the installed theme’s
shared location-bar classes; it does not bundle or select a GTK theme.

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
