# media-summary

A [Claude Code skill](https://agentskills.io) that downloads and summarizes audio/video media — podcasts, YouTube videos, talks, interviews, lectures, and conference presentations.

Given any media URL, it resolves a YouTube equivalent if needed, pulls the transcript via `yt-dlp`, generates a structured markdown summary, saves it locally, and publishes it as a public GitHub Gist.

## Requirements

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- Python 3
- [gh CLI](https://cli.github.com), authenticated
- A markdown editor or viewer registered as the default for `.md` files

## Installation

```bash
npx skills add cristoslc/media-summary
```

## Usage

```
/media-summary <url>
```

Supported sources include YouTube, Apple Podcasts, Spotify, and most conference recording sites. Non-YouTube URLs are automatically resolved to a YouTube equivalent for transcript extraction.

## Output

Each summary is saved to `~/Downloads/<slug>_summary.md` and published as a public GitHub Gist. The markdown file includes YAML frontmatter with the original URL, transcript source URL, Gist URL, and last-updated date.

### Summary structure

1. Key Takeaways
2. Guest/Speaker Background
3. Core Thesis
4. Major Topics Discussed
5. Books, Tools & Resources Mentioned
6. One-Sentence Bottom Line

## Template

The output format is defined in [`references/media-summary-template.md.j2`](references/media-summary-template.md.j2).
