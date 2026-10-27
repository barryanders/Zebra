# Daylight v0.1.1 — local-only preview

This update restricts FFmpeg inputs to local file and pipe protocols.

A small native Mac app that makes SDR copies of HDR videos with no encoding settings.

Drop videos, click **Make SDR copy**, and find the verified MKV copies beside your
originals. The app runs locally and keeps originals untouched.

## Download and setup

- `Daylight-arm64.zip` is the Apple Silicon build, for macOS 14 or later.
- Install the conversion tools once with `brew install ffmpeg-full`.
- Unzip Daylight and move it to Applications.
- The app is ad-hoc signed, not notarized. macOS may require per-app approval in
  Privacy & Security. Source builds are also available; see the README.

## Supported in this preview

HDR10/PQ and HLG with recognized BT.2020 metadata; original resolution; copied
audio, subtitles, chapters and attachments; a sequential queue; cancellation;
non-overwriting filenames; SDR metadata and decode verification.

Dolby Vision and multiple video streams are not supported yet. Output is MKV,
which requires a compatible player. FFmpeg is installed separately, not bundled.

## Validation

Nine local tests passed on Apple Silicon, including real PQ/HLG fixture conversion,
track/chapter preservation, filename collision handling, byte-identical originals,
SDR rejection, and cancellation cleanup. A native picker-to-conversion smoke test
also completed. Synthetic tests do not establish perceptual quality. Real-world
visual review and Intel hardware validation remain outstanding.
