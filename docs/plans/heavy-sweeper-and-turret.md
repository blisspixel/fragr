# Heavy Sweeper and Turret

**Status:** shipped in #245 (v0.50.0), 2026-09-24. Local
evidence is recorded below; no mission places either enemy yet.

## Goal

Add the next two Union enemies through the existing encounter seams so later
missions can use them: a Heavy Sweeper that asks the player to flank, spend
ammunition or land a heavy hit, and a Turret that asks the player to break sight
or flank a fixed gun. Both must read at a glance, telegraph every shot, and keep
the difficulty contract: tiers change tells and recovery, never health or damage.

Also, by Nick's art direction during this work, move the Union's four bodies to
black, dark steel and restrained red issue so the enemy reads as the
authoritarian side and the free humans and agents read as the good guys.

## Non-goals

- Placing either enemy in M01, M02 or any mission. M02's map is being reworked
  in a parallel change. The range is a test map.
- New weapons, projectiles, splash damage or the grenade. The Heavy Sweeper's
  splash counter waits for the grenade.
- Changing Clerk or Sweeper behavior, timing, health or silhouettes.
- A per-kind hitbox. All campaign bodies keep the shared fighter volume.

## Placement notes

Build order rung 7 names both for M03. Docs PR #242 moves the Turret's first
appearance to M04 and puts the Notary patrol drone in M03, so the Heavy Sweeper
is M03's new enemy (the workshop) and the Turret first appears in M04. They can
also give later M02 fights variety once that map settles. Authoring rule for
every placement: a turret needs cover within reach of its lane and a flank route
behind its sweep, and is never an unavoidable gauntlet. The test range
(`server/maps/test/heavy-turret-range.json`) follows that rule with pillar cover
and a walled bypass.

## Design and tuning

Server-owned, deterministic, on the shared 20 Hz tick. Ticks are authoritative;
seconds are for reading.

| | Heavy Sweeper | Turret |
|---|---|---|
| Health, weapon | 160, Flechette (25 per hit) | 100, Rail (80 per hit) |
| Speed | 0.3 of top speed (Clerk and Sweeper 0.5) | fixed |
| Windup, Assisted / Standard / Severe | 32 / 24 / 20 ticks (1.6 / 1.2 / 1.0 s) | 36 / 26 / 20 ticks (1.8 / 1.3 / 1.0 s) |
| Recovery, Assisted / Standard / Severe | 46 / 34 / 28 ticks | 40 / 30 / 24 ticks |
| Attack | four-round burst, aim locked at windup start | one shot, aim locked at windup start |
| Tell | pauldrons flare up and out, stance lowers, red lamps light, cannon rises and spins | red optic and four red charge coils light, barrel spins |
| Hit reaction | none on ordinary hits; a tick of 40 or more damage staggers for 16 ticks, once per attack cycle | same rule, 10 ticks |
| Between attacks | 24 ticks of slow sideways shuffle after each recovery | idle sweep of 0.8 rad each side of its authored yaw at 0.035 rad per tick |
| Sight | shared 32 m line of sight, 24 m engagement | 32 m line of sight, 28 m engagement; notices a new target only within 1.0 rad of its head; tracks at 0.1 rad per tick and charges once within 0.06 rad |
| Losing sight | cancels a windup or burst (shared rule) | cancels the charge; no shot; returns to its sweep |

Why these numbers. The Heavy's burst of four at 25 is 100 damage if every round
lands on a still target, so a player who ignores a 1.2 second tell is punished,
and one sideways step avoids it. Flechette spread and range make a full burst
unlikely beyond close range. 160 health is seven Flechette hits or two Rail hits.
The stagger threshold of 40 is a Rail hit, a close Scatter blast or several
pellets in one tick, so "commit ammo" and "heavy hit" both answer it, while the
once-per-attack rule prevents a stun lock. The Turret's Rail shot is the
strongest single hit in the roster, so it gets the longest tells, tracking lag,
a narrow notice cone and a hard cancel on broken sight. It stays harsh: a still
player loses 80 health. That is the price of standing in its lane.

Difficulty changes only windup and recovery, with Standard in the middle and
Severe still at least one second of tell.

## Architecture

