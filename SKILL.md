---
name: media-summary
description: Downloads and summarizes audio/video media — podcasts, YouTube videos, talks, interviews, lectures, and conference presentations. Saves a structured markdown summary locally, publishes it as a public GitHub Gist, and opens it in the system default application. Use when the user provides a URL to any audio or video content (Apple Podcasts, Spotify, YouTube, conference recordings, etc).
license: MIT
compatibility: Requires uv and gh CLI (authenticated)
metadata:
  author: cristoslc
argument-hint: <media-url>
user-invocable: true
allowed-tools: Bash, Write, Read, WebFetch, Agent
---

The user has provided a media URL: $ARGUMENTS

Follow these steps exactly:

## Step 0 — Bootstrap dependencies

Run the bootstrap script (`scripts/bootstrap.sh` relative to this skill's directory). It installs missing tools, verifies `gh` is authenticated, and skips subsequent runs via a marker file.

```bash
bash "<SKILL_DIR>/scripts/bootstrap.sh"
```

If it exits non-zero, stop and tell the user what to fix before continuing.

## Step 1 — Resolve a YouTube URL

If the URL is already a YouTube URL (`youtube.com` or `youtu.be`), use it directly.

Otherwise (Apple Podcasts, Spotify, conference sites, etc.), extract the title from the page, then search YouTube for the matching video/episode. Use `mcp__MCP_DOCKER__fetch_content` or `mcp__MCP_DOCKER__brave_web_search` to find it.

**Instagram URLs** (`instagram.com`): Do **not** search YouTube. Keep the original URL and proceed directly to Step 2 — yt-dlp handles Instagram natively.

## Step 2 — Download the transcript with yt-dlp

Run:

```bash
bash "<SKILL_DIR>/scripts/yt-dlp.sh" --write-auto-sub --sub-lang en --skip-download --sub-format vtt -o "/tmp/media_transcript" "<URL>"
```

Also download metadata (needed for the caption fallback):

```bash
bash "<SKILL_DIR>/scripts/yt-dlp.sh" --write-info-json --skip-download -o "/tmp/media_transcript" "<URL>"
```

**Note:** For Instagram URLs, add `--cookies-from-browser chrome` to both commands.

Check whether `/tmp/media_transcript.en.vtt` exists and is non-empty:

```bash
test -s /tmp/media_transcript.en.vtt && echo "VTT_OK" || echo "VTT_MISSING"
```

- If `VTT_OK` → proceed to Step 3.
- If `VTT_MISSING` → go to Step 2a (caption fallback).

### Step 2a — Caption fallback

Read `/tmp/media_transcript.info.json` and extract the `description` field. Strip hashtags (`#\w+`) and leading/trailing whitespace. If the remaining text is **>100 characters**, write it to `/tmp/media_clean_transcript.txt` (one paragraph per line) and **skip Step 3** — go directly to Step 4.

If the caption is insufficient (<=100 non-hashtag characters), go to Step 2b.

### Step 2b — Frame extraction fallback (requires user approval)

**Stop and ask the user:**

> No subtitles or usable caption found for this video. I can extract frames and read the on-screen text to build a transcript. This requires `opencv-python-headless` (~30MB, installed transiently via uv). Proceed?

If the user declines, stop with a message explaining that the video can't be summarized without a transcript source.

If the user approves:

**1. Download the video:**

```bash
bash "<SKILL_DIR>/scripts/yt-dlp.sh" -o "/tmp/media_video.mp4" "<URL>"
```

(Add `--cookies-from-browser chrome` for Instagram.)

**2. Extract frames** (scene-change detection):

```bash
uv run --with opencv-python-headless python3 "<SKILL_DIR>/scripts/extract_frames.py" /tmp/media_video.mp4
```

This uses histogram comparison to detect scene changes and saves `/tmp/media_frame_000.png`, `/tmp/media_frame_001.png`, etc. The default threshold (0.85) works well for text-overlay videos. Pass a higher value (e.g. 0.92) to capture more frames if results seem sparse.

**3. Probe vision capability:** Use the **Read tool** on `/tmp/media_frame_000.png`. Then attempt to extract any visible text from the image. If you can identify readable text in the frame, vision works — continue with step 4 below. If you cannot read the image or extract meaningful text, fall back to step 5 (local OCR).

**4. Vision OCR (preferred):** Use the **Read tool** on each remaining frame. For each frame, extract all visible on-screen text. Collect all extracted text, deduplicate across frames (adjacent frames often repeat), and write the combined text to `/tmp/media_clean_transcript.txt`. **Skip Step 3** — go directly to Step 4.

**5. Local OCR fallback:** If vision probing failed, inform the user:

> Vision not available with this model. Falling back to local OCR via EasyOCR (~400MB first-run download). Proceed?

If approved, run:

```bash
uv run --with "easyocr,opencv-python-headless" python3 -c "
import easyocr, glob
reader = easyocr.Reader(['en'], gpu=False)
frames = sorted(glob.glob('/tmp/media_frame_*.png'))
all_text = []
seen = set()
for f in frames:
    results = reader.readtext(f, detail=0)
    for line in results:
        line = line.strip()
        if line and line not in seen:
            seen.add(line)
            all_text.append(line)
with open('/tmp/media_clean_transcript.txt', 'w') as out:
    out.write('\n'.join(all_text))
print(f'Extracted {len(all_text)} unique text lines from {len(frames)} frames')
"
```

**Skip Step 3** — go directly to Step 4.

## Step 3 — Parse the VTT into clean timestamped lines

Run the VTT parser script (`scripts/parse_vtt.py` relative to this skill's directory). It deduplicates overlapping caption windows and preserves timestamps for deep-linking:

```bash
uv run "<SKILL_DIR>/scripts/parse_vtt.py"
```

Output format — one line per segment:
```
[00:00:00] I'm doing something absolutely insane right now.
[00:00:04] Artificial intelligence is a little bit perplexing
```

## Step 4 — Read the transcript in chunks, then generate the summary

### 4a — Check size and read in batches

First check how many lines the transcript has:

```bash
wc -l /tmp/media_clean_transcript.txt
```

Then use the **Read tool** (not Bash) to read the file in batches of **400 lines** using `offset` and `limit`. For a 1000-line file, make three Read calls: offset=1/limit=400, offset=401/limit=400, offset=801/limit=400. Read all batches before writing anything.

### 4b — Classify content type

After reading all batches, classify the content into one of these types based on the transcript:

| Type | Signals |
|------|---------|
| **recipe** | Cooking instructions, ingredient lists/amounts, food preparation steps, kitchen techniques, dish names, "add the…", "cook until…", "season with…" |
| **general** | Everything else — interviews, talks, lectures, panels, commentary, tutorials, reviews |

Set `CONTENT_TYPE` to `recipe` or `general`. This determines which template and summary structure to use in the following steps.

### 4c — Write the summary

**If `CONTENT_TYPE` is `general`**, write a comprehensive markdown summary covering:

- **Speaker/guest background** and why they were invited or why this talk matters
- **Core thesis / main argument**
- **All major topics discussed** with concrete details, examples, frameworks, and notable quotes
- **Key takeaways and actionable insights**
- **Books, tools, or resources mentioned**
- **One-sentence bottom line**

**If `CONTENT_TYPE` is `recipe`**, write a comprehensive markdown summary covering:

- **Overview** — what the dish is, why the chef makes it this way, and who it's for
- **Ingredients** — full list with quantities, grouped by component if the recipe has distinct parts (e.g. dough, filling, sauce). Use a bulleted list.
- **Instructions** — numbered step-by-step directions derived from the video, with enough detail to reproduce the dish. Include temperatures, times, and visual cues ("until golden brown").
- **Key Techniques & Tips** — non-obvious methods, chef's shortcuts, or mistakes to avoid
- **Variations & Substitutions** — any alternatives the chef mentions (dietary swaps, ingredient substitutions, flavour variations)
- **Equipment Mentioned** — notable tools, pans, appliances referenced

Use `##` section headers, bullet points, and bold text for scannability. Aim for 800–1200 words of substance.

**Timestamps:** For each major topic or section in the summary, include a YouTube deep-link using the timestamp from the transcript. Convert `[HH:MM:SS]` to total seconds for the `?t=` parameter (e.g. `[01:05:30]` → 3930 seconds). Format as a linked timestamp at the start of the relevant bullet or subheading:

```markdown
### [[01:05:30]](https://youtu.be/VIDEO_ID?t=3930) Power Concentration
```

or inline for bullets:

```markdown
- **[[00:14:00]](https://youtu.be/VIDEO_ID?t=840) Epistemic collapse** — We are entering...
```

Use the YouTube URL from Step 1 as the base. Include timestamps for every major topic/section — aim for one timestamp per significant topic shift.

## Step 5 — Write the markdown file

Derive a slug from the title using **only lowercase letters, numbers, and hyphens** — strip all other characters (spaces become hyphens, consecutive hyphens collapse to one, leading/trailing hyphens removed). This sanitization is critical: shell metacharacters in the slug (`;`, `$()`, backticks, quotes) would be injected into file paths and `gh` commands below. Example: `jenny-wen-design-process`. Save the summary to:

```
~/Downloads/<slug>_summary.md
```

Choose the template based on `CONTENT_TYPE`:

| Content type | Template |
|---|---|
| `general` | `references/media-summary-template.md.j2` |
| `recipe` | `references/recipe-video-template.md.j2` |

Both paths are relative to this skill's directory. Key points:

- The metadata fields (Guest, Hosts, Podcast, Published) **must be a bullet list**, not bare lines — bare consecutive lines collapse into a single paragraph in CommonMark.
- **No horizontal rules (`---`) between sections.** Use only one, directly before the italicised source attribution at the bottom.
- Key Takeaways is the first section, before Guest Background.
- `gist_url` starts as `(to be filled after publishing)` and is updated in Step 6.
- The source link at the bottom **prefers YouTube or PocketCasts over Apple Podcasts**. If you already have a YouTube URL from Step 1, use that. Otherwise check for a PocketCasts link (`pca.st` or `pocketcasts.com`). Fall back to the original URL only if neither is available.

**Recipe-specific notes** (when using `recipe-video-template.md.j2`):
- The metadata fields (Chef, Channel, Cuisine, Published, Servings, Prep/Cook Time) **must be a bullet list**.
- If the chef doesn't state exact servings or times, estimate from context and note it with "~" (e.g. "~4 servings").
- Ingredients should include quantities. If the chef eyeballs amounts, write "to taste" or approximate with "~".
- Instructions must be **numbered steps**, not bullets — order matters in a recipe.

## Step 6 — Publish as a public GitHub Gist

Create a public GitHub Gist with the summary content. The gist filename must be prefixed with `summary-`, e.g. `summary-jenny-wen-design-process.md`.

Use the `gh` CLI:

```bash
gh gist create --public --filename "summary-<slug>.md" --desc "<Title> — Media Summary" "$HOME/Downloads/<slug>_summary.md"
```

All arguments containing the slug or title **must be double-quoted** to prevent word-splitting and globbing. The `--desc` value is particularly important since the title may contain special characters even after slug sanitization (the description uses the original title, not the slug).

Once you have the Gist URL, update the `gist_url` field in the frontmatter of `~/Downloads/<slug>_summary.md`, then run:

```bash
gh gist edit <gist-id> "$HOME/Downloads/<slug>_summary.md"
```

so the published Gist also contains the self-referencing URL.

Print the resulting Gist URL to the user.

## Step 7 — Open the file and notify

Open the summary in the background (so it doesn't steal focus) and post a macOS notification:

```bash
open -g "$HOME/Downloads/<slug>_summary.md" 2>/dev/null || xdg-open "$HOME/Downloads/<slug>_summary.md" 2>/dev/null || true
```

```bash
osascript -e 'display notification "Summary saved and Gist published" with title "Media Summary"' 2>/dev/null || true
```

## Final output to user

Tell the user:
- The local file path
- The public Gist URL
- A one-paragraph teaser of what the content is about
