# README navigation

**Status:** implemented, 2026-09-27. Draft PR review and CI remain open.

## Goal

Give a new player or host a clear first page: what fragr is, what the current
release can do, how to start the game, four inspected screenshots, and where to
find deeper instructions. Keep planned campaign and draft branch work visibly
separate from shipped features.

## Scope

- Shorten `README.md` while retaining its product voice and concrete quick
  start. Preserve exactly four player-facing stills there.
- Move controls, local save behavior, package installation and manual export,
  dedicated-host commands and options, and advanced agent setup into linked
  guides. Link the existing protocol, architecture, campaign, roadmap and
  asset provenance sources instead of repeating their technical detail.
- Verify every new relative link and each command against repository source,
  scripts or manifests. Keep release claims anchored to the current tag.

## Non-goals

No gameplay or wire change, package rebuild, cloud apply, asset generation,
release tag, or change to a draft feature's shipped status. This documentation
pass has no external spend.

## Review and verification

Inspect the rendered Markdown structure, verify local targets and image paths,
check `git diff --check`, scan added prose for attribution, emoji and dash
violations, and compare installation and command examples to source. A reader
should reach a working local game from the first screenful, then find controls,
save recovery, dedicated hosting, releases and agent setup in one click.

## Progress

- 2026-09-27: Baseline README spans roughly 380 physical lines and repeats
  full controls, saves, release packaging, host hardening, server flags and
  agent setup. Those details have distinct linked homes or will get one.
- 2026-09-27: Reduced the front page to roughly 100 physical lines with a
  playable quick start, current-release limits, four inspected stills and
  direct guide links. Added `PLAYING.md`, `DESKTOP.md` and `HOSTING.md` for the
  moved detail. Verified relative Markdown targets, package and CLI examples
  against the repository, and a clean diff check. No runtime code or assets
  changed. Review and CI on the draft PR remain to be recorded.
