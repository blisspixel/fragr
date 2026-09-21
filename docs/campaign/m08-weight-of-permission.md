# M08: The Weight of Permission

**Status:** proposed, unbuilt. Mars before the wipe. Target 12-16 minutes.
[Treatment](../CAMPAIGN-MISSIONS.md#m08-the-weight-of-permission).

## Story and cast

With communities committed, the coalition attacks industrial custody and launch
works needed to repair and supply its fleet. This is one part of a wider action;
allies seize other sites. Mara coordinates real contributions. Tern identifies
transport requirements. Latch insists workers are invited to help after release,
not transferred to a new owner. Renn can identify control dependencies.

Patterns from lunar cargo rerouting recur. The protagonists isolate an exposed
path while preserving local services. They now have reason to suspect a larger
intelligence, not knowledge of an imminent wipe or a reliable timetable.

## Industrial plan

Service entrance -> foundry edge -> machine hall -> freight galleries -> launch
works. A maintenance ring connects the service entrance, upper gallery and
worker release area. The launch objective is visible through industrial windows.

| Area | Construction and function | Encounter |
|---|---|---|
| Foundry edge | Heat shielding, pouring machinery visible behind barriers | Moving threats and a safe alternative to hazard crossings |
| Machine hall | Dense machines, overhead services and broad work lanes | Mixed squads with meaningful short-range flanks |
| Upper galleries | Cross-floor views and two ordinary stairs | Priority support targets, exposed supply choice |
| Worker access | Restraint/control stations and a nearby secured room | Optional worker release, no walking-escort chore |
| Freight loop | Cargo path with functional bends and alcoves | Recovery then counterattack through known space |
| Launch works | Large but bounded gantries, berms and service rooms | Walker crest, different firing angles and accessible resupply |

No environment hazard requires jumping through a tiny timing window to finish.
Hazards have a visible cycle and bypass. Platforms have real support and headroom.

The launch works is a deliberate increase in battlefield scale after the earlier
indoor missions. Freight buildings, gantry supports and terrain divide local
positions; service interiors provide flanks and recovery. The player can read
the next useful destination from each position. Prove the infantry route before
integrating the planned drivable vehicle. Do not enlarge gaps simply to justify it.

## Vehicle showcase and physical controls

This is the first proposed combined-arms campaign landmark. A captured armed
utility rover connects the freight depot, bermed launch approach and main gantry.
Its mounted weapon helps break an exposed defense, while service interiors and
trenches let infantry flank that same position. Entering a control house opens
a freight shutter and a useful rover shortcut. The Walker remains defeatable if
the rover is lost; scarce vehicle ammunition cannot become a mandatory key.

Before the exterior, a freight lift gives a short view across machinery and
deposits the player at the gallery. Its call switch and destination are visible
together. Ordinary stairs preserve the maintenance loop. There is no lever order,
long timed wait or requirement to move an uncontrolled ally onto a platform.

Vehicle and moving-lift systems are unbuilt. Prototype server authority, safe
occupancy and dismounts, collision, aim, damage, spectator views and agent actions
before authoring a fleet. Then playtest rover and infantry approaches, vehicle
loss, mission retry and mixed threats. The goal is a compact battle with distinct
positions and choices, not an empty map crossed at driving speed.

## Weapons and boss

The Article Blade appears as a risky close-range opportunity before an encounter
that suits it. It is optional against the Walker. Guaranteed ordinary weapons,
Lobber/Arc supplies and movement suffice. Do not make a melee pickup bait into
an unavoidable instant-death stomp.

Walker phases: telegraphed area attack, relocation, exposed recovery and supporting
units entering from visible lanes. Terrain gives more than one viable response.
Health is tuned after movement and attack readability work. The player is fighting
machinery and coordinated defenders, not waiting out invulnerability cutscenes.

Secrets: protected Cores cache reached through the service ring; armor on a
gallery reachable by a clearly readable optional jump; spare Blade/sidearm supply
for a depleted inventory. Never make the last secret necessary to afford the boss.

## State and exit

`works_entered` -> `local_control_secured` -> `walker_disabled` ->
`fleet_supply_ready`. Optional worker rescue is distinct from controlling the
factory. The local systems remain operable after disconnect or failed interaction.
Completion shows allied crews working voluntarily and transports becoming usable.

A continue restarts the mission, including the Walker, supporting units and
entry resources. Keep the approach compact. Measure repeated failures
for causes such as unreadable cues or empty ammo, not just player damage totals.

## Presentation and allies

Forge light, dust, heat distortion kept behind readable silhouettes, and red-rock
industrial architecture. Tern can make a dry joke about liberation arriving with
an unpaid repair invoice. A concise departure panel acknowledges preparation and
elapsed travel before the coalition's return to Earth.

Allied workers and fighters act autonomously; no tactical controls are required.
Test boss target changes, ally loss, solo counters, mission restart and worker
states. Record frame times during the actual largest
fight on named hardware; a quiet static view is not the performance evidence.
