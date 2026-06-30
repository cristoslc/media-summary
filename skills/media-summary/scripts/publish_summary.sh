#!/usr/bin/env bash
# Publish the summary markdown file as a public GitHub Gist, backfill the
# self-referencing gist_url into the file, then open it and post a notification.
#
# Usage: publish_summary.sh <slug> <title>
#   slug  — filename slug (e.g. "atp-683-power-concentration")
#   title — human-readable title for the gist description
#
# Expects ~/Downloads/<slug>_summary.md to exist.
# After success, the published Gist URL is printed to stdout.

set -euo pipefail

slug="${1:?Usage: publish_summary.sh <slug> <title>}"
title="${2:?Usage: publish_summary.sh <slug> <title>}"

summary_path="$HOME/Downloads/${slug}_summary.md"

if [[ ! -f "$summary_path" ]]; then
  echo "ERROR: $summary_path not found. Write the summary first." >&2
  exit 1
fi

# Step 6 — Create public Gist
gist_url=$(gh gist create --public \
  --filename "summary-${slug}.md" \
  --desc "${title} — Media Summary" \
  "$summary_path") || {
  echo "ERROR: gh gist create failed for summary." >&2
  exit 2
}

gist_id=$(echo "$gist_url" | sed 's|.*/||')

# Backfill gist_url into the summary file's frontmatter
sed -i '' "s|gist_url: (to be filled after publishing)|gist_url: ${gist_url}|" "$summary_path" 2>/dev/null || \
  sed -i "s|gist_url: (to be filled after publishing)|gist_url: ${gist_url}|" "$summary_path"

# Update the published Gist so it also contains the self-referencing URL
gh gist edit "$gist_id" "$summary_path" || {
  echo "WARNING: gh gist edit failed — gist created but not updated with self-URL." >&2
}

# Step 7 — Open and notify
open -g "$summary_path" 2>/dev/null || xdg-open "$summary_path" 2>/dev/null || true
osascript -e 'display notification "Summary saved and Gist published" with title "Media Summary"' 2>/dev/null || true

echo "$gist_url"