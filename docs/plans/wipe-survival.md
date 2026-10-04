# Wipe survival

Status: planned high-level direction, 2026-10-04; detailed rules, numbers and
implementation cuts below are proposed and unbuilt. Nick confirmed M20 as the
larger survival finale, with M18 and M19 building toward it, usable vehicles,
placeable automatic turrets, strategic choices and the same system for multiplayer.
His further clarification requires ongoing Union conflict interrupted by an
unexpected takeover, then continuous overwhelming catastrophe. No zombies,
announced arena waves, shopping breaks or defeat of the whole intelligence.

[The complete design](../design/wipe-finale-and-mode.md) owns map decisions,
pressure compositions, device economy, control isolation, life/admission rules,
art references and acceptance questions. [CAMPAIGN](../CAMPAIGN.md), the active
[M18](../campaign/m10-all-systems-normal.md#level-18-design-twenty-level-expansion),
[M19](../campaign/l19-planned-works.md), [M20](../campaign/l20-local-exception.md)
and [Still Here](../campaign/epilogue-still-here.md) own story and outcomes.
The historical M10 filename does not reinstate a single 33-minute retry.

## Placement in the existing sequence

This is a dependency breakdown inside the existing
[Full build order](../ROADMAP.md#full-build-order-updated-2026-10-04), not a second
global queue. Build campaign levels one at a time under rung 8. Reuse the jeep
from current M14, motorcycle from M16 and jetpack from M19 when their actual
gates pass. Build Collector with M18, Paver with M19 and Surveyor with M20.
The Wipe director and local sentry slice belong to those mission needs; add the
shared multiplayer wrapper inside the existing multiplayer/mode work. Release,
LAN, exposed-server and scale proof stay in their existing rungs.

Do not skip M09-M17, ship this as implemented because the plan exists or begin
paid source generation from this document. Keep any provisional art explicit.
Each implementation cut needs a unique bounded plan and its own evidence.

## Contract to preserve

- M17's real leadership victory and Voss's live capture coexist with scattered
  Union field fighting and unreleased controlled bodies at the M18 onset.
- Connected centralized infrastructure and imposed Union control channels are
  seized together. Free people act independently because liberation removed
  control, not because a human/agent skin grants magical immunity. Nature and
  individual autonomy remain outside those channels, physically vulnerable.
- The abrupt coordinated switch interrupts human orders and conflict in actual
  actors. No earlier outbreak countdown, global knowledge claim or instant
  unbounded offworld control. Show the expanding scale through the world.
- Locally isolated hardwired or mechanical resistance equipment can continue
  functioning. Repainting a connected captured jeep never removes a backdoor.
  Equipment control/isolation belongs to server identity and authored facts.
- Independent Latch and friends seek one local reprieve. No mandatory buddy,
  revival, companion command interface, persuasion score or slow NPC softlock.
- Each wipe level has its own clock and mission-start retry. Initial active
  targets remain 10/11/12 minutes. Only terminal survival unlocks the epilogue;
  exhausted failure gets its own ending and credits. Rescue totals affect
  framing and faces, never hidden survival eligibility.
- M20's proposed eight 90-second spans are hidden budget/evaluation windows
  within twelve continuous minutes. They are not broadcasts, rounds, cleanup
  gates, public spawn schedules or eight pieces of the whole 33-minute finale.
- Threats, supplies and destruction persist. New difficulty comes from taught
  routes and combinations, not sponge HP, arbitrary damage or hidden weapon
  immunity. Keep a feasible low-resource route entirely on foot.

## Cut A: shared short catastrophe scenario

First prove a short complete local scenario, proposed at two active minutes, on
one pump-house/pier loop. Use a real existing enemy role and one properly tested
Collector when available. The short duration is a verification fixture, not
campaign timing or an assertion that the finished finale feels good.

One proposed `sim/wipe.rs` owner manages deterministic seed, active ticks,
eligible pressure events, current actual world, finite stock and terminal result.
The mission and multiplayer wrappers configure it; they do not create separate
directors. Extend the strict authored loader with bounded real ingress routes,
safe placement regions, cache/deployment anchors and selected prepared worlds.
Precompute navigation and validate use targets before readiness. Keep rotating
search ownership and the current shared per-tick budget.

Allow a local continuous reinforcement through an actual route and one bounded
world change with a preserved alternate path. Player-facing cues are local
enemy tells and physical danger, not an invasion announcer. Do not retire living
enemies to clean up a wave. A population cap defers an eligible addition rather
than silently buffing enemies or spawning beside a player.

Meaningful gates: identical seed/input yields identical events and stock;
no start before actual readiness; no future or inactive actor damage; actual
routes traversed through shared movement; malformed/over-budget data refused;
current geometry and MapInfo precede changed state; no arbitrary blocked fallback;
committed lethal effects resolve before a same-tick terminal reprieve; duplicate
terminal handling cannot grant extra progress. Retain failed source/hash receipts.

## Cut B: one finite portable automatic sentry

Use an initially local modular source to prove mechanics. The parent may prepare
one distinct production candidate only after its object brief and bounded budget
are reviewed. It is a hardwired non-conscious local tool, not a constrained agent.

The device has explicit owner, position, facing, actual ammo, health, phase and
control-isolation facts. Share traced attacks, damage, hostility and ammunition
ownership. It cannot be a fake player pawn, client timer or remapped Union role
that secretly changes personhood. Four round devices/two per owner are initial
proposed caps. Place near actual feet on clear authored ground, without changing
the first slice's walking topology. Keep a shootable box and a nonblocking tripod.

Parts and initial/refill ammo are finite. Fresh deployment spends once atomically;
failed placement spends nothing. Pack/reclaim preserves exact ammo and damage.
Repair spends finite parts, cannot resurrect a destroyed tool, and lasts a short
interruptible action. It never creates ammunition. Explicit leave disables the
tool; a teammate can reclaim it ordinarily without a grant. Disconnect/resume,
death, committed attacks, reset and reprieve have specified cleanup ownership.

Gates: real near/far and covered/visible target selection; role hostility;
bounded traverse/tell; actual hits, damage and finite depletion; lateral/cover
counters; placement bounds/ground/LOS/actor/gate/spawn/water refusals; stale
preview/input rejection; owner/round caps; duplicate requests; atomic transfers;
pack/reclaim/repair economics; no camping win by dry/hidden devices; death and
leave/rejoin cannot keep a lost team alive or refill stock; actual package helper,
skin and assets survive export. Client preview never establishes a placement.

## Cut C: teach restoration and takeover in M18-M19

Build the new role behavior with its actual mission introduction. Collector work
and exposed commitment, Paver preparation and a bounded damaging strip, and
later Surveyor observation/mark must use real server facts. Do not label delayed
invisible hitscan a traveling canister or call an ordinary Sweeper a restoration
machine. New role tables, timing revisions, actor/control identities and content
requirements need strict capability and save review.

M18 must show already-present controlled Union bodies ignore humans and redirect
together while free agents remain themselves. The supervisor's failed command,
field disruption and nearby infrastructure change establish the threat before
the larger view. Human holdouts can remain hostile, flee or help under explicit
authored allegiance; their species or outfit never implies assimilation.

M19 preserves familiar Low Water routes, growing physical destruction and
Latch's independent departure. The jetpack opens a useful alternate route, while
an ordinary ground path survives all legitimate states. Do not move its first
introduction into M20 or demand fuel to finish a mandatory gate.

Gates: isolated readable counter first, real mixed encounter second; marks and
strip endpoints match actual geometry; interruptions and safe lateral escapes;
living/captive/free/controller identity; legitimate control removal and isolated
equipment; no inferred skin faction; optional ally absence/loss fallback; human
and free local agent control; spectator/skip/muted views; mission entry/death/
continue/exhaustion; finite actual carry and strict byte archives. Add ordinary
first-player checks before certifying the ten/eleven-minute experiences.

## Cut D: M20 district finale, vehicles and durable ending

Author the proposed six-district 180 by 160 metre loop only after route and load
measurement supports it. Every repeated link carries cover, supply, flank or
height value; cut empty space. Validate two ground routes and a retreat through
all prepared stages. Distinguish distant cosmetic collapse from actual dangerous
world changes. New damaging debris/water cannot arrive solely through a shader.

Place already proven isolated jeep/motorcycle/jetpack families. One jeep and one
bike are proposed initial counts. Vehicle loss cannot strand a player or delete
required ammunition. Wipe's finite mounted ammo needs explicit profile review
against the older heat-only jeep proposal; do not silently rewrite its global rule.
No boat, aircraft or new heavy vehicle is required for this slice.

Bring together learned restoration roles, seized familiar bot bodies, known
equipment attacks, local sentries and finite routes. Initial caps are four
participants, 24 simultaneous hostiles, four sentries, two vehicles, four walking
civilian proxies and eight prepared world stages. The approximately four hundred
people in the story can use aggregate authoritative groups plus bounded proxies,
with actual named/outcome continuity. Never count drawings as rescues.

Extend the existing locked run document only after the concrete fields exist.
Freeze scenario seed and exact entry equipment/outcomes. Archive strict historical
bytes, reject forged new fields in older shapes, restore current-level timing on
retry and retain monotonic process tick/input/inventory revisions. Survival
entitlement is an explicit persisted result, separate from statistical history.
Replay cannot consume a continue or invent an entitlement.

Full gates include the real twelve-minute interval, death at the threshold,
duplicate completion, allowance exhaustion, same seed retry, prior M18/M19 entry
carry, late local process shutdown, actual epilogue unlock and failure refusal.
At the terminal reprieve harmful local effects end consistently; no extra boss,
late shot or slow return by Latch revokes an earned ending. Machines continue
outside the local boundary in the inspected scene.

## Cut E: the same continuous system in multiplayer

Add a validated Wipe rules profile and round wrapper around the exact shared
scenario owner. One cooperative four-seat team is the first proposed target.
Muster/results live outside the catastrophe fiction; once active, it has no
announced waves, shop breaks or wave-clear respawns. Friendly fire is off first.
Refuse incompatible host mutators explicitly until tested, including unlimited
weapon/extra-life combinations that contradict finite supplies or team elimination.

The design proposes six finite team reinforcements, no revival and safe-anchor
ordinary admission. A dead participant spectates until a valid request can spend
one charge at a secured anchor. Total team elimination loses immediately. Initial
muster roster gets one deployment; replacement/late join after start consumes
stock. Identity cycling, a bot replacement or repeated disconnect cannot create
free lives or ammunition. Existing valid resume returns the same parked/dead
state, not a fresh inventory. Explicit leave has no refund.

Spectators stay default and never affect progress or spend stock. They can join
when a safe paid deployment is possible or queue for the next round. Human,
agent and rule-bot seats share one Action/wire/controller seam. MCP observes
strategic facts and submits discrete intent slowly; local controllers remain on
the tick. There is no second campaign tool or privileged combat channel.

Gates: humans-only, agents-only, mixed and spectators; safe/unsafe late admission;
full caps; charge atomicity; dead/parked/valid/invalid resume; leave and empty
server timeout; bot replacement; identity churn without minting stock; all-dead
same-tick loss; one last survivor at threshold; same seed shared events;
MapInfo/facts ordering; malformed/new-version refusal; two-machine LAN and
remote-drop evidence before those claims. Competitive teams and endless Sweep
are later explicit profiles, never the default or campaign life contract.

## Art and budget boundary

Required Wipe families: Collector, Paver and Surveyor are the master roster's
three already planned restoration sources; one portable automatic sentry is
the only additional distinct family. No per-wave copies or new named-face casting.
At the conservative planning allowance of 35 credits each, four source candidates
reserve 140 credits total, 35 incremental to the master roster. All four need
local mechanical rigs, zero 5-credit standard humanoid rig calls. This is not a
live quote, generation authorization or finished-animation estimate.

Reuse existing/planned jeep, motorcycle, jetpack, drone, civilian, weapon and
Union body families. Packed/broken sentry derives from its actual source. Build
placement/repair fixtures, barricade remnants, sluices and utility geometry
locally or reuse the world catalog. Boat/aircraft are outside the first slice.
Each object requires a stable brief and reference hash, identity, scale, palette,
footprint, moving joints, actual poses, parent source, package path and acceptance.
Exact future paid stages still need live credit preflight, durable capped receipts
and explicit approved scope. Nothing in this plan submits or expands spend.

## Release and fun gates

Run the repository's full required native checks, coverage floor, client import/
parse/harness checks and package install gate on frozen combined source. Retain
isolated run files, matching native hash and owned-process cleanup. A docs review
does not require runtime tests, but none of these eventual behavior gates can be
replaced by a checklist mark.

Measure actual maximum-population preparation, steady tick headroom, traffic,
navigation fairness, corpse/projectile/device cleanup and rematch memory. Run
real renderer views in busiest legitimate mixtures. Headless PASS is not GPU
performance, and one local renderer is not broad platform or public-server proof.
Larger 8-seat/48-hostile/8-sentry/4-vehicle trials need their own evidence first.

Play full duration on each difficulty with low-resource entry, no vehicles,
no sentries, several honest build/flank strategies, optional rescues absent,
muted audio, reduced flashes and gamepad/remapped controls. Inspect cover and
marked destruction for unavoidable damage and safe camping. Measure empty-run
length and voluntary repeated rematch interest, not just survival success.
Do sentries buy an interesting move instead of playing the game unattended?
Does a wrong supply choice create a recoverable scramble? Does the unexpected
takeover read clearly without an early spoiler? Does the local exception feel
like a reprieve while the world outside remains catastrophic?

The campaign/MP system remains in flight until real ordinary runs, strict failure
branches, full CI, package/lifecycle and human fun gates pass. The fixed clocks,
counts, field-part prices, reinforcements and map size remain proposals until
those played checks justify accepting them.
