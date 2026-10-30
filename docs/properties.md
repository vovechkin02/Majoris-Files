# Properties

General is the sole main page of the existing `Adw.PreferencesDialog`. It shows
an icon or an existing-service thumbnail, a copyable location, concise modified
date, folder contents or combined size, the default application for a single
file, Favorites and Tags. Technical attributes are in Details. Ordinary files
have no “Items: 1” or recursive Contents calculation.

Open With is embedded in General. Change opens a searchable application chooser
with grouped single-selection rows, one Set Default action and a secondary Reset
to System Default action in a fixed native footer. Both actions remain visible
while the application list scrolls. Installed application availability and URI support are
checked. GIO updates the MIME association; this workflow never launches the file.
The separate one-time Open With command remains available.

Sharing, Permissions and Details are contextual rows. They push cached
`Adw.NavigationPage` instances through `PreferencesDialog.push_subpage()`; native
Back, Alt+Left and gestures use the dialog's own navigation stack. There is no
second NavigationView and no permanent section tab bar. Cached page instances
preserve pending edits when going back. Opening a page or closing the dialog
never applies permissions or publishes a share.

## Shared service boundaries

- Sharing still uses `SharingManager` and the existing privileged D-Bus helper.
  Its switch reveals configuration; publication requires Share Folder. Account
  access is expandable; guest access, visibility, firewall actions, reload and
  client inspection are under Advanced Sharing Settings. Mixed account rights
  show Custom Access. Guest restrictions and Stop Sharing confirmation remain.
  The monitor detects path/ACL/guest/visibility changes and blocks stale editing
  until Reload. It stops when the owning dialog closes.
- Permissions still uses `PermissionService`. Basic choices use explicit bit
  masks, preserving unrelated file execute and special bits. Folder choices
  include traversal permission. Extended ACLs use the advanced editor rather
  than misleading simplified choices. Missing ACL tools produce a safe advanced
  fallback. Octal modes through 7777, the R/W/X matrix, numeric UID/GID, account
  selectors, ACL editing, separate file/folder modes and confirmed recursion
  remain available. Apply is explicit and disabled until a proposal changes.
  Successful operations requery actual modes and ownership, including Details.
- Details retains independent asynchronous cloud, rich-media and extension
  providers. Provider failure does not suppress the other sources. File
  information and raw filesystem attributes are expandable; storage, Image,
  Camera, Audio, Video, Cloud, Additional Metadata and Extension Properties appear
  when relevant. Unknown fields and existing payload limits are retained.
- Favorites and Tags use the existing MetadataStore. Bulk favorites snapshot the
  requested state before metadata notifications. Bulk tag replacement requires
  explicit confirmation in its editor. No bookmarks or parallel database exists.
- FileCounts remains the asynchronous counting service. Directory roots are
  excluded from their own displayed child counts. Cancellation, partial totals
  and physical allocation availability are respected. Unknown sizes and disk
  allocation are labelled unavailable, not invented as zero/capacity.

The dialog snapshots the supplied selection and never reads a later Browser
selection. Single symbolic links retain their target information and are not
recursively counted as their target directory. Unsupported/remote permissions
are informational; Sharing is excluded for unsupported selections, system roots,
mount roots and symbolic links. No disk-management functionality was added.

## Source organisation

`src/dialogs/properties.vala` owns composition, snapshots, summaries, cancellation
and native navigation. All former `Dialogs.show_properties` call sites now use
`PropertiesDialog.present_selection`, including the file-manager D-Bus entry.
`dialogs.vala` remains a core utility with no dependency on Properties UI types.
Its prompt helper gained an optional explanatory body for the compact Tags editor.

Reusable PermissionsPage, SharingPage and MetadataPage content remains usable by
existing standalone workflows. Embedded pages retain work across Back navigation;
the coordinator cancels their requests and timers on final close. Only one
instance of each subpage is created per Properties dialog.

Modified production/build files:

- `src/dialogs/properties.vala` (new coordinator)
- `src/dialogs/dialogs.vala`, `permissions.vala`, `associations.vala`
- `src/metadata/details.vala`, `src/sharing/settings.vala`
- `src/operations/permissions.vala` (masked modes and explicit special-bit support)
- `src/models/counts.vala`, `accounts.vala`, `file-item.vala`
- `src/window/window.vala`, `src/application/file-manager.vala`
- `meson.build`, `po/POTFILES`

The account parser now handles empty descriptions. Optional GFile display-name,
content-type, icon and timestamp attributes have safe fallbacks. No application
colors, radii, shadows, theme selectors or new Properties CSS were added.

## Verification

See [Properties verification](properties-verification.md) for exact executed
checks, screenshot locations and the remaining environment-dependent limits.
