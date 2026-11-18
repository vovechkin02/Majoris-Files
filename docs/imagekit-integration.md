# ImageKit integration and verification

Verification date: 18 November 2026, Australia/Sydney.

Files uses ImageKit as its only standalone image-file engine. Files retains
navigation, policy, GTK presentation, cancellation, replacement transactions and
Undo/Redo. ImageKit owns format verification, decoding, orientation, animation,
RAW/HDR/colour interpretation, multipage rendering, thumbnails/cache, metadata
and image export. No application CSS was added.

## Dependency revision and public interfaces

The authoritative repository inspected was
<https://github.com/vovechkin02/Majoris-Image>, main commit
`5428aa1da43c8d649cfbad79a54a83c7e18831ea`.
README, API 2, testing and release verification documents, both public consumer
examples, core/GTK source, generated installed VAPIs and Debian definitions were
reviewed. The upstream checkout is an external development reference, excluded
from Files' build and version control.

That commit lacks perfect lossless JPEG export. The authorized upstream change
was implemented in the adjacent **Majoris-Image** repository, as version 2.0.1.
These upstream changes remain local and uncommitted; they must be reviewed and
released together with this Files migration. `imagekit-revision.json` records the
base commit and SHA256 of every changed upstream file, including the new tests.
Do not substitute unpatched upstream 2.0.0 for this dependency.

Files requires `majoris-image-1` and `majoris-image-gtk4-1`, versions
`>=2.0.1,<2.1.0`. The namespace remains `ImageKit`; the GtkBuilder class remains
`ImageKitView`; SONAMEs remain `.so.2`; GI namespaces remain `ImageKit-2.0` and
`ImageKitGtk-2.0`. No guessed `majoris-image-2` package is used.

## Files components and consumers

| Component | Responsibility |
| --- | --- |
| `src/preview/imagekit-integration.vala`: `ImageKitIntegration` | Shared public decoder/thumbnail services, safe local source handoff, GIO candidate hints, bounded device-pixel thumbnail sizes and metadata presentation. No image algorithms. |
| Same file: `ImageKitPreview` | XML-backed wrapper around the actual `ImageKit.ImageView`; Files' existing Majoris toolbar, loading/errors/warnings, zoom/fit/actual size, preview rotation, animation and page controls. |
| `src/preview/preview.vala` | Existing provider dispatch, remote/cloud policy and selection generations. `ImagePreview` loads the shared widget. Preview and Gallery use this provider. The old 256 MiB preview veto is gone. |
| `data/ui/preview-image.ui` | Expanding `ImageKitView`, contain fit, pan/zoom, Control+wheel policy and accessible label. No hidden GtkPicture fallback or nested image scroller. |
| `data/ui/preview-controls.ui` | Existing control objects, plus Actual Size. No second toolbar. |
| Application and portal `startup()` | Explicit type registration before any relevant windows/templates are constructed. The wrapper and resource tests also ensure registration. |
| `FileThumbnailService` in `src/preview/thumbnail.vala` | Policy and provider dispatch. Image candidates return ImageKit encoded thumbnails before the non-image cache/provider path. Remote requests stage once and pass the staged file to ImageKit. |
| `src/views/browser.vala` | Grid, grouped Grid, List/Details, Columns, Gallery navigation and chooser Browser reuse; physical pixel requests preserve GTK virtualization and existing row cancellables/identity checks. |
| Properties and conflict thumbnails | Same dispatcher; scale-aware requests; normal themed icon remains on failure. |
| `src/metadata/details.vala` | ImageKit probe facts populate existing Image/Camera/Additional Metadata groups. Audio/video metadata and embedded artwork retain their existing provider. Broken cloud providers do not suppress readable local image facts. |
| `src/actions/rotation.vala` | ImageKit exports to a separate private sibling file. Files preserves permissions, original identity check, attributes, replacement journal and Undo/Redo. |

GIO MIME information is a candidate hint, never a decoder capability promise.
For generic `application/octet-stream`, Files uses GIO's filename MIME database;
this is necessary for GVfs SFTP/WebDAV PNGs. ImageKit verifies actual bytes.
No format parser or independent format catalogue was introduced.

## JPEG rotation gap resolved upstream

ImageKit 2.0.1 implements the existing public `EncoderRegistry.encode()` contract
for `ExportOptions.lossless=true` and JPEG. Its worker uses TurboJPEG perfect
coefficient transforms, composes EXIF orientation with quarter turns, preserves
the source profile/metadata, normalizes orientation and removes stale EXIF
thumbnails. It never silently trims or falls back to re-encoding. Other edits,
resizing, colour conversion and metadata filtering are rejected in that path.

Unaligned JPEG edges raise `ImageError.UNSUPPORTED`. Files preserves its
confirmation before explicitly requesting `lossless=false`. PNG export uses
ImageKit too, including 16-bit output. Both paths use Files' original safe
replacement and recovery machinery. Encoder errors other than the documented
unsupported transform do not trigger the lossy-consent path.

