# M02 gallery first view

**Status:** implemented in draft work, 2026-09-28. Stacked after the M02 live cue capture branch at `44c3a15`. No external spend.

## Goal and reason

The accepted Persons Unknown design puts the correction ward and Latch's restraint frame in the first gallery view, before the first shot. The current gallery has a deep sill across the only forward window. A line from the primary spawn's standing eye toward Latch descends into that sill before reaching the room. Establish a real first view that gives the player a destination and a reason to descend, then prove it with the same authoritative solids the server uses for movement and combat.

## Scope

- Adjust only the gallery window and immediately related authoritative geometry, preserving collision, the guard room, stair lesson, ward fight, Latch release and saved M02 content behavior.
- Test the standing view from the primary gallery entry to Latch and the restraint frame. Other gallery spawns must be able to walk to the near-window view. Test a low line through the sill remains blocked and the normal stairs remain walkable. Preserve the introductory fight order and Crawler teaching: the opening view must not expose a ward guard to the primary entry or let a player step through the sill and skip the service stair.
- Add a focused first-person visual tour frame at the entry and inspect it at game resolution. The pixel and pose quality of Latch belongs to a separate character pass; this slice checks that the player can actually see the destination.
- Update the accepted mission brief and roadmap with measured visibility and any remaining presentation gap. Do not call the level finished from this sightline alone.

## Non-goals

No new actor art, new enemy, Notary drone tableau, scripted camera, combat rule, objective, protocol field, paid asset or cloud resource. The Notary seen beyond glass remains a brief requirement for later presentation work.

## Architecture and evidence

The map source is `server/maps/m02-persons-unknown.json`. `RuntimeMap` collision and `combat::line_of_sight` decide whether a sightline exists; the client presents the same MapInfo geometry and the Latch actor from server mission facts. Place regression tests beside the existing M02 route tests in `server/src/mission/m02/route_tests.rs` or the authored map tests. The visual tour belongs in the existing `client/qa/` M02 route rather than a second capture engine.

Acceptance: the primary spawn-height eye sees the restraint frame and Latch-sized point through the authored opening; nearby low rays still strike the sill; all gallery spawns can reach the near-window view; a normal participant walks down the service stair, receives both Crawler cues in order, then reaches the ward and leaves after release. The Shotgun guard room remains the first fight. A rendered image must show the ward and distant restraint without a text card. A clear ray, image and green harness do not establish human recognition of Latch, so that gate stays open.

Verification: focused Rust tests, full `cargo test --workspace --locked`, Rust format and Clippy, pinned `tools/godot_check.sh`, a clean visual QA route and inspected frames, plus the full repository gate before this is called implemented. Record failed attempts and final evidence here. Local development costs $0; no generation or cloud apply is in scope.

## Evidence and correction

The new `gallery_entry_frames_latch_without_exposing_the_ward_guards` test failed against the base map: the standing primary entry could not see Latch. A first y=3.6 sill opened the ray and looked clearer in a two-state first-person tour, but it was exactly 0.6 m above the gallery deck, equal to `movement::STEP_UP`. The scripted route climbed the sill, missed both Crawler cues and changed later encounter and supply paths. A narrow lowered portion did not fix the route. These failed designs are rejected.

An attempted low sill with an overhead safety rail blocked a body but still opened longer combat sightlines that changed the scripted Crawler and side-ward route. It was rejected too. The candidate sill top is y=3.8, 0.8 m above the deck. The primary eye has a clear ray to Latch and the front of the frame; the primary entry still has no ray to the three ward guard centers or the low ward floor. The regression requires the sill to remain more than 0.1 m above the climb limit. The ordinary route reaches the ward through the stairs. All 57 M02-scoped server tests passed serially, including the guard-room Shotgun lesson, both Crawler cues in order, wipe/retry, solo human and agent departure, and Severe optional side-ward supplies. This is deterministic authoring evidence, not an unsteered player result.

The final two-state first-person capture ran with the y=3.8 map on Godot 4.7.2-stable's Compatibility renderer and AMD Radeon 780M at 1280x720. It completed with clean client and server logs. [The unedited before and after entry frames](../screenshots/m02-gallery/README.md) show the new narrow opening. The standard `tools/qa_tour.sh --publish` passed all 32 player-facing states; its contact sheet was inspected. The arena timing stills were restored because this map change does not affect them. Workspace tests, Clippy, formatting, and diff checks passed locally; full Godot and other repository CI checks remain the draft PR gate. The rendered result still does not make Latch readily identifiable at first glance; character pose and contrast belong to the separate visual pass, and the first-player comprehension gate remains open.

Local verification on this uncommitted branch: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --locked -- -D warnings`, `cargo test --workspace --locked`, and `git diff --check` passed. The exact-map two-state QA capture passed with clean logs. The 57 M02-scoped tests passed serially, including `crawler_descent_is_walked_in_order_with_a_hidden_first_cue`, `engaged_descent_clears_the_lone_crawler_before_the_pack_landing`, `first_guard_room_teaches_the_shotgun_across_seeds`, `a_wipe_resets_the_objective_and_the_fights`, and `severe_side_ward_route_survives_with_ordinary_supplies`. Full Godot checker, coverage, performance and playtest gates remain for integration. No fresh-player acceptance or human fun claim follows from this pass.
