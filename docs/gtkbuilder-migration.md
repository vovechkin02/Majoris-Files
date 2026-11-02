# GtkBuilder migration report

The application now bundles 78 GtkBuilder resources, including 70 composite templates. Permanent interface composition lives in XML; the remaining runtime construction sites are enumerated individually in [the construction audit](ui-construction-audit.md).

## Component coverage

| Area | Result |
| --- | --- |
| Main window | Composite ApplicationWindow, ToolbarView/HeaderBar, one shared TabView, TabBar, TabOverview, recovery slot and header controls. |
| Browser | Permanent adaptive/sidebar/preview splits, native Grid/Details/Gallery views and scrollers, view stacks, empty/recovery states and status area are in browser.ui. |
| Toolbars/location | Shared Majoris.Ui.Toolbar constructors and supported append/group APIs remain; static controls, segmented switches, address/search/completion containers and static address menu are resource-defined. |
| Factories | Grid and List templates, reused for Columns/Gallery, metadata cells, filename editor, sidebar and tag rows. Existing SignalListItemFactory binding/unbinding and identity-based transactions remain. |
| Ordinary dialogs | Preferences (all eight pages), shortcuts, checksums, split, archive creation, batch rename, associations, prompt/password/ACL/SMB and Nearby send interfaces. |
| Properties/Tags | File and device properties, hardware subpage, multi-selection details, information/copy/identity/usage rows; manager, assignment, palette, editor and marker templates. |
| Operations/sharing | Operations window, list and job rows (including recovery/details/graph slots); sharing settings, account and shared-folder rows. |
| Preview | Permanent pane/error/download/fallback states; image/PDF/animation shells, media controls, text encoding/source view, Markdown shell, archive and Office fallback presentation, quick-preview window and conflict thumbnails. |
| Chooser/portal | Open/Save shell, permanent header/footer/progress/filename/filter controls, reusable request-choice rows; request options, validation, async imports, cancellation and responses remain Vala. |
| Static menus | Application sections, tab context, selection, custom-icon and address commands. Capability/clipboard/provider-dependent menus remain runtime models. |

## Resource and build integration

Resources retain `/com/majoris/files/ui/` paths. They are compiled into the shared core source set exactly once per binary, including core-only tests that use prompt/password dialogs, the main executable, portal and visual tools. GtkBuilder never reads repository-relative UI paths. Debian installation still ships the compiled executables/resources through the existing packaging. Debian and CI explicitly install `libgtk-4-bin`, which supplies the required native validator.

No Majoris.Ui.Toolbar ABI or Theme repository change was required. Constructing the shared Toolbar in Vala and populating XML controls through its public API preserves setup that ordinary GtkBuilder child packing would bypass. All application-specific CSS, its resource entry, `src/window/theme.vala`, and `FilesTheme.ensure()` were removed. Status presentation uses the existing shared `majoris-statusbar` contract.

Composite children use unowned GtkChild fields, GType registration and explicit template disposal. Native single-child properties are cleared before disposing their templates; signal callbacks guard shutdown, and owned cancellables stop work before child bindings are cleared. Constructor-independent wiring of nested widgets runs in construct blocks. Dependencies continue to be injected.

## Validation and evidence

- Build-time XML/resource/ID/property/parent/binding/callback/translation/CSS checks: 78 resources and 70 templates.
- Runtime resource fixture: registers all custom GTypes, constructs all templates, parses standalone resources and activates the real overview callback/window action ancestry.
- Native gtk4-builder-tool validation covers standalone Gtk/GMenu resources; composite and Adwaita resources are exercised with the registered application types.
- Gettext extraction was verified with xgettext; automatic language detection now extracts both Vala and XML. The previous global C# language override was removed.
- Existing tests remain enabled; structural tests now check XML and visibility rather than absence of permanently templated conditional children.
- Directory performance fixtures completed for 10,000 and 100,000 items (8.45 s and 79.77 s on this WSL environment). These exercise directory enumeration; they do not constitute a new UI scrolling benchmark.

Build and complete-suite results are recorded below after final verification.

### Native visual comparison

