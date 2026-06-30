"""Transcribe audio using faster-whisper (local, no external API).

Usage: uv run --with "faster-whisper,imageio-ffmpeg" python3 scripts/transcribe_audio.py <audio_url_or_path> [model_size]

Extracts speech from an audio source and writes clean transcript lines
(one sentence per line, no timestamps) to /tmp/media_clean_transcript.txt.

Accepts either a local file path or a URL (http/https). For URLs, the audio
is downloaded via imageio-ffmpeg's bundled ffmpeg — no system ffmpeg needed.

model_size defaults to 'base'. Options: tiny, base, small.
"""

import subprocess
import sys

audio_input = sys.argv[1]
model_size = sys.argv[2] if len(sys.argv) > 2 else "base"

import imageio_ffmpeg

ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()

wav_path = "/tmp/media_audio.wav"

if audio_input.startswith(("http://", "https://")):
    cmd = [
        ffmpeg_exe,
        "-y",
        "-i",
        audio_input,
        "-vn",
        "-acodec",
        "pcm_s16le",
        "-ar",
        "16000",
        "-ac",
        "1",
        wav_path,
    ]
else:
    cmd = [
        ffmpeg_exe,
        "-y",
        "-i",
        audio_input,
        "-vn",
        "-acodec",
        "pcm_s16le",
        "-ar",
        "16000",
        "-ac",
        "1",
        wav_path,
    ]

result = subprocess.run(cmd, capture_output=True, text=True)
if result.returncode != 0:
    print(f"ERROR: ffmpeg failed: {result.stderr}", file=sys.stderr)
    sys.exit(1)

from faster_whisper import WhisperModel

model = WhisperModel(model_size, device="cpu", compute_type="int8")

segments, info = model.transcribe(wav_path, beam_size=1, language="en")

lines = []
for segment in segments:
    text = segment.text.strip()
    if text:
        lines.append(text)

with open("/tmp/media_clean_transcript.txt", "w") as f:
    f.write("\n".join(lines))

print(
    f"Transcribed {info.duration:.0f}s of audio into {len(lines)} lines (model={model_size})"
)
