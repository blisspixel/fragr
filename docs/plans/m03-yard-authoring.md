# Scheduled Service yard authoring

**Status:** implemented, 2026-09-30. Development mission acceptance and campaign
expansion remain governed by the parent plan.
**Spend:** planned and actual $0.

## Goal and scope

Author the original M03 daylight rail yard under the
[Scheduled Service prototype](m03-scheduled-service-prototype.md). Own only
`server/maps/m03-scheduled-service.json`, M03 input-driven QA manifests and
map-specific evidence. Preserve M01/M02 bytes. Shared server and client changes,
translation keys, renderer and plan index belong to their assigned lanes.

Two parallel tracks, carriage cover, ground crossovers and ordinary 0.5 metre
roof stairs connect a compact yard. Start with a guaranteed Rifle and bullets,
then platform guards, one isolated Jammer, mixed roof pressure, mast guards and
the locomotive push. Three optional recall cars release after their guards fall
and the party reaches their platform. Their presentation never changes collision
or blocks mast shutdown or deliberate boarding.

## Architecture and contracts

Use strict version 1 map 1003 with discovery equipment and the agreed `m03`
schema. Exactly two authoritative worlds represent intact and fallen mast
solids. All spawns, supplies, enemy feet, landmarks, mission approaches and
captive routes must stand and route in both worlds. Only mast solid bounds
change; no combinatorial car worlds, client blockers, ladders or vehicle physics.
The server resolves pod damage, encounter prerequisites and shared departure.
The client owns keyed signs and optional car presentation. No new dependencies,
paid assets, protocol copies or arbitrary map-supplied text.

## Verification and success criteria

Run focused authored-loader and route tests once the server schema is ready.
Prepare real-input QA covering Rifle pickup, first pulse and dodge, mixed fights,
ordinary roof stairs, optional release, mast shooting and boarding. No equipment
grants, invulnerability or teleports. Record actual commands and outcomes below;
an accurate-aim clear remains authoring evidence, not fresh-player acceptance,
finished art, difficulty acceptance or the proposed ten-minute pacing.

## Work record

- Read the accepted L03 treatment, campaign briefs, current M01/M02 authoring,
  movement and navigation constraints before implementation.
- The accepted prose calls the gantry encounter the third Jammer while naming
  four placements. This prototype will record four: solo, roof, mast and gantry.
- Server handoff specifies mast 40 HP, `mast_disabled` Shoot and
  `party_departed` Use, three optional car records and no collision doors.
- Authored half-extent 44 yard with 74 authoritative solids, six connected car
  roofs, four low rails, mast and locomotive, hut and yard office. West car bays
  have end caps, back walls and 2.5 metre clear interiors; optional releases never
  modify their collision. The first roof has a deliberate stair notch.
- Population is 22 enemies in six groups: four loading guards, one solo Jammer,
  a Jammer and three Sweepers on the roof, two optional siding guards, a Jammer
  and three mast Sweepers, then a Jammer, two Clerks and four locomotive Sweepers.
- Sixteen finite supplies include guaranteed Rifle/bullets, optional office
  Shotgun/shells, hut recovery and two secret finds. Three car releases are
  independent of mast shutdown and train boarding. Captives stand inside open
  bays and follow short clear segments outside; third-car safe feet avoid the hut.
- Prepared `client/qa/m03-scheduled-service.json` with twenty-one real-input states
  covering all fights, ordinary stairs, three releases, mast shots and boarding.
  M03-specific assertions use the coordinating-lane harness for actual mast
  shutdown and each optional car release.
- First focused command `cargo test -p fragr-server --lib maps::authored
  --locked -- --nocapture` did not compile while an in-flight MapInfo test
  fixture lacked the new `m03` field. Reported to its owner; no passed-check claim.
- Server lane added `bundled_scheduled_service_routes` as the next focused check.
- Loader iteration moved platform bullets clear of the roof stairs and one Clerk
  clear of the stair lane. Reading the authoritative inclusive body-radius check
  also prompted 2 metre treads on the roof and mast flights. The mast flight now
  climbs north from its south approach. Signal-roof steps give a west passage
  around the fallen column. Real-input waypoints explicitly use these routes.
