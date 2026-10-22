# External extension protocol

Files loads no extension native code. A separate session D-Bus service implements
`com.majoris.Files.Extension1` on its manifest's BusName and ObjectPath. System
manifests in `/usr/share/majoris-files/extensions` are enabled by default; manifests
in `$XDG_DATA_HOME/majoris-files/extensions` require opt-in in Preferences. A service
runs with the user's authority; enabling an untrusted service is not sandboxing it.
Credential-bearing remote URIs are not passed to extensions.

A `.extension` key file contains an `[Extension]` group with `Id`, localized `Name`,
`Version=1`, `BusName`, `ObjectPath` and semicolon-separated `Capabilities`. Supported
capabilities are `actions`, `metadata`, `columns`, `properties`, `nearby` and
`cloud`. The per-file cloud contract is documented in [cloud-files.md](cloud-files.md).

| Method | Input | Output | Purpose |
|---|---|---|---|
| GetVersion | none | `u` | Must return 1 |
| GetActions | `as` selected URIs | `a(ss)` | Action ID and display label |
| Activate | `s` action ID, `as` selected URIs | none | Perform a currently available action |
| GetFileInfo | `s` file URI | `a{ss}` | Metadata fields; columns look up their field key here |
| GetColumns | none | `a(ss)` | Field key and column label |
| GetProperties | `s` file URI | `a(ss)` | Property title and value |

Each call has a two-second deadline; incompatibility, timeouts and provider errors
remain isolated from the file manager. Selection actions are rechecked on invocation.
Manifests are bounded to 64 KiB and 128 providers, actions to 64 and 1,000 selected
items, columns to 16 per provider/32 overall, and metadata/properties to 64 fields.
Metadata keys are at most 100 bytes and values at most 16 KiB. Visible cells have a
bounded asynchronous cache. Sorting prepares a complete asynchronous snapshot of
the chosen column before changing order; comparisons never issue D-Bus requests.
Snapshots are limited to 100,000 items / 16 MiB of values, 32 concurrent requests
and a 30-second budget checked between batches. Unsupported/failed preparation
keeps the existing sort and reports the error. File stamps avoid re-querying
unchanged entries; provider revisions invalidate snapshots. Columns are refreshed
when providers restart or their enable state changes, including removal of disabled
provider columns. This is bounded sorting, not an unbounded background index.

`examples/checksum.extension`, `checksum-extension.py` and the D-Bus activation
service form a runnable example. It displays file metadata and a size column and
exclusively creates a SHA-256 sidecar for selected local regular files, bounded to
10 files of at most 16 MiB each. Existing sidecars are not overwritten. It is disabled
at build/install time unless `-Dexample_extension=true` is selected. User manifest
installation still requires enabling that provider in Preferences.

`tests/portal.vala` starts the real example in a separate process and verifies
discovery, opt-in, actions, metadata, columns, Properties, sidecar contents,
provider failure, restart, manifest removal and disabling. Additional D-Bus fixtures
exercise multiple registrations, slow replies, invalid action/metadata bounds and
Nearby transfer cancellation. A changed/uninstalled registration is rejected before
invocation; compatibility and cached data are invalidated when the bus owner changes.

## Nearby transport adapters

A `nearby` extension is registered automatically with the Nearby action registry.
Its service additionally implements these methods on `com.majoris.Files.Extension1`:

| Method | Input | Output |
|---|---|---|
| GetNearbyPeers | none | `a(ss)` stable peer ID and display name, at most 100 |
| StartNearbyTransfer | `s` peer ID, `as` selected local file URIs | `o` child operation path |
| GetNearbyTransfer | `o` operation | `s` phase, `s` message |
| CancelNearbyTransfer | `o` operation | none |

Phases are `running`, `completed`, `cancelled`, `error`. Calls use the standard
two-second deadline; transfers have a 30-minute deadline and are cancelled on
interruption/failure. Files confirms the selected peer and files before invoking
the installed transport. A provider is responsible for authenticated discovery,
consent and secure transfer using its supported transport APIs. Files implements
no wireless protocol and bundles no operational Nearby transport. Without an
enabled compatible registration there is no advertised Send action. Tests use a
clearly identified D-Bus fixture, not a claim of real wireless interoperability.