The upstream public test uses asymmetric image content, compares all eight EXIF
orientations against the independent renderer, verifies exact decoded pixels
after a clockwise/counterclockwise coefficient round trip, rejects imperfect
edges and extra edits, and checks cancellation, source preservation and a
same-source destination. The new native C file also passes
`-Wall -Wextra -Werror` in isolation.

## Cache and remote policy

Only ImageKit reads/writes standalone image thumbnails, under
`$XDG_CACHE_HOME/majoris-image/thumbnails-v2`. Files does not hash image cache
filenames, publish image PNG caches or implement their validation/eviction.
Requests use a bounded set of 32–1024 physical-pixel edges. Interactive viewers
are never constructed for list tiles.

The existing `$XDG_CACHE_HOME/thumbnails/normal` cache and sandbox command
`non-image-thumbnail-cache` serve only PDF/video/font/extension results.
Legacy user cache entries are left untouched.

Local-only thumbnails, 8 MiB remote thumbnail limit, on-request previews and
16 MiB preview limit retain their defaults. Staging is private, byte/time bounded,
cancellable and cleaned. Remote thumbnail source identity/size/timestamps/ETag
are checked around the transfer and decode; changed sources cannot publish a
result. ImageKit receives only the authorized local staging source, avoiding a
second download. Cloud online-only metadata does not trigger materialization.

**Public API limitation:** ImageSource does not expose a validated original
remote cache identity for caller-owned staging. Each staged remote thumbnail
therefore has a different ImageKit cache key. Remote cache reuse is less
effective than local reuse. Files does not forge source identity or compensate
with an independent image cache. A future upstream staged-source identity API
would need an explicit, validated provenance contract.

## Removed implementation and dependencies

Removed `image-decoders.c/.h`, `image-metadata.c`, `animation.vala`, `rotation.c`,
`tests/image-decoders.c`, the old image class in `sandbox.vala`,
`preview-animation.ui` and its resource/translation references. Removed helper
commands `image`, `image-animation`, `image-thumbnail`, `image-info` and
`image-rotate`. The former cache command was renamed and restricted by dispatcher
routing to non-image thumbnails.

Files no longer directly depends on LibRaw, libheif, Little CMS, GExiv2,
TurboJPEG or libtiff. GdkPixbuf remains for non-image content. Debian adds
`libmajoris-image-dev (>=2.0.1)` and explicitly retains the GdkPixbuf development
dependency. `dh_shlibdeps` resolves the two ImageKit runtimes; the core runtime
requires its matching worker, whose package requires Bubblewrap. Files need not
explicitly depend on the desktop thumbnailer. Existing non-image Bubblewrap
requirements remain.

## Remaining image-related source inventory

| Remaining code | Why it is necessary |
| --- | --- |
| `imagekit-integration.vala`, `ImagePreview`, preview XML and controls | Thin ImageKit integration and Files UI only. |
| Image branch of `FileThumbnailService`, `ImageKitThumbnail` | Policy/staging handoff and GTK textures created only from ImageKit's encoded results. |
| Non-image branch of `thumbnail.vala`, cache handling in `helper.c` | PDF/video/font/extension bitmaps; unreachable for standalone image candidates. |
| `pdf.vala`, PDF/font drawing in `helper.c`, `FontPreview` in `sandbox.vala` | Non-image document/font preview output. |
| `media.c`, `playback.c`, `playback-worker.c`, `playback.vala`, `MediaPreview` | GStreamer video frames, audio playback and embedded album artwork. |
| GTK bitmap display in `details.vala` | Embedded audio artwork returned by the existing isolated media provider. |
| `rotation.vala` | Permission checks and Files transactions; all pixel/coefficient processing and encoding are in ImageKit. |
| Browser/Properties/conflict thumbnail consumers | Ordinary GTK paintables from dispatcher results; normal GIcon fallback retained. |
| `actions/desktop.vala`, `window/extra-actions.vala`, Properties image file filters | Wallpaper/custom icon file selection and external desktop actions; no image decoding. |
| Search image MIME filter | File-search classification, not image processing. |
| Gtk.Image/GIcon/icon-theme use throughout the UI | Application, toolbar, symbolic, folder, device and file-type icons, outside the migration scope. |
| Tests and CC0 fixtures | Isolated fixture generation, assertions and native captures; no production decoding fallback. |

The final source audit also checked C `gdk_pixbuf_*` operations and direct
`from_file`/`from_filename` texture loading. Remaining C image-file reads are
limited to the isolated **non-image generated-thumbnail cache**, not original
standalone images. No decoder implementation is vendored from ImageKit.

## Verification evidence and limits

Build/test evidence is retained locally under `artifacts/imagekit-verification/`.
The report distinguishes executed checks from scenarios requiring a real
desktop, physical display or additional workload instrumentation. See the final
results below; no production ISO readiness or native HDR output is asserted.

The five matching Debian ImageKit 2.0.1 packages were built on a Linux filesystem
and installed in Debian WSL. The initial Windows export lost executable modes;
the packaging copy was corrected to the repository's recorded Git modes before
building. No upstream compiler/test failure was suppressed. The original
unmonitored `packages@majoris.invalid` maintainer address was preserved.

