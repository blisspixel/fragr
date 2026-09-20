# M01 intake encounter

Status: **in flight**, 2026-09-20. [Task #180](https://github.com/blisspixel/fragr/issues/180).
Baseline: v0.24.0, `67eacf1`, all five integration checks passed. Weapon discovery
and traversal are implemented; this work supplies the first authored fights.

## Outcome

Recover the confiscated Tack in safety, meet one human Clerk with a readable
weapon-raise tell, then face two Sweeper bots arriving through a visible approach.
Cover, retreat to confiscation and the maintenance flank remain useful. Reaching
Flechette prepares the next part of the mission. The fight must work through normal
human input, external-agent actions and spectator eyes.

Clerks are human security and Sweepers are Union bots. Latch remains detained;
M01 discovers the destination and M02 performs the rescue. No Inheritance contact,
Crawler, boss or explosive weapon belongs in this introduction. Procedural
absurdity can be funny; captive suffering is not the joke. Radio is optional.

This is not the complete mission. Objectives, extraction, checkpoints, the opening
scene, full co-op lifecycle and the rest of M01's population remain separate work.
Several connected participants do not establish finished co-op.

## Authority and identity

- Keep one body, movement, inventory, shot and damage path in `GameState`.
  Authored enemies use those bodies with distinct server-owned controllers;
  they do not enter the connection registry or minimum arcade-bot roster.
- Add an optional typed campaign identity to shared actor observations. It
  distinguishes allied participants from Union enemy archetypes and carries
  authoritative attack/pain/death phases. Control `Role` remains human, agent or
  spectator, independent of fictional body and allegiance. Names never select
  hostility, anatomy or attack state.
- Use one shared hostility predicate in simulation and external/local controllers.
  Campaign participants are allies; opposing sides can damage each other.
  Allies intercept rays without losing health. Arcade actors retain their existing
  free-for-all rules and complete deterministic traces.
- Enemy deaths never use ordinary arcade respawn. Retain bounded death evidence
  for animation, exclude dead bodies from targeting and control, then reap them.
  Exclude enemies from participant scoreboards and spectator-player selection.
- Reset these encounters when the last participant leaves or the whole party
  falls, without repeatedly recreating enemies every dead tick. Existing entry
  respawn remains provisional; this does not claim checkpoint or revive support.

## Authoring and controller seams

Extend the existing strict local map document with bounded encounter definitions:
stable IDs, a small set of finite entry regions, an optional earlier-encounter
dependency and typed enemy placements. Require unique IDs, standing clearance,
reachable placements, known archetypes and acyclic dependency order. No scripts,
paths, URLs or arbitrary behavior expressions in map files. Keep the existing
1 MiB byte bound and enforce aggregate enemy/region limits before topology work.

An encounter activates once from a living participant's real position. Crossing
back and forth cannot duplicate it. Completion follows authoritative deaths,
not a client animation or elapsed scene timer. The main and service routes need
authored activation coverage. Sweepers must enter visibly, not appear beside
the player. Position and timing choices remain provisional until measured.

Keep encounter lifecycle and enemy intent in a focused server module. Session
orchestration owns the existing shared navigation budget, including NPCs. Reuse
`NavigationGoal` and the movement controller rather than another pathfinder.
Controllers see one coherent pre-step world and emit ordinary actions.

Clerk: acquire a visible opponent, raise the weapon, fire a committed shot, then
recover or reposition. Sweeper: acquire, brace, fire a short burst and recover.
Both need explicit target loss, blocked sightline, hit interruption, death and
reset transitions. Windup must leave a real evasion opportunity; prevent instant
retargeting shots through cover. Tune health, burst spacing and recovery from
actual play, not a presumed difficulty score. No paid decision model on the tick.

## Wire and presentation

Increment gameplay capability for authored encounters. Legacy arcade messages
remain unchanged; discovery-only maps continue to require capability 2. Reject
older clients before admitting them to encounter maps. Rust consumers share the
server types. Validate new client fields at the network boundary and update MCP
observations/actions, brain, scripted and playtest targeting consistently.

Use the existing pawn presentation seam with dedicated enemy animation data.
Idle, movement, windup, firing, hit and death need distinct readable frames or
poses. Server state controls attack timing; the animation never causes damage.
Render the resolved shot even when its shooter dies in the same tick.

The old `enemy_clerk_0.png` depicts a robot and cannot stand in for the human
Clerk. Inspect existing assets first; prepare a consistent human reference and
bot reference before variants. Use Union bone, institutional green, dark steel
and restrained red from the art bible and palette. Maintain feet registration,
body dimensions, hard alpha edges and readable silhouettes at combat distance.
Do not present a moving single image as a completed animation set.

## Research and spend

The existing Rust/GDScript stack and locked dependencies remain. Godot's current
[SpriteBase3D](https://docs.godotengine.org/en/stable/classes/class_spritebase3d.html)
and [AnimatedSprite3D](https://docs.godotengine.org/en/stable/classes/class_animatedsprite3d.html)
references were checked 2026-09-20: billboard/filter/alpha settings and explicit
frame control are available without a new rendering dependency. Choose the
smallest extension to the existing Sprite3D path after inspecting frame assets.

Start with local assets and tools. Any paid image or sound batch requires a
current balance/quota check, an exact price estimate and an explicit cap through
the approved generators. Preserve receipts and uncertain reservations; never
enable top-ups or overages. No paid request is authorized by this plan beyond the
user's existing approval and remaining balance. New audio must be auditioned and
tested at actual cadence; decodability and peak statistics alone are insufficient.

## Proof and completion

1. Test loader limits, invalid references/placements, trigger entry/re-entry,
   dependency order, target identity/hostility, attack boundaries, cover, target
   loss, hit interruption, death/reaping and party reset. Test actual session
   behavior, not just isolated phase transitions.
2. Prove both approaches with ordinary movement and finite starting supplies.
   Record acquisition order, time to first threat/shot, damage, ammunition spent,
   cover use, retreat and retry. Check multiple participants and late arrival.
3. Exercise human, scripted, local decision and MCP clients plus spectators.
   Allies must not be selected as opponents. Observe through participant eyes;
   an NPC must not replace the watched participant because the roster changed.
4. Inspect first-person and spectator motion through the complete introductory
   fight, including tells, firing, hit and death. Check OpenGL and Vulkan on the
   available hardware, and state platform limits honestly. Refresh the release
   tour. No screenshot-only claim of animation or fun.
5. Run the repository Rust and Godot checks, six-map mixed-client roster and
   16/64/128-fighter baseline trace comparisons from the discovery plan. Preserve
   coverage and performance gates. Review the final diff and record evidence,
   limitations and remaining work here before integration.

Update protocol documentation, mission/roadmap status and asset manifests with
the behavior actually implemented. Publish only after the relevant checks pass.

## Local implementation checkpoint, 2026-09-20

Implemented on `feat/m01-intake-encounter`, not released:

- Strict encounter definitions, ordered dependencies, one-time activation,
  bounded corpses, party retry and last-departure cleanup. Enemies share sim
  bodies, weapons and collision, and Session's four-search navigation budget.
- Typed campaign identity and one hostility predicate across server, equipment,
  scripted, decision and playtest controllers. Allies intercept without damage.
  NPCs neither collect participant supplies nor enter arcade scores or streaks.
- Clerk: 60 HP, Tack, 12-tick aim tell and 20-tick recovery. Sweeper: 80 HP,
  Flechette, 14-tick tell, three shots four ticks apart, 26-tick recovery. Both
  walk at 2.5 m/s. These are initial tuning values, not proven M01 balance.
  Finite magazines use the existing reload path; exhausted enemies close for a
  melee strike. That fallback needs an appropriate strike pose in the art set.
- Gameplay capability 3 gates encounter maps; discovery-only remains 2. Godot
  validates identity/phase fields and keeps NPCs out of participant camera and
  score lists. Initial lower enemy HP no longer creates a false arrival hit flash.

Evidence: workspace tests and strict Clippy pass; unfiltered workspace coverage
is 95.64 percent. Twenty Godot harnesses pass. Focused tests cover real navigation
around cover, committed aim and dodge, blocked sight, hit/reload interruption,
burst spacing, ammunition exhaustion, lethal trades, friendly interception,
supply ownership, corpse lifetime, late arrival and retry. A real socket test
checks all three roles and rejection of older clients. Local logs use
`.agents/m01-encounters-*`. Further supply and lethal-trade tests passed after
the coverage run. These checks do not prove the rendered encounter or its fun.

12,000-tick CPU regressions, seed 42, repeated recordings and default budget gate:

| Fighters | Map | Mean, ms | p99, ms | Maximum, ms |
|---:|---:|---:|---:|---:|
| 16 | 1 | 0.090 | 0.590 | 2.074 |
| 64 | 5 | 0.314 | 1.442 | 3.330 |
| 128 | 6 | 0.929 | 4.063 | 6.185 |

All three complete trace hashes match v0.24.0. These measure CPU session and
encoding, not network capacity or GPU performance. Reports are
`.agents/bench/encounters-{16,64,128}.json`.

Remaining: author and playtest the actual M01 placements and visible arrival
routes, produce and inspect consistent character animation, verify the encounter
through player and spectator eyes on both renderers, and publish encounter
evidence before integration. The committed
M01 JSON still contains traversal and equipment only; no finished enemy art or
mission is implied by the new schema.

The original Clerk and Sweeper images were inspected: the Clerk is a robot and
both use the older rust-heavy look. New reference candidates are specified in
`tools/spritegen/specs/m01-enemy-references.json`. The authenticated exact estimate
was $0.107 per reference, $0.214 total, on 2026-09-20. No generation was submitted.
The API balance is unverified and no browser session is connected. A balance and
automatic-top-up question is pending; continue local work while it is unanswered.
Reference quality must pass before paying for animation variants.

The six-map mixed-client regression passes with unchanged gates:

| Map | Clients | Seed | Frags | First frag, seconds | Spawn deaths |
|---|---:|---:|---:|---:|---:|
| Arena Duel | 2 | 67 | 5 | 10.35 | 0 |
| Compliance Yard | 6 | 42 | 24 | 3.15 | 2 |
| Directive 17 Substation | 6 | 19 | 26 | 3.00 | 2 |
| Sector 9 Transit Hall | 8 | 42 | 38 | 2.95 | 1 |
| Reclamation Gulch | 12 | 42 | 47 | 2.95 | 2 |
| Tripoint Works | 16 | 42 | 74 | 2.95 | 8 |

These are asynchronous network runs, not deterministic trace comparisons. Spawn
deaths remain a balance limitation. Reports: `.agents/playtest/encounters-roster/`.
The 21-state OpenGL regression tour was published and its contact sheet and both
motion strips inspected, including menus, player/spectator eyes and effects.
It shows the existing arcade presentation, not new campaign enemy art. Capture:
`.agents/qa/encounter-foundation/`. Dependency license, ban and source checks pass.
