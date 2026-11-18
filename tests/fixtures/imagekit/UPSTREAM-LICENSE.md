# Regression images

These fixtures come from Majoris Photos. The generated RGB gradients
`rgb8.png` and `rgb16.png`, original `vector.svg`, generated
`multipage.tiff`, and generated `multipart.exr` carry the archive's CC0-1.0
fixture license. `corrupt.bin` deliberately contains no image. The archive
contains no licensed camera RAW samples or its referenced download script.

The framework generates additional fixtures in the build directory,
including an animated GIF and a 200 MP tiled TIFF. Native tests generate
HDR reference images and compare numerical color and luminance values.

`avif-sequence.avif` is a generated CC0 fixture with solid red and green
8 × 8 frames. It was generated with Debian 13's `avifenc`:
`avifenc --speed 10 --timescale 1000 --duration 70 red.png --duration 160 green.png avif-sequence.avif`.
The regression checks the two decoded frames, microsecond timing and
infinite playback and accepts a diagnostic still preview when the optional
backend is disabled.

`avif-hdr-sequence.avif` uses the same source frames, generated with
`avifenc --depth 10 --yuv 444 --cicp 9/16/9 --timescale 1000 --duration 70 red.png --duration 160 green.png -o avif-hdr-sequence.avif`.
It covers 10-bit BT.2020 PQ frames and the SDR tone-mapping path.

`heic-sequence.heic` is a generated CC0 fixture from
`tests/support/make-heif-sequence.c` and the libheif x265 encoder. It contains two
solid-color HEVC images at 70 ms and 160 ms with two presentations.

`heic-multitrack.heic` adds a blue video track before the red/green image
track. Generate it with `make-heif-sequence heic-multitrack.heic multitrack`.
The test fixture generator derives infinite-repeat, edit-offset,
non-unit-rate and invalid-duration inputs from the original HEIC sequence.