Upstream's installed headless, Vala GTK, C GtkBuilder, GI, Photos export and
thumbnail consumers pass with `MAJORIS_IMAGE_WORKER` unset. Files and its portal
compile against the installed packages without custom VAPI paths. The installed
worker is located through its configured production path.

Remaining upstream release blockers include the monitored maintainer address
and the existing repository-wide generated-C/XTest strict-warning gate described
in upstream's `docs/verification-release-2.0.md`. Native physical HDR output,
Wayland gestures and complete GNOME/ISO acceptance remain external qualification.

### Executed results

| Check | Result |
| --- | --- |
| Full Files build: application, portal, all test targets | Passed. |
| Full Files Meson suite, bounded concurrency | **34 passed, zero failures/skips/timeouts**. Earlier resource-path and image-toolbar fixture failures were corrected and rerun. |
| Installed-package Files build | Application, portal, preview helper and affected test targets compile using system-installed VAPI/pkg-config only. |
| Installed-package affected tests | Toolbars, Properties, resource construction and integration: **4/4 passed**. Final adapter/remote refinements also pass their targeted integration and remote checks. |
| ImageKit full suite with external RAW corpus configured | **28 passed, zero failures/skips/timeouts**. Includes worker faults/timeouts/cancellation, source validation, PNG cache corruption/publication, GTK lifecycle, animation and large TIFF/EXR workflows. |
| Nine-camera RAW qualification | Passed for Canon CR2/CRW, Nikon NEF, Sony ARW, Fujifilm RAF, Olympus ORF, Pentax PEF and Panasonic/Ricoh DNG corpus. Files' own preview/thumbnail check also passed on the Canon CR2 fixture without changing its checksum. |
| Perfect JPEG public export | Passed against source-build and installed stock runtime; all EXIF orientations, asymmetric content, exact decoded round trip, refusal, cancellation and source/destination protection. |
| Upstream installed consumers | Headless C/Vala, GTK Vala, C GtkBuilder, GI, Photos export and desktop thumbnail output passed without `MAJORIS_IMAGE_WORKER`. |
| Debian ImageKit package build/install | Five stock 2.0.1 packages built and installed; no runtime/development ABI mismatch. |
| Debian Files runtime dependency resolution | `dpkg-shlibdeps -O` resolves `libmajoris-image2 (>=2.0.1)` and `libmajoris-image-gtk4-2 (>=2.0.1)` for application and portal. |
| Source/UI/style checks | 77 interfaces, 69 composite templates; construction audit and theme ownership checks pass. |
| SFTP and WebDAV | Both disposable loopback services pass Local/Never/All thumbnail policy, on-request/disabled preview policy, single staging handoff, source validation, cancellation and interrupted-transfer checks. The fixture explicitly disables FUSE and verifies the existing unsupported remote-save contract. |
| Native captures | Light and dark through Majoris-Theme's existing GTK4 bridge; JPEG/PNG/RAW thumbnails, Grid/grouped Grid, List, Gallery, preview pane, Quick Preview, animation, TIFF/EXR, Properties metadata, conflict and Open/Save chooser captured. Representative renderer, pane, metadata and RAW captures were visually inspected. |
| 10,000-entry directory | 0.313 s enumeration; 289 main-loop heartbeats; observed RSS 60,728 KiB. |
| 100,000-entry directory | 3.186 s enumeration; 2,952 main-loop heartbeats; observed RSS 379,528 KiB. |
| Mixed image-directory stress | 2,000 entries including 1,000 images; 64 rapid scroll/preview/tab iterations and two windows: 8.259 s, 420 main-loop heartbeats, peak 514 instantiated Grid tiles. Passed virtualization and responsiveness assertions. |

Timings are observations from this Debian WSL environment, not comparisons with
a release baseline. The directory benchmark does not measure thumbnail decode
latency for 100,000 distinct images. The stress run does not prove long-duration
absence of memory growth or quantify a worker-process maximum. Physical HDR
scanout, screen-reader announcements, real Wayland gestures, a large EXR corpus,
and long-duration memory/worker profiling remain unqualified. ImageKit correctly
reports SDR/tone-mapped fallback in the tested environment.

Reproduce the application checks on Debian after installing the matching patched
ImageKit package set:

```sh
meson setup build-imagekit
meson compile -C build-imagekit
GTK_A11Y=none meson test -C build-imagekit --num-processes 4 --print-errorlogs
MAJORIS_IMAGEKIT_STRESS=1 meson test -C build-imagekit imagekit-integration --print-errorlogs
# Optional real camera source (read-only fixture):
MAJORIS_IMAGEKIT_RAW=/path/to/350D.CR2 meson test -C build-imagekit imagekit-integration --print-errorlogs
```

For native capture, set `MAJORIS_IMAGEKIT_EVIDENCE` to a private output directory
and invoke the integration executable through Majoris-Theme's documented GTK4
wrapper and `tests/imagekit-session.py`. Set `MAJORIS_VISUAL_DARK=1` for dark mode.
`tools/collect-imagekit-evidence.py` records the upstream manifest and collects
this task's `/tmp/majoris-files-imagekit-*.log` files plus its five package files;
the large local evidence directory is intentionally ignored by Git.
