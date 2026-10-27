# Daylight

## v0.1 acceptance
- Native compact macOS drop window; no encoding settings.
- Local sequential HDR10/HLG conversion, progress and cancellation.
- Preserve originals and original resolution; copy audio, subtitles, chapters and attachments.
- Reject unsupported HDR instead of silently producing bad color.
- Check output before publishing it beside the input; never overwrite existing files.
- Unit tests, generated-media integration checks, app build and public GitHub source release.

## Follow-up validation
- Human visual review of dark scenes, grain, highlights and skin tones before claiming transparent quality.
- Broader Dolby Vision support, signed/notarized distribution, and Intel testing are outside v0.1.

## v0.1 completed
- Native app compiled and packaged for Apple Silicon; ad-hoc signature verified.
- Nine tests passed, including real PQ/HLG conversions with audio, subtitle,
  attachment and chapter retention; collision handling; original byte preservation;
  SDR rejection; cancellation and partial-file cleanup.
- Native file picker and complete conversion exercised through the app.
- Initial UI inspection found the queue collapsing; it now has an explicit bounded
  height. A second screen capture was unavailable after the display capture service
  failed; recheck the final queue layout on an unlocked Mac.
- Separate FFmpeg installation is required; no third-party binaries are bundled.
