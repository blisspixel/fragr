# M02 natural entry composition

**Status:** in flight, 2026-09-28. Based on the stacked M02 visual head `5283652`. No external spend.

## Goal and reason

The gallery opening and Latch silhouette now exist, but the gallery QA state explicitly aims the player at Latch. That proves a possible view, not the view delivered to a player who joins and does nothing. The primary spawn is at `[0, 3, -31]`, faces yaw 1.5707964 (straight along positive Z), and receives level pitch. Latch's restraint is across the window near `[7.55, 1.9, -10]`, roughly 20 degrees off center and 7 degrees down from the standing eye. Inspect the actual unforced first-person image, then improve the authored opening composition through the spawn facing only if it makes the destination clearer.

## Scope and constraints

- Capture the real primary spawn before any `look_at`, scripted motion, or camera pose change. Record server and camera yaw and pitch together, and inspect the image at game resolution.
- Prefer a minimal yaw edit in `server/maps/m02-persons-unknown.json`. This draft targets the primary solo entry only; alternate party spawns retain their prior facing. Move the spawn only if facing alone cannot show the restraint without breaking immediate Shotgun discovery or the first fight.
- Add deterministic tests for the authored primary spawn facing, standing line of sight to the restraint, frame placement within the camera's horizontal view, nearby Shotgun access, and normal stair reachability.
- Rerun the guard-room Shotgun lesson, both Crawler cues in order, retry, side-ward survival, and solo human and agent route tests. Capture the final unforced view through a QA state without `look_at` or other camera intervention.

No camera takeover, waypoint, new asset, new geometry, encounter change, protocol field, paid call or cloud resource is in scope. A successful frame remains authored engineering evidence; a new player's understanding and human fun still require their own review. The Notary tableau remains separate work.

## Implementation and evidence gate

`server/maps/m02-persons-unknown.json` owns the spawn; `maps/authored/m02_tests.rs` and the M02 route tests own deterministic evidence. `client/scripts/spectator_cam.gd` adopts the server yaw once on first-person join, while `client/scripts/qa_tour.gd` asserts both camera and server yaw with `expect_yaw` and both pitch values with passive `expect_pitch`. The QA manifest must omit `look_at` in its first state. Update the mission brief and the single Full build order in the roadmap with observed status and limitations. Keep the earlier deliberately aimed gallery capture as a separate visibility comparison.

Done for this bounded draft when the unforced image is inspected and linked, the spawn test fails on the old yaw and passes on the new one, M02 route checks pass, and Rust and Godot focused verification is clean. Report wider repository gates separately. Review the diff before committing or pushing; release and player-facing acceptance remain separate gates.

## Observed result and limitations

The untouched primary spawn passed the live no-look QA check at yaw 1.5707964 and pitch zero. Its frame showed the ward through the window, but the restraint destination sat away from the player's natural aim. A new authored spawn test failed at that old yaw. With feet and every solid unchanged, yaw 1.2256624 centers the Latch direction horizontally. The same one-state QA check passed with live camera and server yaw both 1.2256624, pitch zero, no `look_at`, walking or camera pose. [Unedited before and after frames](../screenshots/m02-natural-entry/README.md) record the composition on Godot 4.7.2-stable with an AMD Radeon 780M at 1280x720. Latch is still a small figure near machinery and the first-player recognition gate stays open.

The first version of the new test mistakenly added fighter body radius to the Shotgun's claim radius; the server's pickup check uses the 1.75 m claim radius around the player's center. After correcting the test to the server contract, all 58 M02-scoped Rust tests passed serially. They include the starting Shotgun claim, first guard-room lesson, two Crawler cues in order, wipe/retry, solo human and agent departure, and Severe side-ward supplies. The alternate gallery spawns were not changed or framed by this capture. This is a primary spawn composition improvement, not a full multiplayer arrival review.

The authored map hash changes with the yaw field, so the existing local-run compatibility rule treats an older M02 save as a prior map revision and archives it before a new run. The M02 run-file hash behavior remains covered by its workspace test; this draft adds no save migration.

Local checks passed: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --locked -- -D warnings`, `cargo test --workspace --locked`, `git diff --check`, the full pinned Godot checker, the one-state Godot first-person QA tour on the exact candidate map, and the 32-state standard visual tour. Import and client logs had no script errors; the server logged an expected pre-join WebSocket handshake warning from the port probe and no gameplay error. The baseline and final QA manifests record camera and server facing; the final manifest asserts both yaw and pitch. A deliberately wrong expected pitch failed the QA tour, proving that the passive assertion is active. The standard tour contact sheet was inspected, and unrelated arena timing stills were kept out of this change. Coverage, benchmark, broader playtest and fresh-player gates were not run in this bounded review.
