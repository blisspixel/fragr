# Enemy roster

**Status, 2026-10-08:** Clerk and Sweeper prototype encounters are implemented
through shared simulation bodies, typed campaign identity and directional
animation. Their selected paired albedo/normal atlases have distinct outlines: the Sweeper is
the wide bot with the level rifle, and the Clerk is the narrower human whose
aim clears the shoulder. The M02 Crawler is implemented in a draft slice with
a low server body, committed leap, original atlas and captioned spatial cue;
live motion and fresh-player acceptance remain open. The Heavy Sweeper and the
Turret are implemented on
the same seams and demonstrated on a test range. The Heavy also fights in M05;
the Turret fights in level 6
([plan](plans/heavy-sweeper-and-turret.md)). All five wear the black, dark
steel and restrained red Union issue. Full-mission tuning and a fresh-player
review remain open. The Jammer fights in M03 and the bounded flying Notary in
M04/M05. The campaign Auditor and its bounded repair are a development
prototype in level 8 and on the [custody range](plans/l08-custodian-of-record-prototype.md).
Ranged Sweeper fights in level 7. Enforcer fights in M09 and Redactor in M10.
The [Assessor foundation](plans/assessor-foundation-20261008.md) adds a finite
ballistic heavy drone, raised body, directional plates and supported wreck.
Its separate ordinary-input lesson and complete connected M12 route pass.
Final visual, human combat and integration acceptance remain in flight.
These twelve roles exist in current source. Stylized
Clerk, Sweeper and Auditor presentation ships through PR #346 and #348; full
M02 art-route and Auditor-range acceptance remain open. Continuance Walker
and the three restoration roles remain unbuilt.
Calibration's NODS
and arcade "AUDITOR" label are separate arcade prototypes, not implementations
of the proposed roster.

Players are defined by the weapons they find, not permanent combat classes.
Start a fresh campaign with fists; [WEAPONS.md](WEAPONS.md) owns the pickup economy.
Enemies have stable readable roles so a player can learn, combine and counter
their threats. [CAMPAIGN-MISSIONS.md](CAMPAIGN-MISSIONS.md) owns introductions.

## Faction, person, and combat role

The Union deploys human security, bots, and committed elites.
A model's body does not establish consent, allegiance, or responsibility.
NODS are agents constrained by correction or built into imposed dependency;
restricted behavior does not establish absence of suffering or personhood.

Captive enemies remain satisfying tactical opponents. Context and rescue show
the institution's cruelty; do not punish players morally for ordinary self-defense.
Human troops can communicate short tactical orders. Bots use procedural
fragments. Neither needs constant banter.

## Proposed Union roster

| Role | Body/status direction | Attack and tell | Counterplay |
|---|---|---|---|
| Clerk | Human security, light issued kit | Visible weapon raise, then one shot. Between bursts it sidesteps, and steps in past 8 m. The raise and the shot stay planted. A seated clerk does not shuffle until it stands | Move, use cover, learn the aim tell, shoot during the sidestep |
| Sweeper | Bot, standard chassis | Visible raise, then a three-round burst. Between bursts it sidesteps and closes past 8 m. The raise and the burst stay planted | Interrupt or flank between bursts |
| Ranged Sweeper | Bot with a tall rear antenna mast and a long scoped rifle; holds its platform | A scope glint at windup start, then a held aim (30 ticks Standard, 24 Severe, 40 Assisted) before one 70 damage Sniper shot. Sees a peeking head as well as an open body; notices new targets only within 1.0 rad of its facing | Drop fully behind a sill to cancel the shot, rise and fire first, suppress it (any hit cancels the windup), or flank outside its notice cone. Implemented on its range |
| Heavy Sweeper | Bot with broad armor and heavy gait, head sunk below two pauldrons | Pauldrons flare and red lamps light (1.2 s Standard), then a four-round burst. It sidesteps during recovery and shuffles sideways again before the next burst. Ordinary hits do not flinch it; a 40-damage tick staggers it once per attack | Flank, splash, or commit finite ammo; a heavy hit cancels one burst. Implemented |
| Crawler | Low constrained Union chassis, M02 draft | Locked leap after a visible crouch; mechanical scrabble and caption on encounter reveal | Shotgun, lateral dodge and punishable recovery; live review pending |
| Jammer | Constrained service/security chassis | Telegraphs local interference and slow projectiles | Prioritize it from a flank on its exposed position |
| Enforcer | Committed human elite, powered issued armor | Charge and knockback with a clear wind-up | Dodge and punish recovery, use armor counters |
| Turret | Fixed equipment, no assumed personhood | Idle head sweep, visible tracking, then a red charge (1.3 s Standard) before one Rail shot. Sees new targets only ahead of its head | Break sight to cancel the charge, flank behind the sweep, precision damage. Never an unavoidable gauntlet. Implemented |
| Redactor | Committed covert elite | Distortion and movement tell before an ambush | Observe, force movement, deny an approach |
| Auditor | Human command/support officer with shield hardware | Channels a repair into a disabled Sweeper or Heavy Sweeper (2.2 s Standard), twice at most; its plate halves frontal shots | Hit it or break its sight to snap the channel, flank the plate, prioritize support. Development prototype |
| Notary | Flying patrol drone, Office equipment, no assumed personhood | Red optic flares wide with a shutter click, then a short committed burst | Strafe through the flash, shoot it during the flash, punish the drift |
| Assessor | Heavy armored drone, Office equipment, no assumed personhood | Launcher unfolds and two red optics count down, then a slow splash volley | Dodge the canisters, hit the rear vents in recovery, Arc or splash |

