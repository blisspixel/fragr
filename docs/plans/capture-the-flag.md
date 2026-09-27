# Capture the flag, first playable route

Status: **in flight** (2026-09-26). This is the implementation record for the next multiplayer rung in the full build order. The broader mode proposal remains in [multiplayer-modes.md](./multiplayer-modes.md).

## Goal and why

Ship a complete two-side capture the flag match on Sector 9: authoritative pickup, carry, drop, return, capture, score and round end; legible first-person and spectator presentation; objective-aware rule bots and agent observations; deterministic tests and a real client tour. This is the first objective mode, so the carried-object wire shape should be reusable without making Rescue or Sabotage gameplay now. In the fiction this is a staged league scenario, not a campaign battle. Side markers use Union black, steel and red and Coalition bone and ember; neither flag is a captive agent or a universal faction banner.

## Boundaries and decisions

- Sector 9 is the first authored route. Its west and east halls match existing team spawn halves. Add stand coordinates as authoritative map data and validate reachable, clear ground. Do not silently enable CTF on maps without proven two-side layouts. Arena Duel and Directive 17 need separate route review; Compliance Yard is being retired; Reclamation Gulch's north-south bases conflict with the current team spawn axis; Tripoint Works has three compounds.
- A fighter touches the enemy flag to take it. A carrier may shoot. Death, explicit leave, disconnect expiration or side reassignment drops or returns the flag as appropriate. A living owner-side fighter touching a dropped friendly flag returns it. A living enemy fighter may take its dropped enemy flag again. A flag returns home at 20 seconds without a carrier.
- A capture happens only at the carrier's own stand while the carrier's own flag is home. Captures, not frags, determine the CTF side score. First to three captures wins; at the clock the higher capture count wins, and equal counts draw. Resolve simultaneous touches in deterministic side and player order and record the order in tests.
- Round start resets flag state. CTF currently refuses map rotation; a future rotating playlist must reset on every new map. Warmup and intermission cannot change flags. Spectators cannot interact. A carrier leaving playable bounds drops at the last valid position or returns home. Two Lives is rejected because elimination would decide the winner without captures. Other mutators preserve the flag invariants. Compliance slow and the Compliance Drone do not run in CTF, so the two-side objective is not disturbed by a third hostile.
- CTF uses the existing WebSocket transport and server-owned movement. UDP remains a separate measured transport spike.

## Architecture and wire

- `server/src/maps.rs` and `maps/runtime.rs` own authored stands and validation. `sim/ctf.rs` owns state transitions, using the authoritative positions and tick. `rules.rs` and `sim/modes.rs` keep frag scoring specific to team deathmatch. CTF has distinct capture counts and a capture limit so kills can never decide its score.
- `protocol.rs` adds a typed, bounded `flags` snapshot field, omitted outside CTF, and structured pickup, drop, return and capture events. `docs/protocol.md` records names, units, ordering and compatibility. Bump capability only if a new client would misinterpret an old one; validate both sides.
- Godot validates the new wire values before signal delivery, renders stands and carried/dropped flags as world visuals, and shows a compact status in the existing HUD stack. Localization covers labels and events. The adapter already returns full snapshots; its summary and the brain's objective controller need explicit flag understanding.
- Extend the existing playtest harness with an objective route and assertions. A bot-only capture is a network/logic gate, not a human fun verdict.

## Verification and spend

Start with focused deterministic tests for pickup, enemy denial, own-side return, recapture, death/drop, timed return boundary, leave, reset, simultaneous touches, score limit and time draw. Run the existing Rust, Godot and playtest gates and inspect first-person and spectator captures. Measure a mixed 10-plus fighter CTF run before capacity claims. Record command results and any remaining gaps here. No paid API calls, assets or GCP apply are needed for this mode. External spend for this sprint is $0; the user's 2026-09-26 combined external process ceiling is $20, inside the repository's $50 total cap.

## Acceptance

One human can join or watch a Sector 9 CTF match and read who holds each flag, where a dropped flag lies, which side has captured, and why the round ended. Rule bots pursue objectives instead of only seeking kills. The same facts reach MCP and the brain agent. CI and coverage gates pass without weakening them. Other maps and human balance evidence remain explicitly open until observed.

## Work log

