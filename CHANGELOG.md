# Changelog

## 2026-04-13

### Added
- **Generic HTML ingestion** — 4-tier pipeline for summarizing any web page as an article:
  1. `readability-lxml` article extraction via `fetch_html.py` (HTTP GET + DOM parsing)
  2. MCP browser tools (Playwright-based rendering via MCP)
  3. Puppeteer headless Chromium (`fetch_html_puppeteer.js`) with lazy-load scrolling
  4. MCP `convert_to_markdown` as a last resort
- **Specialty domain handlers** in `fetch_html.py`:
  - **LinkedIn** — tries embed URLs (`/embed/feed/update/urn:li:activity:...`) to bypass auth walls before falling back to the main URL
  - **Medium** — detects Medium site metadata and extracts canonical article content
- **Puppeteer renderer** (`scripts/fetch_html_puppeteer.js`) — Node.js script that renders JS-heavy pages in headless Chromium, waits for content to settle, scrolls for lazy-loaded content, and extracts text using article-aware CSS selectors
- **HTML article template** (`references/html-article-template.md.j2`) — structured output for web articles with Key Takeaways, Overview, Main Arguments & Points, Notable Details & Examples, and Context & Significance sections
- **`html-article` content type** — auto-set for URLs routed through Step 1d
- **Node.js dependency** in bootstrap.sh — checks for `node`, installs via brew if missing; installs `puppeteer` npm package on first run
- **Fxtwitter failure fallback** — when fxtwitter returns only the root post (no account proxy), the skill now falls through to generic HTML ingestion instead of stopping

### Changed
- Fxtwitter failure (Step 1a) now falls through to Step 1d (generic HTML) instead of stopping with an error
- Bootstrap.sh installs Node.js and puppeteer npm package
- SKILL.md frontmatter updated with new allowed-tools (MCP browser, convert_to_markdown)
- README.md updated to document web article support, Puppeteer, and the 4-tier extraction pipeline
- Permissions guidance in bootstrap.sh updated with `readability-lxml` and `puppeteer` entries

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