- `cargo test -p fragr-server --lib bundled_scheduled_service_routes --locked
  -- --nocapture` passed after the final formatting freeze: one test, 656 filtered,
  0.28 seconds reported test runtime. Log:
  `.agents/m03-buildout-20260930/yard-routes.log`. This loads and validates both
  immutable worlds; it is topology evidence, not an input-playable-clear claim.
- Input-tour iteration exposed two capture paths crossing the hut walls. Both
  now use the east doorway at z5.5. The shared movement preflight added by the
  coordinating lane also caught a crossover endpoint inside low cover; the
  crossover now uses z7.5. `cargo test -p fragr-server --locked
  authored_m03_tour_segments_walk_in_both_mast_worlds -- --nocapture` passed:
  one test, 660 filtered, 0.17 seconds reported test runtime. Every consecutive
  declared walk segment is replayed through authoritative movement in both worlds.
- A rooftop-only combat search could not reach the ground Sweeper beneath a
  carriage roof. The fourth run eventually died there. The twenty-one-state
  route now separately requires that ground Sweeper's defeat from the open west
  flank. All twenty-two enemies remain required.
- The fifth run stopped below the intended roof waypoint. Inspection of the
  sixth run's postcombat still showed the body remained on the west roof before
  the next ordinary walk. The diagonal first waypoint crossed the gap before
  reaching the bridge; it now goes to the west crossing first. Those runs do not
  prove strafing was the sole cause. Coordinating-lane surface-safe evasion adds
  a separate guard against roof drops and walls through mirrored movement; all
  rooftop and ground evasion remains enabled in the final route.
- `.agents/qa/m03-yard-first` records a refused incompatible launch flag; no
  server or capture started. The corrected second and third runs passed the
  earlier fights and releases before the hut-path failures. Fourth and fifth
  attempts failed as above; none is a completed route.
- The seventh run passed the roof flank, hut and all three releases, then left
  one mast Sweeper alive. The full-width mast trigger had awakened its guards
  during the western recovery stop, allowing them to pursue into earlier cover.
  Narrowed mast activation to the eastern x12..44 approaches, z4..24, with all
  four enemies and both approach lanes preserved. This restores the intended
  recovery beat. The local mast search now stays in its clear west corridor.
- Coordinating-lane preflight now also replays every declared combat search and
  approach segment. Repaired a platform fallback crossing a car body by using
  the south and far-west crossovers. The expanded preflight passed: one test,
  660 filtered, 0.39 seconds reported test runtime, in the existing preflight log.
- The eighth run ended rooftop combat alive but already on central ground. Its
  next roof waypoint could not recover from that actual pose. The ninth route
  now walks through the central lane, using an ordinary drop if still on the
  roof, then goes south of the cars to the west flank. The ascent proves the
  stairs; this transition does not claim a stair descent or identify one sole
  cause of combat drift. Expanded both-world preflight passed again: one test,
  661 filtered, 0.29 seconds reported test runtime. Evasion remains enabled.
- Renamed the timed first-Jammer strip to `solo_jammer_observation`. It does not
  establish resolved pulse motion. The following combat probe explicitly waits
  for the first shot and captures windup, firing, hit and dead phases; inspect
  its firing still and combat strip separately. The prior range remains the
  existing motion proof. Arrival captions describe the rendered car frontage,
  not an unproven view of the distant mast.
- M01/M02 files remain untouched. SHA256: M01
  `2a7e67311ac0339647ace9d5aba07256dc4db35fe33165f13d7802794d12da67`, M02
  `eeaf880165b826d1f649cfd91c2484fe26d345af91468cd046038e5b55a5bc28`.
