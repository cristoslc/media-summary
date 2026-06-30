"""Fetch an HTML page and extract article text.

Tiered extraction:
  1. Specialty domain handler (LinkedIn embed/noredirect, etc.)
  2. HTTP GET + readability-lxml article extraction
  3. Basic tag-stripping fallback if readability fails

If extracted content is shorter than MIN_CONTENT_LENGTH chars, exits with
code 2 to signal the caller should try browser rendering (MCP tools or
puppeteer).

Usage:
    uv run --with "readability-lxml,lxml,beautifulsoup4" fetch_html.py <url>

Exit codes:
    0 - success, transcript written to /tmp/media_clean_transcript.txt
    1 - hard error (network, parse, etc.)
    2 - content too thin, try browser rendering

Outputs:
    /tmp/media_raw.html                 raw fetched HTML (tier 2+)
    /tmp/media_clean_transcript.txt      extracted article text
    stdout                               JSON metadata
"""

import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

TRANSCRIPT_PATH = "/tmp/media_clean_transcript.txt"
RAW_PATH = "/tmp/media_raw.html"
MIN_CONTENT_LENGTH = 200

UA = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.5",
}

SPECIALTY_DOMAINS = {
    "linkedin.com": "linkedin",
    "www.linkedin.com": "linkedin",
    "medium.com": "medium",
    "www.medium.com": "medium",
}


class MetaExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title = ""
        self.meta = {}
        self._in_title = False

    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        if tag == "title":
            self._in_title = True
        elif tag == "meta":
            name = (
                attrs_dict.get("name")
                or attrs_dict.get("property")
                or attrs_dict.get("http-equiv", "")
            )
            content = attrs_dict.get("content", "")
            if name and content:
                self.meta[name.lower()] = content

    def handle_data(self, data):
        if self._in_title:
            self.title += data

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False


