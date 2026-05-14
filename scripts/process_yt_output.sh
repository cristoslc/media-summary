#!/usr/bin/env bash
# Post-process yt-dlp output: find any subtitle file (VTT or SRT), extract caption
# fallback, detect audio-only content from info.json. Called after yt-dlp has
# written subtitle files and /tmp/media_transcript.info.json.
#
# Usage: process_yt_output.sh
#
# Reads:
#   /tmp/media_transcript.info.json     — yt-dlp metadata JSON
#   Any /tmp/media_transcript.<lang>.(vtt|srt) — subtitle file (discovered)
#
# Writes (conditionally):
#   /tmp/media_subtitle_path.txt        — path to the discovered subtitle file
#   /tmp/media_clean_transcript.txt     — caption fallback text (if subtitle missing
#                                         but description is sufficient)
#
# Exit codes and stdout:
#   0  + VTT_OK           — subtitle file exists and is non-empty; proceed to Step 3
#   0  + CAPTION_OK       — no subtitle, but description written as fallback; skip Step 3
#   0  + AUDIO_ONLY       — no subtitle, no caption; media is audio-only; whisper needed
#   0  + VIDEO_NO_SUBS    — no subtitle, no caption; has video; try frame extraction
#   3  + CAPTION_THIN     — description exists but ≤100 non-hashtag chars
#   4  + INFO_MISSING     — info.json not found (cannot classify)

set -euo pipefail

PREFIX="/tmp/media_transcript"
INFO_PATH="${PREFIX}.info.json"
SUBTITLE_PATH_FILE="/tmp/media_subtitle_path.txt"
TRANSCRIPT_PATH="/tmp/media_clean_transcript.txt"
MIN_CAPTION_CHARS=100

# Discover subtitle file (any language, VTT or SRT)
subtitle_file=""
for f in "${PREFIX}".*.vtt "${PREFIX}".*.srt; do
    if [[ -f "$f" && -s "$f" ]]; then
        subtitle_file="$f"
        break
    fi
done

# Check subtitle
if [[ -n "$subtitle_file" ]]; then
    echo "$subtitle_file" > "$SUBTITLE_PATH_FILE"
    echo "VTT_OK"
    exit 0
fi

# No subtitle — need info.json to decide next step
if [[ ! -f "$INFO_PATH" ]]; then
    echo "INFO_MISSING"
    exit 4
fi

# Step 2a — Caption fallback: extract description from info.json
description=$(python3 -c "
import json, re, sys
with open('$INFO_PATH') as f:
    info = json.load(f)
desc = info.get('description', '')
# Strip hashtags and whitespace
clean = re.sub(r'#\w+', '', desc).strip()
print(clean)
" 2>/dev/null) || description=""

desc_len=${#description}

if [[ "$desc_len" -gt "$MIN_CAPTION_CHARS" ]]; then
    # Write as one paragraph per line
    echo "$description" | fold -s -w 120 > "$TRANSCRIPT_PATH"
    echo "CAPTION_OK"
    exit 0
fi

if [[ "$desc_len" -gt 0 ]]; then
    echo "CAPTION_THIN"
    # Don't exit yet — still need to check audio-only
fi

# Step 2c — Audio-only detection
audio_only=$(python3 -c "
import json, sys
with open('$INFO_PATH') as f:
    info = json.load(f)

# Check subtitles
subs = info.get('subtitles', {})
has_subs = bool(subs)

# Check formats for video streams
formats = info.get('formats', [])
has_video = any(
    f.get('vcodec', 'none') != 'none'
    for f in formats
    if f.get('vcodec') is not None
)

if not has_subs and not has_video:
    print('true')
else:
    print('false')
" 2>/dev/null) || audio_only="false"

if [[ "$audio_only" == "true" ]]; then
    echo "AUDIO_ONLY"
    exit 0
fi

echo "VIDEO_NO_SUBS"
exit 0