The committed pre-migration baseline (`448046f`) was built from `git archive HEAD` in an isolated temporary source directory. Both versions were captured with the actual adjacent Majoris-Theme, using the existing theme integration fixture: light/dark, 1×/2× and large-font settings, normal/narrow windows, all view modes and grid densities, long labels and the adaptive sidebar overlay. There are **84 before/after screenshot and widget-tree pairs** under `build/ui-migration-before/` and `build/ui-migration-after/`.

`python tests/ui-equivalence.py build/ui-migration-before build/ui-migration-after` passes all 84 pairs for headerbar, document tabs, toolbar/location/segmented controls, sidebar placement/width and shared file-tile geometry. `build/ui-migration-after/equivalence.json` records every comparison. Screenshots were also inspected visually.

The documented visual difference is the status area: the shared Theme statusbar is **34 logical pixels** high versus the former **26 pixels**, with shared typography replacing the Files-specific inset rule. The browser viewport changes by the corresponding 8 pixels. This comes from the existing central Theme contract, not replacement Files CSS or hard-coded status padding. Exact legacy status metrics would require a central reusable Theme variant; Files does not reproduce that styling locally.

Existing structural insets separating independent operation rows, device usage content and chooser footer actions were retained in XML. Redundant search-popover padding was dropped in favor of the native/shared popover presentation. Control styling, colors, typography, states and animations remain Theme-owned. Tag colors and rendered document/image content remain user data.

## Complete interface inventory

