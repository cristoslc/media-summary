# Changelog

## 2026-04-12

### Added
- **X/Twitter thread support** — new content-type `x-thread` for multi-post X/Twitter threads. Detected from URL (`x.com`, `twitter.com`, `fxtwitter.com`, `fixupx.com` + `/status/<id>`). Unrolled via the public [fxtwitter](https://fxtwitter.com) API (`api.fxtwitter.com/2/thread/{id}`) — no API key or authentication required.
- **Thread fetcher** (`scripts/fetch_x_thread.py`) — stdlib-only script that calls fxtwitter, writes raw JSON + stitched transcript to `/tmp`, and prints metadata to stdout. Detects and aborts cleanly when the upstream deployment lacks an account proxy (single-post response on a known-multi-post thread opener).
- **X-thread template** (`references/x-thread-template.md.j2`) — Summary, Key Points, Full Thread (verbatim, each post hyperlinked back to its tweet URL), Links & References.

### Changed
- **Step 1 restructured** from "Resolve a YouTube URL" to "Classify source and acquire transcript" — explicit dispatch table for X/Twitter, Instagram, YouTube, and other sources. Each leg either runs yt-dlp (existing) or the new fxtwitter fetcher.
- **Content-type classification** now respects pre-set values. Step 4b skips transcript-based classification when `CONTENT_TYPE` is already set by the source (currently: `x-thread`).
- **Step 5 template table** adds `x-thread` row; new x-thread-specific rendering notes cover slug derivation, Full Thread numbering with per-post hyperlinks, and timestamp omission.
- **Permissions** — `Bash(uv run */scripts/fetch_x_thread.py*)` added to recommended allowed-tool patterns; security rationale covers it (stdlib only, no subprocess, fxtwitter is the only network endpoint).

## 2026-04-04

### Added
- **Recipe video support** — automatic content-type detection classifies videos as `recipe` or `general` based on transcript signals. Recipe summaries use a dedicated template with Ingredients, Instructions, Techniques, Variations, and Equipment sections.
- **Recipe template** (`references/recipe-video-template.md.j2`) for structured recipe output.
- **Instagram support** — Instagram reels/posts handled natively via yt-dlp with browser cookie authentication.
- **Tiered transcript fallback** for videos without speech:
  1. yt-dlp auto-generated subtitles (default)
  2. Post caption from metadata (if >100 non-hashtag chars)
  3. Vision OCR — scene-change frame extraction + model vision (requires user approval)
  4. Local OCR via EasyOCR (fallback if model lacks vision, requires user approval)
- **Scene-change frame extraction** (`scripts/extract_frames.py`) — uses OpenCV histogram correlation to capture frames at visual transitions rather than fixed intervals.
- **yt-dlp wrapper** (`scripts/yt-dlp.sh`) — runs yt-dlp transiently via `uv run --with` instead of requiring a global install.
- **Default browser detection** for Instagram cookie extraction (Chrome, Safari, Firefox, Brave).
- **Vision capability probing** — automatically tests whether the runtime model can read images before falling back to local OCR.

### Changed
- **`uv` is now a hard requirement** — replaces both `python3` and `yt-dlp` as standalone prerequisites. All Python execution uses `uv run`.
- **Bootstrap script** simplified — only checks for `uv` and `gh`. Removed `python3` and `yt-dlp` standalone checks.
- **Timestamps are conditional** — YouTube deep-links only generated when a VTT transcript and YouTube URL are available. Caption/OCR sources omit timestamps.
- **README.md** rewritten to document new capabilities, updated permissions, fallback chain, and both summary templates.
- **Permissions guidance** updated for new tools (`opencv-python-headless`, `easyocr`, `test -s`, `yt-dlp.sh`).
- **Merged yt-dlp subtitle + metadata calls** into a single invocation (eliminates a redundant network round-trip).
- **Extracted inline EasyOCR code** to `scripts/ocr_frames.py` for consistency and auditability.
- **Step 4c summary instructions** now reference the template directly instead of duplicating section lists.

## 2025-12-15

### Added
- Dependency bootstrap script (`scripts/bootstrap.sh`) with auto-install and marker file.

### Changed
- Inverted Key Takeaways layout: plain bottom line, blockquoted bullets.

## 2025-11-20

### Changed
- Removed Typora dependency, use system default `open` command.
- Improved VTT parser: preserve timestamps, read in chunks, add deep-links.
- Platform-agnostic open command (open/xdg-open).
