# External extension protocol

Files loads no extension native code. A separate session D-Bus service implements
`com.majoris.Files.Extension1` on its manifest's BusName and ObjectPath. System
manifests in `/usr/share/majoris-files/extensions` are enabled by default; manifests
in `$XDG_DATA_HOME/majoris-files/extensions` require opt-in in Preferences. A service
runs with the user's authority; enabling an untrusted service is not sandboxing it.
Credential-bearing remote URIs are not passed to extensions.

A `.extension` key file contains an `[Extension]` group with `Id`, localized `Name`,
`Version=1`, `BusName`, `ObjectPath` and semicolon-separated `Capabilities`. Supported
capabilities are `actions`, `metadata`, `columns` and `properties`.

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
Metadata keys are at most 100 bytes and values at most 16 KiB. Column metadata has a
bounded asynchronous cache; broad lazy sorting/invalidation and live column refresh
on provider enable/disable remain incomplete.

`examples/checksum.extension`, `checksum-extension.py` and the D-Bus activation
service form a runnable example. It displays file metadata and a size column and
exclusively creates a SHA-256 sidecar for selected local regular files, bounded to
10 files of at most 16 MiB each. Existing sidecars are not overwritten. It is disabled
at build/install time unless `-Dexample_extension=true` is selected. User manifest
installation still requires enabling that provider in Preferences.

`tests/portal.vala` starts the real example in a separate process and verifies
discovery, opt-in, actions, metadata, columns, Properties, sidecar contents,
provider failure isolation and disabling. Production providers should additionally
exercise slow replies, malformed data, service restarts and cancellation.
