# Sidebar context-menu repair

## Confirmed diagnosis

The original failure was reproduced through a rendered `GtkModelButton`, not by
calling a GAction directly. The original menu item was sensitive, showing that its
`place.open` action resolved while the popup was open. Activation emitted the
popup's close signal and immediately unparented it; the Open action callback never
ran and the browser did not navigate.

Recorded baseline (`artifacts/sidebar-actions/before.txt`):

```text
GTK activation item=GtkModelButton sensitive=true
popover parent changed: none
popover closed parent=none
result commands=0 navigated=false
```

After the repair, the same test records the popup closing while still parented,
then `dispatch open target=file:///`, exactly one callback and successful
navigation. Attaching an action group to a popover was not independently proven
invalid: the verified failure was destruction of its action context during GTK's
close-before-dispatch activation sequence.

The cloud fixture also exposed a separate issue: a static text-only copy could
lose lazily populated D-Bus submenu contents. A live model projection now forwards
provider changes instead of discarding an initially empty remote submenu.

## Dispatch, popup ownership and targets

Each Browser owns one `place` SimpleActionGroup, installed on its persistent
sidebar. The group contains Open, Open in New Tab, Mount, Unmount, Eject and
Properties handlers, registered once. It does not replace the owning window's
`win` action group.

One reusable, arrow-free GtkPopoverMenu remains parented to that sidebar. Closing
does not unparent it. On the next main-context turn, it releases the clicked Place,
focus anchor, provider action group and menu model. Deferring that context cleanup
is intentional: GtkModelButton closes before it dispatches. Opening a new menu
cancels obsolete cleanup. Browser cancellation/unroot cancels pending device work;
disposal unparents the popup.

Commands copy the clicked Place before starting asynchronous work. They never
resolve a target by row number or by the current file selection. Availability
checks compare volume/drive/mount objects, tag IDs, cloud-account objects and file
URIs as appropriate. Volume and mount rows are reconciled through the same GVolume,
so a successful mount may replace its sidebar row without redirecting or losing
the pending Open action. Empty-drive discovery can likewise resolve through that
drive's new volume rows. Rebuilds dismiss the popup, while started work retains its
original target. Removed targets fail safely.

Focus anchors remain owned only through deferred dismissal cleanup, avoiding a
stale widget pointer when rows are rebuilt. Properties callbacks use GWeakRef for
the Browser/dialog slot. Existing Properties dialogs can be presented again for
the same selected device. Cancellation and missing roots prevent an asynchronous
mount from opening a tab in another window after its source Browser is closed.

## Navigation and devices

`SidebarLocations.resolve()` is shared by row activation, Open, Open in New Tab
and Mount. It checks an existing mount before can_mount, mounts through GIO with a
parented GtkMountOperation where needed, waits for completion, then returns the
actual mount root. Ordinary locations and existing mounts share a synchronous
fast path, preserving immediate row activation even before a Browser is rooted.
It rejects synthetic device URIs as browsing destinations.
Mount-only activation does not navigate or create a tab.

Mounted and mountable volumes offer both navigation commands. Read-only status
does not disable navigation. Empty optical drives expose supported Eject and
Properties commands; tape entries expose Properties. A drive with multiple
accessible volumes opens an Adw.AlertDialog selection rather than choosing the
first volume. Ordinary virtual locations keep their existing navigation handling.
Chooser sidebars do not advertise unsupported tab/window commands.

Unmount/Eject recheck the selected device's live capabilities and use the selected
mount, volume or drive's supported GIO method. Root/System Drive checks apply in
both menu availability and execution. Existing GVolumeMonitor inventory updates
remain authoritative; no new device monitor or storage backend was added.

Device Properties uses the existing DevicePropertiesDialog and read-only device
information provider, presented through the rooted owning window. The hardware
information, media identification, storage statistics, Hardware Details and
existing disconnection handling were not rewritten.

## Window, tag, Trash and cloud commands

Network's Connect to Server, Trash's Empty Trash and tag Manage Tags actions retain
their existing `win.*` handlers. The Tags heading uses the same stable popup and
supports pointer and keyboard invocation. Empty Trash remains in the Trash
context menu, with its existing confirmation/deletion backend.

