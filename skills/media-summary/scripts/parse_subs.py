#!/usr/bin/env python3
"""Parse any subtitle file (VTT or SRT) into clean timestamped lines.

Discovers the subtitle file via /tmp/media_subtitle_path.txt (written by
process_yt_output.sh) or scans /tmp for known patterns. Deduplicates
overlapping caption windows and preserves the timestamp of first appearance.

Usage: parse_subs.py

Reads: subtitle file (VTT or SRT)
Writes: /tmp/media_clean_transcript.txt
"""
import os
import re
from collections import deque


def discover_subtitle_file():
    """Find the subtitle file written by process_yt_output.sh or scan /tmp."""
    # Path file written by process_yt_output.sh on VTT_OK
    path_file = "/tmp/media_subtitle_path.txt"
    if os.path.isfile(path_file):
        with open(path_file) as f:
            p = f.read().strip()
        if p and os.path.isfile(p):
            return p

    # Fallback: scan /tmp for known patterns
    for pat in ["/tmp/media_transcript.*.vtt", "/tmp/media_transcript.*.srt"]:
        import glob
        matches = glob.glob(pat)
        for m in matches:
            if os.path.isfile(m) and os.path.getsize(m) > 0:
                return m
    return None


def parse_timestamp(ts):
    """Extract HH:MM:SS or MM:SS or SS from a cue timestamp line."""
    ts = ts.strip()
    # Match HH:MM:SS or MM:SS
    m = re.match(r'^(\d{1,2}:\d{2}:\d{2})', ts)
    if m:
        return m.group(1)
    m = re.match(r'^(\d{2}:\d{2})', ts)
    if m:
        # Prefix with 00: for bare MM:SS (rare in SRT)
        return "00:" + m.group(1)
    return None


def parse_vtt(content):
    """Parse VTT content into list of (timestamp, text) cues."""
    cues = []
    blocks = re.split(r'\n\n+', content)
    for block in blocks:
        lines = [l.strip() for l in block.split('\n') if l.strip()]
        timestamp_line = None
        text_lines = []
        for line in lines:
            if '-->' in line:
                ts = parse_timestamp(line)
                if ts:
                    timestamp_line = ts
            elif not re.match(r'^\d+$', line) and not line.startswith('WEBVTT') \
                 and not line.startswith('Kind:') and not line.startswith('Language:'):
                clean = re.sub(r'<[^\u003e]+>', '', line).strip()
                if clean:
                    text_lines.append(clean)
        if timestamp_line and text_lines:
            cues.append((timestamp_line, ' '.join(text_lines)))
    return cues


def parse_srt(content):
    """Parse SRT content into list of (timestamp, text) cues."""
    cues = []
    # SRT blocks are separated by blank lines, each starts with a sequence number
    blocks = re.split(r'\n\n+', content)
    for block in blocks:
        lines = [l.strip() for l in block.split('\n') if l.strip()]
        if not lines:
            continue
        # First line should be a sequence number, skip it
        i = 0
        if re.match(r'^\d+$', lines[0]):
            i = 1
        if i >= len(lines):
            continue
        timestamp_line = None
        text_lines = []
        for line in lines[i:]:
            if '-->' in line:
                ts = parse_timestamp(line)
                if ts:
                    timestamp_line = ts
            else:
                clean = re.sub(r'<[^\u003e]+>', '', line).strip()
                if clean:
                    text_lines.append(clean)
        if timestamp_line and text_lines:
            cues.append((timestamp_line, ' '.join(text_lines)))
    return cues


def deduplicate(cues):
    """Emit only new words per cue, preserving the timestamp of first appearance."""
    WINDOW = 50
    result_lines = []
    recent_words = deque(maxlen=WINDOW)

    for timestamp, text in cues:
        words = text.split()
        tail = list(recent_words)
        overlap = 0
        for i in range(min(len(words), len(tail)), 0, -1):
            if words[:i] == tail[-i:]:
                overlap = i
                break
        new_words = words[overlap:]
        if new_words:
            result_lines.append(f'[{timestamp}] {" ".join(new_words)}')
            recent_words.extend(new_words)

    return result_lines


def main():
    sub_file = discover_subtitle_file()
    if not sub_file:
        print("No subtitle file found", file=__import__('sys').stderr)
        __import__('sys').exit(1)

    with open(sub_file, 'r', encoding='utf-8-sig') as f:
        content = f.read()

    if sub_file.lower().endswith('.vtt'):
        cues = parse_vtt(content)
    elif sub_file.lower().endswith('.srt'):
        cues = parse_srt(content)
    else:
        # Try VTT first, then SRT
        cues = parse_vtt(content)
        if not cues:
            cues = parse_srt(content)

    lines = deduplicate(cues)

    with open('/tmp/media_clean_transcript.txt', 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    print(f"Saved {len(lines)} lines from {sub_file}")


if __name__ == '__main__':
    main()
