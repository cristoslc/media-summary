"""Fetch an X/Twitter thread via the fxtwitter API and write transcript + metadata.

Usage:
    uv run fetch_x_thread.py <tweet_url_or_id>

Outputs:
    /tmp/media_thread.json            raw fxtwitter response
    /tmp/media_clean_transcript.txt   stitched thread, one post per paragraph
    stdout                            JSON metadata (author, count, title_guess, post_urls)
"""
import json
import re
import sys
import urllib.error
import urllib.request

TRANSCRIPT_PATH = "/tmp/media_clean_transcript.txt"
RAW_PATH = "/tmp/media_thread.json"
API = "https://api.fxtwitter.com/2/thread/{id}"


def extract_tweet_id(s: str) -> str:
    m = re.search(r"/status/(\d+)", s)
    if m:
        return m.group(1)
    if s.isdigit():
        return s
    raise SystemExit(f"error: could not extract tweet id from: {s}")


def fetch(tweet_id: str) -> dict:
    req = urllib.request.Request(
        API.format(id=tweet_id),
        headers={"User-Agent": "media-summary/1.0"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: fetch_x_thread.py <tweet_url_or_id>")

    tweet_id = extract_tweet_id(sys.argv[1])
    try:
        data = fetch(tweet_id)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"error: fxtwitter HTTP {e.code} for tweet {tweet_id} ({e.reason})")
    except urllib.error.URLError as e:
        raise SystemExit(f"error: fxtwitter unreachable: {e.reason}")
    if data.get("code") != 200:
        raise SystemExit(f"error: fxtwitter returned {data.get('code')}: {data.get('message')}")

    thread = data.get("thread") or []
    if not thread:
        raise SystemExit("error: empty thread in response")

    root = thread[0]
    root_text = root.get("text", "")

    # Guard against the account-proxy caveat: root looks like a thread opener
    # but only one post came back.
    if len(thread) == 1 and re.search(r"(1/|🧵)", root_text):
        raise SystemExit(
            "error: root post looks like a thread opener but only 1 post returned. "
            "Upstream fxtwitter deployment likely lacks an authenticated account proxy."
        )

    with open(RAW_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    total = len(thread)
    paragraphs = [
        f"[{i}/{total}] {p.get('text', '').strip()}"
        for i, p in enumerate(thread, 1)
    ]
    with open(TRANSCRIPT_PATH, "w", encoding="utf-8") as f:
        f.write("\n\n".join(paragraphs) + "\n")

    author = root.get("author") or {}
    title_text = re.sub(r"^(@\w+\s+)+", "", root_text).strip()
    title_text = re.sub(r"\s+", " ", title_text)
    if len(title_text) > 80:
        truncated = title_text[:80]
        last_space = truncated.rfind(" ")
        title_text = truncated[:last_space] if last_space > 40 else truncated
    title_guess = title_text or f"Thread by @{author.get('screen_name', 'unknown')}"

    meta = {
        "tweet_id": tweet_id,
        "source_url": root.get("url"),
        "author_name": author.get("name"),
        "author_handle": author.get("screen_name"),
        "author_url": author.get("url"),
        "published_date": root.get("created_at"),
        "tweet_count": total,
        "title_guess": title_guess,
        "post_urls": [p.get("url") for p in thread],
    }
    print(json.dumps(meta, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
