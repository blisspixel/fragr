# M05 client prototype

**Status:** implemented, 2026-09-30. Child of
[M05 No Forwarding Address](m05-no-forwarding-address-prototype.md).
**Spend:** $0 new charges or asset calls in this lane. The round has consumed 693
included audio credits with a separate $3 equivalent reserve. No publishing,
release build or additional generation is part of this lane.

## Goal and contract

Present the Episode I evacuation through recognizable Low Water roofs, a working
tram workshop and a usable trench. Reuse strict mission, equipment, input,
settings, world, scenes, local process and QA seams. Rust remains authoritative
for objectives, rescue, grenade count/flight/bounce/blast and tram movement,
collision, rider transport and shot cover. Gameplay capability 26 applies to
authored missions; campaign rules remain revision 3. Six weapon/statistic slots keep
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
Grenade records aggregate separately while the six weapon slots retain their meaning.

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

At the initial freeze, outstanding gates were M05 local child isolation/v5 carry and owned cleanup,
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

The first native child run reached both development and historical pending M05
arrival, retained the input barrier and saved exact v6 entry data. It then caught
an unintended entry pickup: the roof Rifle was one metre from the spawn, so idle
entry claimed it and added 60 Bullets before walking. Exact carried-gear assertions
remain in place while authoring corrects that placement. Historical JSON outcome
checks compare named fields and integer counts rather than whole dictionaries
with different parsed numeric representations. Two independent fixture lifecycle
failures also converged: town light preferences wait for initialized settings, and
equipment UI safely accepts clear or inventory data before its child labels exist.
The later ready callback hydrates retained data. Focused clean PASS receipts:
`test_equipment-lifecycle-final.log`, `test_jammer_audio-lifecycle-final.log`, and
`test_shot_effects-lifecycle-final.log`. Both native children were stopped before
handing executable ownership back for the updated embedded map.

Grenade motion QA collects at most 128 real snapshot samples and 64 serials only
during its strip, disconnecting at finish or scene cleanup. It excludes projectiles
already live before the tap and requires one actual stock decrement, one observed
launch and a same-ID resolved explosion. Initial position, fuse, bounce counts and
resolved hit facts are retained in the receipt. A missed transient fails the gate.
`test_qa_combat-grenade-receipt-final.log` parses the new receipt seam cleanly.

`test_m05_local-converged.log` now passes the real development and historical
v5 transition checks with exact carried values and owned cleanup. The first
complete client pass, `godot-full-converged.log`, exits 0 with 174 scripts and 81
harnesses. `checker-verifier-final.log` exits 0 for all ten fault scenarios.

Rendered route iteration remains explicit. The first launch failed before play
on a project-relative manifest path. The second reached six states and caught an
incorrect exact claim expectation after ordinary Shotgun discovery. The third
reached 18 states and proved one real grenade launch, stock decrement and matching
explosion, plus equal 4.860018 m tram/rider displacement with 98 supported samples.
Its Heavy phase gate then failed correctly: a prior stage's travel-fire override
had leaked into quiet stages and killed the Heavy before the observer began.
The shared helper now resolves each stage against the declared manifest default,
preserving globally enabled defense. The regression locks scoped enable and
disable restoration, with `test_qa_combat-scoped-travel-converged.log` clean PASS.
The subsequent full checker was stopped for serialized map/release work; its
partial `godot-full-scoped-final.log` is not a passing receipt.

The tank and service signs now carry the accepted 6 motif; catalog import and
`test_map_decoration-six-copy-final.log` pass localized bounds. The third's former
service sign faced a narrow gap, so authoring selects its accessible registered
face for final capture. Freed-worker camera framing follows the actual route;
the earlier empty-pen strip does not prove visible walking. Earlier roof combat
strips which began after a clear only prove the post-clear view. Final current
source still needs a complete checker and coherent 25-state rendered receipt,
including actual Heavy phases, passenger cancellation/confirmation and sign fit,
followed by the standard published tour. Historical partial captures are retained
as diagnostics rather than exported as current completed evidence.

The scoped-travel boundary also rejects nonboolean global values rather than
casting them. `test_qa_combat-scoped-boundary-final.log` records clean PASS for
invalid string and numeric defaults, plus restoration of both declared boolean
defaults after a stage override. The optional grenade-follow capture is restricted
to a throw stage and a fresh, locally owned serial already observed launching.
Existing projectiles, other owners, stale ticks and invalid positions cannot steer
the capture. Launch aim remains ordinary first-person input; later camera movement
uses actual projectile and matching resolved explosion positions. It changes no
movement, trajectory or outcome. `test_qa_combat-grenade-follow-converged.log`
exits 0 with clean PASS. Its receipt explicitly identifies this camera mode.

Final authoring preflight selects a higher ordinary lob from the same supported
bench, with actual seeded damage beyond the chassis. This is deterministic
authoring evidence; the prior rendered throw landed on its roof and had no hits.
The final rendered receipt must establish its own result. The current registered
service-panel face and matching map are tracked by the server authoring plan;
the client waits for its matching release and exclusive runtime handback before
rerunning the complete checker and capture sequence.

