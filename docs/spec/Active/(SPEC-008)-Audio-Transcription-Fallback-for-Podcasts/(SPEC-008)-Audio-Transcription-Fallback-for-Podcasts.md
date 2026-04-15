---
title: "Audio Transcription Fallback for Podcasts"
artifact: SPEC-008
track: implementable
status: Implemented
author: cristoslc
created: 2026-04-15
last-updated: 2026-04-15
priority-weight: high
type: enhancement
parent-epic: ""
parent-initiative: ""
linked-artifacts: []
depends-on-artifacts: []
addresses: []
evidence-pool: ""
source-issue: ""
swain-do: required
---

# Audio Transcription Fallback for Podcasts

## Problem Statement

When `media-summary` encounters a podcast episode (audio-only URL, no YouTube equivalent) without subtitles, it skips directly to frame extraction — which is useless for audio-only content — and then presents the user with an OCR fallback prompt they shouldn't need to answer. The skill also skips the YouTube search step that is documented for non-YouTube URLs. Both gaps mean podcasts without captions produce no summary.

## Desired Outcomes

- Every podcast episode produces a transcript, regardless of whether the host provides captions
- Onboard audio transcription (Whisper) handles the "no subtitle" case without external API calls
- The YouTube search leg runs for podcasts before the audio-only detection, catching episodes that exist on YouTube
- Users get a summary for all media types — no manual fallback prompts required

## External Behavior

### Inputs
- A podcast episode URL (mp3/audio direct URL or podcast page URL)

### Outputs
- `/tmp/media_clean_transcript.txt` — one segment per line, no timestamps (same format as caption fallback)
- A published GitHub Gist summary

### Preconditions
- `uv` is available
- `imageio-ffmpeg` Python package is available (transient via `uv run --with`, bundles ffmpeg binary)
- `faster-whisper` Python package is available (transient via `uv run --with`)

### Postconditions
- Transcript file exists and is non-empty
- Summary is generated and published

### Constraints
- All transcription runs locally — no external API calls (Whisper, not OpenAI)
- Audio extraction uses the URL from `media_transcript.info.json` or the resolved audio URL
- No video download for audio-only content
- Must not break existing YouTube, X/Twitter, and web article workflows

## Acceptance Criteria

1. **YouTube search for podcasts** — When Step 1c receives a podcast URL (not YouTube), it searches YouTube for the episode title and uses the YouTube URL if found, proceeding to Step 2 (VTT download)
2. **Audio-only detection** — When the resolved media has no video streams and no subtitles, the skill detects this as audio-only and skips frame extraction entirely
3. **Onboard Whisper transcription** — For audio-only media without subtitles, the skill extracts audio via ffmpeg, runs faster-whisper (tiny or base model), and writes the result to `/tmp/media_clean_transcript.txt`
4. **No OCR prompt** — The Step 2b user prompt is never shown for audio-only content
5. **Graceful degradation** — If imageio-ffmpeg or Whisper fails, the skill falls back to the show notes description (existing Step 2a behavior)

## Verification

| Criterion | Evidence | Result |
|-----------|----------|--------|
| YouTube search runs for podcast URLs | URL classification log shows search leg running for atp.fm/683 | Pass |
| Audio-only detected without subtitles | `media_transcript.info.json` shows `subtitles: {}` and no video streams | Pass |
| Whisper produces transcript | `/tmp/media_clean_transcript.txt` exists with >500 characters of text | Pass |
| No OCR prompt shown | Skill output contains no "frame extraction" or "opencv" messages | Pass |
| Summary published | GitHub Gist URL in output | Pass |

## Scope & Constraints

### In Scope
- YouTube search for podcast episode titles
- Audio-only detection (no video streams, no subtitles)
- ffmpeg audio extraction
- faster-whisper transcription (tiny/base model)
- Show notes fallback if Whisper fails

### Out of Scope
- Video frame extraction for audio-only content
- Paid transcription APIs (Whisper only)
- Multi-language transcription
- Speaker diarization

### Non-Goals
- Transcribing in languages other than English
- Timestamped transcripts for podcasts
- Handling premium/members-only audio URLs that require auth

## Implementation Approach

### Step 1c — Add YouTube search for podcasts

In Step 1c, after detecting a non-YouTube URL:

1. Extract the episode title from the page (fetch via Tier 1 `fetch_html.py` or browser snapshot)
2. Search YouTube via `mcp__MCP_DOCKER__brave_web_search` for `<title> atp.fm` or similar
3. If a YouTube result matches the episode, use that URL and proceed to Step 2
4. If no match, fall through to audio-only detection

### New Step 2c — Audio-only detection and Whisper transcription

After Step 2a (caption fallback) determines subtitles are missing:

1. Read `/tmp/media_transcript.info.json`
2. Check if `formats[0].vcodec == "none"` (audio only) and `subtitles` is empty
3. If audio-only:
    a. Extract audio: `imageio-ffmpeg` bundles a ffmpeg binary — transcribe_audio.py uses it internally, no system ffmpeg needed
    b. Transcribe: `uv run --with "faster-whisper,imageio-ffmpeg" python3 -c "..."` with tiny or base model
   c. Write segments to `/tmp/media_clean_transcript.txt` (one sentence per line, no timestamps)
   d. Skip Step 2b (frame extraction) entirely
4. If extraction fails, use show notes description as fallback (Step 2a behavior)

### Step 1c modification

Change Step 1c logic from:
```
If already a YouTube URL → use it directly
Otherwise → extract title, search YouTube, use YouTube URL if found
```

To:
```
If already a YouTube URL → use it directly
Otherwise → extract title, search YouTube, use YouTube URL if found
If no YouTube result → check if URL is audio-only (mp3/m4a direct audio)
  → If audio-only: download directly, skip to Step 2c
  → If not: proceed to yt-dlp as before
```

## Lifecycle

| Phase | Date | Commit | Notes |
|-------|------|--------|-------|
| Active | 2026-04-15 | - | Initial creation |
| Implementable | 2026-04-15 | - | Implementation completed |