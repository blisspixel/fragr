# Notice to Vacate market authoring

**Status:** implemented for bounded authoring, 2026-09-30. Integrated release
checks remain in the parent plan; fresh-player acceptance is separate.
**Spend:** planned and actual $0.

## Goal and ownership

Implement the original Low Water market, clinic and court under the
[M04 prototype](m04-notice-to-vacate-prototype.md). Own
`server/maps/m04_notice_to_vacate.json`, `client/qa/m04-market.json`,
`server/src/tests/m04_qa.rs` and bounded town presentation in
`client/scripts/m04_town.gd` with its focused harness. Preserve M01-M03 bytes.
The server lane owns the strict flight and mission boundary. The client lane
owns translations, mission UI and civilian validation. Integration owns hooks,
Notary artwork, run carry and shared documentation.

## Architecture and scope

Map 1004 is a compact hub with repair stalls, one optional clinic shutter and
a habitation court with three accessible balconies and a far-side roof stair.
Six ordered groups contain 28 enemies: a three-guard notice fight, one isolated
Notary, a mixed street advance, two market waves and a court watch. Future wave
actors must be staged by authoritative eligibility, never merely screened by
an `after` string. Ordinary supplies support local discovery and carried gear.

Flight uses actual authoritative underside feet and explicit bounded hover
volumes, bands, patrol points and grounded combat approaches. The existing
walking topology validates those approaches; no false grounded drone body or
general flying navigation. Exactly two prepared worlds represent the closed
and raised clinic shutter. Clinic opening and patients remain optional and
never add a departure wait. Six required arrival objectives lead to physical
roof use. A photograph is a resolved server fact, never inferred from sprites.

Town dressing derives from validated MapInfo geometry, decorations and mission
facts. Water tanks, awnings, workshop fixtures and the clinic sign establish a
place without adding collision. Three exploration pickups mark a paint locker,
awning pocket and shared meal table. Real input must reach each; an ordinary
service stair also keeps the rooftop pickup reachable to shared navigation.

## Verification and acceptance

Run strict loader and both-world movement checks, then a full ordinary-input
tour with normal health and all 28 required enemies, the optional clinic,
three secrets and deliberate roof departure. Capture actual Notary windup,
resolved photograph, interruption, movement and harmless crash evidence.
Inspect the selected gallery and run a focused town presenter harness.
Record exact commands and failures. An accurate-aim clear is authoring evidence,
not fresh-player acceptance, the accepted eleven-minute pacing, final art or
implementation of every proposed difficulty-specific mission brief.

## Work record

- Read the accepted L04 treatment, campaign/lore continuity, drone design,
  current authored maps, strict schemas, movement and navigation capacity.
- Existing damage alarms can wake later groups despite `after`; reported to
  the server lane for authoritative staged-wave implementation.
- The server lane confirmed the exact flight, clinic, patient, six-objective and
  departure fields. Current geometry has 81 solids, 28 enemies, 20 supplies,
  15 registered decorations and one optional two-state shutter.
- The meal secret uses the open edge beside the table's carved leg, with a
  normal 0.9 metre table. Existing supply validation requires full-standing
  clearance, so literal under-table placement is narrowed for this prototype.
  The awning secret has an ordinary service stair; jump traversal remains a
  separate unproven optional route, never a claim inferred from an overhead hop.
- No paid calls, new dependencies, publishing or external services.

## Current verification receipt

- `cargo test -p fragr-server --lib bundled_notice_to_vacate_routes --locked -- --nocapture`:
  PASS. Strict loading caught invalid shared supply claims, unsupported guard
  placements, hover-band containment and overlong Scatter approaches. Existing
  contested claims and physically valid placements resolved those failures.
- `cargo test -p fragr-server --lib authored_m04 --locked -- --nocapture`:
  PASS, four tests. Every declared movement/search segment runs through shared
  authoritative movement in both clinic worlds, with clinic interior travel
  intentionally tested only after opening. The roster test requires every one
  of the 28 guards and all three secret pickup positions. Negative checks reject
  a closed shutter, a clinic wall shortcut, a direct roof shortcut and walking
  into the normal meal table.
