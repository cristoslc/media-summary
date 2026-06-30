#!/usr/bin/env bash
# Bootstrap script for media-summary skill.
# Installs missing dependencies (gh). Requires uv.
# yt-dlp runs transiently via `uv run --with yt-dlp`; brew for non-Python tools.
# Safe to re-run — skips anything already installed.

set -euo pipefail

MARKER="${XDG_DATA_HOME:-$HOME/.local/share}/media-summary/.bootstrapped"

# If already bootstrapped, verify tools still exist and exit early
if [[ -f "$MARKER" ]]; then
  missing=0
  command -v uv  >/dev/null 2>&1 || missing=1
  command -v gh  >/dev/null 2>&1 || missing=1
  if [[ $missing -eq 0 ]]; then
    exit 0
  fi
  # Something was removed — fall through to re-check
fi

echo "media-summary: checking dependencies…"

# uv is a hard requirement — it manages Python and Python packages
if ! command -v uv >/dev/null 2>&1; then
  echo "ERROR: uv is required but not found. Install it first:" >&2
  echo "  curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  exit 1
fi

HAS_BREW=0
command -v brew >/dev/null 2>&1 && HAS_BREW=1

install_with_brew() {
  echo "  → installing $1 via brew …"
  brew install "$1"
}

# Node.js is needed for puppeteer (HTML ingestion for JS-heavy pages)
if ! command -v node >/dev/null 2>&1; then
  if [[ $HAS_BREW -eq 1 ]]; then
    install_with_brew node
  else
    echo "WARNING: Node.js is required for puppeteer (JS-heavy HTML pages) but not found." >&2
    echo "  Install manually: https://nodejs.org" >&2
  fi
fi

# --- gh CLI (not a Python package — brew only) ---
if ! command -v gh >/dev/null 2>&1; then
  if [[ $HAS_BREW -eq 1 ]]; then
    install_with_brew gh
  else
    echo "WARNING: gh CLI requires Homebrew to install automatically." >&2
    echo "  Install manually: https://cli.github.com" >&2
  fi
fi

# --- Verify gh is authenticated ---
if command -v gh >/dev/null 2>&1; then
  if ! gh auth status >/dev/null 2>&1; then
    echo "WARNING: gh CLI is installed but not authenticated." >&2
    echo "  Run: gh auth login" >&2
  fi
fi

# --- Puppeteer npm package (for JS-heavy HTML pages) ---
SKILL_NODE_DIR="$(dirname "$0")/../node_modules"
if ! node -e "require('puppeteer')" 2>/dev/null; then
  echo "  → installing puppeteer via npm …"
  mkdir -p "$(dirname "$0")"/..
  npm install --prefix "$(dirname "$0")"/.. puppeteer 2>&1 | tail -1
fi

# Stamp the marker so subsequent runs exit early
mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"

# --- One-time permissions audit ---
# Scan settings files for overly broad patterns that could be exploited
# if a transcript contains prompt injection.

# Each entry: "colon_pattern|space_pattern|explanation"
BROAD_PATTERNS=(
  'Bash(osascript:*)|Bash(osascript *)|Full arbitrary code execution via AppleScript — keychain access, app control, shell commands.'
  'Bash(open:*)|Bash(open *)|Opens any file or URL via default handler — phishing, payload launch.'
  'Bash(gh gist:*)|Bash(gh gist *)|Covers gh gist delete — a hijacked session could wipe your public gists.'
  'Bash(gh:*)|Bash(gh *)|Covers every gh subcommand — delete repos, close issues, merge PRs, add deploy keys.'
)