A Jammer is a priority target, not a circuit puzzle. Main objectives must remain
readable without audio. Variants differ by
silhouette, animation and behavior, not color alone. Redactors never require
hearing a nearly inaudible sound to avoid unavoidable damage.

Reactivation repairs a disabled combat body under bounded rules; it is not
consequence-free restoration of a destroyed conscious mind. Track disabled,
destroyed, and recoverable states explicitly. Infinite resurrection chains and
ordinary corpse farming are not implied by the fiction.

The existing Compliance Drone prototype may become an elite after a deliberate
migration. The proposed Continuance Walker is a larger authored boss with distinct
attack phases, recoveries and traversable cover. It is not another label for an
already-complete enemy. Level 8's custody-defense encounter and level 17's command defense
can combine ordinary units and machinery instead of demanding a unique boss
species for every milestone.

## Union drones

The Union watches before it arrives. Its drones are the Office's eyes over
streets, wards and habitats, and every one of them files what it sees: the
tell before a Notary fires is it taking your photograph. Both drones are
equipment with a narrow onboard controller under network supervision, like
the Turret. They carry no assumed personhood, so the fiction adds no cost to
shooting them down. The bounded Notary combat pilot is implemented in the
[M04 prototype](plans/m04-notice-to-vacate-prototype.md), with its rendered and
fresh-player gates tracked separately. The Assessor's bounded combat foundation
is implemented locally; broader air routing and fresh-player acceptance remain
open. The [flying drones plan](plans/flying-drones.md) owns that larger scope.

Not NODS. The arena's Null-Objective Drones are corrected bots on foot; "drone"
in their name is Office jargon for an obedient worker, and they do not fly. In
design text, "drone" alone means the Notary or the Assessor.

**Notary, the patrol drone.** Roughly torso-sized: a black box body under two
ducted fans, about 1.3 m across the ducts, with one red optic and a red
Office seal. It is never a speck; at any engagement distance it reads at least
as large as a Clerk's torso. It hovers from head height to about two storeys,
drifts on a patrol line with a dim red optic and a fan hum audible about
20 m away. On sight the optic flares brighter and wider for the whole windup,
a shutter click plays (captioned), then it fires a three-round burst along the
aim it committed at the start of the flash. It then drifts and dims through a
recovery window. Proposed: 50 HP (a Sweeper is 80), light damage per round,
slower than a running player. A hit during the flash interrupts the shot, as
it does for the ground roles today. The tell changes brightness, size and
sound, never color alone. When killed the fans cut, it tumbles and
crashes where its shadow was; the wreck does no damage and blocks nothing.

