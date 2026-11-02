# File Operations implementation and verification

The shared `OperationManager` remains the backend for file operations, conflicts,
retry plans, Undo/Redo, replacement journals and rename recovery. No additional
transfer service, CSS, or external dependency was added.

## Model and accounting

`JobState` describes queued, calculating, running, pausing, paused, waiting,
finalising and terminal states. The existing Job API remains available. Managed
copy/move/delete operations use 64-bit item and byte statistics; specialist jobs
retain their fraction or textual status adapters. Structured progress is derived
from aggregate statistics, with a monotonic presentation fraction and a ceiling
below 100% until successful completion.

Preparation asynchronously enumerates folders without following symlinks. It
counts folders, regular files and bytes, caches subtree item counts for atomic
moves, and stops preflight after a bounded time/item budget. Incomplete metadata
falls back to indeterminate or known item progress. Copy callbacks contribute
only their increase since the previous callback. Recursive deletion counts each
removed entry; Trash and metadata operations count selected items. Skips are
reported and switch to item progress when transferred-byte totals no longer
represent the remaining work.

Monotonic sampling runs twice per second. Smoothed throughput uses incremental
bytes and a bounded 120-sample history. ETA requires known bytes, three samples,
positive throughput and an actively running job. Paused and conflict states do
not continue an ETA countdown. Same-filesystem moves do not invent throughput.

## Transfers and controls

Eligible native regular files use bounded asynchronous read/write chunks within
the manager's existing transfer traversal. Pause checkpoints stop actual I/O;
Resume continues the same streams. Cancellation wakes paused work and uses the
same GCancellable. New files are written into exclusive hidden staging files;
metadata, source validation and durability flushes precede exclusive publication.
Ordinary copies preserve mode, timestamps and supported user extended attributes
while retaining the copying user's ownership; image-edit replacements retain their
existing stricter ownership-preservation behaviour.
Replacement copies use the existing replacement-journal staging path. Cleanup
failures report retained partial-data paths. Source validation before copy/delete
move cleanup preserves a source that changed during the transfer.

Sparse files, copy-on-write filesystem paths, symlinks, special files and remote
backends retain GIO copying where the controlled path is ineligible. Those jobs
pause at file boundaries, with Pausing displayed until a checkpoint is reached.
Atomic rename moves cannot pause inside the rename. Archive, provider, split/join,
image rotation and other specialist jobs do not expose unsupported Pause controls.
The existing archive worker callbacks already marshal observable updates through
the main context.

Retry Remaining Items keeps the existing backend and journals. It validates the
destination and available source identities, while preserving the existing live
retry case in which a previously missing source is subsequently created.
Interrupted plans retain their stricter identity checks.

## Presentation and application lifetime

The header button opens one shared, non-modal Adw.Window. It also reflects activity
using a themed symbolic icon. The window shows stable operation rows with native
controls, item/byte summaries, per-operation expandable details, textual speed and
ETA, current-file byte counts, active time, and a theme-coloured DrawingArea graph.
Recovery notices remain separate. Their buttons explicitly route to existing
FilesWindow recovery actions, opening a browser window when needed.

Operations active after one second request automatic presentation. The application
only presents automatically while a Files window is active. Successful completion
can hide the window after four seconds; failures, retries and recovery notices
prevent automatic hiding. Closing the window hides it without cancelling jobs.
The existing application hold/release mechanism still owns active job lifetime.
The progress window registers with the application while shown, so an error or
retry remains available after the last browser closes; hiding it removes that
window registration to avoid an invisible application-lifetime leak.
Ordinary application activation searches for a FilesWindow, independently of the
progress window. Conflict dialogs can fall back to the progress window when their
original browser window is unavailable.

Job history pruning retains actionable failures and recovery. Backend sampling and
row refreshes are bounded, graph history is bounded, and completion disconnects
sampling handlers. No operation is owned by its originating tab.

## Files

Changed: `src/operations/manager.vala`, `src/operations/presentation.vala`,
`src/window/window.vala`, `src/application/main.vala`, `src/operations/durability.vala`,
`src/actions/rotation.vala`, `src/window/extra-actions.vala`, `tests/menus.vala`,
`meson.build`.

Added: `tests/operation-progress.vala`, `tests/operation-progress-ui.vala`,
`tools/capture-operation-progress.py`, this report and themed evidence under
`artifacts/operation-progress/`.

## Verification

Build: `meson setup build --reconfigure`, `meson compile -C build` in Debian WSL.
The build retains pre-existing Vala/GTK deprecation and generated-C warnings.

Focused automated tests cover aggregate accounting, nested/empty files and
folders, symlinks, 64-bit counts, repeated byte callbacks, pause/resume with content
comparison, cancellation while paused, atomic folder moves, ETA gating, unknown
totals and failed finalisation. The existing filesystem and replacement process
crash suites are also run. Results are recorded in `build/progress-targeted-tests.log`.

The complete suite is recorded separately in `build/progress-final-tests.log`.
That run passed 24 of 25 suites; the UI suite exposed notification delivery from a
headless test application. After restricting desktop notifications to the actual
Files application, all five affected suites passed (`build/progress-integration-tests.log`).
The final incremental build and four affected suites also passed
(`build/progress-targeted-tests.log`): filesystem, replacement crash recovery,
operation progress and general UI. There are no outstanding failures from those
reruns. An earlier complete 25-suite run also passed before the final lifecycle
and notification refinements.
Initial parallel runs hit GTK session/resource failures; bounded-concurrency reruns
are used for final evidence. A run that overlapped a rebuild also hit executable
file locks and was repeated after the build completed. Do not interpret an earlier failed log as a passing result.

Visual evidence: eleven presentation states in each of the installed Majoris Theme's
light and dark variants. These are explicit UI state fixtures, rather than claims
that every pictured state was reached using a real external device. Real pause,
resume and cancellation are verified by the separate transfer tests. Capture logs
and PNG/widget-tree evidence are under `artifacts/operation-progress/`.

## Backend-specific verification limits

No live GVfs remote server or removable device was exercised. A local cross-filesystem
move is tested using an isolated destination on `/dev/shm` when available.
Mid-file pause is only implemented for eligible native regular-file copies; other
GIO paths pause between files. Move progress may use item totals when actual
transferred-byte totals are unavailable. Enumeration that exceeds its preparation
budget intentionally leaves totals unknown. The visual fixtures do not replace
manual usability testing with physical external devices or remote storage.
