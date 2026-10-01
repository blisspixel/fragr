# M05 client prototype

**Status:** in flight, 2026-09-30. Child of
[M05 No Forwarding Address](m05-no-forwarding-address-prototype.md).
**Spend:** $0 new charges or asset calls. Preserve the round's existing 475
included audio credits and separate $2 equivalent reserve. No publishing,
release build or additional generation is part of this lane.

## Goal and contract

Present the Episode I evacuation through recognizable Low Water roofs, a working
tram workshop and a usable trench. Reuse strict mission, equipment, input,
settings, world, scenes, local process and QA seams. Rust remains authoritative
for objectives, rescue, grenade count/flight/bounce/blast and tram movement,
collision, rider transport and shot cover. Gameplay capability 26 applies to
authored missions; campaign rules remain revision 3. Six gun/statistic slots keep
their meanings; grenades are separate counted equipment capped at six.

Do not implement a cosmetic moving tram or choose a passenger outcome from art.
Map/state, grenade/explosion and tram shapes must match the agreed server types
before their helpers are encoded. Retain earlier outcomes on entry and retry;
M05 rescue attempts reset. Pending Port of Entry is `port_of_entry`, with episode
refill deferred to its future authoritative transition.

## Owned work and integration

Client lane owns new `m05_mission_state.gd`, `m05_town.gd`, grenade presentation
helpers and focused tests, and affected mission HUD/dispatcher, controls,
settings, equipment, records, boot/local frontend, story and QA glue. Root owns
server save/local/runtime and protocol documentation; map lane owns authored
M05 map and route manifest. Coordinate GameManager/NetClient/movement glue by
symbol and inform root before a live shared edit. Preserve all prior work.

Grenade controls use G, middle mouse and left trigger through InputBindings and
the same Action. Existing ingress edge latching retains short taps before latest
movement overwrite. Client queues a brief event until successful send, suppresses
it behind menus/story/focus loss, and never repeats a throw each held tick.
Historical custom bindings retain their inputs: only missing new grenade binding
defaults lose tokens already owned by an overlapping action. Add a quiet separate
grenade glyph/count, live device-aware prompts and authoritative empty feedback.

Use strict finite/integer/bounds/identity/exact-key and monotonic/reset validation
at existing boundaries. Geometry replacement invalidates old steering and prompts
until matching facts arrive. Count changes are server facts, not local rewards or
optimistic subtraction. Retain resolved explosions after projectile removal and
bound presentation nodes, lifetimes, deduplication and camera clearance.

Practice navigation must fit smaller windows as a fourth prototype is added.
Use bounded scrolling or a compact selector with working keyboard/gamepad focus.
M04-to-M05 Continue Run plays arrival once through the existing held-input release
barrier; a true existing-entry resume skips it. Development launch does not replace
the durable run. Existing narration bytes and paired captions remain unchanged.
New original keyed arrival/departure scenes use text fallback without named voices
or silent survivor resurrection. Departure lists authoritative aboard/missing
people and supports cancellation before existing Use commits the outcome.

## World presentation

Continue muted plaster, sage, teal, patched steel and terracotta with the same
late-afternoon skyline. Give roofs maintained tanks/utility detail, workshop
registered tram/windows/workbench/gantry activity and trench recesses/crossings,
with practical lights on the existing eight-light budget. Substantial objects
come from registered authoritative solids. Flush detail never promises cover.
Use existing repaired surface textures and water shader. Register small puddles
only on supported, validated floor outside conflicting solids; no liquid gameplay,
pond through a platform or automatic inherited M04 coordinates.

The real tram view and prediction collider consume authoritative transforms and
current solid bounds. Prove riding, dismount/jump, obstruction, cover and reset
through shared movement. Keep a complete walking route. Static Tern ship landmark
does not imply simulated interplanetary flight. Provisional character bodies and
unfinished authored density remain explicit limitations until reviewed.

## Verification and acceptance

Baseline: 163 client scripts and 76 harnesses, full checker and ten-scenario
verifier passed for M04. Add focused strict state/bad input/handoff/reset tests,
historical custom-binding migration, keyboard/mouse/pad short tap/hold/blocked
throw checks, independent count/records counters and bounded live projectile/
resolved explosion presentation. Test real supported tram prediction including
ride, departure, jump and retry. Do not lower authority or coverage checks.

Use isolated local child storage for a real completed-v5 M04 resume into M05,
then exact body/gear/HP/armor/continues/outcomes, arrival release barrier and retry.
Root coordinates release executable ownership. All checks require exit 0, clean
error logs and each harness's PASS marker. Record failed attempts honestly.

Request framebuffer ownership before Compatibility proofs. Inspect multiple
frames of throw/bounce/blast, patients and real tram motion, plus workshop lit and
shaded views, roof/trench route, menus and departure/cancel. Full pinned checker,
verifier and regenerated published tour are integration gates. An ordinary-input
clear is authoring evidence, not twelve-minute pacing, five-minute par, fresh-
player acceptance, all rescue/difficulty combinations or hardware performance.