`godot-full-follow-final.log` passes all 174 scripts and 81 harnesses with exit 0.
The fourth authored tour passes 25 states and all 21 required enemy deaths,
ordinary jump boarding, 97 supported ride samples with equal 4.860018 m tram and
rider displacement, three visibly walking freed workers and their eventual
boarding. Its Heavy probe records actual windup, firing, recovery and death,
including four enemy shots. Physical passenger review opens without queuing Use,
Escape cancels without mission progress, and a fresh reopen/confirmation reaches
the authoritative departure. The actual grenade spends one stock unit and resolves
its observed serial beyond the chassis, with no hits in that rendered run.
Deterministic seeded damage evidence remains separate from this outcome.

The first final standard tour passes 32 states and publishes 13 stills. Independent
full-size review then catches a passenger-modal layering defect: the underlying
live Use prompt overlaps its cancel line. The modal now uses the same CanvasLayer
convention as the match menu, above the HUD. The regression uses a real HUD canvas
and verifies layer ordering while retaining held-input, release, cancellation and
stale-prompt checks. `test_m05_mission-modal-layer-final.log` exits 0 with clean
PASS. The complete checker and both tours are rerun after this visible correction;
the earlier passenger still is not exported as the final UI receipt.

The corrected modal source passes `godot-full-modal-final.log`, again with 174
scripts, 81 harnesses and exit 0. The fifth authored capture remains a failure:
the Heavy is defeated, then the freight group activates and kills the idle player
during its post-clear capture handoff. The fourth zero-death receipt remains
historical evidence; it cannot substitute for current modal proof. Authoring
corrects the ordinary tactical route or scoped defensive handoff, preserving
actual phase requirements, enemy roster, damage, supply limits and the zero-death
gate. No current completed passenger still is published until that converges.

## Final verdict

The existing approach tell policy now honors explicit `evade_tells: false`, while
an absent flag retains its historical approach evasion. Nonboolean values are
rejected. `test_qa_combat-approach-policy-final.log` passes default, true, false and
invalid-policy regressions. Authoring holds the ordinary Heavy engagement at
z=26, before the freight trigger, with the same observer and required phases.
Its seeded proof discovers equipment normally, survives four shots and leaves
the freight guards dormant during the post-clear interval. No enemy, supply,
collision, damage, difficulty or map change is part of this correction.

Final current-source receipts under `.agents/m05-client-buildout-20260930/`:

| Gate | Receipt | Result |
|---|---|---|
| Pinned complete client check | `godot-full-approach-final.log` | Exit 0, 174 scripts, 81 harnesses, clean PASS |
| Checker failure verification | `checker-verifier-modal-final.log` | Exit 0, all ten scenarios |
| Authored M05 route | `m05-tour-sixth-wrapper.log` | Exit 0, 25 states, all 21 named enemy deaths |
| Current standard publication | `standard-tour-modal-final-wrapper.log` | Exit 0, 32 states, 13 published stills |
| Readable motion contact sheets | `motion-tiling-sixth.log` | Exit 0, original frames rearranged without new rendering |

The sixth route confirms ordinary jump boarding and equal 4.800017 m rider/tram
movement over 99 supported samples. All three workers visibly leave the workshop
and are actually aboard by departure. The Heavy has four observed shots, with
windup, firing and death required; the player ends at 100 HP, no armor, zero
deaths and three secret claims. The corrected physical review visibly shows
`F: DEPART NOW` and `ESC: KEEP WAITING` without overlapping the world prompt.
Escape restores that prompt with no departure action; a fresh confirmation
reaches the authoritative departed state.

All three secret locations are reached, but the three counted supply claims are
the tank armor plus service-pit Shells and Grenades across two locations. The
market medkit remains available at full HP. Neither the secret counter nor the
permanent equipment claim list implies that every location's consumable was
collected. No artificial damage was introduced to force the market pickup.

The actual grenade receipt records stock 4 to 3, serial 1, 41 live/resolved samples
and its matching far-side explosion with no hits. The visible flight and real
contact/fuse/result are established; effective blast damage in this rendered run
is not. The blast is occluded by actual chassis cover from the player's eye.
The isolated original burst proof and seeded damage checks remain separate.
The saved Heavy windup still faces Latch with the Heavy offscreen; only its typed
phase receipt proves that moment. The firing still visibly frames the Heavy and
resolved incoming shot, so it is the appropriate gallery selection.

Final read-only review inspected the authored contact sheet, full-size sign,
worker, Heavy, review, cancellation and departure frames, plus rearranged original
grenade, worker and tram motion samples. It also inspected the latest standard
contact sheet, published menus/settings/profile/records, first-person and team
views, both participant bodies, arena overview and weapon strips. No remaining
concrete clipping or control-overlap regression was found in those captures.
The practice selector and narrated arrival have their earlier isolated actual
renderer receipts; the main standard tour does not establish those scenes.

All owned native, renderer, checker and helper processes closed before the runtime
lease returned. This is an implemented prototype with inspected Compatibility
renderer evidence on the recorded AMD device, not fresh-player acceptance,
difficulty acceptance, full mission fun proof, final Splice art, carrier flight or
Port of Entry. No additional asset calls or external charges were made in this
lane. Root owns final gallery selection, documentation convergence and release.