| Resource under data/ui/ | Composite type / purpose | Binding source |
| --- | --- | --- |
| `about.ui` | Standalone native/final-type controls or menu model | Resource-backed GtkBuilder construction/setup |
| `application-choice-row.ui` | `ApplicationChoiceRow` | `src/dialogs/ui-components.vala` |
| `application-launch-row.ui` | `ApplicationLaunchRow` | `src/dialogs/ui-components.vala` |
| `archive-preview.ui` | Standalone native/final-type controls or menu model | Resource-backed GtkBuilder construction/setup |
| `association-chooser.ui` | `AssociationChooser` | `src/dialogs/associations.vala` |
| `associations-dialog.ui` | `AssociationsDialog` | `src/dialogs/associations.vala` |
| `associations.ui` | `AssociationsPage` | `src/dialogs/associations.vala` |
| `batch-rename.ui` | `BatchRenameDialog` | `src/dialogs/batch-rename.vala` |
| `browser.ui` | `Browser` | `src/views/browser.vala` |
| `checksum.ui` | `ChecksumDialog` | `src/dialogs/checksum.vala` |
| `chooser-choice.ui` | `ChooserChoiceRow` | `src/views/item-widgets.vala` |
| `chooser.ui` | `ChooserWindow` | `src/chooser/window.vala` |
| `column-settings-row.ui` | `ColumnSettingsRow` | `src/views/item-widgets.vala` |
| `conflict-previews.ui` | `ConflictPreviewPair` | `src/preview/ui-components.vala` |
| `content-scroll.ui` | Standalone native/final-type controls or menu model | Resource-backed GtkBuilder construction/setup |
| `copy-properties-row.ui` | `CopyPropertiesRow` | `src/dialogs/ui-components.vala` |
| `destination-row.ui` | `DestinationRow` | `src/dialogs/ui-components.vala` |
| `device-hardware.ui` | `DeviceHardwarePage` | `src/dialogs/ui-components.vala` |
| `device-identity.ui` | `DeviceIdentity` | `src/dialogs/ui-components.vala` |
| `device-properties.ui` | `DevicePropertiesDialog` | `src/dialogs/device-properties.vala` |
| `device-usage.ui` | `DeviceUsageRow` | `src/dialogs/ui-components.vala` |
| `file-operations-view.ui` | `FileOperationsView` | `src/operations/presentation.vala` |
| `file-operations.ui` | `FileOperationsWindow` | `src/operations/presentation.vala` |
| `filename-cell.ui` | `FilenameCell` | `src/views/filename-cell.vala` |
| `grid-item.ui` | `GridFileItem` | `src/views/item-widgets.vala` |
| `list-item.ui` | `ListFileItem` | `src/views/item-widgets.vala` |
| `menus.ui` | Standalone native/final-type controls or menu model | Resource-backed GtkBuilder construction/setup |
| `metadata-cell.ui` | `MetadataCell` | `src/views/item-widgets.vala` |
| `metadata-details.ui` | `MetadataPage` | `src/metadata/details.vala` |
| `metadata-list.ui` | `MetadataList` | `src/preview/ui-components.vala` |
| `multi-selection-details.ui` | `MultiSelectionDetails` | `src/dialogs/ui-components.vala` |
| `navigation-controls.ui` | Standalone native/final-type controls or menu model | Resource-backed GtkBuilder construction/setup |
| `navigation-fields.ui` | `NavigationFields` | `src/views/item-widgets.vala` |
| `nearby-send.ui` | `NearbySendDialog` | `src/dialogs/ui-components.vala` |
| `operation-row.ui` | `OperationJobRow` | `src/operations/presentation.vala` |
| `password.ui` | `PasswordDialog` | `src/dialogs/prompt-widgets.vala` |
| `permissions-acl.ui` | `AclDialog` | `src/dialogs/ui-components.vala` |
| `permissions-dialog.ui` | `PermissionsDialog` | `src/dialogs/permissions.vala` |
| `permissions.ui` | `PermissionsPage` | `src/dialogs/permissions.vala` |
| `preferences.ui` | `PreferencesDialog` | `src/dialogs/preferences.vala` |
| `preview-animation.ui` | `AnimatedImageView` | `src/preview/animation.vala` |
| `preview-controls.ui` | Standalone native/final-type controls or menu model | Resource-backed GtkBuilder construction/setup |
| `preview-image.ui` | `ImageView` | `src/preview/sandbox.vala` |
| `preview-markdown.ui` | `MarkdownView` | `src/preview/archive.vala` |
| `preview-media.ui` | `MediaPreviewWidget` | `src/preview/ui-components.vala` |
| `preview-pdf.ui` | `PdfView` | `src/preview/pdf.vala` |
| `preview-plain-text.ui` | `PlainTextPreview` | `src/preview/ui-components.vala` |
| `preview-text.ui` | `TextPreviewWidget` | `src/preview/ui-components.vala` |
| `preview.ui` | `PreviewPane` | `src/preview/preview.vala` |
| `prompt.ui` | `PromptDialog` | `src/dialogs/prompt-widgets.vala` |
| `properties-row.ui` | `PropertiesInformationRow` | `src/dialogs/properties.vala` |
| `properties-subpage.ui` | `PropertiesSubpage` | `src/dialogs/ui-components.vala` |
| `properties.ui` | `PropertiesDialog` | `src/dialogs/properties.vala` |
| `quick-preview.ui` | `QuickPreviewWindow` | `src/preview/ui-components.vala` |
| `rename-preview-row.ui` | `RenamePreviewRow` | `src/dialogs/ui-components.vala` |
| `search-filters.ui` | `SearchFilters` | `src/search/filters.vala` |
| `section-heading.ui` | Standalone native/final-type controls or menu model | Resource-backed GtkBuilder construction/setup |
| `sevenzip.ui` | `SevenZipDialog` | `src/dialogs/sevenzip.vala` |
| `shared-folder-row.ui` | `SharedFolderRow` | `src/sharing/ui-components.vala` |
| `shared-folders.ui` | `SharedFoldersDialog` | `src/sharing/settings.vala` |
| `sharing-account-row.ui` | `SharingAccountRow` | `src/sharing/ui-components.vala` |
| `sharing-dialog.ui` | `SharingDialog` | `src/sharing/settings.vala` |
| `sharing-settings.ui` | `SharingPage` | `src/sharing/settings.vala` |
| `shortcuts.ui` | `ShortcutsDialog` | `src/dialogs/shortcuts.vala` |
| `sidebar-heading.ui` | Standalone native/final-type controls or menu model | Resource-backed GtkBuilder construction/setup |
| `sidebar-row.ui` | `SidebarRow` | `src/views/item-widgets.vala` |
| `smb-password.ui` | `SmbPasswordDialog` | `src/dialogs/ui-components.vala` |
| `split.ui` | `SplitDialog` | `src/dialogs/split.vala` |
| `tag-marker.ui` | `TagMarker` | `src/metadata/tags-dialog.vala` |
| `tag-name-editor.ui` | `TagNameEditor` | `src/metadata/tags-dialog.vala` |
| `tags-assignment-row.ui` | `TagAssignmentRow` | `src/metadata/tag-assignment-row.vala` |
| `tags-assignment.ui` | `TagAssignmentDialog` | `src/metadata/tags-dialog.vala` |
| `tags-manager-row.ui` | `TagManageRow` | `src/metadata/tags-dialog.vala` |
| `tags-manager.ui` | `TagsDialog` | `src/metadata/tags-dialog.vala` |
| `tags-palette.ui` | `TagPalette` | `src/metadata/tags-dialog.vala` |
| `value-row.ui` | `ValueRow` | `src/dialogs/ui-components.vala` |
| `view-settings.ui` | `ViewSettingsDialog` | `src/views/item-widgets.vala` |
| `window.ui` | `FilesWindow` | `src/window/window.vala` |