Primary InputMap/ImmediateMesh/Shader 4.7 API references checked by the parent
plan on 2026-09-30; retain the Godot 4.7.2-stable pin and Compatibility path.

## Work record

Research complete. Implementation begins with independent controls/menu groundwork
while exact M05, grenade/explosion and moving-tram contracts are finalized.

## Client implementation receipt, 2026-09-30

The strict M05 helper binds the six fixed objectives, the three stable worker IDs,
same-height walking corridors terminating in boarding, retained M03/M04 outcomes,
prepared freight flag and monotonic bounded tram poses. Gate handoffs clear old
prompts and hide the moving registered body until matching facts arrive. Rider
support uses center feet exactly as ordinary authoritative support does; the
sweep still checks the full 0.5 m radius and 1.8 m body. Eleven shared vectors in
`client/golden/m05_tram_vectors.json` are consumed on both sides. LocalPrediction
keeps a bounded pose history and extrapolates at most its existing three ticks.

G, middle mouse and LT use one rebindable action. Historical custom ownership of
those tokens is retained; a missing new binding adopts only unclaimed defaults.
Live snapshots own grenade positions, fuse and bounce count. Contacts synchronize
silently on join; only newer contact counts produce bounce cues. Resolved serials
own bounded voxel bursts and spatial Effects cues, including after owner death.
The burst's roughly 1.4 m visual silhouette is separate from the 4 m damage radius.
A view-depth shader rejects effect geometry within 0.6 m of the actual render eye.
Grenade records aggregate separately while the six gun slots retain their meaning.

Low Water reuses repaired surfaces, late-afternoon skyline and three validated
floor runoff patches: workshop center (-19,-10), size (2.4,3); trench center
(-4,15), size (2,3); freight center (14,36), size (2,3). Conflicting solids reject
individual patches. Registered roof/wall/tank/bench/pen/carrier volumes receive
flush repairs, utility marks and bounded practical lamps. All three workers use
provisional free-agent strips; Splice has a restrained magenta repair patch.
Approved final named character artwork remains separate work.

Practice uses one focusable four-mission selector, one Launch button and a visible
Back action. The lowest explicit settings resolution is 1280x720. An additional
640x360 resizable-window capture is exploratory evidence, not a new platform or
resolution commitment. Departure previews actual held/freed/aboard feet, permits
cancellation and queues only a fresh existing Use Action on confirmation.

Focused clean PASS logs under `.agents/m05-client-buildout-20260930`:
- `test_grenade_controls-third.log`, `test_grenade_effects-fourth.log`.
- `test_m05_mission-final-focused.log`, `test_equipment-final-focused.log`.
- `test_local_match-fourth.log`, `test_local_prediction-fourth.log`.
- `test_campaign_audio-ninth.log`, `test_frontend-ninth.log`.
- `parse-all-second.log`: 174 scripts, zero parse failures.
- `test_m05_presentation-tenth.log`: headless verbose, no retained audio leaks.
- `m05-rendered-proof-second.log`: isolated Compatibility render PASS on AMD780M.

Inspected actual isolated frames: `practice-development-1280x720.png`,
`practice-development-resized-640x360.png`, `m05-arrival-voice-caption.png`,
`grenade-authoritative-live-body.png` and `grenade-resolved-burst-strip.png`.
The selector and return control fit; the exact arrival caption and controls render
while Voice playback is active. The revised burst strip shows a readable warm
bone/orange silhouette that shrinks across actual frames. These are fixture and
mechanical audio receipts, not authored combat, human listening or fun acceptance.
Root delivered the bounded three narration/two SFX batch; its exact generation
and spend receipts remain in `m05-audio-batch.md`. Existing nine-caption pairs
match submitted text and committed byte manifests; decoded assets have positive
energy. M05 clips measure 13.28, 7.12 and 6.72 seconds; bounce/blast decode at
0.48/0.88 seconds, within 0.05 seconds of the submitted 0.5/0.9 requests.

Outstanding gates: actual M05 local child isolation/v5 carry and owned cleanup,
full client checker/verifier, authored gameplay grenade/ride/worker/departure
capture and final standard published tour. Source stays in flight until these
converge. Fresh-player, route timing, difficulty acceptance, final character art,
carrier flight and later Port of Entry remain unproven or unbuilt.

Post-checkpoint review corrections: newly created workshop practical lamps now
receive the selected graphics shadow policy after town configuration. The real
registered-wall fixture checks Balanced shadows and Performance light retention.
`test_m05_mission-practical-final.log` and `test_qa_combat-modal-final.log` both
exit 0 with clean PASS markers. The mission harness also exercises held Use
refusal, release, a fresh physical key event through the passenger modal's signal,
and stale-prompt refusal. Authored QA has separate physical review and cancellation
hooks which retain the visible review for its named screenshot, verify the mission
prefix remains unchanged with no queued Use, then reopen and confirm normally.
These hooks still require the actual rendered route receipt.
