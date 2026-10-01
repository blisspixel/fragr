# M04 client prototype and presentation

**Status:** shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. Child of
[Notice to Vacate](m04-notice-to-vacate-prototype.md). External spend: $0.

The later [M05 increment](m05-no-forwarding-address-prototype.md) replaces the
pending unbuilt M05 boundary with playable carry, capability 26 and save version
6. Earlier evidence below retains the versions actually tested.

## Goal and boundaries

Present the accepted Low Water market, optional clinic, habitation court and
deliberate roof departure through the existing authoritative campaign wire.
Support isolated development launch, saved M03 carry into M04, M04 resume,
retry and the unbuilt M05 boundary. Keep M02's passive Notary unchanged.
This prototype does not certify fresh-player pacing, narrated scenes or final
character production. No paid service, cloud apply, commit or release is needed.

## Ownership and architecture

This lane owns the M04 strict helper, MissionState dispatcher and HUD, local
launch/menu, records/story boundaries and their focused tests, M04 catalog
copy and scene manifests, offline Notary audio, and Latch's near-camera
presentation material and checks. Integration owns GameManager, NetClient,
ActorState, EnemyView, the Notary rig/atlas, PlayerPawn connector, world renderer
and shared checker. Authoritative positions, flight, aim, damage, photographs,
clinic gate, patient travel, continues and departure remain Rust-owned.

Every authored mission now requires capability 25, retiring revision 2 live
readers before admission. Map 1004 carries current rules revision 3. `MapInfo.m04`
binds the optional clinic control/release region, bounded patient route points,
six fixed arrival objectives, deliberate departure, boarding and companion
start. Only `clinic_open` may change in the ordered prepared-world handoff.
Mission facts carry the completed prefix/current action, clinic secured/open,
patient release and registered feet, photograph count and carried recall cars.
Validate exact types, bounds, route corridors, objective order, prompt party
readiness and progress monotonicity. Retained M03 choices cannot change during
retry. Historical record revisions remain readable; live rules require 3.

Scenes reuse ScenePlayer's reader fallback and input-release readiness barrier.
Objective cards leave the aiming area, device switches refresh existing copy
without restarting timers, and optional patient rescue never becomes a wait gate.
M05 is shown honestly as pending, without an available launch button.

Notary audio is original deterministic locally baked mono 16-bit PCM with
source/output hashes and level measurements. Fixed spatial Effects voice pools
follow validated nearby actor/phase and resolved fire facts. A timer cannot
invent a shutter launch or landing. Late joins, retries, duplicate/out-of-order
facts and map/disconnect cleanup are explicit. Captions survive mute.

The live Latch material removes only intrusive near-camera fragments. It keeps
world position, scale, depth testing, lighting, ordinary opaque surfaces and
authoritative blocking. The ward's default materials and release gesture remain
unchanged. Accept only after close approach/retreat and ordinary M02/M03 capture
review, without claiming that hidden fragments remove server collision.

Godot 4.7 APIs checked 2026-09-30:
[spatial shader built-ins](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html)
and [AudioStreamPlayer3D](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer3d.html).
Fragment `VERTEX` is view-space; bounded `discard` retains opaque rendering.
Spatial attenuation and `max_distance` bound the audio footprint.

## Verification and acceptance

- Focused strict map/state tests include clinic world ordering, current binding,
  route corners/intermediate feet, corrupt fields, prompt readiness, retries,
  immutable carry, records and keyboard/gamepad glyph refresh.
- A real owned local child uses isolated save/settings/records directories,
  confirms capability/readiness, holds input through scene dismissal, preserves
  the existing save during development and cleans up only its own PID/lease.
- Audio tests require fresh nonsilent assets, phase/shot deduplication,
  interrupted tells, late-join suppression, supported landing and bounded pools.
- Companion tests retain ward material/pose and registered live-body geometry;
  close captures and shot-blocking evidence distinguish presentation from combat.
- Full pinned Godot import/parse/harnesses and checker verifier pass with clean
  logs. Integration serializes release builds and owned-child runs.