- The fourth route test retains actual body positions between the tour's 0.3
  metre horizontal and 0.03 metre vertical arrival disks through both court
  rooftop states. It rejects the previous unsupported edge crossing and proves
  the revised stair-first crossing in both clinic worlds.
- Movement preflight exposed the central street cover and the taller stair
  obstruction across the court at z32.5. The search now uses the clear x4 lane;
  the balcony crosses at z31 over an ordinary half-metre step.
- Godot 4.7.2 import and `--check-only --script res://scripts/m04_town.gd`:
  PASS, clean logs. `--headless --script res://scripts/test_m04_town.gd`:
  PASS, exit 0 and harness marker. Registered tank and canopy anchors follow
  delivered geometry, every fixture uses the world light layer, no collision
  body is created, patients follow validated server feet, repeated samples do
  not prolong gait, malformed replacement removes old presentation.
- The actual local-child check exposed an omitted wire `bottom` default that
  the initial presenter fixture had supplied explicitly. The presenter now
  shares the geometry boundary's ground/top defaults, publishes its geometry
  only after construction finishes and checks all patient views before applying
  state. The focused harness includes an omitted-bottom tram regression and
  passes cleanly. The client lane repeats actual launch after this correction.
- Read-only integration review and
  `cargo test -p fragr-server --lib mission::run_file --locked -- --nocapture`:
  PASS, 26 tests. Historical upgrade, archive replacement, exact equipment and
  body carry, M03 choices, M04 retry and pending M05 outcome projection were
  checked through existing owning seams. The focused `m04` filter passed 19
  server tests covering the new combat, controller and authoring contracts.
- M04 map frozen at SHA256
  `6171f39e0a83e74dd91d822c92c1f03ab0442153fe5fba1b9f02f8f17c7d2d79`.
  M01, M02 and M03 hashes match their entry receipts, so their bytes are preserved.
- Diagnostics: `.agents/m04-buildout-20260930/`. The final rendered 23-state
  route passed and the selected gallery was inspected. The receipt below owns
  that authoring result; neither strict loading nor a headless presenter check
  alone establishes playability or visual quality.

## Rendered iteration record

- First tour `.agents/qa/m04-market-first`: failed in the mixed street fight.
  The human defeated eight guards in total, then the surviving western Sweeper
  killed the human and reset the attempt. Actual solo windup, firing ray,
  tumbling chassis, shadow and crash feedback were captured. The solo still
  ended at 45 HP and zero armor after the context observation exposed unanswered
  bursts. This is a failed route, never a playable-clear receipt.
- Second tour `.agents/qa/m04-market-second`: failed at the same fight after
  entering from the west. The pre-lesson health visit occurred while full, so
  the normal pickup correctly remained unclaimed. The static lesson exposure
  still left 45 HP and zero armor. All owned wrapper, client and server processes
  finished before the next route edit.
- The third route visits the existing board medkit after the lesson, shortens
  only the context still's idle delay and strip interval, and approaches the
  lone Notary closer through ordinary movement. Actual windup, firing, death
  and support-crash requirements remain intact. Postcombat arrival returns
  guard against clearing a wave outside its required objective region. Three
  movement, roster and secret tests still pass after these route changes.
- First stills have clear geometry and readable combat, but the inherited
  industrial warehouse backdrop and distant drone tell do not establish the
  final Low Water look. Integration owns a bounded town backdrop treatment;
  final visual, shadow, motion and patient inspection remains pending.
- Third tour `.agents/qa/m04-market-third`: cleared all first nine guards with
  zero deaths, 55 HP lost and 50 armor lost, then physically opened the clinic.
  It failed because the shared checker requested the use prompt after successful
  use had removed that prompt. Integration moved prompt proof before use while
  retaining the post-action opened-world assertion. This run is partial evidence,
  not a full mission clear. Upper row homes now replace the industrial arena's
  skyline labels; further clinic/court visual inspection is still needed.
- Fourth tour `.agents/qa/m04-market-fourth`: passed clinic use, actual patient
  release and both market waves, obtained the awning armor secret through real
  stairs, then failed in the court. Its court preparation crossed the alarm
  and walked through multiple supplies without defending against eight active
  guards. Integration added a strict per-state opt-in to the existing ordinary
  travel combat controller; named deaths remain required by the subsequent
  ground and balcony probes. No enemy, damage or health value was reduced.
