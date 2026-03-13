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

echo "media-summary: all dependencies ready."
