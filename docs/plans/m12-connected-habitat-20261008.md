# Connected Terms of Cooperation habitat

Status: **shipped** in [PR #375](https://github.com/blisspixel/fragr/pull/375)
at `73cd69e8`, released as v0.80.0. Spend: $0. The connected habitat, Arc
discovery, Assessor, shelter, pumps and coalition departure are on `main`.
Fresh-player, difficulty and final-art acceptance remain open. The dated
standalone map and its evidence remain historical artifacts.

## Source and intended behavior

The accepted [level 12 brief](../campaign/m07-terms-of-cooperation.md#level-12-design-twenty-level-expansion)
owns the pressure arrival, market, maintenance bay, greenhouse, pumping court,
shelter, galleries and mutual-aid depot. The required facts are
`shelter_route_secured`, `aid_force_arrived` and `coalition_commitment`. Optional
people never gate departure. The separate
[habitat slice](m12-habitat-development-20261008.md) has ordinary walking and
finite combat evidence, but no mission identity, Arc, Assessor, shelter release,
pump receipts, aid arrival or connected save. It cannot be renamed to imply
those systems already exist.

Create `server/maps/m12-terms-of-cooperation.json`, map id 1012, using the
standalone habitat's established routes as the geometry source. Keep
`server/maps/test/m12_habitat_development.json`, its helper and old receipts
unchanged. Reuse the [Arc foundation](arc-foundation-20261008.md) and
[Assessor foundation](assessor-foundation-20261008.md). Do not relabel a Notary
as an Assessor or give the player a gun before actually finding it.

## Server contract and ownership

Use the existing mission readiness, objective controller, actor participation,
encounter groups, Use targets, prepared worlds and shared departure. Reserve
mission id `terms_of_cooperation` and gameplay floor 44, below Low Water's 45.
Campaign rules revision 4 and save version 15 belong to their existing owners.
There is no alternate readiness, continue, network or persistent history door.

Proposed ordered objectives are `market_secured`, `arc_found`,
`greenhouse_secured`, `shelter_route_secured`, `aid_force_arrived` and
`coalition_commitment`, followed by `party_departed`. Final identifiers and
shared hooks are agreed with the integration owner before source edits.
Clear facts require the actual corresponding encounter groups and physical
arrivals, not actor names, an arbitrary global kill count or client state.
The Arc fact also requires actual equipment ownership. The court clear secures
the shelter route. Reaching the depot after that clear establishes actual aid
arrival; a subsequent physical depot Use establishes commitment. Departure
requires a fresh living, ready, aboard party and the ordinary shared Use seam.

Prepare the shelter's closed and open worlds, their same-source navigation and
registered use faces before readiness. After the court clear, a physical Use
beside the shelter opens its one door. Optional shelter and worker release
facts are retained separately; neither opens the required route by magic nor
becomes an escort dependency. Anonymous people and existing cast keep their
actual identity and hostility. Prior rescue history is never invented.

Pump health comes only from resolved impacts through the shared combat seam.
The severe brief needs a real damaged-pump negative control. The standard
Assessor-on-squad brief needs actual Union victims from that drone's one-time
supported wreck, reported by the combat owner. A landing animation, a generic
frag count or simultaneous deaths cannot establish it. Player and civilian
damage remains excluded from wreck targets. Aid staging, lights and equipment
read server facts; visible arriving help must not imply a physical collision or
motion outcome the server has not supplied.

The mission owner takes new `protocol/m12.rs`, `maps/authored/m12.rs`,
`mission/m12.rs`, `mission/controller/m12.rs`, canonical map, focused native
tests, client state validator, HUD copy, habitat presenter and client tests.
Shared enum, MapInfo, MissionState, authored-loader, runtime, controller,
local-launch and manager edits are surgical and coordinated. The combat owner
supplies Assessor wreck and pump-impact hooks. The save owner supplies strict
historical migration, M11-to-M12 promotion, retry inventory and outcome carry.
Builds and renderer windows are serialized with those owners.

## Client and visible meaning

Add strict matching map/state validation, including ordered objectives, source
identity, pump bounds and health, optional rescue facts, challenge chronology
and the exact current objective action. Register the exact canonical venue name
with the existing habitat material and sky kit. Render the shelter, pump
condition, people, depot aid and supplied controls from those accepted facts.
No presenter decides clear, arrival, rescue, commitment, damage or departure.

Use short existing story and localized text seams outside combat to establish
that help arrived late and came with resources. Preserve the accepted political
meaning and do not turn the communities into secret villains. The district's
working name remains a proposal. Vegetation, protected habitation, incoming aid
and human story comprehension require inspected walking-height evidence.
Existing proxy cultivation frames do not establish finished greenhouse art.

The proposed early Rocket Launcher secret cannot be claimed: that weapon is
not implemented in the current roster. Do not replace it with a renamed gun or
grenade. Record this remaining design gate explicitly while building the
available required Arc/Assessor and mission systems. No earlier optional reward
is required to clear the level.

## Verification and acceptance

- Strict authoring rejects incorrect group order, clipped Assessor hover,
  blocked supplies, stale gate worlds, unsupported required targets and
  unreachable depot or shelter routes. Prove both approaches and the utility
  loop with shared movement and actual players.
- Test each required fact's ordinary positive path and wrong-order, wrong
  actor, stale state, missing Arc, remaining threat, missing aid, remote Use,
  dead party and partial boarding negative paths. Keep optional release
  independent of required completion. A retry resets the whole current attempt
  without rewinding ticks, input or inventory revision.
- Fight the actual finite Arc lesson and Assessor. Resolve the wreck challenge
  and damaged-pump failure path through combat, not injected counters. Finish
  the mission with its normal finite equipment and without secret guns.
- Verify strict client fixtures, new mission admission, MapInfo-before-state,
  owned process readiness, current record/history and exact-byte save
  migrations with the owning lanes. Complete an actual socket route and an
  inspected renderer route through shelter, greenhouse, court and depot.
- Retain commands, failed controls, frozen source hashes, native outcomes,
  current renderer/device and inspected originals under
  `.agents/m12-connected-habitat-20261008/`. Public evidence distinguishes the
  new connected map from the unchanged dated standalone slice.

Local implementation and mechanical acceptance do not establish a twelve-minute
human experience, enjoyable difficulty, final art, all rescue permutations,
other-platform execution or shipment. Keep those gates open until their actual
evidence exists. The integration owner maintains the one roadmap sequence and
shared plan index. No paid requests, cash charges, new dependencies, commits or
external publication belong to this work.

The first two owned M12 renderer attempts on the corrected canonical stairs
failed before their first capture. Passive lifecycle tracing in the second
attempt confirmed the correct map and mission briefing, then an invalid
participant-record disconnect. `PlayerRecord._valid_scope` still allowed only
M01 through M11. Add M12 to that existing strict boundary, replace the obsolete
pending-M12 rejection with pending M13, and check current nine-column M12 records,
durable allowance, actual network delivery and unknown-mission refusal. Preserve
both failed attempts and the intentionally stopped old-source full client check;
repeat the owned route and complete client gate on the corrected source.

The same boundary review found stale frontend expectations for the pending
mission and ten-item practice selector. Verify the existing M12 saved button,
arrival selection and eleventh practice option; retain M13 as unavailable.
Correct M12's launch title and preparing text, which otherwise fall through to
the earlier annex copy. These checks build menu state without starting a server.

The corrected boundary and focused frontend checks now pass. The third owned
renderer route completes all 17 canonical states and writes an actual durable
M12 departure on early M12-only native `e4804f...`. Its exact representative
prior-history input, finite equipment, preserved earlier outcomes, inspected
originals and normally retired owned processes are bound in
[the connected M12 evidence](../evidence/m12-connected-habitat-20261008.md).
The actual record has 91 attacks, 69 connects, 17 kills and zero deaths. One pump
is destroyed and the Assessor wreck earns no Union victims; those challenge
paths remain explicit. This establishes no played M01-M11 history. Final
composed gates with corrected M09 and the final native identity remain pending,
so the campaign checkpoint remains at eleven accepted missions.

Both focused corrections now pass. The record harness verifies current M12
scope, retained second-attempt allowance, actual network delivery and strict
pending-M13 refusal. Its first two diagnostic assertions compared manually
constructed integers with JSON-decoded numeric variants; actual delivery had
already succeeded. Those failures remain retained, and the final expectation
uses the decoded wire shape. The complete frontend harness passes M12's saved
button, arrival selection, eleven-item practice selector and launch copy while
keeping the pending M13 unavailable.

The third owned M12 renderer route passes all seventeen states on native
`e4804f1963430481970ebdd222e96e5bf69d9bf21aa18987faa58f8715186b79`
and canonical map `c30871c5e11f9792eb8353158b94e27335b4d14a7c65ee5ac28b1c0f99a91431`.
Its authoritative record has 91 attacks, 69 connections, 17 weapon kills,
2,449 mission ticks, no deaths, 101 HP lost and 99 armor lost. Actual pickups
and recovery explain the losses without a death. It begins with a representative
saved entry at 37 HP; this is not a played M01-M11 history. The real departure
preserves all prior fixture history, run identity, synthetic body and the one
remaining continue. Both owned processes retire cleanly. The saved outcome
honestly retains one destroyed pump and zero Assessor-wreck Union victims.
This is early M12-only proof, separate from the subsequent corrected M09 native
and complete client composition. Raw checks and failed attempts remain under
`.agents/m12-connected-habitat-20261008/` and
`.agents/crouch-controls-20261008/`.

Splice's focused regression run also found an older compact-selector assertion
in `test_m05_presentation.gd`. It still expects ten entries ending at M11.
Update that existing assertion to require the eleventh M12 option while retaining
the selected M07 default and every earlier index. Preserve its original failed
log and source, then rerun the complete owning presentation harness. This changes
no menu behavior or acceptance bound.

The corrected complete presentation harness passes with numeric exit zero and
clean owned retirement. Its assertions retain earlier mission indices, the M07
default, keyboard/gamepad navigation, exact arrival playback and the bounded
grenade fixture. The new source and process receipt are bound in
`.agents/crouch-controls-20261008/m12-selector-fix-first/result.json`.

The final current-native M12 route exposed a separate presentation defect:
the shelter and mutual-aid signs use oversized double-sided `Label3D` copy.
The actual shelter control approach sees mirrored lettering across the open
doorway; the bridge and aid approaches see the aid sign's back. Preserve the
original presenter and exact ordinary images before correction.

Replace only those two signs with the shared fitted, one-sided `WorldSign`,
keeping keyed copy and actor/state behavior. Place a bounded cosmetic shelter
plaque on the existing north doorway jamb, facing its occupied west approach,
and an aid plaque on the existing north boundary, facing south toward the
bridge and depot. Cosmetic plates add no collision or map/native change.
Extend the existing M12 presentation harness for fitted readable copy, one-sided
front direction and retirement, then inspect controlled before/after renders
using actual current geometry and retained ordinary approach positions. Keep
the old bytes/images and all previous route receipts separate. Whole-client
and package checks wait for this bounded final presenter freeze.

The separate fourth owned route now passes all 17 canonical states on final
native `3dabae6ba53355fa349b11d253c83fd45ae631b8091f8ce6226ae1b79617c7d4`,
with actual durable departure, preserved representative history and finite
equipment, 88 attacks, 69 connects, 17 kills and zero deaths. Both pumps remain
intact; the wreck earns no Union victims. The
[final-native supplement](../evidence/m12-connected-habitat-final-20261008.md)
retains its distinct facts and source bindings without changing the early
M12-only receipt. Full-size shelter and bridge originals expose mirrored
lettering in the retained pre-correction source; the bounded correction below
supplies separate presentation evidence. Final human art acceptance remains open.
This does not establish the whole-client composition or played M01-M11 history.

The sign-facing correction is implemented locally. The complete existing M12
presentation harness passes, as does a cleanly retired twelve-frame paired
renderer on actual native MapInfo and current cover. Exact original presenter
bytes, actual ordinary mirrored captures and the explicitly derived old-class
control remain retained. All four plaque corners fit their registered host walls.
Full-size doorway/jamb and aid-facing originals show forward readable copy on
bounded plates, with the doorway clear. The exact ordinary control-facing views
do not show complete plaques; the bridge view establishes removal of mirrored
far copy only. The [separate sign receipt](../evidence/m12-sign-facing-20261008.md)
binds 45 files, with an independent selected four-frame review. No native/map
change or additional gameplay outcome is claimed. Production presenter source
is frozen for the whole-client and package checkpoint.
