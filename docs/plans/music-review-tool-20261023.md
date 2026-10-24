# Radio music review tool

**Status:** implemented locally, 2026-10-23. Local crate and workspace checks pass; the PR carries CI.
**Spend:** $0. The tool reads local files and calls no paid service.

## Goal

Nick listens to radio tracks and marks each one keep or reject quickly, then
promotes keepers into the shipped library with provenance intact. The radio is a
small in-game feature (seven music stations plus the news and chat station in
`client/assets/audio/radio/stations.json`), not the plot, so the tool stays small.

## Non-goals

- No generation, credit spend or quota calls. `batch` remains the producer.
- No commit, staging or Godot import. Promotion leaves the working tree for review.
- No browser game client. The page is a developer review aid on loopback only.
- No renumbering of existing tracks or changes to `radio.gd`.

## Architecture

- `fragr-audiogen review` (in `tools/audiogen/src/review.rs`) binds
  `127.0.0.1:6780` with `std::net`, one thread per connection and
  `Connection: close`. No new crates; `cargo deny` sees the same graph.
- The page is one embedded HTML file (`review.html`). It lists stations from
  `stations.json` and, per station, shipped files under
  `client/assets/audio/radio/<id>/` and candidates under
  `.agents/asset-round-20261023/audio/radio/<id>/`. Metadata comes from the
  nearest `audiogen-manifest.json` within two levels of the station folder.
- Decisions persist on every mark to
  `.agents/asset-round-20261023/music-review.json` through the crate's atomic,
  symlink-refusing writer. A damaged decisions file is an error, never overwritten.
- `fragr-audiogen promote` prints a plan; `--apply` copies keepers as
  `NN-slug.<ext>` after the station's highest number, copies the candidate
  manifest entry into `client/assets/audio/audiogen-manifest.json` (the record
  `radio.gd` loads), deletes rejected shipped files with their `.import`
  sidecars and manifest entries, and marks promoted candidates so a second run
  is a no-op. All paths are validated before any write.

## Safety

- Audio is served only for ids the server itself listed, with single-segment
  names, and the resolved path must stay inside its root.
- Requests need `Host` of `127.0.0.1` or `localhost` on the bound port (DNS
  rebinding). Decisions need `application/json` and a same-origin `Origin`
  when present (cross-site form posts).
- Header and body sizes are capped. Range requests are supported for seeking.
- A keeper without candidate provenance blocks promotion. A station that loses
  tracks may not end below 12 (the radio's no-repeat window) without `--force`.

## Verification

- Unit tests in `review.rs` and `main.rs`: decision persistence and reload,
  catalog scan with provenance, promotion planning, minimum and provenance
  refusals, idempotent apply, path traversal and symlink-style escapes, HTTP
  parsing, routing, range responses and one loopback socket round trip. No network.
- `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --locked -- -D warnings`,
  `cargo test --workspace --locked`, `cargo deny check licenses bans sources`.
- Manual smoke: the server on the real library with a scratch candidate,
  `curl` state, decision, range and refusal checks, a headless muted Chromium
  render of the page, and a dry-run promote.

## Success criteria

One command opens the page; marks survive restart; promotion is a reviewed,
reversible working-tree change with manifest provenance for every new track.