- The actual patient strip showed gait and doorway travel, but the observer
  stood on the patient's path and one body briefly filled the frame. The next
  route observes from z3.5 within the same release region. The clinic care-board
  viewing position also moves along the real interior lane to keep Vale's body
  out of the aiming area. Movement preflight still passes all three tests.
- Fifth tour `.agents/qa/m04-market-fifth`: failed in the mixed street fight
  after the solo lesson ended at 100 HP and 30 armor. The actual combat strip
  shows the central Sweeper behind low cover while both Notaries commit bursts;
  the human killed that Sweeper but died about 1.1 seconds after activation.
  The failure does not support attributing this iteration to missing health.
  The sixth route enables the existing ordinary travel combat controller before
  crossing each mixed encounter threshold, then explicitly disables it during
  clinic and recovery visits. All named enemies, phase requirements, damage,
  normal pickups and secret checks remain intact. Three movement/roster tests
  pass after the change; the full clear remains pending.
- Sixth tour `.agents/qa/m04-market-sixth`: travel defense defeated all five
  advance guards, but then selected newly eligible market-wave-A actors while
  still completing the first street waypoint. The human traded with that
  wave's Notary before reaching the clinic. This exposed a shared travel target
  scope gap: the state already restricts its later probe to named guards, while
  the travel controller selected every visible hostile. The failed run ended
  cleanly before further edits. Integration is reviewing that shared scope;
  changing enemy health, activation or required rosters is unnecessary.
- Integration added a strict optional `combat_travel_targets` list using the
  existing visible-target filter. The seventh route names only the current
  street or market wave during each approach. Court travel names all eight
  court guards, while the later probes still require their original six ground
  and drone enemies, then two balcony Clerks. Focused shared boundary/target
  tests and all three authored route tests pass; legacy tours retain their
  previous unfiltered behavior when the field is absent.
- Seventh tour `.agents/qa/m04-market-seventh`: all 28 guards were defeated
  with zero human deaths, including both elevated Clerks. The human recorded
  27 kills and the companion one. The optional clinic opened, both patients
  walked out, and the revised care-board view remained readable. The tour then
  failed at the balcony crossover: stopping just below z31 left a route on the
  support edge, which exact-centre segment tests had missed. The revised route
  climbs to 3.5 metres on the next half-metre stair before crossing onto the
  balcony. The new retained-position tolerance regression catches the failed
  path and passes the correction. The full roof departure still needs a rerun.
- Seventh's service record contains 110 HP lost, 50 armor lost and two claimed
  secrets. The meal medkit correctly remained unclaimed at full health after
  repair recovery. The next route obtains the Shotgun and ammunition from the
  normal pickup radius but bypasses the repair medkit along a collision-tested
  lane. This leaves it available and permits the meal secret to restore actual
  remaining damage. No enemy, damage, pickup or map geometry was changed.
- Eighth tour `.agents/qa/m04-market-eighth`: passed both market waves, clinic,
  patient release, actual Shotgun ownership and awning armor, but died at the
  initial court travel step with 75 HP and 50 armor. It never reached the new
  rooftop crossing, so the four movement tests remain the correction's current
  evidence. Server telemetry degraded during concurrent verification, as
  recorded below. This is a confound, not a proven sole cause. The ninth route
  restores the ordinary repair medkit used
  by the seventh successful all-guard clear. Completing a secret claim never
  requires deliberately taking damage, and a full-health unclaimed medkit will
  be reported honestly. All three secret locations remain reached by the route.
- Three shallow puddles and their drains/shore dressing appeared in actual
  eighth market and court captures. The closer phase stills show the Notary's
  firing ray and tumbling chassis. Two long sky triangles in the aftermath are
  a rendering defect under integration review, not invented drone debris.
  Final gameplay capture waits for this and the bounded material/audio source
  handoffs, with heavy verification serialized outside the actual tour.