- `protocol/actors.rs`: `EnemyKind::HeavySweeper` and `EnemyKind::Turret`
  (`heavy_sweeper`, `turret` on the wire). Phases are unchanged.
- `encounters/enemy.rs`: the per-kind table (`body`, `gait`, `burst`, `stun`,
  `attack_timing`) and the controller: armored stagger reads the tick's damage
  from the authoritative body, the Heavy's shuffle, and the Turret's sweep,
  notice cone, tracking and cancel. `encounters.rs` passes the authored yaw and
  exposes `gait`.
- `sim.rs`: two single-expression call sites now read the shared table
  (spawn health and weapon, movement scale). Hit resolution is unchanged, so the
  in-flight ammunition and pellet work does not conflict with stagger.
- Client: `actor_state.gd` owns `ActorState.KINDS`; `enemy_animation.gd` runs
  the Turret's traverse on phase time; `enemy_view.gd` already loads atlases by
  kind. `qa_combat.gd` accepts the new kinds and now keeps one evade side per
  tell, because reversing mid-tell carried a long tell's locked aim back onto
  the body.
- Art: `client/art/characters/machines.gd` builds both bodies from the same
  unshaded kit; `bake.gd` bakes four atlases and records `machines.gd` in the
  manifest. Palette constants live in `geometry.gd` and match the new `union_*`
  entries in `docs/palette.json`.

## Rules revision

