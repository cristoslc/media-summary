#!/usr/bin/env bash
# Bootstrap script for media-summary skill.
# Installs missing dependencies (yt-dlp, gh, python3).
# Prefers uv over brew for Python packages; uses brew for non-Python tools.
# Safe to re-run — skips anything already installed.

set -euo pipefail

MARKER="${XDG_DATA_HOME:-$HOME/.local/share}/media-summary/.bootstrapped"

# If already bootstrapped, verify tools still exist and exit early
if [[ -f "$MARKER" ]]; then
  missing=0
  command -v yt-dlp  >/dev/null 2>&1 || missing=1
  command -v python3  >/dev/null 2>&1 || missing=1
  command -v gh       >/dev/null 2>&1 || missing=1
  if [[ $missing -eq 0 ]]; then
    exit 0
  fi
  # Something was removed — fall through to re-check
fi

echo "media-summary: checking dependencies…"

# Detect available package managers
HAS_UV=0
HAS_BREW=0
command -v uv   >/dev/null 2>&1 && HAS_UV=1
command -v brew >/dev/null 2>&1 && HAS_BREW=1

if [[ $HAS_UV -eq 0 && $HAS_BREW -eq 0 ]]; then
  echo "ERROR: Neither uv nor brew found. Install one of them first:" >&2
  echo "  uv:   curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  echo "  brew: https://brew.sh" >&2
  exit 1
fi

install_with_uv() {
  echo "  → installing $1 via uv …"
  uv tool install "$1"
}

install_with_brew() {
  echo "  → installing $1 via brew …"
  brew install "$1"
}

# --- yt-dlp (Python package — prefer uv) ---
if ! command -v yt-dlp >/dev/null 2>&1; then
  if [[ $HAS_UV -eq 1 ]]; then
    install_with_uv yt-dlp
  elif [[ $HAS_BREW -eq 1 ]]; then
    install_with_brew yt-dlp
  fi
fi

# --- python3 ---
if ! command -v python3 >/dev/null 2>&1; then
  if [[ $HAS_BREW -eq 1 ]]; then
    install_with_brew python3
  elif [[ $HAS_UV -eq 1 ]]; then
    echo "  → installing Python via uv …"
    uv python install
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
  "Bash(python3 */scripts/parse_vtt.py)",
  "Bash(yt-dlp:*)",
  "Bash(gh auth:*)",
  "Bash(open -g ~/Downloads/*_summary.md*)",
  "Bash(osascript -e 'display notification*)",
  "Bash(gh gist create --public*)",
  "Bash(gh gist edit*)"

WHY THESE ARE SAFE:
  • bootstrap.sh    — no-op after first run; only installs via uv/brew
  • parse_vtt.py    — pure string processing; no eval/exec/subprocess/network
  • yt-dlp           — always called with --skip-download (subtitles only)
  • gh auth          — read-only status check
  • open -g          — background-only, scoped to ~/Downloads/*_summary.md
  • osascript        — only matches 'display notification', not arbitrary AppleScript
  • gh gist create   — create-only; cannot delete or list existing gists
  • gh gist edit     — edit-only; needed to backfill the self-referencing URL

REVIEW BEFORE GRANTING:
  Scripts live at the installed skill location. Read them first:
    ~/.claude/skills/media-summary/scripts/bootstrap.sh
    ~/.claude/skills/media-summary/scripts/parse_vtt.py
    ~/.claude/skills/media-summary/SKILL.md

THREAT MODEL (what could go wrong):
  Full details: ~/.claude/skills/media-summary/README.md

GUIDANCE
