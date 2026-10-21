# Implementation status

The remaining-feature task is **partially implemented and is not release complete**.
The implementation remains Vala, GTK4, libadwaita and GIO/GVfs with the existing
Majoris identifiers. Existing browsing, operation, metadata and portal architecture
has been extended. The original 102-section specification and full expanded
Section 79 were not included in the supplied audit; comparison with those complete
documents cannot be asserted. The supplied Nautilus source was reviewed as a reference.

## Implemented in this pass

- Configurable remote Open import (default 10 GiB / 30 minutes), streaming progress,
  cancellation, free-space checks, source identity checks, private pending storage
  and abandoned-transfer cleanup. Completed imports are retained in the application
  data directory and returned through the ordinary document portal. Imports are
  independent copies; they do not write edits back to their remote originals.
- Actual public xdg-desktop-portal/document-portal/Flatpak verification for Open,
  multiple Open, Save, folders, SaveFiles and cancellation. Gtk.FileDialog callers
  also exercise Open, multiple Open, Save, folders and cancellation. The fixture
  checks that an unselected host file remains inaccessible and verifies saved bytes.
- Per-user Samba R/F/D ACL editing, external-policy change detection, live usershare
  inventory and folder emblems. Connected-client inspection is authorized and
  filtered to an owned share. Firewall controls operate only on the bundled owned
  firewalld policy, only when firewalld is already active, and only for home/work zones.
- Durable replacement-backup records before moving old data, identity-checked
  recovery after restart and a graphical recovery action. Existing current files
  are preserved when recovering original data.
- GtkSourceView highlighting and encoding selection; sandboxed media/EXIF metadata,
  artwork, representative video thumbnails, bounded image animation with reduced
  motion, and isolated LibreOffice-to-PDF rendering with macros and updates disabled.
  Remote previews require explicit download by default and have independent limits.
- TinySPARQL indexed filename/content search with relevance, PDF/Office content,
  indexing preferences, cancellation, deduplication and recursive GIO fallback.
- Batch rename with live Before/After, find/replace, prefix/suffix, templates,
  numbering, dates and available metadata. Two-phase rename handles swaps; grouped
  Undo/Redo survives an application restart.
- Native 7-Zip creation, compression levels, volumes and encrypted headers;
  passwords use stdin. Multi-volume extraction uses the existing safe libarchive
  reader. Output staging and conflict checks precede publication.
- Copy To, Move To, Duplicate, New Folder with Selection and Paste as Link use the
  shared chooser/operation manager. Context menus reflect selection and support
  Shift+F10/Menu. Properties includes Metadata, Permissions and Open With pages.
- An opt-in, versioned out-of-process extension protocol with actions, metadata,
  columns and Properties, plus a working checksum example and integration test.
- Shell SearchProvider2, gettext infrastructure and template generation, indexing
  and network preferences, updated Debian dependencies and staged installation.

## Verification and remaining work

See [the completion matrix](release-matrix.md) for each task area, its source,
test evidence and exact remaining limitations. See [platform integration](platform-integration.md)
for reproducible build and acceptance commands and [the extension protocol](extensions.md)
for external providers.

The automated suite, real local X11 Flatpak fixture and directory benchmarks do
not establish Windows SMB enforcement, Wayland parenting, USB removal, hardware
codec playback, real cloud providers or production ISO acceptance. Important code
work also remains: true hidden-share policy, broad image format/color support,
playback decoder isolation, remote archives, full replacement/rename crash
transactions, Grid section headings and complete localization/accessibility.
Do not install this tree as the production default until the matrix's remaining
implementation and system acceptance requirements are resolved.
