#!/usr/bin/env node
/**
 * Puppeteer-based HTML renderer for JS-heavy pages.
 *
 * Usage: node fetch_html_puppeteer.js <url>
 *
 * Renders the page in a headless Chromium, waits for content to settle,
 * then extracts the main article text. Writes to /tmp/media_clean_transcript.txt
 * and prints JSON metadata to stdout.
 *
 * Requires: npm install puppeteer (handled by bootstrap.sh)
 */

const fs = require('fs');
const path = require('path');

const TRANSCRIPT_PATH = '/tmp/media_clean_transcript.txt';
const RAW_PATH = '/tmp/media_raw_puppeteer.html';
const MIN_CONTENT_LENGTH = 200;

async function waitForContent(page, maxWait = 8000) {
  const start = Date.now();
  let prevLen = 0;
  while (Date.now() - start < maxWait) {
    const len = await page.evaluate(() => document.body?.innerText?.length || 0);
    if (len > MIN_CONTENT_LENGTH && len === prevLen) break;
    prevLen = len;
    await new Promise(r => setTimeout(r, 500));
  }
}

async function extractContent(page) {
  return page.evaluate(() => {
    const selectors = [
      'article', '[role="article"]', 'main', '[role="main"]',
      '.post-content', '.article-body', '.entry-content',
      '.story-body', '.post-text', '.feed-shared-update-v2__description',
      '.break-words', '.attributed-text-segment-list__content',
      '.update-components-text', '.core-rail',
    ];
    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el && el.innerText.trim().length > 100) {
        return el.innerText.trim();
      }
    }
    return document.body.innerText.trim();
  });
}

async function extractMetadata(page) {
  return page.evaluate(() => {
    const getMeta = (names) => {
      for (const name of names) {
        const el = document.querySelector(`meta[property="${name}"], meta[name="${name}"]`);
        if (el && el.content) return el.content;
      }
      return '';
    };
    return {
      title: getMeta(['og:title', 'twitter:title']) || document.title || '',
      author: getMeta(['author', 'article:author', 'og:article:author']) || '',
      published_date: getMeta(['article:published_time', 'date', 'publishdate']) || '',
      description: getMeta(['og:description', 'twitter:description', 'description']) || '',
      site_name: getMeta(['og:site_name', 'twitter:site']) || '',
    };
  });
}

async function main() {
  const url = process.argv[2];
  if (!url) {
    console.error('usage: fetch_html_puppeteer.js <url>');
    process.exit(1);
  }

  let puppeteer;
  try {
    puppeteer = require('puppeteer');
  } catch (e) {
    console.error('error: puppeteer not installed. Run: npm install puppeteer');
    process.exit(1);
  }

  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
  });

  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1280, height: 800 });

    await page.setUserAgent(
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' +
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
    );

    await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });
    await waitForContent(page);

    // Scroll to load lazy content
    await page.evaluate(async () => {
      const delay = ms => new Promise(r => setTimeout(r, ms));
      for (let i = 0; i < 8; i++) {
        window.scrollBy(0, 800);
        await delay(300);
      }
      window.scrollTo(0, 0);
    });
    await new Promise(r => setTimeout(r, 1000));

    const rawHtml = await page.content();
    fs.writeFileSync(RAW_PATH, rawHtml, 'utf-8');

    const content = await extractContent(page);
    const metadata = await extractMetadata(page);

    if (content.trim().length < MIN_CONTENT_LENGTH) {
      metadata.source_url = url;
      metadata.needs_browser = true;
      metadata.content_length = content.trim().length;
      console.log(JSON.stringify(metadata, null, 2));
      process.exit(2);
    }

    fs.writeFileSync(TRANSCRIPT_PATH, content.trim() + '\n', 'utf-8');

    metadata.source_url = url;
    metadata.needs_browser = false;
    metadata.content_length = content.trim().length;
    console.log(JSON.stringify(metadata, null, 2));
  } finally {
    await browser.close();
  }
}

main().catch(e => {
  console.error(`error: ${e.message}`);
  process.exit(1);
});