# Media-family recognition completion report

The complete [identifier mapping and architecture](../../docs/media-recognition.md)
are documented separately. All screenshots and storage measurements here use
injected fixtures, not physical media.

| Requested area | Result |
| --- | --- |
| 1. Families | USB thumb drives, all documented flash-card families, conventional floppy, Zip/Jaz cartridges and all documented optical families. |
| 2. Identifier mapping | All **35** identifiers have central gettext descriptions; see the complete table in the implementation guide. |
| 3. Categories | Added `MEMORY_CARD` and `REMOVABLE_CARTRIDGE`. Existing categories and protected system/tape/image/portable precedence remain. |
| 4. Current versus compatible | Current media supplies the format description. Compatibility describes supported formats/readers, never proof of inserted media. Presence remains present/absent/unknown. Fixed MMC is not automatically a removable card. |
| 5. Sidebar | Suitable GIO icons and all GIO labels remain. Theme-checked family fallbacks update existing row widgets through an incremental presentation signal. Existing identity/deduplication rules remain. |
| 6. Properties | Existing dialog shows readable Type, Media type, media presence and Supported media; Hardware Details retains all existing identifiers and relationships. No independent media dialogs or CSS were added. |
| 7. Optical/cartridges | Zip/Jaz are distinct from floppy. Optical descriptions include DVD-RAM, HD DVD, magneto-optical and Mount Rainier capabilities. Capabilities never become inserted-disc labels. Mounted optical filesystem capacity does not require a track count. |
| 8. Unknown formats | Known family prefixes have generic descriptions; other formats use Unknown media and the hardware-derived generic category. Raw identifiers are retained. No speculative format identifiers or capacities exist. |
| 9. Changes | One shared event-invalidated ObjectManager snapshot serves the inventory and dialogs. Cancellation/generations reject stale replies. An original reader can adopt its single inserted volume; replacement drive objects cannot inherit the selection. Media removal clears stale filesystem/usage information. |
| 10. Files | Listed below. |
| 11. Build | Meson setup/reconfigure and complete production/portal builds succeeded. See setup/build logs and the final build log. No new dependencies. |
| 12. Tests | Full Meson suite: **23 passed, 0 failed**. Device fixtures include a 35-identifier table, presence/precedence/cache/reader lifecycle tests and native UI tests; sidebar fixtures cover availability, fallback, names and identities. The final capability-only case has an additional focused model run. |
| 13. Physical hardware | None tested. All card, cartridge and optical cases are deterministic fixtures. |
| 14. Icons | Installed standard symbolic resources were verified. No dedicated Zip/Jaz artwork is assumed: `drive-removable-media-symbolic` is the available fallback. No missing icon resource blocks this implementation. |
| 15. Identification limits | Specific form factors, embedded MMC identity and unknown future formats can remain indeterminate. No microSD/SDUC/CFexpress identities are inferred. Existing conservative handling of ambiguous physical backing relationships remains. |

## Verification evidence

* `setup.log`: required Meson reconfiguration.
* `build.log`: complete production build.
* `final-build.log`: complete rebuild after the capability-only regression case.
* `tests.log`: 23-suite regression result.
* `final-model-tests.log`: final model/provider tests; the two UI groups are
  intentionally excluded here because they passed in the complete suite.
* `visual-tests.log`: native fixture/UI and in-place sidebar assertions.
* `geometry-check.json`: **30 captures**, **20 usage bars**, **972 labels**,
  no overflowing label geometry and no raw identifiers in ordinary labels.
* `contact-sheet.png`: all 30 final light/dark views.

Screenshot indices (`light-media-*` and `dark-media-*`):

| Index | Media |
| --- | --- |
| 00 | SD |
| 01 | SDHC |
| 02 | SDXC |
| 03 | CompactFlash |
| 04 | Memory Stick |
| 05 | SmartMedia |
| 06 | MMC |
| 07 | Empty multi-format reader |
| 08 | Zip |
| 09 | Jaz |
| 10 | DVD-RAM |
| 11 | HD DVD |
| 12 | Magneto-optical filesystem without track metadata |
| 13 | Unknown generic removable media |
| reader-hardware | Readable reader compatibility and existing hardware fields |

The captures use the existing Majoris Theme in Xvfb. Native scrolling is retained
at the production dialog's default height. WSL/Xvfb results do not establish
physical hotplug or assistive-technology behaviour in a full desktop session.

## Modified files

* `src/devices/media-identity.vala` — new central descriptor/classification/icon policy.
* `src/devices/device-info.vala` — typed media state and adaptive names.
* `src/devices/device-provider.vala` — enrichment, shared snapshots and reader reconciliation.
* `src/sidebar/places.vala` — batched metadata and incremental presentation updates.
* `src/views/browser.vala` — in-place sidebar image updates.
* `src/dialogs/device-properties.vala` — readable media values and optical capacity handling.
* `tests/device-properties.vala` — mapping, provider, cache, lifecycle and UI fixtures.
* `tests/places.vala` — family-icon and sidebar regressions.
* `meson.build` — new source and expanded UI-test timeout.
* `po/POTFILES` — gettext source registration.
* `docs/media-recognition.md` — mapping, policy and reproduction instructions.

The final audit found UDisks identifier comparisons only in the central mapping;
the only remaining family-prefix handling is its conservative unknown-format
fallback. Browser and Properties consume the central policy. No management
actions, raw-device operations, application-specific CSS or icon artwork were added.
