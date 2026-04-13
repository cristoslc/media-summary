---
name: media-summary
description: Downloads and summarizes audio/video media and X/Twitter threads — podcasts, YouTube videos, Instagram reels, recipe videos, talks, interviews, lectures, conference presentations, and multi-post X threads. Handles speech-based transcripts, post captions, on-screen text overlays (via vision OCR), and X thread unrolling via the fxtwitter API. Saves a structured markdown summary locally, publishes it as a public GitHub Gist, and opens it in the system default application. Use when the user provides a URL to any audio/video content or X/Twitter status.
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

## Step 1 — Classify source and acquire transcript

Inspect the URL and dispatch to the matching leg. Each leg ends with `/tmp/media_clean_transcript.txt` written. Some legs also pre-set `CONTENT_TYPE` (consumed in Step 4b).

| Source | Detect | Leg | Pre-sets CONTENT_TYPE? |
|---|---|---|---|
| X/Twitter thread | `(x\|twitter\|fxtwitter\|fixupx)\.com/.+/status/\d+` | 1a | yes → `x-thread` |
| Instagram | `instagram.com` | 1b (yt-dlp native) | no |
| YouTube | `youtube.com`, `youtu.be` | 1c (yt-dlp) | no |
| Podcast / talk / other | (everything else) | 1c after resolving to YouTube | no |

### Step 1a — X/Twitter thread

Run the thread fetcher. It calls fxtwitter's `/2/thread/{id}` endpoint and writes both the raw JSON and a stitched transcript:

```bash
uv run "<SKILL_DIR>/scripts/fetch_x_thread.py" "<URL>"
```

The script prints a metadata JSON object to stdout — capture its fields (`author_name`, `author_handle`, `author_url`, `published_date`, `tweet_count`, `title_guess`, `source_url`, `post_urls`) for Steps 4c and 5.

Set `CONTENT_TYPE=x-thread`. **Skip Steps 2 and 3** — proceed directly to Step 4.

If the script exits non-zero (empty thread, or a thread-opener that only returned one post because the public fxtwitter deployment lacks an account proxy), report the error to the user and stop. Unrollable threads have no summarization path via this skill.

### Step 1b — Instagram

Keep the original URL and proceed to Step 2 with `--cookies-from-browser` (yt-dlp handles Instagram natively — see Step 2 for the flag).

### Step 1c — YouTube / podcast / other

If already a YouTube URL (`youtube.com` or `youtu.be`), use it directly. Otherwise (Apple Podcasts, Spotify, conference sites, etc.), extract the title from the page, then search YouTube for the matching video/episode — use `mcp__MCP_DOCKER__fetch_content` or `mcp__MCP_DOCKER__brave_web_search`. Proceed to Step 2.

## Step 2 — Download the transcript with yt-dlp

Run a single yt-dlp call to download both subtitles and metadata:

```bash
bash "<SKILL_DIR>/scripts/yt-dlp.sh" --write-auto-sub --sub-lang en --write-info-json --skip-download --sub-format vtt -o "/tmp/media_transcript" "<URL>"
```

**Note:** For Instagram URLs, add `--cookies-from-browser BROWSER`, where `BROWSER` is the user's default browser. Detect it with:

```bash
defaults read ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers 2>/dev/null | grep -B1 'https' | grep -o '"com\..*"' | head -1
```

Map the bundle ID: `com.google.Chrome` → `chrome`, `com.apple.Safari` → `safari`, `org.mozilla.firefox` → `firefox`, `com.brave.Browser` → `brave`. Default to `chrome` if detection fails.

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

(For Instagram, add `--cookies-from-browser BROWSER` using the same browser detected above.)

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
uv run --with "easyocr,opencv-python-headless" python3 "<SKILL_DIR>/scripts/ocr_frames.py"
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

If `CONTENT_TYPE` was already set in Step 1 (e.g. `x-thread`), skip classification and use that value.

