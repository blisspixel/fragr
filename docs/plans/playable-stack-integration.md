# Playable stack integration

**Status:** implemented, 2026-09-28. Integration review: [PR #297](https://github.com/blisspixel/fragr/pull/297). External spend $0.

## Goal and reason

Combine the independently green campaign, multiplayer, controls, hosting and
README drafts on one exact source tree. Each draft passes against its parent,
but their shared client, server, roadmap and screenshot files have not been
verified together. This integration is the v0.58.0 release candidate and
prepares the next player session. It does not substitute for that session.

## Scope

1. Start from `main` in an isolated worktree. Integrate the exact tips of the
   M02 player gate (#293), CTF socket gate (#295), delayed WebSocket probe
   (#296), local and plan-only container host (#287), and concise README
   (#271). Keep their existing feature and test commits intact in their own
   draft branches. Record the exact tip hashes in the evidence section.
2. Resolve overlaps by preserving both contracts. The server remains
   authoritative, M02 run carry and CTF rules remain distinct, prediction
   stays on WebSocket, and the README stays a short entry point to linked docs.
   Do not infer a transport migration or cloud deployment from this build.
3. Verify formatting, Clippy, workspace tests, unfiltered coverage, release
   build, Godot checks, focused campaign and CTF sockets, container and
   Terraform validation where tools are available. Run and inspect the visual
   tour if any player-facing conflict requires a presentation change.
4. Record commands, results, merge choices, remaining failures and the next
   human gates in this plan. An integration success must be demonstrated on
   the combined exact head, not inferred from the separate draft checks.

## Boundaries

No protocol revision was needed. If a conflict changes a wire or save shape,
update its owner, readers and protocol document together. M02 keeps Latch's
voluntary help, optional captive evacuation, and a noncombat Notary glimpse.
CTF remains server-owned. No paid asset API, GCP apply or deployment is part
of this work. The integrated branch is to pass CI, merge to `main` and be
released as v0.58.0. The M02 uncoached player gate,
human CTF round, two-machine controls session and public week remain open.

## Success criteria

- All five tip trees are represented in one clean integration head.
- Any source conflicts are resolved with focused tests for their behavior.
- The combined tree passes the relevant local and exact-head CI gates, with
  no coverage-floor change or omitted failure.
- README remains concise, accurate for the latest shipped release, and links
  to detailed playing, hosting, campaign and roadmap documents.

## Evidence and handoff

The local integration branch combines these exact tips, all of which are
ancestors of its head:

| Draft | Tip |
|---|---|
| M02 player gate #293 | `03a755fe1fb33ac6667607d1814ca6535ed9b973` |
| CTF socket gate #295 | `0d741e9c7ddf0ddbcec18ee8ef0ba0d934102b07` |
| Delayed WebSocket probe #296 | `7f6f729bb633c87beab3cabf8a8078e53e613853` |
| COS container host #287 | `3965395488a8c83178938fee75e4ec84b307eb87` |
| Concise README #271 | `fb7f532c78ff6fcfe61d7806788fe0cdcfeaf12c` |

The M02/CTF merge kept both presentation and event types and assigned their
existing gameplay capabilities 22 and 14. The network merge required a shared
height-aware live movement step so low Crawlers still fit under the authored
beam while ordinary fighters use the same default-height step as prediction.
Its deterministic test checks both paths. The hosting merge kept the latest
twenty-level canon, local container image and plan-only COS host. The README
merge kept four inspected stills and linked the longer playing and hosting
instructions.

Independent review found teammate aim assist in team modes and lost one-shot
inputs after a failed WebSocket send. Both were fixed with focused Godot tests.
The first full Godot run also found test network doubles that did not report
successful sends, and a camera read of an absent prediction field. The focused
tests now pass. These failures were retained as integration evidence rather
than counting the separate draft checks as a combined pass.

Local `cargo fmt --all -- --check`, workspace Clippy with warnings denied,
workspace tests, release server build and the pinned full Godot checker passed
on the combined tree. Unfiltered `cargo llvm-cov --workspace --locked
--fail-under-lines 90` passed at 93.77% of workspace lines. The 32-state
`tools/qa_tour.sh --publish` passed and refreshed the tour stills. Its contact
sheet was inspected. Docker Desktop is unavailable locally, so the container
CI job is the image and Compose gate. Two rejected $0 M02 rendered studies
were preserved from dirty side worktrees as superseded plans before cleanup.
No cloud resource or paid API was called. The unsteered M02, human CTF,
two-machine LAN and public-week gates remain open after this integration.

The exact-head CI and merge record live on [PR #297](https://github.com/blisspixel/fragr/pull/297).
The packaged release record lives at [v0.58.0](https://github.com/blisspixel/fragr/releases/tag/v0.58.0).
Superseded draft PRs and worktrees are retired after the merge.
