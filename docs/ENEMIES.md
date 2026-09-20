# Enemy roster

**Status, 2026-09-19:** design proposals. Current combatants are Player entities
with five rule-bot behaviors and prototype boss/elite paths. Calibration uses
NODS and Auditor labels; it does not implement the roster below, resurrection,
projectiles, authored encounter placement, or full character animation.

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
| Heavy Sweeper | Bot with broad armor and heavy gait | Suppressive fire, slow reposition | Flank, splash, or commit finite ammo |
| Crawler | Low constrained chassis | Fast close attack preceded by a leap/wind-up | Scatter, movement and spacing |
| Jammer | Constrained service/security chassis | Telegraphs local interference and slow projectiles | Prioritize or bypass its exposed position |
| Enforcer | Committed human elite, powered issued armor | Charge and knockback with a clear wind-up | Dodge and punish recovery, use armor counters |
| Turret | Fixed equipment, no assumed personhood | Visible tracking/sweep before a strong shot | Cover, flank, precision damage |
| Redactor | Committed covert elite | Distortion and movement tell before an ambush | Observe, force movement, deny an approach |
| Auditor | Human command/support officer with shield hardware | Channels limited reactivation of disabled units | Break channel, flank shield, prioritize support |

A Jammer affects explicit local machinery or equipment states, never only optional
radio. Main objectives must remain readable without audio. Variants differ by
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

Introduced sparingly before full restoration encounters in M10-M12. Names and
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

- Telegraphs have visual and sound/caption paths. Author durations in seconds.
- Every role needs coherent facing, locomotion, attack, pain, disable/death and
  any reactivation frames, with registered scale and weapon origins.
- Sight, hearing rules, friendly fire and target selection belong to the server.
  Proposed infighting follows explicit faction/role rules; not every unit attacks
  its ally after one stray hit.
- Test each counter with guaranteed weapons, then combinations, multiple rooms,
  solo/co-op, agents and spectator views. A single empty test range is insufficient.
- Shared movement/navigation are reused; entity ownership and state are explicit.
  See [framework requirements](plans/campaign-continuance.md).