Otherwise, classify the transcript into one of these types:

| Type | Signals |
|------|---------|
| **recipe** | Cooking instructions, ingredient lists/amounts, food preparation steps, kitchen techniques, dish names, "add the…", "cook until…", "season with…" |
| **general** | Everything else — interviews, talks, lectures, panels, commentary, tutorials, reviews |

Set `CONTENT_TYPE` to `recipe` or `general`. This determines which template and summary structure to use in the following steps.

### 4c — Write the summary

Read the appropriate template (see Step 5 for template selection) and follow its section structure. Fill every section with comprehensive, substantive content drawn from the transcript. Use `##` section headers, bullet points, and bold text for scannability. Aim for 800–1200 words of substance.

**Timestamps (YouTube sources only):** If the transcript came from a VTT file (Step 3) and a YouTube URL is available, include YouTube deep-links for each major topic or section. Convert `[HH:MM:SS]` to total seconds for the `?t=` parameter (e.g. `[01:05:30]` → 3930 seconds). Format as a linked timestamp at the start of the relevant bullet or subheading:

```markdown
### [[01:05:30]](https://youtu.be/VIDEO_ID?t=3930) Power Concentration
```

or inline for bullets:

```markdown
- **[[00:14:00]](https://youtu.be/VIDEO_ID?t=840) Epistemic collapse** — We are entering...
```

Use the YouTube URL from Step 1 as the base. Include timestamps for every major topic/section — aim for one timestamp per significant topic shift.

**No timestamps available:** If the transcript came from caption fallback (Step 2a) or frame extraction (Step 2b), the content has no timestamps. Omit timestamp links entirely — just use plain section headers and bullets.

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
| `x-thread` | `references/x-thread-template.md.j2` |

Both paths are relative to this skill's directory. Key points:

- The metadata fields (Guest, Hosts, Podcast, Published) **must be a bullet list**, not bare lines — bare consecutive lines collapse into a single paragraph in CommonMark.
- **No horizontal rules (`---`) between sections.** Use only one, directly before the italicised source attribution at the bottom.
- Key Takeaways is the first section, before Guest Background.
- `gist_url` starts as `(to be filled after publishing)` and is updated in Step 6.
- `generated_by.model` must be set to the runtime model identifier (e.g. `claude-opus-4-6`, `claude-sonnet-4-6`, `claude-haiku-4-5`). Use the exact model ID from the runtime environment, not a friendly name.
- The source link at the bottom **prefers YouTube or PocketCasts over Apple Podcasts**. If you already have a YouTube URL from Step 1, use that. Otherwise check for a PocketCasts link (`pca.st` or `pocketcasts.com`). Fall back to the original URL only if neither is available.