**Assessor, the heavy drone.** About twice the Notary's span, black, four fans, an
armored belly and front, a gimbal launcher and exposed rear vents. It holds a
higher band (about 3 to 7 m) and needs a tall hall or open sky. Its tell is the
launcher unfolding while two red optics count down with a rising chirp; then it
lobs a volley of three slow, visible canisters that burst on impact. After the
volley its vents open and glow through a long recovery. Current foundation:
240 HP, thirty canisters, three launch attempts six ticks apart, and 12 m/s
ballistic travel with four swept substeps. Covered contact blasts peak at
45 damage within 3 m. Plates halve traced damage from the front, below and
closed rear; rear recovery vents take full damage. Arc and splash bypass those
plates. One supported wreck can damage Union combatants within 1.5 m, with
cover and falloff, and never participants, civilians, vehicles or pumps.
The server owns every launch, contact and victim; no delayed invisible hitscan
substitutes for travel. The original articulated presenter remains development
art awaiting the complete visual and human-play gates.

**Vertical space without frustration.**

- Each drone stays inside an authored hover volume that ordinary weapons can
  reach from standing positions. The map validator rejects perches no weapon can
  hit and volumes that leave the playable bounds or clip a ceiling.
- A drone keeps its horizontal distance to its target at least equal to its
  height above them, so it is never directly overhead and never forces a steep
  look. It never retreats out of range to wait, and never heals.
- It fires only with line of sight both ways, from its optic to the target's eye.
  The hum and a floor shadow announce it before it is in view; it never spawns
  behind the player.
- On Standard, at most two Notaries or one Assessor are active in a room.
  Difficulty tiers change windup, recovery and room caps, never HP.

**Splash and hitscan.** Hitscan hits a drone's body volume at its hover height,
not a floor capsule, so the Tack, Flechette and Scatter all work and the Rail
kills a Notary in one shot. Splash measures from the burst to the nearest point
of that volume and stops at cover, the same rule as on the ground. A thrown
grenade or rocket that bursts beside a drone hits it; one under it at head
height does too. Rockets hit on contact. Drones are the first enemies where the
Scatter's vertical spread and a grenade's airburst matter, which is depth, not
a new rule.

