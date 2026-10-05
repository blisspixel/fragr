# Common Carrier prototype

Status: in flight, 2026-10-04. Native promotion work is authorized in isolated
branch `feat/m10-common-carrier`, based on crew receipt `32dd8ea2`. The frozen
Repeater and crew branches remain unchanged. This lane submits no paid calls
or GPU work. The Repeater foundation is merged, and this prototype was normally
composed with main `cc8efcc8`. The separate crew receipt PR 363 is frozen at
`501e8a80`, with eight CI jobs and all three desktop packages passing. Parent
integration remains separate. Final acceptance must precede publication or a
complete-mission claim.
The initial outline came from M09 `01912934`, now shipped in v0.73.0.
This is one bounded level under the existing campaign build order.

## Source and canon

[CAMPAIGN](../CAMPAIGN.md) places Common Carrier at level 10, the start of
Episode III, four days toward Mars and before the wipe. The active
[twenty-level design](../campaign/m06-common-carrier.md#level-10-design-twenty-level-expansion)
owns the three-deck boarding defense and Repeater discovery. Its older top
half mixes the Remote Mine and Redactor into this level and uses obsolete
rescue numbers; those finds belong to M11 in the active expansion.
[Ship direction](../design/space.md), [cast](../lore/cast.md) and
[voice](../lore/voice.md) own construction, identity and ordinary-life tone.

Shipped main has eight weapon identities, six number-key slots and strict
participant-record revision 2, with preserved revision 1 readers accepting
five, six or seven columns. The accepted Repeater foundation appends index 7,
private finite warmup, capability 35 and save version 11. Actual Repeater
presentation and the M10 lesson remain unbuilt.
M09's shipped v10 run file preserves earlier outcomes and actual equipment,
but no M09 crew outcome. The separately tested v12 capture checkpoint retains
real released crew and the immutable aboard-at-departure subset, or explicit
historical missing facts. That receipt does not complete transit.
Completed M09 currently waits for unplayable `common_carrier`.
No existing boarding fact, cabinet fact or legacy prose supplies the missing
M10 systems automatically.

## Playable goal

Learn the ship as a place people live, then repel a Union boarding force
through its working cargo, service and habitation routes. The familiar freight
shaft, two stair trunks and window toward the custody tender let a player
recover orientation after a fight. After securing the passenger deck, a fresh
physical confirmation by the living ready party leads to pending M11.
No pilot simulation or NPC arrival time decides whether the player can finish.

The first-player budget of roughly twelve minutes and the brief's five-minute
par remain design proposals. Do not emit par until an actual route is played
and the value is reviewed. There is no forced opening wait to fill the budget.

## Inhabited ship and spatial contract

The ship is repaired transport with ordinary possessions and finite supplies,
not a succession of sterile corridors. Keep the M09 name, worn bone pressure
doors, gunmetal ribs, warm practical work lights and cargo fittings. Union
boarders bring their black/red issue kit into this different environment.
Sparse cyan belongs to navigation equipment. Habitable rooms have real shells.

| Space | Work and possessions | Route and fight purpose |
|---|---|---|
| Passenger/refit deck | Bunks, a galley, wash/recycling corner, shared charging, repair bench and tied personal bags | Safe initial orientation; two useful exits; the returning final defense changes this familiar space |
| Forward cargo hold | Lashed containers, pallet handling lane and freight marks | First boarding pairs on floor and supported rack gallery, with readable cover and a lateral retreat |
| Lower service deck | Power distribution, contained coolant, accessible maintenance clearances and repairs | Close work bays connect a direct route and a service flank; Crawlers enter through visible bounded passages |
| Command approach | Shielded controls, charts, personal lamp and a framed exterior window | A short breath and Tern at work; message and outbound traffic remain ambiguous |
| Aft cargo loop and freight shaft | Cargo transfer aperture, overhead service gallery and clear equipment access | Two-level mixed fight; the shaft joins, rather than replaces, the walking routes |
| Passenger return | The same bunks, tools and possessions after combat | Final threat has two stair approaches; optional passengers take protected routes without blocking them |

Use two ordinary enclosed stair trunks and a cargo figure-eight. A direct
route is fast and exposed; the service route changes the angle and reaches
finite supplies. Neither becomes an empty long bypass or a mandatory switch
chain. Every deck remains reachable on foot, including the optional overlook.
The tall freight volume supplies contrast to smaller habitation rooms; wide
cargo fights remain useful. No fire-door objective or sealed route is added
merely to make a room look busy.

Proposed blockout allocation, subject to actual shared-body tests:

- Retain the roughly 16 by 36 m main hull footprint. The initial collision
  source reserves two separated 4.2 by 13 m stair trunks, each with two
  1.8 m clear flights, seven 0.2 m rises per flight, 1 m service treads and 3 m return landings.
  Identically oriented flights stack 2.8 m apart. The earlier 2.8 m-wide
  straight-flight proposal could not supply paired 1.8 m lanes and safe
  returning headroom. One trunk is forward port, the other aft starboard,
  producing useful alternate approaches rather than adjacent doors.
- Keep a central cargo/service opening approximately 4 by 8 m, with supported
  galleries and railings outside the walking clearance. This taller volume
  explains freight handling and exposes recognizable deck edges; it is not
  a lethal mandatory jump or an elevator timing gate.
- Lower service has two working aisles around equipment bays. The passenger
  deck has a galley and bunks to one side and repair/charging to the other;
  doors reconnect both aisles. The upper deck has command and an aft handling
  gallery rather than another full floor of repeated boxes.
- A preliminary floor spacing of 2.8 m gives floors at 2.0, 4.8 and 7.6 m,
  with at least 2.4 m clear standing headroom after slabs. The roof would need
  to reach approximately 10.2 m. The accepted raised-deckhouse direction uses
  a 10.1 m roof underside and 10.4 m outer roof in the initial collision source.
  The provisional M09 keel's 9 m sides require coherent exterior refinement;
  its existing upper freight and stern neck already rise above that keel.
  Never shrink bodies or clip a ceiling to make three decks fit.

The first generated collision source had 92 solids without mission authority.
The in-flight prototype now registers its own M10 authority and capability,
but grants no Repeater and has no complete combat or visual acceptance. Initial
native geometry and actual-server walking checks pass: strict authored loading,
sealed three-deck headroom, both flights and turns, forward/reverse walking
in both trunks and the complete cargo/command return. Actual movement uses
no jumps and causes no damage. Earlier 0.4 m treads had no canonical navigation
nodes; a subsequent 2 m turning landing still lacked a clear grid connection
around its divider. Both failures are retained. These are collision checks,
not authored fight, visual, transit or fresh-player acceptance. Prototype
the stair run, 180-degree landings and every deck return with real 1.8 m
bodies before decoration. Both ordinary routes must support retreat and
finite supplies, while open cargo lanes remain wide enough for the intended
mixed fight. Large volume is appropriate where its roof, ribs, cargo access
and pressure seal make its purpose visible.

Before coordinates freeze, reconcile the interior with the actual exterior.
M09's provisional keel is 16 m wide and 36 m long, its bow reaches 23 m forward,
and its stern access rises above the main hull. Do not hide an arbitrarily
larger interior behind that shell. Three inhabited decks, slab thickness,
stairs, headroom and the full-height freight shaft must fit an authored ship
envelope or require an explicitly reviewed exterior refinement. The shared
fighter body is 1.8 m high with 0.5 m radius; snapshot reference height is not
its collision height. Prove actual supported body clearance before dressing.

All floors, ceilings, stair treads, blocking cargo, machinery, pressure panes
and columns are server solids. View-only details attach to registered faces.
Windows expose bounded black space and the distant tender, never an opening
into playable vacuum. Off-ship scene motion is presentation, not physics.

## Ordered fights and discovery

The following sequence is an authoring proposal, not a frozen guard count:

1. Forward cargo: paired Clerks and Sweepers establish floor/gallery fronts.
   A visible boarding tube explains their arrival; its opening does not spawn
   a damaging body inside a player or behind the only escape.
2. Lower service: obtain Repeater at a real cargo locker before a Crawler
   group enters the long service aisle. Its visible passage, approach sound,
   commitment and retreat space teach tracking a stream, then releasing it.
3. Aft loop: existing Heavy Sweeper pressure and a Notary in a validated tall
   shaft combine with a cross-deck front. Both stair routes stay useful.
4. Passenger return: the final push uses the two known stair trunks. Every
   required living hostile must be resolved before a fresh exit can succeed.

Each group uses existing authored activation and server intent. Precompute
all worlds and navigation before readiness. Future groups cannot take damage
or act before their gate. Do not replace identifiable threats with a long
hold timer, repetitive reinforcements or arbitrarily inflated HP. Guard count,
trigger volumes and supply amounts freeze only after controller/body preflight;
then the same exact roster must survive full rendered acceptance.

Existing tiers remain rules revision 3 unless a genuine existing timing rule
changes. The brief's side-supply preservation and no-boarder-passenger-entry
challenges remain optional. A missed challenge cannot softlock an otherwise
cleared ship. If recorded, native counters must count actual events, not client
estimates or pre-existing dead bodies.

## Repeater contract before the lesson

Append a genuine gun identity without changing earlier indices. It shares
finite Bullets with Pistol and Rifle; there are no magazines, reloads or new
ammo pool. Keep it out of the default arcade kit and earlier campaign finds.
Use existing held `Action.fire`, selection and equipment decisions, including
the same controller used by humans and agents. No second combat channel.

The server owns idle, warmup and active fire, with a bounded warmup before the
first resolved shot and a denser stream than the Rifle. Proposed timing and
damage need an isolated feel trial before becoming constants. Holding fire
does not spend bullets until actual shots; each shot spends exactly one.
Release stops fire, and restarting requires the defined warmup. Switching,
death, leave, readiness loss and retry clear cycle state coherently. Dry fire
cannot produce damage, hidden shots or unbounded audio. Existing ray, armor,
cover, statistics and resolved-shot paths own every outcome.

Foundation PR 358 preserves every physical key: Shotgun remains key 3 and
the automatic Rifle/Repeater family uses repeated key 4. Its wheel places
owned Repeater beside Rifle; earlier indices remain unchanged. No seventh
physical key or renamed Rifle is proposed. The client must draw the actual
warmup and shot cues from authoritative state; it cannot infer a successful
shot from trigger hold or animate a false barrel stream after suppression.
Committed dead-shooter results retain existing shot feedback semantics.

Foundation capability 35 protects Repeater maps for all roles before Welcome.
Its explicit record revision 2 has eight columns; revision 1 retains exact
five/six/seven-column validators and older recipients receive only a genuine
zero downgrade. The retained-reader transport proof is recorded in the
[foundation evidence](../evidence/repeater-foundation-20261004.md).
M10 mission/transit and future cycle-presentation facts need their own reviewed
strict extension and all-role admission contract. Reserve no later capability
silently. Private warmup alone is not a truthful warmup presenter. Never
truncate actual new counters or borrow another gun's art or audio.

## Carry, episode refill and persistence

Promote completed M09 to M10 only under the existing run writer lock, carrying
actual HP, armor, body, selection, owned weapons, all ammunition, grenades,
mines and recorded earlier outcomes. Clear only old-map supply claims. This
is the Episode III boundary: refill continues to three exactly once when
promotion succeeds, never equipment or health. Reopen, preview, repeated
continue calls and M10 retry cannot refill again. Retry anchors the real M10
entry, including its passenger/transit facts, while tick, input and inventory
revisions remain monotonic within a process.

The owned prototype uses strict version 13 after the v12 berth receipt.
A v12 document cannot contain M10 or its transit. Versions 10 and 11 retain
their exact earlier shapes. Preserve the exact strict v11 and v10 readers, original-byte
archives, all older migration readers and
correct known/unknown outcomes. Historical v10 M09 completion cannot invent
crew boarding, restored memories or new gun ownership. Native new completion
records actual new facts. An explicit historical-unrecorded shape can preserve
unknown facts only for legitimate historical upgrades, not as a forged escape
from validation in new native documents. M11 remains pending and unplayable.

## Voluntary passengers and story decisions

Nick accepted released crew finishing boarding during a short authoritative
departure transition on 2026-10-04. Keep M09 boarding-at-confirmation and later
transit completion separate. The player can move on while actually released,
eligible crew finish this transition; no escort wait or companion clock gates
progress. Implementation remains a subsequent reviewed checkpoint, not part
of foundation PR 358.

Capture actual release and already-aboard sets at accepted M09 departure,
then record explicit transit completion for the eligible released set through
the same server-owned transition. A held person cannot arrive merely because
a later room has a marker. The transition must survive process exit/reopen
without duplication or equipment refill. A new native completion needs
validated facts; strict historical documents without a crew outcome remain
explicitly unknown, never synthetic empty sets or assumed rescues. Preserve
the accepted old zero-aboard route receipt as what happened at confirmation,
even when a later native transition records additional people aboard.

Edda follows the accepted recorded clinic-team rescue mapping. Splice requires
actual M05 evacuation. Those are eligibility facts, not a substitute for actual
release/transit outcomes. Tern, voluntary berth crew and Latch have their own work
and grounded movement; they are not obedience tokens. Optional dialogue,
assistance or staging cannot become a mandatory NPC arrival gate. Missing
people produce visible empty places or alternate ordinary support, not copies.
Historical unknown choices remain unknown and cannot block completion.

M08 cabinet secured is not proof that Orrin was restored, that memory survived
or that a new chassis is the same person. A named restoration needs an explicit
authored event and honest outcome first. Mara/Renn appearances and the exact
message quoting Latch's ledger require cast and already-established-detail
review. No code derives a personal count from unrelated kill statistics.
Text must carry all essential meaning; optional sound is restrained. No wipe
countdown, identified hidden sender, inevitable catastrophe warning or AGI
omniscience is revealed here. Practical disagreement, repaired belongings and
the bunk argument establish ordinary relationships between fights.

## Implementation outline and owned seams

After M09 promotion and contract review, use one mission branch with bounded
checkpoints, not a competing global queue:

1. Accept the isolated Repeater foundation and its exact-head CI/packages;
   then review actual source, cues and played feel before selecting a lesson.
   Own the narrow protocol/inventory/sim/statistics and client boundary seams;
   prove the real gun before building its lesson.
2. Review the explicit crew-transition/save contract and raised deckhouse
   envelope, then author a collision-correct leaf map and exact encounter roster.
   Prove actual movement, shot cover, hover clearance and living contacts.
3. Add `mission/m10`, `maps/authored/m10`, protocol and controller leaves,
   strict client state and a ship presenter through existing registries.
4. Extend locked promotion/retry and local preview, then the existing opening,
   readiness, story and results handoff. No second save or companion door.
5. Freeze a complete ordinary-input route, match its native build, run focused
  and whole-stack checks, then inspected hardware and fresh-player review.

### First native checkpoint: actual departure-to-entry promotion

Use `RunDocument::promote_next` and the existing `RunStore` lock, original-byte
archive and atomic replacement. Add Common Carrier's private entry identity
only as needed to represent the canonical saved transition. Until the authored
M10 destination exists and validates, native launch must refuse before Ready;
the identity alone cannot make the level playable or grant a gun. Build the
real authored collision/objective leaf and use its exact source hash through
the existing fixed campaign-content table, rather than adding an alternate
optional-hash framework solely for this intermediate stage. Capability 36 is
reserved for the strict M10 map/mission facts and all-role pre-delivery gate.

The proposed strict version 13 document preserves the v12 M09 receipt without
altering its released set or actual berth subset. A separate transit outcome is:

- `Recorded`: the completed arrival set equals the canonical actually released
  set from the recorded M09 receipt. The short departure transition finishes
  boarding for those people while the player moves on. It does not resample
  live berth feet, set all live NPC flags, or convert merely eligible people
  into a release. Empty, reordered, duplicate or extra arrivals refuse.
- `HistoricalUnrecorded`: a historical M09 receipt has no factual release or
  boarding set. Keep arrival history unknown rather than fabricate zeros or
  infer release from earlier clinic/workshop outcomes. Optional unknown crew
  cannot block the living player's mission.

Transit is absent while awaiting M10 and is committed with its real M10 entry,
never in a story callback or a separate file. Only this accepted edge refills
the Episode III continue allowance to three. HP, armor, weapon ownership,
Bullets, Cells, Shells, grenades and mines retain their actual finite exit
values. Only old-map personal claim IDs clear. Reopen, retry and a repeated
promotion request cannot refill or duplicate arrivals. Retry retains the M10
entry anchor and immutable departure/transit history.

Retain an exact strict v12 reader plus v11 and earlier readers and archives.
Adding a current Common Carrier identity must not broaden historical mission
acceptance: every old shape still refuses forged M10 entry/completion, transit
fields and future Repeater ownership. Current forged arrivals and unsupported
M11 transitions must refuse. A failed write preserves original bytes and the
pending M09 step; successful reopen has the same crew, finite supplies and
single episode refill. Native tests must exercise the actual locked store,
including source-matching historical whitespace and failure-before-replace.

The native checkpoint owns `mission/run_file.rs`, its strict legacy/store
leaves and the transit boundary. The separately owned capability 36 M10 map,
mission and controller seams now deliver those facts only after all-role
admission. Exact compatibility and route gates remain required.

### Cast and ship gates still requiring explicit work

Recorded Edda and Splice arrivals follow actual M09 release plus their accepted
clinic-team and workshop-evacuation eligibility. The unknown case does not
reconstruct their travel from eligibility alone. Any unconditional Tern staging
in historical runs is an authored appearance rule, never a recorded arrival.
Tern's current pilot staging is accepted independently of unknown history.

Orrin's recovered cabinet does not prove restoration or continuity. The active
brief asks for a restored person with missing recent memories, so M10 needs an
explicit authored restoration event and honest outcome before presenting that
state. No mandatory companion, repair timing or survival gate follows from it.
That event is separate from completing berth crew boarding.

The raised deckhouse/headroom fit remains a geometry review gate. Repeater's
real source, truthful cues and isolated played lesson remain presentation gates.
These do not prevent testing finite promotion data now; they do prevent claiming
a finished ship mission from a correct save transition.

Root-owned cast/catalog, README, global roadmap and plan index stay unchanged
in this outline. Implementation coordinates exact shared file hooks with other
lanes before touching them. Rust/GDScript and existing wrappers only.

## Meaningful acceptance

- Real warmup, held stream, release/restart, finite depletion, cover refusal,
  heavy-role interactions and reset behavior through GameState. Test human and
  shared agent control, true resolved records and malformed cycle facts.
- Old-reader wire proof, stable earlier weapon indices, strict legacy records,
  unsupported-role refusal before admission and packaged new resources.
- Actual all-deck controller movement with closed room ceilings, both stair
  trunks, every finite supply, elevated enemy and service flank. Living civilian
  contact must not strand any mandatory player route; Notary volumes stay clear.
- Safe entry through reader-paced opening and real readiness, including the
  authentic low-health, finite M09 carry. No damage while only partly ready.
- Native departure after every required guard, with fresh use and all ready
  living participants. No optional challenge, passenger delay or absence gates it.
- Strict v11/v10 and earlier byte archives, forged-field refusal, exact-once Episode
  III continue refill, actual inventory carry, save/reopen/retry/exhaustion,
  transit-known/unknown cases and honest pending M11. Own process cleanup.
- Real released/already-aboard/transit-completed sets through all four Edda/
  Splice eligibility combinations, held-person refusal and process interruption
  before/after transition commit. Historical zero-aboard receipts remain exact;
  missing old crew facts remain unknown and never block the living player's exit.
- Full ordinary-input fights and departure on a frozen matching native; retain
  every rejected attempt. Inspect first arrival, Repeater lesson, multi-deck
  motion, room function, final passenger return and spectator eyes. Verify
  story dismissal consumes/releases input and retry never fires it twice.
- Full workspace, Clippy, matching client checker, exact-head CI and all desktop
  packages before shipping. Fresh people must orient by deck shape/sign and
  freight shaft, find the gun, understand finite resources and choose a useful
  flank without a verbal walkthrough. First-player time and optional par remain
  measured/reviewed gates, not checklist-derived claims.

## Assets and limits

Reuse packaged Latch, civilian placeholders, existing hostile atlases, weapons,
surface kits, fixtures and story infrastructure for mechanics. Ship rooms,
blocking cargo, bunks, workbenches and pressure frames use local authoritative
construction. Common Carrier exterior and Repeater are existing catalog
families, not new paid orders from this plan. Named cast faces, a polished
Repeater model/motion/sound and final ship craft stay candidate gates until
their own references, source, package and played checks pass. No new asset
family, paid request, runtime service, zero-gravity, vacuum damage, vehicle,
decompression, Remote Mine, Redactor or M11 map is added by this outline.

## Native contract checkpoint

The owned prototype reserves capability 36 for the actual M10 map/facts, required
before all-role Welcome. Its current encounter candidate is 17 guards in four
ordered groups (4, 5, 4, 4), including a three-Crawler service pack, forward
floor/gallery pairs, an aft Heavy Sweeper and bounded freight-shaft Notary,
and the passenger return. No Redactor or remote mine is reassigned from M11.
All current authored placements and physical confirmation pass strict loading.

Save version 13 retains the immutable M09 receipt and a separate strict
M10 transit fact, absent before actual promotion. Recorded arrivals must equal
actual released IDs; unknown historical receipts remain unknown. Pilot Tern's
current appearance is independent of unknown historical boarding. Optional
passengers appear only from actual Recorded arrivals. Strict v12 and every
earlier reader must refuse forged M10 stages or transit fields, archive exact
bytes and preserve finite entry and one Episode III refill. M10 retry uses
that entry and the already-committed transit. Orrin remains a secured backup.
## CPU prototype evidence, 2026-10-04

Twelve focused native tests pass on the current prototype, including real
capability 35 refusal for human, agent and spectator before Welcome, accepted
capability 36 map-before-mission delivery, strict map-bound controller facts,
readiness-safe entry and actual anchored continue. Seeded authority fixtures
clear the same 17-body roster explicitly; they are not combat playthroughs.
They prove all-ready living party departure, physical aimed use and refusal
of a held use through peer arrival. No optional challenge gates departure.

The client import and M10, M09, M08, participant-record and shared mission
harnesses pass with clean logs. Unknown transit presents current Tern alone;
all four Recorded optional rosters, fake restored Orrin, duplicate arrivals,
map mismatch, rewinds, disappearing archive facts and map retirement are
checked. Essential arrival/departure text uses the existing consumed-input
story/readiness boundary. Civilian strips remain provisional casting.

A new Latch marker at the first stair-side candidate was refused by strict
supported reachability. The final marker is at the supported east passenger
entry, and spawning uses the existing companion lifecycle. Native source and
all new map facts still need complete workspace and real owned-process checks,
full ordinary combat, hardware inspection, inhabited room dressing, finite
supply pacing and actual Repeater source/cues before mission acceptance.

## Real launch and continue checkpoint

The composed native workspace passes 941 server tests, all 17 then-existing
real local-child tests and the other workspace suites, with three previously
ignored server tests unchanged. Format and all-target Clippy pass. A first
real M10 client launch exposed a missing CLI value-parser registration, despite
the existing dispatch branch. That failure is retained. The corrected executable
and added child regression prove capability 35 refusal for all three roles,
capability 36 ship-world delivery before facts and owned shutdown.

The actual two-child M10 local harness passes with clean logs. It upgrades an
exact strict v12 completed M09 fixture once, preserves its empty berth boarding
subset, commits all five actually released crew as separate transit arrivals,
refills continues once, carries 39 HP, 17 armor, one Cell, two grenades and
three mines, and spends one mine through ordinary input. Reopening restores
the unchanged finite entry. Ordinary movement activates the first real fight;
actual enemy damage kills the player, and the existing continue input restores
39 HP and the entry counts while reducing continues to two and retaining
monotonic ticks and transit. No guards, player damage or inventory are granted
by the client. These are migration, lifecycle and retry checks, not a won
combat route or final ship art acceptance.
