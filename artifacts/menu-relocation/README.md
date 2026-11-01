# Menu relocation verification

Meson setup/reconfigure and the complete build succeeded, including the Files executable and shared chooser integration. The final complete test run passed **24/24 suites**, with zero failures, skips or timeouts. See `tests-final.log` and `build/meson-logs/menu-relocation-verified.txt`.

The menu suite covers the six exact labels/action targets and native sections, disabled Reopen state, About/version, contextual selection and Templates visibility, originating-tab search/pattern operations, sidebar keyboard menus, Preferences action routing, password cancellation cleanup, hidden-tag fallback, normal operation controls, isolated Trash confirmation/cancellation/deletion/empty state, and both durable recovery types through restart, cancellation, success and failure retention. Existing inline creation, sorting, chooser, operation, replacement-crash, tag and device suites remain enabled.

The full themed UI scenario passed both tests; see `visual.log`. Fresh native-popover evidence and the durable recovery scenario also pass in `application-visual.log`. No tests empty real Trash or provision a real SMB password.

## Required visual states

Each state is saved in light and dark variants under `screenshots/`:

| State | Filename prefix |
| --- | --- |
| Six-entry application menu | application |
| Network sidebar context | network-sidebar |
| Trash sidebar context | trash-sidebar |
| Tag sidebar context | tag-sidebar |
| Preferences → Network → Sharing | preferences-network |
| Preferences → Tags | preferences-tags |
| Search Options / Save Search | search-options |
| File Operations without recovery | operations-no-recovery |
| File Operations with both recovery types | recovery |
| Writable background context | empty |
| Selected-item More Actions | more-actions |

There are 40 PNGs: the 22 required captures plus existing file contexts, About, View Settings, responsive overflow and device sidebar coverage. `contact-light.png` and `contact-dark.png` collect the required states. Both palettes were inspected for readable labels, separators, text-only entries, hidden submenu indicators, pointer-free popovers and unclipped recovery buttons. Network Preferences is scrolled to show both Sharing rows fully.

The environment uses Debian WSL, GTK/libadwaita, Xvfb/Openbox, Cairo, and the existing sibling Majoris Theme. Xvfb root screenshots omit some native popup surfaces and the long capture run emits Pixman rectangle diagnostics. Application/background/empty-operations popovers are therefore captured directly from their real GTK content widgets using WidgetPaintable/GSK; the application menu also has native widget allocation/label JSON. Other states use X11 root screenshots. No UI is mocked or restyled for these captures.

## Reproduce

From the repository in Debian WSL, after building:

```sh
dbus-run-session -- xvfb-run -a -s '-screen 0 1440x1000x24' bash artifacts/menu-relocation/capture.sh
```

The capture script runs the complete themed menu scenarios, then refreshes the native-popover/Sharing evidence and contact sheets. `MAJORIS_MENU_APPLICATION_ONLY=1` selects only the fresh-window evidence scenario; ordinary Meson tests do not set this variable and execute every normal scenario.

Live SMB provisioning, external-server sessions and external terminal startup were not exercised. Their existing backends and safe argument-based terminal launch remain in place. No Files CSS or Majoris Theme files changed.
