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

The placement checkpoint below follows this authority-only verification.
Remaining release gates include consistent character animation, full player and
spectator presentation and fresh-player pacing evidence.
No finished enemy art or mission is implied by the schema or automated wins.

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

## M01 placement checkpoint, 2026-09-20

Draft PR [#182](https://github.com/blisspixel/fragr/pull/182) now includes the actual
opening population and two sightline changes: an inspection partition in
confiscation and a screen below records. The Clerk enters around the partition
after safe Tack discovery, before the route splits. The Sweepers activate after
the Clerk's defeat at the hall threshold or upper service route. Their starting
positions are hidden by the screen or deck on the tested approaches.

Early versions exposed two spatial mistakes: the central bay triggered the bots
before the player chose the service route, and a five-second initial search
could expire before a stair approach. Activation now waits for the hall or upper
flank. Initial dispatch follows its fixed alarm position for at most 30 seconds;
visual pursuit still remembers only five seconds of last-seen position. Neither
uses hidden player movement. The longer route to a stationary service landing
is exercised separately from the rendered route, which advances to the overlook.

`server/src/tests/m01.rs` drives the real session with ordinary navigation, aim,
finite supplies and reload, for human and agent roles. It verifies safe first
weapon acquisition, hidden initial placements, all three defeats, both stair
approaches, access to the transfer office/lift and no arcade score. Seed 67:

| Approach | Elapsed simulation seconds | Final HP | Shots | First visible threat, seconds |
|---|---:|---:|---:|---:|
| Main hall | 24.65 | 80 | 17 | 3.35 |
| Service landing, including waiting for approach | 40.45 | 100 | 22 | 4.15 |

Both control roles produce the same measurements. These use perfect target aim
and omit reading/exploration; they do not establish first-run pacing, difficulty,
mission length or fun. The full 10-15 minute M01 target is still unbuilt.

The rendered tour now has a focused `QaCombat` driver. It uses the normal input
path, validated snapshots and Godot's native AABB segment intersection to avoid
firing through walls. It excludes allies and corpses, reloads real magazines,
latches participant death across respawn, deduplicates snapshot evidence, and
records motion plus newly observed phases. Its headless regression checks these
failure cases. [AABB documentation](https://docs.godotengine.org/en/stable/classes/class_aabb.html)
was verified on 2026-09-20; this is a QA helper, not a second combat authority.

Local verification: 663 workspace tests pass, two existing tests remain ignored,
strict workspace Clippy passes, and unfiltered line coverage is 95.70 percent.
Twenty-one Godot harnesses pass. The main approach passed OpenGL and Vulkan on
Windows with the AMD Radeon 780M; the service route also passed both renderers.
The ten-state traversal and twelve-state ammunition tours passed OpenGL.
Main captures deliberately allow one Clerk shot, reducing HP
from 100 to 80 before returning fire. The final OpenGL sheet captures Clerk
windup, firing, recovery, hit and dead states. The bots' motion, hit and death
states are captured; their burst timing is separately covered by server tests.
No NVIDIA or macOS rendered combat claim follows from these runs.

Inspected captures: `.agents/qa/m01-encounters-gl-final/`,
`.agents/qa/m01-encounters-vk/`, `.agents/qa/m01-maintenance-gl-fixed/`,
`.agents/qa/m01-maintenance-vk/`, `.agents/qa/m01-routes-encounters/` and
`.agents/qa/m01-discovery-encounters/`. The first capture attempt failed because
the sheet and source images had different formats; explicit conversion fixed
the capture, and the failed run is not counted as passing evidence.

Final self-review removed a duplicate body-height constant from the QA driver;
it now uses the golden-tested `MoveStep` contract. Its focused harness and main
OpenGL run passed again at `.agents/qa/m01-encounters-reviewed/`, including all
five Clerk attack/hit/death phases. The workspace release build passed. The
21-state general tour was republished and its contact sheet and effect strips
inspected at `.agents/qa/m01-placement-regression/`.

The images expose the remaining art defect clearly: the two archetypes share
placeholder bodies, attack phases have no distinct poses, and dead bodies remain
upright for their bounded lifetime. These are release blockers. Produce the
reviewed human/bot references and animation set, including melee fallback and
death, then repeat both approaches and spectator eyes. Do not publish these
placeholders as finished character art. No credits were spent in this increment.

## Directional character increment, 2026-09-20

The first local model study was rejected for toy-like block limbs and helmet.
The revised human has shaped cloth, a visible face, open helmet and issued armor;
the bot has covered mechanical limbs, a status slit and battery pack. Both retain
the Union palette. Original joint poses now supply eight directions of movement,
weapon raise, recoil, recovery, pain, collapse and exhausted melee. This improves
the placeholder bodies; it does not establish finished character production.

Source and reproducible bake instructions live in
[`client/art/characters/README.md`](../../client/art/characters/README.md).
`enemy_animation.gd` owns the shared layout and presentation selection;
`enemy_view.gd` binds validated state through the existing pawn. Gait follows
distance, resolved shots start recoil, stale windup never predicts a shot, and
late corpses remain down. Enemy bodies retain fixed feet registration and scale,
including hit feedback and broadcast cameras. Spawn facing now uses `ServerYaw`
immediately instead of starting in the wrong convention.

The offline baker rejects empty/clipped tiles and records source/output hashes.
The client harness checks every tile, pose progression, actual corpse pixels,
direction conventions, repeated snapshots, teleport exclusion, the live pawn's
render selection and stale bakes. Source files are excluded from player exports.
Recovery is a lowering/regrip pose: the wire does not distinguish a reload, so
there is no invented client reload state.

| Asset property | Per archetype | Both archetypes |
|---|---:|---:|
| Poses times directions | 54 times 8 | 864 tiles |
| Atlas pixels | 2880 by 3840 | 22,118,400 |
| RGBA8 base texture allocation, calculated | 42.1875 MiB | 84.375 MiB |

Textures load lazily and are shared across pawns. This allocation is not a GPU
performance measurement. Assess loading and texture budgets before expanding the
cast; a small PNG is not a small uncompressed texture.

Rendered evidence on Windows/AMD Radeon 780M:

| Run | Renderer | Evidence |
|---|---|---|
| Main intake | OpenGL | Clerk tell and shot, Sweeper movement and burst, hits and collapse; three enemies defeated with finite Tack ammunition |
| Maintenance flank | Vulkan | Human and bot bodies, Flechette combat and bots traversing to the upper floor; three enemies defeated |
| Separate spectator socket | OpenGL | Fourteen inspected-state captures following the human participant's actual ID through intake; no local pawn and no enemy selected as the watched player |

Captures: `.agents/qa/m01-animated-bursts/`,
`.agents/qa/m01-animated-maintenance-vk/`, `.agents/qa/m01-observer/` and its
simultaneous driver `.agents/qa/m01-observer-driver/`. The main run observes four
Sweeper shots before the pair falls; ending HP is 80. The maintenance run ends
at 100 HP. These are controlled, accurately aiming runs, not fresh-player balance
or fun evidence. The initial wrongly selected tour manifest failed and is not
counted as evidence.

All 22 Godot harnesses pass, including the new atlas/pawn regression. The prior
663 Rust tests and 95.70 percent coverage baseline are unchanged by this client
increment. The placement commit's five hosted checks passed before this work.
No NVIDIA, macOS rendered combat, full co-op or agent-eye capture claim follows.
The 21-state general tour was republished at
`.agents/qa/m01-animation-regression/`; its contact sheet and both effect strips
were inspected. The separate observer's contact sheet and close combat stills
were inspected as well. Source changes need a fresh hosted CI run before merge.

`SubViewport`, `Camera3D`, `SurfaceTool`, `SpriteBase3D`,
[Sprite3D](https://docs.godotengine.org/en/stable/classes/class_sprite3d.html) and
[FileAccess](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html)
were checked against official documentation on 2026-09-20. No paid requests were
made. The draft remains open for character motion/art critique, environmental
detail and first-run encounter pacing before integration. Full mission objectives,
extraction, saves and co-op lifecycle remain separate bounded work.

## Facility detail increment, 2026-09-20

The [facility pass](m01-facility-detail.md) gives the prototype's rooms registered
signs, lockers, vents, original Union markers and practical lights. It preserves
all collision and encounter placements. Both rendered routes were reviewed in
OpenGL and Vulkan after correcting the new shader's color-space handling.
Keyed English world text fits its panels and loads from a clean checkout.
The plan records 667 Rust tests, 95.72 percent coverage, 23 Godot harnesses,
the six-map mixed-client regression and refreshed general gallery. These replace
the older local verification counts for the current branch. Hosted checks still
need to run on this increment. The previous directional-character commit passed
all five jobs in run 35503324104.