audit_permissions() {
  local dominated=()
  local settings_files=(
    "$HOME/.claude/settings.json"
    "$HOME/.claude/settings.local.json"
  )
  local project_root
  project_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$project_root" ]]; then
    settings_files+=("$project_root/.claude/settings.json")
    settings_files+=("$project_root/.claude/settings.local.json")
  fi

  for f in "${settings_files[@]}"; do
    [[ -f "$f" ]] || continue
    for entry in "${BROAD_PATTERNS[@]}"; do
      IFS='|' read -r colon_pat space_pat explanation <<< "$entry"
      if grep -qF "$colon_pat" "$f" 2>/dev/null || \
         grep -qF "$space_pat" "$f" 2>/dev/null; then
        dominated+=("$colon_pat  in $f|$explanation")
      fi
    done
  done

  if [[ ${#dominated[@]} -eq 0 ]]; then
    return
  fi

  echo ""
  echo "┌─────────────────────────────────────────────────────────────┐"
  echo "│              ⚠  BROAD PERMISSIONS DETECTED                 │"
  echo "└─────────────────────────────────────────────────────────────┘"
  echo ""
  echo "  Found overly broad patterns in your settings:"
  echo ""
  for item in "${dominated[@]}"; do
    local pattern="${item%%|*}"
    local risk="${item#*|}"
    echo "    • $pattern"
    echo "      → $risk"
    echo ""
  done
  echo "  Why this matters: this skill feeds YouTube captions — which"
  echo "  anyone can write — into Claude's context. Broad patterns"
  echo "  widen the attack surface if a transcript contains prompt"
  echo "  injection. Swap them for the narrow entries listed below,"
  echo "  or ignore if this is a sandboxed/throwaway environment."
  echo ""
}
audit_permissions

echo ""
echo "media-summary: all dependencies ready."

cat <<'GUIDANCE'

┌─────────────────────────────────────────────────────────────┐
│                  PERMISSIONS SETUP                         │
└─────────────────────────────────────────────────────────────┘

This skill will ask you to approve several shell commands on
every run. To skip those prompts, add the permissions below
to your Claude Code allowedTools.

HOW TO ADD PERMISSIONS:

  For this project only (recommended):
    Open (or create) .claude/settings.json in your project root
    and add an "allowedTools" array, or run:
      claude config set allowedTools '[ ... ]' --project

  Globally (all projects):
    Edit ~/.claude/settings.json, or run:
      claude config set allowedTools '[ ... ]' --global

  Why not per-session? When Claude Code prompts you to allow
  a tool, the pattern it saves is broader than these entries
  (e.g. "Bash(gh gist:*)" instead of "Bash(gh gist create
  --public*)"), which grants more access than intended.

Add these entries to the allowedTools array:

  "Skill(media-summary)",
  "Bash(bash */scripts/bootstrap.sh)",
  "Bash(uv run */scripts/parse_subs.py)",
  "Bash(uv run */scripts/fetch_x_thread.py*)",
  "Bash(uv run --with readability-lxml*)",
  "Bash(node */scripts/fetch_html_puppeteer.js*)",
  "Bash(bash */scripts/yt-dlp.sh*)",
  "Bash(uv run --with opencv-python-headless*)",
  "Bash(uv run --with easyocr*)",
  "Bash(uv run --with mlx-whisper*)",
  "Bash(uv run --with faster-whisper*)",
  "Bash(test -s /tmp/media_transcript*)",
  "Bash(gh auth:*)",
  "Bash(open -g ~/Downloads/*_summary.md*)",
  "Bash(osascript -e 'display notification*)",
  "Bash(bash */scripts/publish_transcript.sh*)",
  "Bash(bash */scripts/publish_summary.sh*)",
  "Bash(bash */scripts/process_yt_output.sh)",
  "Bash(gh gist create --public*)",
  "Bash(gh gist edit*)"

WHY THESE ARE SAFE:
  • bootstrap.sh    — no-op after first run; only installs via uv/brew/npm
  • uv run parse_subs — pure string processing; discovers subtitle file, parses VTT or SRT, deduplicates overlapping cues, writes to /tmp
  • fetch_x_thread   — calls fxtwitter API only; writes to fixed /tmp paths
  • uv run readability — HTTP GET + article extraction; writes to /tmp only
  • node puppeteer   — headless Chromium renders page; extracts text; writes to /tmp
  • yt-dlp.sh        — thin uv wrapper; called with --skip-download for subs, full download only for frame extraction
  • opencv/easyocr   — transient via uv; only used when subtitle/caption fallback triggers
  • faster-whisper/imageio-ffmpeg — transient via uv; local transcription + bundled ffmpeg, no external API calls
  • test -s           — read-only file existence check on /tmp transcript files
  • gh auth          — read-only status check
  • open -g          — background-only, scoped to ~/Downloads/*_summary.md
  • osascript        — only matches 'display notification', not arbitrary AppleScript
  • gh gist create   — create-only; cannot delete or list existing gists
  • gh gist edit     — edit-only; needed to backfill the self-referencing URL
  • publish_transcript — verifies transcript ≥200 chars; uploads as gist; exits hard if not
  • publish_summary  — creates summary gist; backfills URL; opens file; sends notification
  • process_yt_output — checks VTT; extracts caption fallback; detects audio-only

REVIEW BEFORE GRANTING:
  Scripts live at the installed skill location. Read them first:
    ~/.claude/skills/media-summary/scripts/bootstrap.sh
    ~/.claude/skills/media-summary/scripts/parse_subs.py
    ~/.claude/skills/media-summary/scripts/transcribe_audio.py
    ~/.claude/skills/media-summary/SKILL.md

THREAT MODEL (what could go wrong):
  Full details: ~/.claude/skills/media-summary/README.md

GUIDANCE
