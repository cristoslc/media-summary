---
title: "Routing Determinism in Media Summary"
artifact: SPIKE-009
track: container
status: Active
author: cristoslc
created: 2026-04-15
last-updated: 2026-04-15
priority-weight: high
type: ""
parent-epic: ""
parent-initiative: ""
linked-artifacts:
  - SPEC-008
depends-on-artifacts: []
addresses: []
evidence-pool: ""
source-issue: ""
swain-do: ""
---

# Routing Determinism in Media Summary

## Problem Statement

SPEC-008 identified two routing failures in `media-summary`:
1. YouTube search leg (Step 1c) was skipped for podcast URLs
2. Audio-only content triggered an OCR fallback prompt instead of Whisper

Both failures were enabled by prose-based conditional logic that agents can interpret flexibly. The question is what enforcement layer makes the skill's routing decisions deterministic for all future agents and edge cases.

## Questions

1. Which enforcement layer is appropriate given the skill's current maturity?
2. What is the minimal viable deterministic routing structure?
3. How does enforcement interact with the existing Step 1a/1b/1c/1d leg structure?

## Options Under Investigation

### 1. Assertions at Decision Gates (low enforcement)

A fail-fast approach: after key steps, assert preconditions are met.

```python
# In Step 2a after caption check
assert have_vtt or have_audio_url, "No captions and no audio URL — cannot proceed"

# In Step 2b before frame extraction prompt
assert have_video, "Frame extraction requires video — use Step 2c for audio-only"
```

**Pros:** Minimal structure, easy to retrofit, clear failure signal
**Cons:** Post-hoc (damage already done), relies on test coverage to catch gaps

### 2. Explicit Branching Table (medium enforcement)

Replace prose conditionals with a code block or YAML table:

```yaml
legs:
  x-thread:       → skip 2,3 → Step 4
  youtube:        → Step 2 → Step 3 → Step 4
  podcast-audio:  → Step 1c (YouTube search) → Step 2c (Whisper) → Step 4
  web-article:   → skip 2,3 → Step 4
```

**Pros:** Human-readable, unambiguous transitions, easy to audit
**Cons:** Still prose-adjacent — no machine enforcement unless parsed

### 3. State Machine with Required Transitions (high enforcement)

Encode the skill as a JSON state machine where each step declares valid next states:

```json
{
  "Step 1a": { "next": ["Step 4"], "required": true },
  "Step 1c": {
    "next": ["Step 2", "Step 2c"],
    "required": true,
    "condition": "non-YouTube URL"
  },
  "Step 2": { "next": ["Step 3", "Step 2a"], "required": true },
  "Step 2b": { "next": [], "blocked_if": "audio_only" }
}
```

**Pros:** Machine-verifiable, enforces skip-prevention structurally
**Cons:** Significant refactor of SKILL.md structure, higher maintenance burden

### 4. media-type Field in info.json (artifact-pinned classification)

Have `yt-dlp` write a `media_type` field to `info.json`:

```json
{
  "media_type": "podcast-audio",
  "has_vtt": false,
  "has_video": false,
  "has_audio": true
}
```

Then assert on `media_type` before each decision gate:

```python
assert media_type in allowed_types[step_name], f"Unexpected media_type {media_type} for step {step_name}"
```

**Pros:** Classification is pinned in artifacts, enabling post-hoc audit; separates detection from routing
**Cons:** Requires yt-dlp info-json format changes; adds coupling between steps

## Gate Criteria

| Criterion | Threshold |
|-----------|-----------|
| All 4 options documented | 4 entries in options section |
| Recommendation | One option selected with rationale |
| Implementation sketch | Concrete next step for selected option |

## Findings

_(empty — Active phase)_

## Summary

_(populated on transition to Complete)_

## Lifecycle

| Phase | Date | Commit | Notes |
|-------|------|--------|-------|
| Active | 2026-04-15 | - | Initial creation |