Cloud commands keep their original action identities, targets, enabled states and
submenus. The selected account's action group is installed under `cloudprovider`
on the sidebar, then detached after dismissal. The live text-only MenuModel strips
icons, preserves action parameters and forwards asynchronous item changes through
nested provider models. The related cloud-account menu in Other Locations uses
the same projection, retaining its existing explicit namespace aliases.

All menus remain native, vertical, text-only and arrow-free under Majoris-Theme.
No CSS, custom menu button list, hardware-query backend or dependency was added.

## Verification

`tests/sidebar-actions.vala` opens real sidebar popups with X11 pointer events,
finds rendered GtkModelButtons and activates those widgets. It also uses Menu,
Shift+F10, Return and Escape key events. It asserts dispatch counts and clicked
identities, navigation, tab counts, dialog types, focus restoration and mock device
mutation counts. GTK criticals fail the test.

Coverage includes:

- System Drive, ordinary folders, Recent, Favorites, Network, Trash and tag navigation.
- Open and exactly one new tab, including unmounted and already-mounted volumes.
- Volume-to-mount row replacement during mounting, failed mounts without empty tabs,
  multi-volume drive selection, and closing a tab while mounting is pending.
- System, mounted/unmounted, internal/removable/card/floppy/optical and tape Properties;
  Properties must not perform device mutations.
- Mount without navigation, Unmount, selected mount Eject and selected drive Eject.
- Network connection dialog, both Tags context menus, and cancelled Trash confirmation.
- Real exported CloudProviders accounts, parameters, disabled commands, live submenus,
  switching between accounts, and disappearing sidebar accounts.
- Repeated popup reuse, sidebar rebuilding, multiple tabs and separate Files windows.

`tests/sidebar-actions-session.py` gives the GTK regression a private HOME,
configuration, data, cache, Trash and D-Bus session. Device mutations use GIO
interface fixtures only. No host device is unmounted/ejected. The Trash fixture is
never emptied through the UI. Existing device-information and integration tests
remain in place.

Final results:

| Check | Result |
|---|---|
| Meson reconfigure | Passed |
| Complete application/test build | Passed |
| Full 26-suite run | 25 passed; the existing unrooted System Drive UI test caught a regression |
| Final UI rerun after the shared fast-path fix | Passed, including all 30 UI cases |
| Final sidebar activation/lifecycle rerun | Passed, 102.47 seconds, with GTK criticals fatal |
| Diff whitespace check | Passed |

The other 24 existing suites and the new sidebar suite passed in the full run.
Both affected suites passed again after fixing the immediate navigation regression.
There are no unresolved failures from the final rerun. No failing test was removed
or weakened. The complete suite was not repeated after that final narrow fix.

Build/test commands and final results are recorded in:

- `build/sidebar-configure.log`
- `build/sidebar-full-build.log`
- `build/sidebar-full-tests.log`
- `build/sidebar-final-build.log` and `build/sidebar-final-tests.log`
- `artifacts/sidebar-actions/full-suite-results.json` and `final-rerun-results.json`
- `artifacts/sidebar-actions/activation.log`

## Changed files

- `src/views/browser.vala`: stable actions, popup/target lifetime, shared navigation,
  valid Properties parenting, cancellation and keyboard/heading integration.
- `src/sidebar/location.vala`: shared destination, identity and capability resolution.
- `src/actions/registry.vala`: live text-only provider menu projection.
- `meson.build`: resolver source and the GTK activation regression.
- `tests/sidebar-actions.vala`, `tests/sidebar-device-fixtures.vala`,
  `tests/sidebar-actions-session.py`: real activation and isolated fixtures.

## Verification limits

Physical USB, optical, floppy and tape devices were not mounted, unmounted or
ejected. Hardware-specific authentication, busy-device failures and physical
hotplug behavior remain dependent on the installed GIO/GVfs backends. Device
operations and lifecycle cases were exercised with controlled interface fixtures;
existing device-information tests cover the provider's read-only interpretation.
The GTK activation checks are automated integration tests, not a claim of manual
hardware testing.
