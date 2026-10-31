# Menu implementation and validation report

Implemented in Majoris-Files and the adjacent Majoris-Theme repository.

1. **Main menu:** native vertical sections for Open / Open With / Preview;
   Cut / Copy / Rename / Move to Trash; dynamic Favorites / Tags; More Actions;
   Properties. There is no horizontal strip, action icon or heading.
2. **More Actions:** Duplicate, Copy To, Move To, New Folder with Selection,
   Create Link; Compress, Checksums, Split/Join; applicable image Quick Actions,
   User Actions and provider-capability cloud commands. Empty groups are omitted.
3. **Context:** folders use Open in New Tab and supported Share; archives add
   Extract near Open; multiple selections use Batch Rename and omit opening
   commands. Trash offers Restore/Delete Permanently/Properties. Empty space
   has destination/display/location controls, with creation/paste hidden in
   read-only and virtual locations. Pointer targeting preserves a clicked
   multi-selection and clears stale selection on empty space in all four views.
4. **Properties:** advanced Permissions, General/Open With/Change, and Sharing
   remain available. A compact identity-area Icon menu sets/resets the persisted
   custom icon. Their existing standalone action registrations are preserved.
5. **Archives:** one extended SevenZipDialog exposes format, name, destination,
   supported encryption, 7z volume size and compression level. Inapplicable
   controls are disabled. Extraction uses one destination workflow and requests
   a password after an authentication-related backend error. Existing
   ArchiveService/SevenZip validation, isolation and no-overwrite behavior remain.
6. **Icons:** Files models contain text actions. Recursive provider adaptation
   removes icon attributes while preserving targets, parameters, nested links
   and action-group behavior. Theme factory/helper rows no longer reserve an
   icon column. File-view, sidebar and toolbar-button icons are preserved.
7. **Submenu arrows:** reusable rules in Majoris-Theme's canonical GTK3/GTK4
   templates suppress native menu-arrow nodes. GTK4's realized hierarchy and
   zero-width arrow allocations were checked. Submenu links remain native.
8. **Popover pointers:** directly owned menu popovers use has_arrow=false;
   MenuButton-generated popovers receive the same setting. MenuButton direction
   NONE hides redundant button arrows. Theme rules cover internally owned menu
   pointers, including tab menus.
9. **Theme:** templates, generated light/dark GTK3/GTK4 CSS, native menu tests,
   factory menu fixture/row and the shared Python row helper were updated.
   Generated CSS was produced by tools/generate-theme.py. Files CSS is unchanged.
10. **Other menus:** sidebar devices and locations now use native MenuModels
    and scoped action groups. System devices cannot expose Eject. Application,
    toolbar overflow, Sort, Share, address and tab menus retain native semantics
    and receive the shared text/arrow presentation contract.
11. **Keyboard/accessibility:** native action/submenu relationships, targets,
    state indicators and shortcuts are preserved. tests/menu-keyboard.py verifies
    actual Right/Left submenu navigation and Escape with the generated Theme. The Files test invokes Menu
    and Shift+F10 and verifies Escape dismissal and repeated invocation. Context
    keys are handled in capture phase, excluding editors. The original invoking
    widget regains focus when the menu closes. Theme fixtures exercise native
    keyboard movement/activation/dismissal, radio/check and disabled states.
    Live screen-reader announcement testing still requires a desktop session.
12. **Files changes:** meson.build; src/window/window.vala;
    src/window/extra-actions.vala; src/views/browser.vala;
    src/actions/registry.vala; src/models/directory-model.vala;
    src/extensions/manager.vala; src/dialogs/properties.vala;
    src/dialogs/sevenzip.vala; tests/properties.vala; tests/menus.vala; tests/menu-keyboard.py;
    tools/capture-menus.py; docs/menus.md and this report.
13. **Build:** Meson reconfiguration and compilation succeeded in Debian WSL
    with GTK 4.18/libadwaita 1.7. Existing compiler warnings remain. git diff
    --check passes. No changes were made to the user's existing ZIP files.
14. **Tests:** the sequential Files suite passed **19/19**. The expanded final
    menu test passed separately, covering all four pointer-targeting modes,
    mixed Favorites, provider model adaptation, cloud capability filtering,
    read-only and virtual locations, Trash, and keyboard invocation. Theme's
    initial parallel suite passed 130/133; its three display-sensitive failures
    all passed sequential reruns. All eight GTK3/GTK4 light/dark 1x/2x native menu
    cases and the menu source contract passed after the menu-helper changes.
    Native screenshots are in artifacts/menu-integration/{normal,2x,large-text},
    with light/dark file, folder, image, archive, multiple-selection, empty-space,
    More Actions, sidebar device, application and overflow captures. The capture
    runner also asserts native submenu activation and collapsed arrow width.

Remaining platform validation: live provider authentication and sync, remote
server permissions, physical device hotplug/unmount/eject, and real screen-reader
announcements. No such services/devices were available in the WSL fixture session.
The final theme must be packaged/deployed with Files to supply the arrowless
submenu presentation; no application-local styling fallback was added.