## Modified Vala sources

- `src/actions/nearby.vala`
- `src/chooser/window.vala`
- `src/dialogs/associations.vala`
- `src/dialogs/batch-rename.vala`
- `src/dialogs/checksum.vala`
- `src/dialogs/device-properties.vala`
- `src/dialogs/dialogs.vala`
- `src/dialogs/permissions.vala`
- `src/dialogs/preferences.vala`
- `src/dialogs/prompt-widgets.vala`
- `src/dialogs/properties.vala`
- `src/dialogs/sevenzip.vala`
- `src/dialogs/shortcuts.vala`
- `src/dialogs/split.vala`
- `src/dialogs/ui-components.vala`
- `src/metadata/details.vala`
- `src/metadata/tag-assignment-row.vala`
- `src/metadata/tags-dialog.vala`
- `src/operations/presentation.vala`
- `src/preview/animation.vala`
- `src/preview/archive.vala`
- `src/preview/office.vala`
- `src/preview/pdf.vala`
- `src/preview/preview.vala`
- `src/preview/sandbox.vala`
- `src/preview/thumbnail.vala`
- `src/preview/ui-components.vala`
- `src/search/filters.vala`
- `src/sharing/settings.vala`
- `src/sharing/ui-components.vala`
- `src/views/browser.vala`
- `src/views/filename-cell.vala`
- `src/views/item-widgets.vala`
- `src/window/extra-actions.vala`
- `src/window/theme.vala` (removed)
- `src/window/window.vala`

## Cleanup and runtime exceptions

Removed the procedural Preferences page/group/row construction helpers, shortcut row builder, SearchFilters entry builder and Browser search-option button builder. Permanent shell assembly, repeated item/cell/sidebar/tag/application/account/device/operation-row hierarchies and static menu arrays were removed from their original constructors. Settings helpers now bind existing XML rows; filesystem, model, validation and async logic remain in their original subsystems.

The remaining runtime sites are not exempted by whole component: [ui-construction-audit.md](ui-construction-audit.md) records all 146 individual toolkit construction sites and their responsibilities. They include models/factories/controllers, shared Toolbar setup, runtime breadcrumbs/completions, generated group headings, decoded artwork/Markdown content, backend/provider metadata sections, portal-supplied boolean choices and temporary native service/alert/toast objects. Repeated multi-widget data presentations are template-backed.

## Theme contract audit

Literal canonical class families were checked against the adjacent Theme sources: data/tile/cell/metadata/density classes in `design/templates/gtk4-data.css.in`, document tabs/statusbar in `gtk4-editor.css.in`, location classes in `gtk4-location.css.in`, sidebar headings in `gtk-sidebar.css.in`, and toolbar/segmented/control classes in `gtk-toolbar.css.in` and `ui/toolbar.vala`. The old `files-sidebar` identifier remains only as an existing semantic test/inspection hook. The obsolete `files-status` assignment was removed. No Files-specific stylesheet/provider or replacement theme rule was introduced.

### Final command results

- Debian WSL, GTK 4.18.6 and libadwaita 1.7.6: Meson configured and compiled successfully. All 34 suites passed with no skips or timeouts. After moving the last conditional device sections into XML, the device properties, sidebar actions and UI resource suites passed again.
- The 10,000- and 100,000-item directory benchmarks passed (8.45 s and 79.77 s). These fixtures exercise large-directory handling; they do not measure interactive scroll frame rates.
- Native captures with the adjacent Majoris Theme passed all 84 before/after geometry comparisons. The expected shared statusbar metric change is recorded separately. The capture matrix covers the main browser; it is not a pixel comparison of every dialog.
- The source and resource audits validated 78 interfaces, 70 composite templates and 146 remaining runtime construction sites. The theme ownership check passed.