def http_get(url: str, headers: dict = None) -> tuple:
    status, body, final_url = 0, "", url
    h = {**UA, **(headers or {})}
    req = urllib.request.Request(url, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode("utf-8", errors="replace")
            return r.status, body, r.url
    except urllib.error.HTTPError as e:
        body = (
            e.read().decode("utf-8", errors="replace")
            if hasattr(e, "fp") and e.fp
            else ""
        )
        return e.code, body, url
    except urllib.error.URLError as e:
        raise SystemExit(f"error: network error fetching {url}: {e.reason}")


def extract_metadata(html: str) -> dict:
    parser = MetaExtractor()
    parser.feed(html)
    m = parser.meta
    title = m.get("og:title") or m.get("twitter:title") or parser.title.strip() or ""
    author = (
        m.get("author") or m.get("article:author") or m.get("og:article:author") or ""
    )
    published = (
        m.get("article:published_time")
        or m.get("date")
        or m.get("publishdate")
        or m.get("pubdate")
        or ""
    )
    description = (
        m.get("og:description")
        or m.get("twitter:description")
        or m.get("description")
        or ""
    )
    site_name = m.get("og:site_name") or m.get("twitter:site") or ""
    return {
        "title": title,
        "author": author,
        "published_date": published,
        "description": description,
        "site_name": site_name,
    }


def extract_readability(html: str) -> str:
    from readability import Document
    from bs4 import BeautifulSoup

    doc = Document(html)
    summary_html = doc.summary()
    soup = BeautifulSoup(summary_html, "lxml")
    paragraphs = []
    for el in soup.find_all(
        ["p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "pre"]
    ):
        text = el.get_text(strip=True)
        if not text:
            continue
        if el.name.startswith("h"):
            paragraphs.append(f"\n## {text}\n")
        elif el.name == "li":
            paragraphs.append(f"- {text}")
        elif el.name == "blockquote":
            paragraphs.append(f"> {text}")
        else:
            paragraphs.append(text)
    return "\n\n".join(paragraphs)


def extract_basic(html: str) -> str:
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(html, "lxml")
    for tag in soup.find_all(
        ["script", "style", "nav", "footer", "header", "aside", "form", "noscript"]
    ):
        tag.decompose()
    return soup.get_text(separator="\n", strip=True)


def try_linkedin(url: str) -> tuple:
    post_id_match = re.search(r"-(\d+)-", url) or re.search(r"activity:(\d+)", url)
    if not post_id_match:
        urls_attempted = []
        embed_url = _linkedin_embed_url(url)
        if embed_url:
            urls_attempted.append(embed_url)
            status, html, final = http_get(embed_url)
            if status == 200 and html:
                meta = extract_metadata(html)
                content = meta.get("description", "")
                if len(content.strip()) < MIN_CONTENT_LENGTH:
                    try:
                        content = extract_readability(html)
                    except Exception:
                        pass
                if len(content.strip()) >= MIN_CONTENT_LENGTH:
                    return meta, content
        return None, None

    post_id = post_id_match.group(1)
    attempts = [
        f"https://www.linkedin.com/embed/feed/update/urn:li:activity:{post_id}",
        f"https://www.linkedin.com/posts/johnpcutler_activity-{post_id}-",
    ]

    for attempt_url in attempts:
        try:
            status, html, final = http_get(attempt_url)
        except SystemExit:
            continue
        if status != 200 or not html:
            continue
        meta = extract_metadata(html)
        content = meta.get("description", "")
        if len(content.strip()) < MIN_CONTENT_LENGTH:
            try:
                content = extract_readability(html)
            except Exception:
                pass
        if len(content.strip()) >= MIN_CONTENT_LENGTH:
            return meta, content

    return None, None


def _linkedin_embed_url(url: str) -> str | None:
    activity_match = re.search(r"activity[:=](\d+)", url)
    if activity_match:
        return f"https://www.linkedin.com/embed/feed/update/urn:li:activity:{activity_match.group(1)}"
    post_id = re.search(r"-(\d+)-", url)
    if post_id:
        return f"https://www.linkedin.com/embed/feed/update/urn:li:activity:{post_id.group(1)}"
    return None


def try_medium(url: str) -> tuple:
    try:
        status, html, final = http_get(url)
    except SystemExit:
        return None, None
    if status != 200 or not html:
        return None, None
    meta = extract_metadata(html)
    if "medium.com" in meta.get("site_name", "").lower() or meta.get("author"):
        try:
            content = extract_readability(html)
        except Exception:
            content = ""
        if len(content.strip()) >= MIN_CONTENT_LENGTH:
            return meta, content
    return None, None


SPECIALTY_HANDLERS = {
    "linkedin": try_linkedin,
    "medium": try_medium,
}


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: fetch_html.py <url>")

    url = sys.argv[1]
    parsed = urllib.parse.urlparse(url)
    domain = parsed.hostname or ""
    domain_key = SPECIALTY_DOMAINS.get(domain)

    metadata = {}
    content = ""

    # Tier 1: specialty domain handler
    if domain_key and domain_key in SPECIALTY_HANDLERS:
        try:
            spec_meta, spec_content = SPECIALTY_HANDLERS[domain_key](url)
            if spec_meta and spec_content:
                metadata = spec_meta
                content = spec_content
        except Exception:
            pass

    # Tier 2: generic HTTP fetch + readability
    if not content:
        try:
            status, html, final_url = http_get(url)
        except SystemExit:
            raise
        with open(RAW_PATH, "w", encoding="utf-8") as f:
            f.write(html)

        metadata = extract_metadata(html)

        try:
            content = extract_readability(html)
        except Exception:
            content = extract_basic(html)

    # Evaluate content sufficiency
    clean_content = content.strip()
    if len(clean_content) < MIN_CONTENT_LENGTH:
        meta_out = {
            **metadata,
            "source_url": url,
            "needs_browser": True,
            "content_length": len(clean_content),
        }
        print(json.dumps(meta_out, ensure_ascii=False, indent=2))
        sys.exit(2)

    with open(TRANSCRIPT_PATH, "w", encoding="utf-8") as f:
        f.write(clean_content + "\n")

    meta_out = {
        **metadata,
        "source_url": url,
        "needs_browser": False,
        "content_length": len(clean_content),
    }
    print(json.dumps(meta_out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
