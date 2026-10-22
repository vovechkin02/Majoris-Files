# Per-file cloud provider contract

Files retains libcloudproviders account discovery, status, menus and account actions.
That framework alone does not supply per-file availability or pin/evict APIs. An
account without a compatible adapter is explicitly unsupported for these operations;
a local pathname is never taken as evidence that a file is synchronized.

An installed adapter runs as a separate session D-Bus service and delegates to its
provider's supported APIs. Files contains no proprietary synchronization client.
System descriptors are enabled by default; user descriptors require the existing
extension opt-in preference. A descriptor is a bounded `.extension` key file:

```ini
[Extension]
Id=example-cloud
Name=Example cloud adapter
Version=1
BusName=com.example.CloudFiles
ObjectPath=/com/example/CloudFiles
Capabilities=cloud;

[Cloud]
RootURI=file:///home/example/Cloud/
```

Use a credential-free root URI. The provider must expose its file namespace through
GIO, including entries for online-only files. Overlapping roots use the most specific
adapter. Installing a descriptor does not install or authenticate a cloud account.

The root object implements `com.majoris.Files.CloudFiles1`:

| Method/signal | Input | Output |
|---|---|---|
| GetVersion | none | `u`, must be 1 |
| GetFileState | `s` file URI | `a{sv}` |
| StartOperation | `s` URI, `s` action, `t` maximum content bytes | `o` operation below the root object |
| Changed signal | `s` affected URI, or empty for root-wide invalidation | none |

State dictionary fields are `state` (`s`), `capabilities` (`as`), `size` (`t`, omit
when unknown), `mime` (`s`, optional), `progress` (`d`, -1 when unknown), `error`
(`s`, optional), and optional `quota-used`/`quota-total` (`t`, both required).

States are `local`, `online-only`, `cached`, `pinned`, `downloading`, `uploading`,
`syncing`, `completed`, `error`, `unavailable`, `quota-exceeded` or `unsupported`.
Capabilities are explicit operation names: `materialize`, `pin`, `evict`, `retry`
and `cancel`. Do not advertise operations that the upstream provider cannot perform.

An operation implements `com.majoris.Files.CloudOperation1`:

| Method | Output |
|---|---|
| GetStatus | `s` phase, `a{sv}` fields |
| Cancel | no output |

Phases are `running`, `completed`, `error`, `cancelled`. Status fields are optional
`progress` (`d`) and `message` (`s`). Calls have a three-second deadline, polling is
200 ms, and operations have a 30-minute deadline. Cancellation is forwarded when
advertised. Provider restarts and Changed signals invalidate visible cached state.

Materialization must make the **original GFile** readable in the provider-owned
namespace; Files accepts no arbitrary returned host path. Honor the supplied byte
limit, preserve the authoritative cloud copy during eviction, emit actual state
changes, and return completion only after the promised operation has finished.
Pinning and materialization require a verified size. Local materialization also
requires verified free space plus a 32 MiB reserve.

Grid/List/Column/Gallery/chooser use one status badge over the existing icon or
thumbnail. Properties displays only reported quota/error data. Online-only
thumbnails do not download content; explicit preview and chooser selection invoke
supported materialization with cancellation and their configured limits.

Discovery is bounded and watches installed descriptors; malformed descriptors do
not prevent other providers from loading. Visible status queries are bounded to
32 pending requests and 2,048 cached files. Descriptor removal or disabling removes
the adapter rather than leaving an advertised offline action.

`tests/cloud.vala` exercises a real D-Bus fixture with actual materialization bytes,
pin/evict state changes, offline errors, quota, size bounds and cancellation. This
is protocol evidence, not certification of OneDrive, Google Drive, Dropbox or any
other commercial provider. A vendor adapter still needs its own acceptance pass.
