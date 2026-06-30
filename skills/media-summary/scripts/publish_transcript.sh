#!/usr/bin/env bash
# Hard gate: verify /tmp/media_clean_transcript.txt exists and is substantial,
# then publish it as a public GitHub Gist. Exits non-zero if transcript is
# missing or too short, or if gist upload fails.
#
# Usage: publish_transcript.sh <title>
#   title  — used to derive the gist filename slug (falls back to "media-transcript")
#
# Outputs (stdout):
#   TRANSCRIPT_GIST_URL=<url>
#
# Exit codes:
#   0 - success
#   1 - transcript missing or too short
#   2 - gist upload failed

set -euo pipefail

TRANSCRIPT_PATH="/tmp/media_clean_transcript.txt"
MIN_CHARS=200

title="${1:-media transcript}"

# 3.5a — Verify transcript
if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "ERROR: $TRANSCRIPT_PATH does not exist. Transcript acquisition failed." >&2
  exit 1
fi

transcript_chars=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
echo "Transcript size: $transcript_chars characters" >&2

if [[ "$transcript_chars" -lt "$MIN_CHARS" ]]; then
  echo "ERROR: Transcript too short ($transcript_chars chars, minimum $MIN_CHARS). A summary cannot be generated without a substantial transcript." >&2
  exit 1
fi

# 3.5b — Derive slug and upload to Gist
slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-\+/-/g;s/^-//;s/-$//')
if [[ -z "$slug" ]]; then
  slug="media-transcript"
fi

gist_url=$(gh gist create --public \
  --filename "transcript-${slug}.txt" \
  --desc "${title} — Transcript" \
  "$TRANSCRIPT_PATH") || {
  echo "ERROR: gh gist create failed. Cannot publish transcript gist." >&2
  exit 2
}

# 3.5c — Confirm
echo "TRANSCRIPT_GIST_URL=${gist_url}"