# Civic Pressure Valve connected stadium

Status: **in flight**, reconciled 2026-10-17. The Article Blade foundation is on main; the connected stadium belongs to the unpublished convergence branch. The earlier v0.86.0 release claim was premature. Follows the [M14 integration](m14-launch-authority-integration-20261015.md), merged in PR #404.
This document refines the existing campaign rung in the
[Full build order](../ROADMAP.md#full-build-order); it creates no new sequence.
Spend for this increment: $0, existing assets and local tools only.

## Goal and limits

Build the accepted [M15 brief](../campaign/l15-civic-pressure-valve.md): arm the
entrants, break the sanctioned bout with the Article Blade, take the broadcast
booth, survive the final wave and leave through the ceremonial gate. Preserve
the distinction between the Union's coercive games and the independent scrap
league. The Host takes over the stadium feed after the booth; he does not become
a campaign dispatcher. Arrival is the capital nine days after Mars, continuing
M14's coalition departure. Do not invent a new Voss speech, entrant identity,
survivor history or named-character voice to fill missing media.

This is a connected development mission, not acceptance of the twelve-minute
first-run target, five-minute par, final stadium kit or finished campaign.
M16 stays pending. No transport, engine, dependency, vehicle, general-purpose
moving-platform or all-mission co-op rewrite belongs here. Existing enemy rules
and timings remain unchanged unless separately measured and versioned.

## Inspected starting point

The [October 9 graybox](m15-civic-pressure-valve-20261009.md) owns
`server/maps/test/m15_civic_pressure_development.json`, map 1015. Its integration
test proves loading and static landmark routes, not a completed bout. Preserve
that source and its historical assertions. Author a new connected source at
`server/maps/m15-civic-pressure-valve.json` with an independent content hash.

The graybox has the pen, arming crate, plinth, four low lift platforms, two
stairs, upper booth, podium/screen, north gate leaves and ordered enemy groups.
Its exit landmark is in front of the closed leaves. It has no mission owner,
moving lifts, entrants, Blade, caption track or connected departure. The arena
seal and actual avenue exit therefore require new prepared worlds and route
proof, not a renamed static-map launch button.

Current reusable owners are `inventory.rs`, `sim.rs` and shared shot/damage
statistics; `encounters.rs` and its enemy controllers; `mission.rs`, authored
mission validation and `mission/controller.rs`; versioned `run_file` storage;
and Godot's accepted-fact presenters. M02's companion owner demonstrates shared
body, target and firing integration, but only defines Latch. It is not an
existing general armed-entrant system. Golden Rail demonstrates one-holder
return-to-pad lifecycle, but its mutator and instant-kill behavior are not Blade
rules and must not be reused as hidden campaign authority.

## Bounded implementation and ownership

1. **Article Blade foundation.** Add the canonical weapon through the existing
   action, inventory, equipment, combat and resolved-shot owners. The accepted
   M15 brief fixes 70 damage and twelve swings per claim; use nine ticks between
   swings at 20 Hz as the foundation candidate matching the proposed 0.45 s
   WEAPONS table, with no ammunition-pool or magazine refill. A missed accepted swing
   consumes one use; cooldown-rejected input does not. No melee head bonus.
   One registered plinth has at most one holder. Exhaustion, holder death,
   explicit leave and mission reset have explicit return semantics. Ordinary
   gun selection remains available. Keep Fists and Shiv unchanged. Resolve the
   foundation reclaim policy below before freezing the wire. Prove the isolated finite
   weapon before integrating the stadium, as for Rocket and Walker.
2. **Armed entrants.** Add a small authored roster with stable identities and
   bounded routes through the pen, floor and ring. A supported arming action at
   the crate commits its finite Pistol kits once. Actual actor bodies, ordinary
   intent, shared hostility, cover, damage and death determine combat. Entrants
   are free allies, not Union enemies renamed by callsign or fake human network
   participants. Their readiness does not consume party seats. No invulnerability,
   resurrection or remote scripted damage. Latch's handout is presentation of
   the accepted crate transaction; missing animation cannot block it. A dead or
   blocked ally must not prevent mission completion. Do not generalize this into
   a squad-command interface or mandatory escort system.
3. **Mission and stadium worlds.** Add `protocol/m15.rs`, `maps/authored/m15.rs`,
   `mission/m15.rs` and `mission/controller/m15.rs`. Precompute the pen/tunnel,
   sealed-bout and released-exit worlds and navigation before readiness. Register
   exactly the brief's two door systems: the players' tunnel and the arena seal.
   Closing a gate cannot embed a living actor, strand a participant outside the
   required arena, or imprison the only remaining enemy beyond the seal. Hold a
   closing transition until its shared boundary is clear; never teleport or
   crush an actor to force progress. Send MapInfo before changed mission facts.
   Maintain both stairs, floor/ring loops, booth access and supplies in every
   reachable world. The old exit landmark is not the new departure volume.
4. **Ordered bout.** Preserve the pen's three Clerks, the close three-Sweeper
   Blade lesson, tunnel wardens, camera Notaries, booth's two Clerks and Auditor,
   and final Heavy Sweeper/Assessor/two-Enforcer wave. Gate activation through
   accepted mission progress. Give the plinth a readable approach and room to
   use melee without standing inside its solid. Floor-lift arrivals must be
   visible authoritative staging: if platform motion carries bodies, implement
   and verify bounded support motion; static spawn-on-platform tests cannot
   claim moving-lift acceptance. Keep attacks off bodies until they can actually
   enter combat. Breath between waves creates room to read standings and find
   supplies; caption duration never determines server progress. Clearing booth
   guards and a fresh supported takeover action change the broadcast receipt,
   then introduce the final wave. Win opens the seal. Departure uses fresh
   all-party arrival/Use through the existing mission control channel.
5. **Presentation and controllers.** Add strict `m15_mission_state.gd`, a stadium
   presenter and HUD using native golden MapInfo/full-Snapshot/mission vectors.
   Mirror gate collision in prediction, navigation and visible cover. Present
   Blade holder/use count and actual swing/hit/return facts. Entrant appearance,
   death and allegiance follow accepted actor identity. Add the ordinary shared
   agent controller and an independently exercised human route with actual
   magazines/reloads. Respect weapon range, move while under pressure, capture
   only at safe checkpoints and test geometry-safe destinations; the M14 depot
   failures demonstrate why a passing accurate native route is insufficient.
6. **Connected persistence.** Promote completed M14 into M15 through the current
   writer lock, applying Episode IV's three-continue refill exactly once at
   promotion. Retain actual carried resources and all prior outcomes. Retry
   restores M15 entry resources, gates, entrants, plinth and fresh encounter
   state without rewinding ticks, input sequences or inventory revisions.
   Do not carry a borrowed venue Blade into M16. Preserve exact historical byte
   archives and reject unknown content rebinding. Extend the typed built-stage
   list, bundled source, CLI/menu/preview, MCP schemas and wire controllers
   together. Completed M15 stores pending M16 without pretending it is playable.

## Facts and compatibility

Map facts should identify the ordered objective contract, crate, plinth, gate
indices/world variant, entrant roster, booth control and departure. Mission
facts should retain completed/current progress, introduced wave, broadcast
takeover, armed/fallen entrant identities and challenge receipts. Existing
snapshot actors own current HP and position. A single Blade owner supplies
holder, remaining swings and plinth availability; never copy these into two
independently mutable mission and inventory authorities.

The M14 branch currently requires gameplay 49 and save version 18. Recheck the
merged source before assigning the next capability, save or record version.
Adding a weapon changes fixed statistics arrays and strict historical records,
not merely a weapon enum. Old records need explicit compatible decoding with
zero historical Blade use, and old saves must never gain a historical Blade.
Test client and adapter boundaries with actual complete native snapshots,
including allies, gates, pickups, shots and changed map identity.

## Decisions to resolve before the corresponding code

- The foundation choices and remaining Blade feel questions are scoped below.
  Reclaim timing remains a measured candidate, not an addition to accepted lore.
- Define the Blade-only wave receipt precisely with cooperating entrants.
  Recommended interpretation: all participant damage to that wave is Blade,
  at least one participant Blade hit is required, and allied Pistol contribution
  does not invalidate it. This is a proposed challenge interpretation, not
  established lore or an implemented rule. Resolve whether non-Blade misses
  count before naming the receipt. Track committed explosives from earlier
  waves and same-tick kills through resolved damage, not the final held gun.
- Fix a small entrant roster and per-kit ammo budget before authoring. Names,
  appearances and survival copy must respect existing character direction.
  Decide whether the unarmed pen is vulnerable before arming; the Severe brief
  explicitly concerns armed entrants. Loss after arming is retained even if
  someone leaves the combat area. None of these outcomes gates departure.

These are bounded mechanics choices for the next increment, not permission to
change the accepted plot, fabricate a voice performance or invent an ending.

## Next-round Article Blade foundation scope

Status: **planned**, refined 2026-10-15; still dependent on this round returning
to passing main. This is the first bounded slice of item 1 above, not a second
build sequence. It ends at a separate development range, before connected M15,
armed entrants, gates, new save stages or paid art. Inspect the merged baseline
again before assigning versions or editing shared files.

### Mechanics and acquisition candidate

[WEAPONS](../WEAPONS.md#the-ladder), the accepted M15 brief and
[weapon fiction](../lore/guns.md#the-article-blade) agree on 70 damage, twelve
swings and return to the plinth. Choose nine ticks at 20 Hz for the foundation
candidate, matching the proposed 0.45 s WEAPONS table; no implemented Blade
cooldown exists yet. Count every accepted swing, including misses and covered or
shielded contacts, exactly once through `Inventory::try_fire`; rejected cooldown,
inactive input and unowned selection spend nothing. Use the ordinary resolved
shot, damage, armor and statistics path. No head bonus, armor bypass, cleave,
remote damage or second damage counter. Resolve the twelfth committed swing
before removing the borrowed weapon, so its last hit and attribution survive
exhaustion or a simultaneous shooter death.

The older [weapon-economy proposal](weapon-economy.md#melee-which-you-always-have)
also suggests a sixty-second clock, Shiv replacement and a short lunge. These
are proposed mechanics, not current behavior or additional requirements of the
M15 brief. Do not import them as requirements. Compare **300 active ticks
(15 seconds)** and **1200 active ticks (60 seconds)** after return in the
isolated foundation, with the first plinth available immediately. Both are
experimental candidates; start the pacing trial at the shorter interval and
retain measured empty-plinth waiting before selecting a default. The 60-second
candidate is not canon or an accepted result. A twelve-swing lesson must not
turn into a mandatory minute of waiting. Death and explicit leave use the same
chosen interval as exhaustion, preventing suicide from accelerating supply;
whole-attempt reset restores the initial available plinth. No wall-clock
recharge while paused.

Reuse the existing contested pickup's radius, supported-height test, authored
line of sight, eligible participant filtering and sequential claim arbitration
in `sim.rs::tick_pickups`. The current loop automatically claims any available
useful pad on touch, and campaign contested stock normally never respawns. A
Blade plinth therefore needs one explicit, registered lifecycle exception:
available, held, cooling, available. Do not change other campaign supplies or
use `SupplyClaim::Personal`, whose retained claim prevents later reclamation.
Do not reuse Golden Rail's mutator, unlimited gun or instant-kill flag.

Fresh acquisition means an eligible player is observed outside the claim radius
after availability, then enters it. Initial available-world spawn counts only
after an outside observation too. A pawn already camping on the pad when it
returns must leave and reenter; an overlapping late join cannot acquire by
hydration. Use a small bounded per-participant approach latch, retired on leave
and reset. No new input or MCP verb is needed. The chosen winner receives twelve
uses atomically, and no contender can replenish a held Blade. Show availability
and the leave/reenter instruction in the range so this rule is discoverable.

Keep the found Shiv owned. A borrowed Blade does not replace durable equipment;
selection/cycling may prefer it in the melee slot while held. On removal restore
the last still-owned non-Blade selection, falling back to Fists, and clear the
held fire latch until release so the thirteenth held input cannot unexpectedly
punch or fire a gun. Ordinary dry gun behavior remains unchanged. This explicit
removal fallback is necessary because the selected borrowed weapon ceases to
exist, unlike an empty owned gun.

Use a two-metre straight trace as the first range candidate, with ordinary
walking and shared living-body contact. Lunge distance, collision behavior and
target assistance remain genuine feel decisions: do not silently interpret a
long ray or teleport as the proposed lunge. If a lunge is selected after the
basic finite proof, it needs a bounded authoritative movement step, solid/body
sweep, prediction mirror and movement vectors before connected acceptance.
The foundation receipt must say that this candidate has no lunge.

### Ownership and compatibility changes

Keep the remaining-use count in `Inventory`, separate from `ammo` and human
magazines. The plinth owner stores registration, holder identity, cooldown and
approach eligibility; it reads the holder's inventory count when publishing
facts. Claim, spend and return are atomic simulation operations, with an
invariant that precisely one eligible holder has 1..12 uses. Snapshot plinth
facts and private loadout facts are projections of this state, not independent
counters. Unregister on map retirement, clear through shared reset/death/leave
seams, and never let generic `grant_weapon` create an unregistered Blade.

The concrete compatibility surface inspected in this round is:

- Append `article_blade` at index 10 in `WeaponType::ALL`; preserve indices
  0..9 and the three-weapon `ARCADE` set. Audit `Inventory::owns`, `usable`,
  `try_fire`, `weapon_pad_useful`, grants and controller `shots()` paths: today
  absence of an ammo pool implies unlimited use. Reject the unsupported
  weapon-only mutator instead of accidentally making an unlimited Blade.
  Keep all four ammo pools, capacities and magazine schemas unchanged.
- Add strict registered plinth facts and bounded optional loadout uses, requiring
  zero/absence when unowned and 1..12 while owned. Validate matching registration,
  holder eligibility, cooldown/availability and count relationships with native
  full-snapshot vectors. Extend client equipment validation, selection, HUD,
  pickup/held presentation and resolved-shot feedback, plus adapter, brain and
  shared equipment controller readers. Use existing action selection and fire.
- Reserve gameplay 50 only if merged main remains 49. Require the new capability
  for every role on Blade maps, with shared arcade rooms following the existing
  global-floor policy; do not raise older campaign mission floors arbitrarily.
  Keep campaign rules 4 unless actual enemy timing changes require otherwise.
- Current participant records are version 4 with exactly ten weapon columns.
  New Blade records need version 5 and eleven columns in `protocol/statistics.rs`,
  `statistics/record_wire.rs` and `player_record.gd`. Give historical version 4
  an explicit ten-column branch before enlarging `WeaponType::ALL`; retain v1
  widths 5..7, v2 width 8 and v3 width 9. Historical decoding appends zero Blade
  counts internally and preserves historical serialization width. Reject a
  historical extra column even if zero. Exercise local `PlayerRecords` history
  v3 and owned-best/reward proofs without inventing retrospective Blade use or
  changing their independent document version merely for the new record type.
- The foundation range is non-durable. Do not bump save version 18 solely to
  store a borrowed venue weapon, and do not add M15 to built-stage/CLI/MCP lists.
  `SavedEquipment::validate` must explicitly reject Blade ownership/selection:
  adding a shared enum otherwise broadens current and historical saves. Test
  all historical decoder entry points against forged Blade equipment, including
  null/new count fields. Connected M15 later needs its own versioned stage and
  outcome migration; its entry has no Blade, retry resets the plinth, and exit
  must return the borrowed weapon before capturing ordinary carried equipment.

### Smallest standalone proof

The foundation's proposed native contract is explicit so the parallel client
and art lanes share one boundary. `MapInfo.article_blade` binds one registered
contested weapon pickup by `pickup_id`, supported claim-floor `feet` and
`return_ticks` (300 or 1200 for the measured candidates). The ordinary pickup
position is 0.4 m above that floor point. Refuse extra generic Blade grants.
`Snapshot.article_blade` carries `pickup_id`, `phase`, `uses_left`, `changed_at`
and conditional `holder` or `return_in`. Available means zero uses with neither
holder nor timer; held means one eligible holder and one to twelve uses with no
timer; cooling means zero uses, no holder and one to the registered maximum
remaining active ticks. Remaining active ticks preserve pause semantics. Require
the snapshot field exactly when the map registers the weapon and cross-check
the matching ordinary pickup projection. Private loadout carries optional
`article_blade_uses` from one to twelve exactly while owned; explicit null and
zero are invalid. Compare public/private samples only when their ticks match.

The native lane owns the protocol, authored registration, sim lifecycle,
inventory/combat hooks, record revision, save-equipment rejection and native
goldens. Integration owns all Godot fact boundaries, NetClient, equipment/HUD,
selection and record compatibility. Art owns isolated source/bake and visual
presenters. The CTF lane owns its new shared contact controller and changes to
brain `plan.rs`/`bot.rs` and playtest policy; coordinate small Blade enum-reader
changes in those files with that owner. Final-swing feedback consumes the
existing resolved ShotResult/ShotTrace weapon even when selection has fallen
back. Do not introduce another damage channel. This is a proposed wire shape
to validate in the foundation, not an already supported protocol.

Author a new range under `server/maps/test/`, with a supported central plinth,
clear approach and retreat, one wall for occlusion, a low obstruction for the
reach check and one small ordinary Sweeper encounter. Leave the historical M15
graybox and production missions unchanged. Supply a finite Pistol as a fallback,
not an unlimited kit. Use an ordinary-input route with wire-reconstructed
navigation: claim, spend a documented mixture of hits and misses, resolve the
twelfth swing, hold fire and remain on the pad through cooldown, then release,
walk outside and reenter for a second twelve-use claim. Retain actual shots,
pickup identities, loadout revisions and record columns; no forced phase,
position, HP or resource grants count as route evidence.

Focused native tests cover exact nine-tick cadence, twelve accepted uses,
blocked/range/head/armor outcomes, last-swing simultaneous death, atomic two-party
claims, cooldown and camping, inactive/detached/late participants, selection
fallback, leave, map retirement and reset. Wire goldens cover available, held,
one use, returned/cooling and reclaimed states plus malformed combinations.
Client and adapter consume actual complete native envelopes. Prove both human
magazine-bearing inventory and agent single-count inventory keep identical Blade
budgets without changing their gun reload rules. Then inspect the ordinary human
route in both supported renderers with a local readable sword placeholder and
text count/return cues. This establishes finite handling and interoperability,
not the final melee feel, stadium balance, lunge or full weapon asset acceptance.

### Parallel foundation presentation

The existing Article Blade and stadium asset briefs select local/derived work;
there is no retained reviewed sword asset. Build one rigid sword source through
ModelGeometry and the established source/bake seam, reusing cached metal/enamel
finishes and the accepted glove family. A distinct guard, issued grip and long
metal edge distinguish it from Shiv. Derive held motion, the 48-pixel pickup/icon
and plinth view from that same source. Preserve physical Union construction and
restrained black/red markings without implying magic, lunge or cleave.

The art lane owns the source, bake, held/swing presenter and plinth visuals.
The native lane owns claim, twelve-use, cooldown, return and resolved-hit facts;
integration owns strict client validation, selection and HUD seams. The twelfth
resolved hit must remain visible when exhaustion changes the selected weapon.
Show accepted remaining uses and available/held/returning states with readable
text and shape, not tint or sound alone. Check grip, wrist and screen edges at
4:3 and 16:9, muted play, reduced motion and clean retirement on both renderers.

Primary guidance rechecked 2026-10-15: [Xbox guideline 103](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/103)
supports distinct swing/contact feedback through multiple channels;
[guideline 102](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/102)
informs contrast-backed count/status text against changing backgrounds; and
[guideline 117](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/117)
informs preserving reduced motion and avoiding forced camera movement. These
guide candidate acceptance, not a compliance or final-feel claim. This lane
uses existing local tools at $0 and does not expand into stadium scenery.

## Readability research and lore checks

Primary guidance checked 2026-10-15: [Xbox accessibility guideline 104](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/104)
calls for speaker identification, readable configurable captions and meaningful
audio information in text. Use labelled official and pirate tracks; do not rely
on colour alone or a distant screen for the booth's change. Preserve Voss's
spoken English when the diegetic pirate text changes its meaning. Actual spoken
dialogue captions remain distinct from the deliberately subversive screen text.
The muted route must still explain the turn. Existing scene/text fallback owns
missing audio; missing paid media is not a gameplay dependency.

[Xbox accessibility guideline 118](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/118)
calls for photosensitivity review of flashes and patterns. Bound Notary camera
flash presentation and screen transitions, preserve readable attack warnings,
and inspect the composed fight rather than declaring compliance from an isolated
effect. This plan introduces no new version-sensitive engine API or dependency;
retain the pinned stack. Verify official documentation before any later API or
pin change instead of importing examples written for another Godot version.

The [Earth direction](../design/earth.md), [character direction](../design/characters.md)
and [games lore](../lore/the-chancellery.md#the-games) govern the kit: issued
enamel/steel, restrained red, occupied service areas, numbered hooks, ceremonial
podium and legible institutional coercion. Placard 67 remains unissued. Entrants
are people, not replenishing friendly turrets. The proposed countersignature
joke in the brief remains a proposal. No regeneration, wipe imagery or later
campaign revelation moves forward into this stadium.

## Verification and acceptance

Require focused native tests for finite Blade misses/hits/cooldown, exclusive
claim, simultaneous claim/death/return, reset and exhausted selection; shared
entrant targeting, finite ammo, death/contact and nonblocking loss; closed/open
gate reachability, occupied gate refusal and no stranded enemy; ordered waves,
booth-before-final-wave, exact challenge damage attribution and immutable facts.
Native golden vectors must cover briefing, arming, sealing, Blade exhaustion,
entrant loss, pirate takeover, gate release, departure and retry, plus invalid
states. Test hydration and MapInfo-before-facts in client, adapter and controller.

Prove an ordinary finite-input full route, the Blade lesson, the all-allies-lost
fallback, actual human reloads and selected difficulty challenge routes. Use
wire-reconstructible navigation. Test M14 promotion/refill exactly once, reopen,
retry, complete/pending M16 and strict historical upgrades. Then run composed
native/client/network gates and inspect ordinary routes in both supported
renderers, including muted captions and wide/small aspect ratios. Retain failed
captures and separate deterministic route evidence from fresh-player fun,
all-difficulty balance, final art and hardware-performance acceptance.

No paid generation, new cash charge or live service is required. Any later
asset production requires its own exact preflight, live allowance verification,
durable reservation and existing approval rules. Return this bounded increment
to passing main before starting another connected mission.
