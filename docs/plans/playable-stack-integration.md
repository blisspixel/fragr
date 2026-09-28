# Playable stack integration

**Status:** in flight, 2026-09-28. Local integration branch only. External spend $0.

## Goal and reason

Combine the independently green campaign, multiplayer, controls, hosting and
README drafts on one exact source tree. Each draft passes against its parent,
but their shared client, server, roadmap and screenshot files have not been
verified together. This integration is a rehearsal for review and the next
player session, not a release or a substitute for that session.

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

No protocol revision is planned. If a conflict changes a wire or save shape,
update its owner, readers and protocol document together. M02 keeps Latch's
voluntary help, optional captive evacuation, and a noncombat Notary glimpse.
CTF remains server-owned. No paid asset API, GCP apply, deployment, merge to
`main`, tag or release is part of this work. The M02 uncoached player gate,
human CTF round, two-machine controls session and public week remain open.

## Success criteria

- All five tip trees are represented in one clean integration head.
- Any source conflicts are resolved with focused tests for their behavior.
- The combined tree passes the relevant local and exact-head CI gates, with
  no coverage-floor change or omitted failure.
- README remains concise, accurate for the latest shipped release, and links
  to detailed playing, hosting, campaign and roadmap documents.

## Evidence and handoff

In progress.
