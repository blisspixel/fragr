# Enemy roster

**Status, 2026-09-24:** Clerk and Sweeper prototype encounters are implemented
through shared simulation bodies, typed campaign identity and directional
animation. Their unshaded atlases no longer share one outline: the Sweeper is
the wide bot with the level rifle, and the Clerk is the narrower human whose
aim clears the shoulder. The Heavy Sweeper and the Turret are implemented on
the same seams and demonstrated on a test range, not yet placed in a mission
([plan](plans/heavy-sweeper-and-turret.md)). All four wear the black, dark
steel and restrained red Union issue. Full-mission tuning and a fresh-player
review remain open. Other roles below, including the flying drones added
2026-09-24, reactivation and projectiles are proposed.
Calibration's NODS and Auditor are separate arcade prototypes, not
implementations of the proposed roster.

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
| Clerk | Human security, light issued kit | Low-pressure shots after visible weapon raise | Move, use cover, learn the aim tell |
| Sweeper | Bot, standard chassis | Mobile bursts with a visible and audible cycle | Interrupt or flank between bursts |
| Ranged Sweeper | Bot with distinct antenna/weapon silhouette | Stops to line up a precision shot | Break sight or close through cover |
| Heavy Sweeper | Bot with broad armor and heavy gait, head sunk below two pauldrons | Pauldrons flare and red lamps light (1.2 s Standard), then a four-round burst; slow sideways shuffle after recovery. Ordinary hits do not flinch it; a 40-damage tick staggers it once per attack | Flank, splash, or commit finite ammo; a heavy hit cancels one burst. Implemented |
| Crawler | Low constrained chassis | Fast close attack preceded by a leap/wind-up | Scatter, movement and spacing |
| Jammer | Constrained service/security chassis | Telegraphs local interference and slow projectiles | Prioritize it from a flank on its exposed position |
| Enforcer | Committed human elite, powered issued armor | Charge and knockback with a clear wind-up | Dodge and punish recovery, use armor counters |
| Turret | Fixed equipment, no assumed personhood | Idle head sweep, visible tracking, then a red charge (1.3 s Standard) before one Rail shot. Sees new targets only ahead of its head | Break sight to cancel the charge, flank behind the sweep, precision damage. Never an unavoidable gauntlet. Implemented |
| Redactor | Committed covert elite | Distortion and movement tell before an ambush | Observe, force movement, deny an approach |
| Auditor | Human command/support officer with shield hardware | Channels limited reactivation of disabled units | Break channel, flank shield, prioritize support |
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
already-complete enemy. M05's custody-defense encounter and M09's command defense
can combine ordinary units and machinery instead of demanding a unique boss
species for every milestone.

## Union drones

The Union watches before it arrives. Its drones are the Office's eyes over
streets, wards and habitats, and every one of them files what it sees: the
tell before a Notary fires is it taking your photograph. Both drones are
equipment with a narrow onboard controller under network supervision, like
the Turret. They carry no assumed personhood, so the fiction adds no cost to
shooting them down. Proposed, unbuilt; the
[flying drones plan](plans/flying-drones.md) owns the implementation.

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
volley its vents open and glow through a long recovery. Proposed: about three
Sweepers of HP; plates halve bullet damage from the front and below, vents take
full damage, and the Arc and splash ignore the plates. Its falling wreck damages
Union units it lands on and never participants, so dropping it on a squad is a
reward, not a trap. It needs the shared server projectile seam; it never fires
delayed invisible hitscan.

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

**Introductions.** M02 shows one Notary behind the observation gallery's glass,
photographing captives, out of reach and out of combat. M03's Union sweep brings
the first fight: Notaries over the roof loop and the tram trench with Sweepers
below, in place of the Turret, which first appears in M04. The Assessor is M07's
armored threat over the greenhouse trench, the enemy that the Arc lesson
answers, so Mars adds a variant of an existing subsystem rather than a new one.
From M08 on they mix with established roles. In M10 the Inheritance can seize
surviving Notaries as infrastructure; same tells, changed targets.

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
Hover integration, air routing, a raised hit volume, the fall and crash, and
the Assessor's projectiles are new. The arena prototype keeps its behavior
until a deliberate migration.

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

Introduced sparingly before full restoration encounters in M10. Names and
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
| Crawler + Sweeper | Keep space from the close threat without backing into a ranged lane | M02 correction/service loop, planned |
| Heavy + mobile security | Spend ammunition on suppression or take the exposed flank while lighter units move | M03 workshops and later industrial spaces, planned |
| Notary + Sweeper | Look up to break the flash or keep pressure on the ground burst; take the roof to meet the drone level | M03 roof loop and tram trench, planned |
| Assessor + human security | Leave the canister splash while the squad pushes, or spend Arc charge on the vents | M07 greenhouse trench, planned |
| Ranged Sweeper + Jammer | Break the precision sightline while dodging clearly traveling interference shots | Lunar galleries with side routes, planned |
| Auditor + disabled bodies | Interrupt a bounded repair channel or finish an immediate attacker | M05 custody defense, planned |
| Absorbed bot + restoration machine | Apply the learned weapon counter while responding to newly marked work zones | M10 survival finale, planned |

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
