# media-summary

A [Claude Code skill](https://agentskills.io) that downloads and summarizes audio/video media and X/Twitter threads — podcasts, YouTube videos, Instagram reels, recipe videos, talks, interviews, lectures, conference presentations, and multi-post X threads.

Given any media or thread URL, it resolves a YouTube equivalent if needed, pulls the transcript via `yt-dlp` (or unrolls the thread via the [fxtwitter](https://fxtwitter.com) API), generates a structured markdown summary, saves it locally, and publishes it as a public GitHub Gist. For videos without speech (e.g., Instagram reels with text overlays), it falls back to post captions or vision-based OCR on extracted frames.

## Requirements

- [uv](https://docs.astral.sh/uv/) (manages Python and Python packages)
- [gh CLI](https://cli.github.com), authenticated
- A markdown editor or viewer registered as the default for `.md` files

All other dependencies (`yt-dlp`, `opencv-python-headless`, `easyocr`) are run transiently via `uv run --with` and do not require global installation. The bootstrap script checks for `uv` and `gh` on first run:

```bash
./scripts/bootstrap.sh
```

## Installation

```bash
npx skills add cristoslc/media-summary
```

## Permissions

To run the skill fully autonomously (no approval prompts), add these to your Claude Code `allowedTools` settings. Each entry is scoped narrowly to limit blast radius — see [SECURITY.md](SECURITY.md) for the rationale behind each pattern, patterns to avoid, and the threat model.

```json
"Skill(media-summary)",
"Bash(bash */scripts/bootstrap.sh)",
"Bash(uv run */scripts/parse_vtt.py)",
"Bash(uv run */scripts/fetch_x_thread.py*)",
"Bash(bash */scripts/yt-dlp.sh*)",
"Bash(uv run --with opencv-python-headless*)",
"Bash(uv run --with easyocr*)",
"Bash(test -s /tmp/media_transcript*)",
"Bash(gh auth:*)",
"Bash(open -g ~/Downloads/*_summary.md*)",
"Bash(osascript -e 'display notification*)",
"Bash(gh gist create --public*)",
"Bash(gh gist edit*)"
```

## Usage

```
/media-summary <url>
```

Supported sources include YouTube, Instagram, Apple Podcasts, Spotify, most conference recording sites, and X/Twitter threads. Non-YouTube URLs are automatically resolved to a YouTube equivalent for transcript extraction (except Instagram, which is handled natively, and X threads, which are unrolled via the fxtwitter API).

### X/Twitter threads

For URLs matching `(x|twitter|fxtwitter|fixupx).com/.../status/<id>`, the skill unrolls the thread via `api.fxtwitter.com/2/thread/{id}` — no API key or authentication required. The output preserves every post verbatim with a hyperlinked post number pointing back to the original tweet, plus a model-generated Summary, Key Points, and Links & References section.

Caveat: fxtwitter relies on an authenticated account-proxy to walk self-reply chains. If the public deployment ever loses that proxy, the API silently returns only the root post. The skill detects this case (thread length = 1 but root text looks like a thread opener) and stops with an explicit error.

### Transcript fallback chain

For videos without speech-based subtitles (common with Instagram reels):

1. **Subtitles** — yt-dlp auto-generated subtitles (default path)
2. **Post caption** — extracted from metadata if >100 non-hashtag characters
3. **Vision OCR** — frames extracted via scene-change detection, read by the model (requires user approval)
4. **Local OCR** — EasyOCR fallback if the model lacks vision capabilities (requires user approval, ~400MB first-run download)

### Content-type detection

The skill classifies content as **general** (interviews, talks, tutorials, etc.), **recipe** (cooking videos), or **x-thread** (X/Twitter threads) and selects the appropriate summary template. The `x-thread` type is determined up-front from the URL; `general` vs `recipe` is inferred from the transcript.

## Output

Each summary is saved to `~/Downloads/<slug>_summary.md` and published as a public GitHub Gist. The markdown file includes YAML frontmatter with the original URL, transcript source URL, Gist URL, and last-updated date.

### Summary structure (general)

1. Key Takeaways
2. Guest/Speaker Background
3. Core Thesis
4. Major Topics Discussed
5. Books, Tools & Resources Mentioned
6. One-Sentence Bottom Line

### Summary structure (recipe)

1. Overview
2. Ingredients
3. Instructions
4. Key Techniques & Tips
5. Variations & Substitutions
6. Equipment Mentioned

### Summary structure (x-thread)

1. Summary (2–3 paragraphs)
2. Key Points
3. Full Thread (every post verbatim, numbered, each number hyperlinked to the original tweet)
4. Links & References (external URLs, @mentions, hashtags)

## Templates

Output formats are defined in the `references/` directory:

- [`references/media-summary-template.md.j2`](references/media-summary-template.md.j2) — general content
- [`references/recipe-video-template.md.j2`](references/recipe-video-template.md.j2) — recipe videos
- [`references/x-thread-template.md.j2`](references/x-thread-template.md.j2) — X/Twitter threads