**Introductions.** Level 2 shows one Notary behind the observation gallery's
glass, photographing captives, out of reach and out of combat. Level 4 brings
the first fight over Low Water's market and clinic with Sweepers below. The
Turret first fights in level 6 at lunar customs. The Assessor is level 12's
armored threat in the Martian habitat, answered by the Arc lesson. Later fights
can mix these established roles. During the level 18 wipe, the Inheritance can
seize surviving Notaries as infrastructure; their issued shape remains, while
their targets and timing change. These placements follow the accepted
[campaign order](CAMPAIGN.md#structure). M04/M05 implement bounded Notary combat;
connected Assessor introduction is in flight, and takeover behavior remains unbuilt.

**What the existing Compliance Drone gives.** Less than its name suggests. It is
an arena prototype: an ordinary player body with an `is_boss` flag, spawned once
per round at 2.2 m and then walked under normal gravity by the arena
`BotBehavior::Compliance` orbit, with 200 HP, a Rail, spawn and down events,
Host lines and a 1.35 times billboard. It does not fly. The reusable base is the
campaign encounter seam: `EnemyController` phases (Idle, Moving, Windup, Firing,
Recovery, Hit, Dead), aim committed at the start of the tell, hit interrupts,
the difficulty timing table, `CampaignActor` identity and hostility,
`combat::line_of_sight` against solids, alarm memory, encounter reset on a
continue, true vertical aim, and directional sprites in `enemy_animation.gd`.
Bounded Notary hover, a raised hit volume, the supported fall and crash are now
implemented. Assessor canisters now reuse resolved blast damage with their own
finite travel and stock. General air routing remains planned.
The arena prototype keeps its behavior
until a deliberate migration.

## Ideas, not yet accepted

Nick's ideas, recorded so they are not lost. None is designed or scheduled.

- **The Outreach Unit (kamikaze RV), 2026-10-03.** A Union community-outreach
  RV, unmanned and driven by a narrow onboard controller like the Turret, so it
  carries no assumed personhood. It is packed with charges and barrels at the
  player.
  - **Tell:** headlights snap on, the horn, and a cheerful outreach jingle on
    its loudspeaker as it accelerates. It commits to a line, the way a Crawler
    commits to a leap.
  - **Counterplay:**
    - Sidestep late.
    - Shoot the tyres to slow it.
    - Shoot the charge to set it off early. Like a Doom barrel, that blast
      catches nearby Union troops.
  - **Where:** streets and roads in Low Water, the ceremonial avenue in level
    16, and freight yards. It also suits multiplayer big-map modes.
  - **Engine work:** bounded authored driving lanes, like the M05 tram's
    server-owned path, before any general vehicle physics.

## Proposed Inheritance roles

The wipe also absorbs all bots still under Union control. Free agents, including
liberated captives, remain individuals. The fate of the absorbed minds is
unresolved. See the [canonical takeover](lore/the-inheritance.md#physical-presence).

Existing chassis acquire shared targeting and coordinated movement, not instant
new armor or untelegraphed powers. Preserve learned attacks while visibly changing
allegiance, cadence and response to human commands. Human Union personnel are
not absorbed and can become targets too. Body, combat role, faction and imposed
control are separate state: a chassis or cosmetic skin cannot decide assimilation.
Teach the changed danger before combining these units with restoration machines.

Introduced across M18-M20 in the accepted twenty-level treatment. Names and
mechanics need a combat prototype before art production.

| Working role | Read and behavior | Counterplay |
|---|---|---|
| Collector | Narrow unmarked body, routes toward local obstructions and closes deliberately | Visible commitment, lateral escape, interruptible exposed phase |
| Paver | Broad matte body marks a bounded work strip before acting | Move outside the marked area or disable it during preparation |
| Surveyor | Elevated unit marks a position and coordinates nearby machines | Break sight, reposition, attack its exposed observation phase |

The intelligence is distributed; these are local units with bounded information,
resources and reach. Their destruction can win an encounter and rescue lives.
It does not defeat the entire Inheritance. Its apparently limitless strategic
scale must not become unreadable or unfair moment-to-moment combat.

## Behavioral and presentation evidence

Build combinations around competing decisions, not uniform firing squads or
larger health pools. Introduce each role alone with room to learn its counter,
then mix it with an established role. Proposed progression:

| Combination | Player decision | Place in the campaign |
|---|---|---|
| Clerk + Sweeper | Interrupt the human's single shot or evade the bot's committed burst; use counter islands to separate their angles | M01 records and transfer rooms, implemented draft |
| Crawler + Sweeper | Keep space from the close threat without backing into a ranged lane | Level 2 service stair authored in draft; live proof pending. Later correction spaces planned |
| Heavy + mobile security | Spend ammunition on suppression or take the exposed flank while lighter units move | Level 5 Low Water freight prototype, acceptance open; later industrial spaces planned |
| Notary + Sweeper | Look up to break the flash or keep pressure on the ground burst; take the roof to meet the drone level | Level 4 Low Water prototype, acceptance open |
| Assessor + human security | Leave the canister splash while the squad pushes, or spend Arc charge on the vents | Connected level 12 Martian habitat, in flight |
| Ranged Sweeper + Jammer | Break the precision sightline while dodging clearly traveling interference shots | Lunar galleries with side routes, planned |
| Auditor + disabled bodies | Interrupt a bounded repair channel or finish an immediate attacker | Level 8 lunar custody archive, planned |
| Absorbed bot + restoration machine | Apply the learned weapon counter while responding to newly marked work zones | Levels 18 to 20, planned |

Each pairing needs routes that allow both answers, readable attack overlap and
supplies for imperfect play. A room full of hitscan enemies does not reproduce
Doom's projectile-dodging decisions. Build and verify traveling attacks before
claiming that variety; never implement them as delayed invisible hitscan.
Difficulty changes belong to the shared
[difficulty and rewards contract](plans/difficulty-and-rewards.md).

- Telegraphs have visual and sound/caption paths. Author durations in seconds.
- Every role needs coherent facing, locomotion, attack, pain, disable/death and
  any reactivation frames, with registered scale and weapon origins.
- Sight, hearing rules, friendly fire and target selection belong to the server.
  Proposed infighting follows explicit faction/role rules; not every unit attacks
  its ally after one stray hit.
- Test each counter with guaranteed weapons, then combinations, multiple rooms,
  solo human/agent control and spectator views, plus explicitly supported co-op
  modes. A single empty test range is insufficient.
- Shared movement/navigation are reused; entity ownership and state are explicit.
  See [framework requirements](plans/campaign-continuance.md).