- Inspect a complete ordinary-input M04 route, Notary directions and actual
  flight/tell/fire/interruption/crash sequences, patient travel, clinic worlds,
  market/court and roof departure, plus the standard published tour and affected
  M02/M03 companion captures. Static images alone do not prove motion or fun.

## Work record

The strict M04 boundary, route validation, typed clinic/roof prompts, retained car
choices, current rule retirement, record scope, development/resume menu, arrival
and departure scenes, Mara's market-clear notice and original Notary audio are
implemented. M05 remains an unavailable saved boundary. Historical record rules
remain readable. World copy uses the registered M04 sign keys.

The client source is frozen for integration checks. Pinned headless import passed
with a clean log at `.agents/m04-client-buildout-20260930/import-carry.log`.
Focused `test_m04_mission.gd` passed strict protocol, clinic ordering, patient
routes, retries, carry, prompt and keyboard/gamepad behavior. The final layout
regression caught a real intersection between the departure card and field
status; placing status below the visible card fixed it. See
`test_m04_mission-layout-fixed.log` in the same directory.

The README and playing guide now describe the independent M04 practice entry,
exact Continue Run progression through M03 to M04, pending M05 without a launch,
and explicit compatible v2/v3/v4 to v5 migration with historical rules retirement
and preserved archives. They retain the open fresh-player acceptance distinction.

`test_m04_local.gd` passed against two actual isolated owned children, exit 0 and
clean log `test_m04_local-carry-fixed.log`. Development preserved existing save
bytes. A real v4 pending M03 document then entered M04 from the menu, played its
arrival, held readiness while fire remained pressed, and carried exactly 61 HP,
7 armor, Synthetic body, selected Rifle, Fists/Rifle/Shotgun, 29 bullets, 8 shells,
0 cells, one remaining continue, run identity, and platform/roof car outcomes.
Old map supply claims retired. The child upgraded rules 2 to 3 and storage to
v5, preserved one archive containing the exact old bytes, and stopped cleanly.
The harness removes only its own isolated files, including the lock and archive.

The first actual child check found that the town presenter required an optional
solid bottom value. The world lane corrected the default and made construction
atomic before the clean repeat. Initial failed logs remain distinct from passes.

Focused frontend, M01/M02/M03 mission, LocalMatch, story scene, records, Notary
audio, Latch and M02 ward harnesses all passed cleanly, exit 0, under
`test_<name>-final.log` in the same directory. Notary assets have deterministic
source hashes, fresh output hashes, real nonzero PCM energy, explicit import
format and loop settings. Its four fan and four cue voices remain bounded;
confirmed shots, supported falling landings, late joins, repeated map packets,
reset and missing-asset caption fallback have focused coverage.

The Latch shader also passed an actual Compatibility renderer check on AMD
Radeon 780M, clean exit 0, `test_latch_near_clip-rendered.log`. Inspected
`latch-near-original.png`, `latch-near-clipped.png` and
`latch-distant-clipped.png` show the nearby aiming pixel occupied before clipping,
clear afterward, and an ordinary opaque body at distance. A later actual-camera
depth correction also removes close peripheral fragments in the upward-looking
rendered regression. This proves shader execution and the
bounded correction, not universal close-camera quality, gameplay pass-through,
hardware performance or ordinary M02/M03 motion. Collision and shot blocking
remain server-owned and unchanged.

Final integrated checks passed all 163 scripts and 76 harnesses. The M04 tour
passed all 23 states, and the standard published tour all 32; the parent plan
links their inspected gallery and actual-camera-depth receipts. No single
static still establishes Notary tell, flight, burst or crash motion, patient
travel, or fresh-player acceptance. Scenes retain text fallback. Six caption-
matched narration clips for M03 departure, M04 arrival and M04 departure are
integrated under [campaign transition audio](campaign-transition-audio.md),
using previously included credits and no new cash charge. M03 arrival remains
reader paced. No named character performance or listening review is claimed.
