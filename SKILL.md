---
name: media-summary
description: Downloads and summarizes audio/video media — podcasts, YouTube videos, talks, interviews, lectures, and conference presentations. Saves a structured markdown summary locally, publishes it as a public GitHub Gist, and opens it in Typora. Use when the user provides a URL to any audio or video content (Apple Podcasts, Spotify, YouTube, conference recordings, etc).
license: MIT
compatibility: Requires yt-dlp, Python 3, gh CLI (authenticated), and Typora
metadata:
  author: cristoslc
argument-hint: <media-url>
user-invocable: true
allowed-tools: Bash, Write, Read, WebFetch, Agent
---

The user has provided a media URL: $ARGUMENTS

Follow these steps exactly:

## Step 1 — Resolve a YouTube URL

If the URL is already a YouTube URL (`youtube.com` or `youtu.be`), use it directly.

Otherwise (Apple Podcasts, Spotify, conference sites, etc.), extract the title from the page, then search YouTube for the matching video/episode. Use `mcp__MCP_DOCKER__fetch_content` or `mcp__MCP_DOCKER__brave_web_search` to find it.

## Step 2 — Download the transcript with yt-dlp

Run:

```bash
yt-dlp --write-auto-sub --sub-lang en --skip-download --sub-format vtt -o "/tmp/media_transcript" "<YOUTUBE_URL>"
```

This produces `/tmp/media_transcript.en.vtt`. (The raw transcript stays in `/tmp/` — only the final summary goes to `~/Downloads/`.)

## Step 3 — Parse the VTT into clean text

Run this Python script to strip timestamps and deduplicate lines:

```bash
python3 - << 'EOF'
import re

with open('/tmp/media_transcript.en.vtt', 'r') as f:
    content = f.read()

lines = content.split('\n')
text_lines = []
seen = set()
for line in lines:
    line = line.strip()
    if not line or line.startswith('WEBVTT') or line.startswith('Kind:') or line.startswith('Language:'):
        continue
    if re.match(r'^\d{2}:\d{2}', line) or '-->' in line:
        continue
    line = re.sub(r'<[^>]+>', '', line)
    line = line.strip()
    if line and line not in seen:
        seen.add(line)
        text_lines.append(line)

transcript = ' '.join(text_lines)
with open('/tmp/media_clean_transcript.txt', 'w') as f:
    f.write(transcript)
print(f"Transcript: {len(transcript)} chars")
EOF
```

## Step 4 — Generate the summary

Read `/tmp/media_clean_transcript.txt` in full. Then write a comprehensive, well-structured markdown summary covering:

- **Speaker/guest background** and why they were invited or why this talk matters
- **Core thesis / main argument**
- **All major topics discussed** with concrete details, examples, frameworks, and notable quotes
- **Key takeaways and actionable insights**
- **Books, tools, or resources mentioned**
- **One-sentence bottom line**

Use `##` section headers, bullet points, and bold text for scannability. Aim for 800–1200 words of substance.

## Step 5 — Write the markdown file

Determine a clean, slug-style filename from the title, e.g. `jenny-wen-design-process`. Save the summary to:

```
~/Downloads/<slug>_summary.md
```

Follow the template at `references/media-summary-template.md.j2` (relative to this skill's directory). Key points:

- The metadata fields (Guest, Hosts, Podcast, Published) **must be a bullet list**, not bare lines — bare consecutive lines collapse into a single paragraph in CommonMark.
- **No horizontal rules (`---`) between sections.** Use only one, directly before the italicised source attribution at the bottom.
- Key Takeaways is the first section, before Guest Background.
- `gist_url` starts as `(to be filled after publishing)` and is updated in Step 6.
- The source link at the bottom **prefers YouTube or PocketCasts over Apple Podcasts**. If you already have a YouTube URL from Step 1, use that. Otherwise check for a PocketCasts link (`pca.st` or `pocketcasts.com`). Fall back to the original URL only if neither is available.

## Step 6 — Publish as a public GitHub Gist

Create a public GitHub Gist with the summary content. The gist filename must be prefixed with `summary-`, e.g. `summary-jenny-wen-design-process.md`.

Use the `gh` CLI:

```bash
gh gist create --public --filename "summary-<slug>.md" --desc "<Title> — Media Summary" ~/Downloads/<slug>_summary.md
```

Once you have the Gist URL, update the `gist_url` field in the frontmatter of `~/Downloads/<slug>_summary.md`, then run:

```bash
gh gist edit <gist-id> ~/Downloads/<slug>_summary.md
```

so the published Gist also contains the self-referencing URL.

Print the resulting Gist URL to the user.

## Step 7 — Open the file

```bash
open ~/Downloads/<slug>_summary.md 2>/dev/null || xdg-open ~/Downloads/<slug>_summary.md 2>/dev/null || true
```

## Final output to user

Tell the user:
- The local file path
- The public Gist URL
- A one-paragraph teaser of what the content is about