- The ninth input tour passed all twenty-one states with wrapper exit 0 and clean
  import/client logs. Seven combat probes confirmed all twenty-two named enemies;
  the human record counts twenty-one kills and the companion resolved one.
  Three cars released, mast HP reached 0, the two secret pickups were claimed,
  and physical local use confirmed `party_departed`. The completed human record
  has zero deaths, 205 HP lost and 100 armor lost; the boarding/departure stills
  show 25 HP and zero armor. Finite recovery supplies explain the accumulated
  damage. The roof ascent, ordinary drop, hut doorway, mast precision stairs,
  fallen-world signal roof and locomotive approach all used ordinary input.
- Independent visual review found a literal `{MENU}` token on the ninth
  departure card. The client lane is correcting the registered copy to use the
  existing device-aware pause substitution and refresh on device changes.
  The tenth full route passed through the signal secret but failed at the train
  push: entering z25 from the east awakened the seven guards during the long
  crossover before the combat probe. The human claimed +65 HP at north recovery
  and died one second later. That is a failed capture, not a passed rerun.
- The final approach now descends the mast stairs, uses the known west corridor
  and z7.5 ground crossover, then reaches the western supplies at z23 before
  entering the unchanged z24 train activation boundary. A z23 crossing beside
  the mast platform was rejected by shared movement; the more generous known
  route passed in both worlds. All seven train enemies, twenty-one states,
  ordinary health and evasion remain required. The eleventh full route verified
  the actual corrected card and superseded the selected ninth-run gallery.
  No map bytes, encounter regions or enemy strength changed for this correction.
- Final eleventh tour passed with wrapper exit 0, all twenty-one states and clean
  import/client logs. Combat confirmation counts were 4, 1, 3, 1, 2, 4 and 7,
  matching all twenty-two named required enemies. The human record is complete
  with twenty-two kills, zero deaths, 57 HP lost and 100 armor lost. Final stills
  show 75 HP and zero armor. Three optional cars are released, both secret
  pickups are logged, mast HP is 0, and local use confirms `party_departed`.
  The actual departure card visibly reads `ESC: RETURN TO MENU`, with no literal
  placeholder. The source did not change during this run. Focused shared movement
  preflight passed after the final route correction: one test, 661 filtered,
  0.24 seconds reported test runtime.
- Reproduction: set `FRAGR_QA_BOTS=0`, `FRAGR_PORT=6774`,
  `FRAGR_QA_MAP_FILE=server/maps/m03-scheduled-service.json`,
  `FRAGR_QA_MANIFEST=res://qa/m03-scheduled-service.json`, `FRAGR_QA_SEED=42`
  and `FRAGR_GODOT` to the pinned local binary, then run
  `bash tools/qa_tour.sh .agents/qa/m03-yard-eleventh`. Do not combine the map-file
  option with `FRAGR_QA_NO_ROUND_EVENTS`. Receipt and owned-process cleanup are
  recorded in `.agents/qa/m03-yard-eleventh/manifest.json`, `client.log` and
  `server.log`. No server child remains from this run.
- Inspected the full contact sheet and arrival, roof ascent, actual Jammer firing,
  released third car, intact pod aim, shutdown, fallen mast, secret and boarding
  frames. The firing phase shows the resolved orange pulse; the shutdown still
  carries Mara's line outside the aiming area. The fallen mast is visibly on the
  signal roof and the secret capture says `SECRET FOUND`. The locomotive sign
  shows a normal use prompt before departure and the finished state afterwards.
  The nine `m03_*.png` gallery files in `docs/screenshots/` were refreshed only
  from the final passed eleventh run, including the corrected departure card.
  The departure establishes the authoritative use outcome, not moving train
  physics or a cinematic. Arrival frames car frontage rather than the far mast;
  open bays, primitive locomotive geometry and repeated surfaces remain prototype
  art. The offline optional office Shotgun route was validated by the loader but
  was not visited in this input tour.
- No external charges or service calls. This is deterministic accurate-aim
  authoring evidence on Standard, not fresh-player acceptance, a completed
  campaign mission, difficulty acceptance or a measured ten-minute pacing gate.
