# Folia FFmpeg builds

Small, static, audio-focused FFmpeg builds for the Folia Electron desktop app.
This repository is derived from
[`acoustid/ffmpeg-build`](https://github.com/acoustid/ffmpeg-build) and keeps its
upstream variants available while adding a Folia-specific runtime contract.

The pinned FFmpeg version is **8.1.2**. Builds do not enable GPL-only or
nonfree components and are distributed under FFmpeg's LGPL terms. The build
scripts themselves retain their MIT license.

## Folia runtime contract

`FFMPEG_VARIANT=folia` is the default. It provides:

- audio decoding for MP3, AAC/ALAC, FLAC, Vorbis, Opus, PCM, APE, WavPack,
  TTA, WMA, AIFF, CAF, DSD and E-AC-3;
- MOV/MP4 demuxing for E-AC-3 tracks carrying the `ec-3` codec tag in `.m4a`;
- FLAC output with PCM S16LE WAV as the compatibility fallback;
- the `null` muxer used by Folia to decode and validate the complete output;
- `aresample` for channel and sample-format conversion;
- only local `file` and `pipe` protocols, with network access disabled;
- only the `ffmpeg` program; `ffprobe` and `ffplay` are not bundled.

Folia's caller deliberately omits `-ar`, so the source sampling rate is
preserved. A 96 kHz input therefore remains 96 kHz after transcoding.

This remains an audio-focused build. Future video processing should use a
separate `folia-video` variant rather than silently expanding the desktop
runtime binary.

## Supported targets

- Linux: `x86_64-linux-gnu`, `arm64-linux-gnu`
- Windows: `x86_64-w64-mingw32`
- macOS: `x86_64-apple-macos10.9`, `arm64-apple-macos11`

## Build locally

```sh
ARCH=x86_64 FFMPEG_VARIANT=folia ./build-linux.sh
ARCH=x86_64 FFMPEG_VARIANT=folia ./build-windows.sh
TARGET=arm64-apple-macos11 FFMPEG_VARIANT=folia ./build-macos.sh
```

Outputs are written below `artifacts/`. Source downloads use HTTPS and are
rejected unless they match the pinned SHA-256 in `common.sh`.

## Verify

For a native Linux build, pass the Folia binary and an optional full reference
FFmpeg used only to generate synthetic E-AC-3-in-M4A and CAF fixtures:

```sh
./verify-folia.sh artifacts/ffmpeg-8.1.2-folia-x86_64-linux-gnu/bin/ffmpeg /usr/bin/ffmpeg
```

Verification checks the component allowlist, absence of network protocols,
FLAC/WAV output, complete decoding through the `null` muxer, 96 kHz
preservation, E-AC-3 in `.m4a`, and CAF input.

## Releases

Tags such as `v8.1.2-folia.1` build every supported target and publish:

- one target-specific `.tar.gz` per platform and architecture;
- the exact corresponding FFmpeg source archive;
- `SHA256SUMS` covering every published archive.

Each binary archive also contains `share/folia-ffmpeg/BUILD-INFO.txt`, the
FFmpeg LGPL text, and the build-scripts MIT license.

Folia's application repository should pin a release asset and SHA-256 in its
own manifest, download it during packaging, and copy only `bin/ffmpeg` (or
`bin/ffmpeg.exe`) into `resources/ffmpeg/`.

## Upstream variants

The original `decode` and `encode` variants remain available for upstream
comparison. Folia releases build only the `folia` variant.
