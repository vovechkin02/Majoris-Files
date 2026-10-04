# Majoris Files

Vala / GTK4 / libadwaita file manager and shared system file chooser for Majoris.

```sh
meson setup build --prefix=/usr
meson compile -C build
meson test -C build --print-errorlogs
./build/majoris-files
```

See [platform integration](docs/platform-integration.md) for dependencies,
portal routing, GTK client examples and Samba setup;
[architecture](docs/architecture.md) for service and security boundaries;
and [implementation status](docs/status.md) for outstanding requirements.

This initial implementation builds and has automated core, filesystem, UI and
D-Bus tests. It does not yet satisfy the full supplied production specification.