- 2026-09-26: Audited mode, simulation, client, map and lore seams. Sector 9 selected. No paid calls or cloud resources used.
- Implemented server-owned flags, captures, events, a capability 14 boundary, Sector 9 stand validation, HUD and world markers, adapter and brain reads, rule-bot routes, and a CTF network playtest gate. The branch is stacked on the mode-chip layout so the combined HUD can be reviewed.
- Independent server and client review found and fixed parked-carrier re-takes, a Two Lives elimination path that bypassed capture scoring, the missing default capture-limit enforcement, floating airborne drops, side-order ambiguity, stale Arena Duel CTF branding, and Compliance arena pressure entering the two-side mode. Focused regressions cover those server paths. The drop location is projected to reachable support, and the HUD gives a fighter a bearing and distance to a dropped flag.
- Network measurements on this Windows development host, using the real WebSocket client path:

  | Agents | Policies | Round clock | Frags | Pickups | Captures | Result |
  |---:|---|---:|---:|---:|---:|---|
  | 4 | Reflex, Planner | 180 s | 9 | 2 | 1 | Passed in 92.2 s; 2 per side. |
  | 12 | Reflex only | 120 s | 0 | 1 | 1 | Passed in 57.4 s; proves the objective route, not combat. |
  | 12 | Reflex, Planner | 120 s | 63 | 3 | 0 | Failed the capture gate after 121.9 s; 6 per side. |
  | 12 | Reflex, Planner | 180 s | 34 | 5 | 1 | Passed in 105.8 s; 6 per side. The longer clock allowed a contested objective route. |
  | 12 | All combat | 120 s | 78 | 0 | 0 | Rejected: combat displaced the objective. |
  | 12 | Aim and strafe | 180 s | 123 | 0 | 0 | Rejected: worse objective behavior. |

- The 12-fighter runs show that the host accepts and updates a six-a-side roster. A mixed 180-second run captured once after 34 frags, while the 120-second version did not capture. These runs do not prove enjoyable six-a-side balance, capture reliability across seeds, or headroom on a small cloud host. Keep a mixed 12-fighter human/agent balance session open before calling CTF complete. The four-agent mixed run is the CI smoke because it exercises combat and a capture without masking this gap.
- The post-review four-agent mixed socket smoke passed in 61.0 s with 3 frags, 1 pickup and 1 capture. The emitted report is `.agents/playtest/ci-ctf.json` (local and ignored). This is an objective path check, not a human feel verdict.
- Rendered review on the stacked HUD: [Union stand](../screenshots/ctf_union_flag.png), [Coalition stand](../screenshots/ctf_coalition_flag.png), [joined first-person HUD](../screenshots/ctf_joined.png), and a [round result layout fixture](../screenshots/ctf_result_fixture.png). The custom `client/qa/ctf.json` tour uses a real server on Sector 9 and the AMD Radeon 780M renderer. It asserts live home-flag states and zero capture scores in its home shots. The result banner is an explicit client fixture; live scored evidence follows below.
- A second, outcome-gated tour (`client/qa/ctf_live.json`) observed a [live bot carrying the Free flag](../screenshots/ctf_live_carried.png) and a [live Union 1:0 capture-limit win](../screenshots/ctf_live_result.png). Both images were captured from the real server snapshot on the AMD Radeon 780M renderer. The tour waits for the flag and round conditions, then rechecks them at capture. The carried image shows overlapping pawn nameplates around the carrier; visual density needs a human session review. A 12-rule-bot attempt to capture a dropped flag timed out after the round recorded zero frags and a 2:2 capture draw. Dropped-marker and return-timer presentation remain unverified by a live image, though server and client contract tests pass. No dropped image from that failed tour was published.
- Final live tour command: `FRAGR_QA_MANIFEST=res://qa/ctf_live.json FRAGR_QA_MODE=ctf FRAGR_QA_MAP=4 FRAGR_QA_BOTS=4 FRAGR_QA_CAPTURE_LIMIT=1 FRAGR_QA_SEED=42 FRAGR_PORT=6783 tools/qa_tour.sh .agents/qa/ctf-live-final` from Git Bash. It passed two states with a clean Godot log. The captured manifest records `home,carried`, 0:0 and `Active`, then `home,home`, 1:0 and `Ended`. The full `tools/godot_check.sh` also passed after the tour-script change.
- Full Rust workspace tests, Clippy, release build, cargo deny, unfiltered workspace line coverage at 93.41 percent, the deterministic 16-bot release benchmark, and the full Godot checker passed on the stacked branch after the review fixes. The standard 32-state player-facing tour published 13 stills, and the six-state CTF tour passed. Keep this plan in flight through a human/spectator CTF session and mixed six-a-side balance review.
- All local CI network gates passed: FFA, TDM, Rail Only, TDM with Licence to Kill, the CTF objective smoke, and `tools/playtest_roster.sh` across six maps with 2, 6, 6, 8, 12 and 16 mixed clients. The roster gate logged one non-opening spawn death each on maps 2 and 6, inside its allowed threshold. These are free-for-all roster runs, not CTF six-a-side balance proof.
- The 120 s rotating-map soak passed with 4 bots, 4 agents and 2 spectators: 20.00 Hz, lifetime tick p99 0.52 ms, RSS 37.8 to 38.8 MiB on this Windows host. This is local host evidence only; no small-cloud performance claim follows from it.
- Draft PR #267 is stacked on draft #266. The repository workflow currently runs for pull requests targeting `main`, so GitHub does not schedule checks on this stacked PR until its base moves to `main`. The full local gates above are the current verification evidence. No merge, cloud apply or paid API call was made.
