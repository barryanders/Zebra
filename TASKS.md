# Zebra

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

## v0.1.1
- Restrict FFmpeg/ffprobe to file and pipe protocols, including validation.
- Split bitrate parsing for the older Swift compiler used by GitHub's macOS runner.

## v0.2 branding and publication
- Rename to Zebra, retaining the bundle ID for upgrade continuity.
- Use the zebra icon in the app and installable package.
- Publish the renamed repository and preview release, and add the product to the
  existing Anders GitHub Pages catalog with setup and supported-format details.

## v0.2 final choices and verification
- Final name: Zebra, descriptor “HDR to SDR for Mac”.
- Latest sculptural cinematic zebra icon selected after four rejected candidates.
- Optional Buy Me a Coffee link in the main window and Help menu.
- All nine tests passed after module renaming; final release app built and signed.
- Product page and catalog entry checked at desktop and phone widths.
- Public repository is barryanders/zebra. Bundle identifier retained for continuity.