| Tour/status window | Ticks sampled | Lifetime p99 ms | Maximum ms | Over-budget ticks | Context |
| --- | ---: | ---: | ---: | ---: | --- |
| Seventh, 180 second status | 3,601 | 0.328 | 0.663 | 0 | All 28 guards cleared; later route edge failed |
| Eighth, 180 second status | 3,571 | 7.340 | 68.323 | 5 | Concurrent verification; lower starting court HP; no causal attribution |

These are local tour diagnostics from their `server.log` status lines, not an
isolated benchmark or a scale claim. Integration owns final benchmark and soak
measurements.

## Final ordinary-input receipt

Ninth tour `.agents/qa/m04-market-ninth` passed with exit 0 and clean logs:
23 states, all 28 named guards, both market waves, both elevated Clerks, all six
arrival objectives and authoritative roof departure. The ready human stood at
approximately `[13.5, 4, 36.506]` on the exit roof and pressed the existing use
action. The final card reads `ESC: RETURN TO MENU`. The one clinic shutter
opened and both released patients reached their server-authored safe positions.
There were seven observed Notary support crashes and zero completed photographs.
The solo probe recorded actual windup, firing and death phases; the crash gate
passed. All wrapper, client and server children stopped before handoff.

| Authoritative human service record | Result |
| --- | ---: |
| Kills | 28 |
| Deaths | 0 |
| HP lost | 125 |
| Armor lost | 100 |
| Claimed secrets | 2 |
| Final HP / armor | 100 / 50 |
| Rifle attacks / damaging attacks | 147 / 89 |

All three secret locations were reached through ordinary movement. Shells and
awning armor were claimed. The table medkit remained available at full health
after the ordinary court medkit restored 80 HP; visiting its location is not
reported as a third claim. No grant, teleport, enemy reduction or forced damage
was used. Normal Shotgun ownership was asserted from the private equipment
state. M01-M03 bytes and the frozen M04 map hash remain unchanged.

Replay in Git Bash, with the pinned local renderer available:

```bash
FRAGR_PORT=6774 FRAGR_SERVER=127.0.0.1:6774 FRAGR_QA_BOTS=0 \
FRAGR_QA_MAP_FILE=server/maps/m04_notice_to_vacate.json \
FRAGR_QA_MANIFEST=res://qa/m04-market.json FRAGR_QA_SEED=42 \
bash tools/qa_tour.sh .agents/qa/m04-market-final
```

## Inspected gallery and limits

The final Windows Compatibility capture uses Godot 4.7.2-stable and an AMD
Radeon 780M. This identifies inspected renderer evidence, not a hardware
performance claim. Ten selected files are copied unchanged into
`docs/screenshots/`; the four README stills remain owned by the standard tour.

| Artifact | What happened |
| --- | --- |
| [Arrival](../screenshots/m04_arrival.png) | Notice board, market sightline and varied upper row homes |
| [Notary windup](../screenshots/m04_notary_windup.png) | Actual committed windup with readable airborne silhouette |
| [Notary firing](../screenshots/m04_notary_firing.png) | Resolved firing ray, not a claimed photograph completion |
| [Notary motion strip](../screenshots/m04_notary_motion_strip.png) | Combat phases and falling chassis; support crash asserted separately |
| [Patient strip](../screenshots/m04_clinic_patients_strip.png) | Actual patient gait through the open doorway |
| [Clinic care board](../screenshots/m04_clinic_care.png) | Readable care message without a companion covering it |
| [Market water](../screenshots/m04_market_water.png) | Shallow puddle, drain/shore dressing, town silhouettes and repair surfaces |
| [Awning secret](../screenshots/m04_awning_secret.png) | Roof pocket reached by ordinary service stairs |
| [Court balcony](../screenshots/m04_court_balcony.png) | Physical upper crossing after the corrected stair approach |
| [Roof departure](../screenshots/m04_roof_departure.png) | Actual completed mission and resolved keyboard return label |

The ninth aftermath has no stray beige sky triangles. The new surfaces, water,
town fixtures and skyline preserve visible world light and shadows. Patients
still use provisional body silhouettes, and the environment remains a compact
prototype with sparse furnished interiors. The accurate-aim route does not
establish the fresh-player, 11-minute pacing, runner, optional jump or
difficulty-specific brief gates. Story/audio playback is proved separately by
integration because this route skips opening scenes. M05 remains unbuilt.
