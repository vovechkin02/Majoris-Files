# Majoris Files

Vala / GTK4 / libadwaita file manager and shared system file chooser for Majoris.

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