`CAMPAIGN_RULES_REVISION` stays at 2, the value the ammunition change (#243)
set. It changes when the difficulty semantics of a saved run change. No
existing timing changed, and no mission places the new kinds, so every
revision 2 run file still means the same game. The new rows are part of
revision 2 from the first build that has them, and the client accepts the new
kinds. The next change to any existing row, or a later retune of these rows
after a mission ships them, needs revision 3 and the matching client check.

## Protocol

Wire-visible: two new `kind` values in the existing `campaign` object, and
kind-specific phase meaning. `docs/protocol.md` and `agent-adapter/README.md`
describe both. Agents read tells through the same `phase`/`phase_ends`; the MCP
`observe` result carries them unchanged (adapter test
`mcp_observation_carries_heavy_sweeper_and_turret_tells`).

## Verification

Server (seeded tick tests):

- `mission::difficulty_tests::heavy_and_turret_tells_precede_damage_by_the_documented_time_on_every_tier`:
  on every tier, no shot and no damage before the documented windup, the shot on
  the tick it ends, equal damage (25, 80) and burst (4, 1) on every tier,
  documented recovery, strictly ordered tiers, and a strafe during the tell
  evades every round.
- `tests::heavy_turret::turret_tracks_in_place_and_broken_sight_cancels_the_charged_shot`
- `tests::heavy_turret::turret_ignores_a_flank_behind_its_sweep_and_can_be_destroyed_there`
- `tests::heavy_turret::heavy_sweeper_shrugs_light_hits_and_staggers_once_on_a_heavy_one`
- `tests::heavy_turret::heavy_sweeper_bursts_four_then_shuffles_sideways_at_a_heavy_gait`
- `tests::heavy_turret::party_wipe_resets_destroyed_turret_and_heavy_for_retry`
  (loads the test range, so the map also validates)
- `tests::heavy_turret::new_kinds_are_strict_on_the_actor_wire`

Client: `test_actor_state.gd` accepts the new kinds and rejects near misses.
`test_enemy_animation.gd` checks all four atlases (bounds, gait, corpse on the
floor), the Turret's time-driven traverse, and outlines. Measured widths at
rest: Clerk 43 px, Sweeper 67, Heavy 87, Turret 51. Outline difference (1 minus
overlap) at full size and at 47 px, the size of a tile 30 m away in a 720p
view at the default 75 degree field of view:

| Pair | Rest, near / 30 m | Attack pose, near / 30 m |
|---|---|---|
| Heavy vs Clerk | 0.58 / 0.56 | 0.68 / 0.67 |
| Heavy vs Sweeper | 0.49 / 0.48 | 0.58 / 0.59 |
| Heavy vs Turret | 0.69 / 0.68 | 0.74 / 0.73 |
| Turret vs Clerk | 0.64 / 0.59 | 0.62 / 0.57 |
| Turret vs Sweeper | 0.67 / 0.63 | 0.66 / 0.61 |

The gate is 0.22 for every pair at both sizes. The Heavy's tell alone changes
0.23 of its outline (gate 0.15), so it reads as shape, not only lamps.

Rendered evidence (Windows, Godot 4.7.2, AMD Radeon 780M, OpenGL):

`FRAGR_QA_BOTS=0 FRAGR_QA_MAP_FILE=server/maps/test/heavy-turret-range.json
FRAGR_QA_MANIFEST=res://qa/heavy-turret.json tools/qa_tour.sh` passed all seven
states with ordinary input. The Turret fight observed its shot first, strafed
through the charge and took no damage, then needed four Flechette hits. The
Heavy fight observed its burst, took one round (100 to 75 health), and needed
eight shots. Inspected stills, committed under `docs/screenshots/`:

- `heavy_turret_turret_phases.png`: idle, charge, shot and recovery, cropped
  and enlarged from 8 to 11 m first-person frames. Idle is a dark head on a
  thin braced column with a dim red optic. Early in the charge only the optic
  is lit; at that distance it is a few pixels, so the charge is readable but
  not loud. The shot shows the muzzle flash and the rail trace. Recovery, seen
  from the side, shows the lit coils along the barrel.
- `heavy_turret_heavy_phases.png`: idle at 12 m, then windup, burst and
  recovery. At rest in shade against the dark yard wall the Heavy is dark and
  low contrast; the visor and armband are the brightest parts. The windup is
  clearly different: both pauldrons flare and two red lamps light. The burst
  and recovery frames also carry the muzzle light and the hit flash.
- `heavy_turret_heavy_windup.png`, `heavy_turret_turret_firing.png`: the full
  frames.
- `heavy_turret_sheet.png`: baked Heavy and Turret cells (rest, tell, pain,
  death, side rest, side tell).

Union recolor: `union_recolor_before.png` and `union_recolor_after.png` compare
the same Clerk and Sweeper cells. The outline tests still pass unchanged, so
the difference is color, not shape. `union_recolor_m01_clerk.png` and
`union_recolor_m01_sweeper.png` come from a live M01 encounter tour
(`client/qa/m01-encounters.json`, passed): the black bodies stand out against
the bone and green interiors, and the Sweepers' red visors read at distance in
front of the dark lockers.

Full suite on Windows, 2026-09-24: fmt, clippy with `-D warnings`, workspace
tests, the 16-fighter bench with `--bench-check --bench-assert`, coverage
94.07 percent of lines (floor 90),
release build, `cargo deny`, the four-agent playtest, the mixed roster and
`tools/godot_check.sh` all passed, again after rebasing onto the ammunition and pellet change (#243).
The range tour also passed again after that rebase (Turret destroyed in five
shots, Heavy in seven). A scripted adapter bot on the test range
claimed supplies and destroyed both enemies, logged as `Campaign combatant
down` for `lane_turret` and `yard_heavy`; a four-bot arcade smoke logged frags.

## Spend and safety

$0. Offline GDScript rig and bake; no paid generation or services.

## Success criteria

- Both kinds on the wire, validated by server, adapter and client. Met.
- Tells precede damage by the documented time on every tier, and difficulty
  changes only timing. Met by seeded tests.
- Broken sight cancels the Turret's shot; heavy hits stagger the Heavy once per
  attack; death and retry reset both. Met by seeded tests.
- Silhouettes distinct from each other and from the Clerk and Sweeper at 30 m.
  Met by the outline harness.
- A demo encounter plays through with ordinary input and inspected stills. Met.

## Gaps

- No fresh-player review and no mission placement. The Turret's 80-damage shot
  is untested in a real mission layout.
- The Heavy's pauldrons are wider than the shared hit volume, so a shot that
  clips only a pauldron edge misses. A per-kind volume is separate work.
- Shots start at eye height (1.6 m) for every kind, so the Heavy's hip cannon
  is presentation, not the ray origin.
- The Turret's charge is a small red light at 10 m and more. A louder tell,
  sound or caption cues, and per-kind audio are not built.
- The Heavy is low contrast at rest in shade against dark walls. The lighting
  pass running in parallel should be checked against it.
- Eight directions give the Turret's sweep coarse rotation steps.
- A dry Turret (out of Rail ammunition) stops firing and stays idle; it has no
  melee, by design, but no mission has tested it.