**X-thread-specific notes** (when using `x-thread-template.md.j2`):
- Slug derivation: use `<handle>-<first-few-words>` from the metadata printed by `fetch_x_thread.py` (e.g. `schlickw-us-foreign-policy-anthropic-mythos`). Same sanitization rules — lowercase, hyphens only.
- `thread_url` and `source_url` are the root post's URL from the metadata.
- **Summary** must be **2–4 sentences, strictly descriptive**. State what the thread is about and the shape of its argument — nothing more. Do **not** infer author background, credentials, or biographical detail from outside the thread. Do **not** categorize or editorialize the content (e.g. "the list is loosely organized by…"). If you find yourself writing more than 4 sentences, the rest belongs in Context & Annotations.
- **Full Thread**: render every post verbatim as a numbered list. Format: `N. [[N/total]](post_url) <verbatim text>` — the bracketed counter is the hyperlink back to that specific post on X. Preserve the author's wording, line breaks, and hashtags. Strip the leading auto-mention chain (consecutive `@handles` at the start that X auto-prepends in reply threads), since those are artifacts of the threading mechanism, not the author's words. **Hyperlink every `@mention`** inline as `[@handle](https://x.com/handle)` — both in post text and in any external link preview lines. Hyperlink hashtags as `[#tag](https://x.com/hashtag/tag)`.
- **Cite referenced posts inline.** When a thread post links to another X/Twitter status, `fetch_x_thread.py` resolves that tweet and includes it in the `cited_posts` metadata field (keyed by URL). For each cited post that appears under a thread post, render it as an indented blockquote directly below that thread post, using the format: `> **[@handle](https://x.com/handle)** ([date-link](tweet_url)): <verbatim cited text>`. Do not just leave the bare URL — the reader should see what's being cited without leaving the summary. If a cited post is missing from `cited_posts` (deletion, private account, API failure), leave only the bare URL and add a brief `> _[cited post unavailable]_` note.
- **Include substantive self-replies in the citation.** The `self_replies` field contains the cited author's follow-up posts to the target tweet (the script auto-walks the self-reply chain). If a self-reply is just a bare URL (it'll already be in `external_links`), skip it in the blockquote — it's redundant. If a self-reply adds substantive content (continues the thought, extends the argument, adds clarification), append its text to the blockquote as continuation (`>\n> <self-reply text>`), so the reader sees the full mini-thread the author is citing. Cap at the first 3 substantive self-replies per citation to keep the blockquote readable; link out (`> _+N more posts in this thread — see [link](first_self_reply_url)_`) if there are more.
- **Resolve external links inside cited posts.** Cited tweets often link to longer-form content (X Article, Substack, blog post, paper) — sometimes the tweet body is just a teaser. The `cited_posts` metadata per citation exposes: `article` (an X-native long-form post, when present — has `title`, `preview_text`, `body_excerpt`, `body_truncated`), `external_links` (URLs from the cited tweet **and its author's self-replies** — the script fetches the thread chain to catch the common "teaser post + bare-URL self-reply" pattern), `self_replies` (the full self-reply chain under the target), `photos`, `twitter_card`, and `author_website`. Resolve in this priority (progressive disclosure — stop at the first tier that yields content):
  1. **`article` is present** — the cited tweet *is* an X long-form Article; the body is already in `article.body_excerpt` (first ~6000 chars). Render the title as a link to the cited tweet URL and produce a 1–2 sentence synopsis from `preview_text` + `body_excerpt`. No WebFetch needed. If `body_truncated` is true, mention "(article continues on x.com)" so the reader knows there's more.
  2. **`external_links` non-empty** — WebFetch the first substantive longform URL and add a 1–2 sentence synopsis as a sub-blockquote (`> _Linked: [title](url)_ — <synopsis>`). Self-reply URLs are already included here, so teaser-then-link pairs work out of the box.
  3. **`twitter_card == "summary_large_image"` and `photos` non-empty** — download the first photo (`curl -sL <photo_url> -o /tmp/cited_<handle>.jpg`) and use the **Read tool** on it. Authors embed article titles and publication domains directly into preview images when X didn't generate a native link card. If the image reveals a title and domain, construct a likely article URL (e.g. `<domain>/p/<slug-of-title>`) and WebFetch; add the synopsis as a sub-blockquote.
  4. **`author_website` + tweet teases an external piece** (text mentions "Substack", "blog", "post", "article") — note "Substack/blog index — see [website]" without fetching.
  5. **Else** — skip; the cited tweet is self-contained.

  Skip resolution entirely for retweets, social-media-only links, or photos that are clearly not preview cards (selfies, memes, screenshots of other tweets).
- **Context & Annotations** (optional but recommended): everything that was inferred, looked up, or editorialized. Include author background pulled from the fxtwitter metadata (name, bio excerpt if useful) — and clearly label it as "from the author's X bio" or similar so the reader knows it's not from the thread. May also include per-post annotations on what's being linked, domain groupings, or observations on the thread's structure. Keep separate from the thread itself.
- No timestamps — X threads have no internal timeline to deep-link to.

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
