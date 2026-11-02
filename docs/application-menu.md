# Application menu and contextual commands

The application More menu has two native sections:

- New Window (`app.new-window`), New Tab (`win.new-tab`), Reopen Closed Tab (`win.reopen`).
- Preferences… (`win.preferences`), Keyboard Shortcuts (`win.shortcuts`), About Files (`win.about`).

Reopen stays visible and is disabled when closed-tab history is empty. About Files uses `Adw.AboutDialog`, the Meson project version, and the existing app icon, developer, GPL licence, website and issue tracker metadata.

| Command | Destination |
| --- | --- |
| Duplicate Tab | Existing tab context menu |
| New Folder / New File | Writable folder background context; existing inline creation |
| New Document from Template… | Writable folder background context, with usable XDG Templates |
| Show Hidden Files | Current folder View Settings and Ctrl+H; global default stays in Preferences → View |
| Preview Pane | Existing Preview toolbar control and Preferences → Preview |
| Sorting / descending | Sort toolbar, Details headers, View Settings and background Sort menu |
| Save Search… | Search Options, with native text-labelled scope/filter controls, enabled for an active query; query/location captured before naming |
| Select All / Pattern / Invert / None | Background Selection… and selected-item More Actions → Selection… |
| Batch Rename / Create Link | Existing selected-item menus, subject to context checks |
| Open in Terminal | Native folder/background context; argument-based process launch |
| Connect to Server… | Network sidebar context and Network background |
| Shared Folders… / SMB Account Password… | Preferences → Network → Sharing; existing workflows |
| Manage Tags… | Assignment dialog, tag sidebar and heading context, Preferences → Tags fallback |
| Restore / Delete Permanently | Selected items in Trash |
| Empty Trash… | Exact built-in `trash:///` sidebar destination, including keyboard context menus |
| Recover interrupted batch rename / preserved replacements | File Operations recovery rows; startup Review banner |

The narrow File Actions overflow remains separate from application More. It has contextual file controls without duplicate sorting or a redundant Share submenu. Existing actions, shortcuts, operation services and storage schemas remain in place.

File Operations binds stable rows to jobs. Normal jobs retain progress, Cancel and Retry Remaining Items. Recovery rows offer native Review/Recover controls and disappear when durable journals are resolved. Cancel and failure retain recovery data. One window-level native banner opens File Operations and deduplicates unchanged recovery state across tabs.

Empty Trash enumerates asynchronously before confirmation. Empty state is reported without a destructive prompt; enumeration failures are reported. Confirmed deletion still runs through OperationManager. Regression tests only enumerate/delete isolated temporary directories and never activate real Trash deletion.

All added menus use native text-only GMenu models; popovers have no pointers. No Files CSS or Majoris Theme changes are part of this refactor.

## Implementation files

- `src/window/window.vala`: six-entry menu, About, action availability, contextual relocation, captured saved searches, window recovery banner, reusable Preferences/Tags dialogs.
- `src/window/extra-actions.vala`: retained actions, Select All, cached asynchronous Templates availability, originating selection/destination capture, asynchronous Trash workflow, reusable sharing dialog, password cancellation cleanup.
- `src/views/browser.vala`: Search Options, per-folder hidden setting, native View Settings row, contextual narrow overflow, sidebar pointer/keyboard menus and Tags heading.
- `src/dialogs/preferences.vala`: Network Sharing and Tags management entry points using window action lookup.
- `src/operations/presentation.vala`: stable normal/recovery job rows and compact empty state.
- `src/operations/manager.vala`: journal-driven recovery notices, availability and durable state signature.
- `src/operations/replacements.vala`, `src/operations/rename-recovery.vala`: change signals after durable journal updates; restoration safeguards retained.
- `src/application/build-info.vala.in`, `meson.build`: generated project version and UI source wiring.
- `po/POTFILES`: new translatable presentation source.
- `tests/menus.vala`: application inventory, contextual/keyboard state, originating-tab selection/search, isolated Trash and durable recovery checks.
- `docs/tags.md`, `docs/tags-implementation-report.md`: current tag-management entry points.

That menu-relocation change did not alter Majoris Theme, the sharing service, tag schema, or chooser protocol. The subsequent [GtkBuilder migration](gtkbuilder-migration.md) removed Files-specific CSS entirely.

## Verification and limits

The final Meson setup and complete build passed. The complete final regression run passed **24/24 suites**, with zero failures, skips or timeouts (`artifacts/menu-relocation/tests-final.log`). This includes the primary UI/chooser integration, inline creation and rename, sorting, operation/crash recovery, tags, Properties, device, toolbar and grid-caption suites. The expanded menu tests exercise the relocated commands and safe isolated recovery/Trash fixtures.

Majoris Theme light/dark verification includes all 11 requested states, plus About, View Settings and adaptive/file contexts. See `artifacts/menu-relocation/README.md`, the 40 screenshots and both contact sheets. The required popovers are native GTK captures; three popup types use direct WidgetPaintable/GSK captures because the Xvfb root grab omits their native surfaces. Sharing is captured after scrolling its Preferences page so both rows are visible.

No existing action registrations were removed. About and Select All were added; existing keyboard accelerator registrations and operation services remain available. Live external-server sessions, SMB password provisioning and terminal startup were not performed during validation. There are no known remaining implementation gaps; the capture environment limitation is documented with the evidence.
