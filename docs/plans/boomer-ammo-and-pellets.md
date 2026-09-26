# Boomer ammo and shotgun pellets

Status: **shipped** in #243 (v0.49.0).
Spend: $0. Checked 2026-09-24.

## Goal

Nick's playtest (2026-09-24): "the reload count doesnt make sense. and the
shotgun has terrible aim". Both were real.

- **Ammo.** The Rifle (`flechette`) and the Shotgun (`scatter`) drew from one
  shared Darts reserve, and a shell cost four darts, so the corner's
  `magazine / reserve` pair did not add up for either gun. The README meanwhile
  said pads read Bullets, Shells and Cells.
- **Shotgun.** `check_hitscan` fired one seeded ray somewhere inside a 0.20
  radian (11 degree) half-angle cone. At arm's length a shot that looked dead on
  often missed the body entirely. It was a wide single bullet, not a spread.

Nick chose Doom style with no reload.

## What changed

1. **One count per ammunition type, no magazines, no reload.** Bullets feed the
   Pistol (`tack`) and the Rifle, Shells the Shotgun, Cells the Railgun. One
   shot spends one unit; a shotgun blast is one shell. Fists need nothing. The
   reload action is gone from the server, the wire `Action`, the MCP `act`
   schema, the shared controller, the brain, the playtest harness, the Godot
   input map, the HUD, the loading card, the console and the tips.
2. **The Shotgun fires seven pellets.** Each is its own seeded ray against cover
   and fighters with its own distance falloff. Damage is summed per struck
   fighter, applied once (armour absorbs once), and one death is one frag.
3. **The HUD shows one number beside a drawn ammo sprite** (two brass bullets,
   two red shells, or a cell) for the held gun, dimmed with a red zero when
   empty. No caption words, per the quiet-HUD rule in `hud-quiet.md`. The weapon
   no longer lowers for a reload.

Non-goals: new weapons, projectiles, a moving-spread penalty, automatic weapon
switching on empty, balance of the rail through full armour (still 2.0 s, an
existing gap in `gunfeel.md`), or any spend.

## Tuning (ours to tune, sourced where possible)

| Number | Value | Why |
|---|---|---|
| Bullet cap | 200 | Doom's cap. |
| Shell cap | 50 | Doom's cap. |
| Cell cap | 100 | One cell is one 80 damage rail shot. Shipped at 50, Doom's rocket cap; raised to 100 on 2026-09-25 by Nick's decision in [multiplayer-modes.md](multiplayer-modes.md), with capability 12. |
| Tack pickup | 50 bullets | Doom's pistol start; the magazine era gave 48 shots. |
| Flechette pickup | 60 bullets | Doom's chaingun gives 20, too stingy for five shots a second. |
| Scatter pickup | 12 shells | Doom gives 8; our blast is slower per shell than Doom's pump. |
| Rail pickup | 10 cells | The magazine era gave 12 shots. |
| Pellets | 7 | Doom's shotgun. |
| Pellet damage | 10, full to 4 units, linear to 0.35x (4) at 12 | Doom's average 5d3 pellet is 10. |
| Pellet cone | 0.095 rad (5.4 degrees) half-angle | Every pellet lands at four units, about half at eight. |
| Scatter cooldown | 12 ticks (0.60 s) | Two full blasts kill a bare fighter in 0.60 s and three go through full armour in 1.20 s, inside the 0.6 to 1.2 s and under 1.8 s bands. |
| M01 bullet boxes | 20 (four pads), 50 (two pads) | Doom's clip is 10 and box 50; one shared count replaces two pools. |

## Architecture impact

- `protocol/loadout.rs`: `AmmoPool` is `bullets|shells|cells`; `LoadoutState`
  is `{player_id,tick,selected,weapons:[WeaponType],ammo:[{pool,rounds}],
  personal_claims,dry_fire_count}` with `deny_unknown_fields`, so the
  magazine-era shape is refused whole. `validate_equipment` is shared with the
  saved run entry.
- `inventory.rs`: owned flags and three counts; `try_fire` spends one unit.
- `sim.rs`: `check_hitscan` resolves `weapon.pellets()` rays;
  `resolve_fighter_hit` commits one fighter's summed pellets. Pellets group by
  struck fighter in firing order, then one miss result for the rest.
- `protocol.rs`: `ShotTrace.pellets: Vec<PelletTrace>` (omitted when empty,
  at most seven); `end`/`impact` repeat the first pellet for readers that
  ignore pellets. `Action.reload` is removed.
- `statistics.rs`: one `hit` call per attack summed over struck fighters; a
  record's scatter kills are bounded by seven per damaging attack.
- `encounters/enemy.rs`: guards no longer pause to reload; an empty guard goes
  to fists as before.
- Godot: `equipment_state.gd`, `equipment_hud.gd`, `shot_effects.gd` (draws
  every pellet), `game_manager.gd` (folds a shooter's results in one tick into
  one flash, one kick and one summed hit marker), `net_client.gd`,
  `project.godot`, QA tour and combat probes.

## Versioning and saves

- `AMMO_GAMEPLAY_VERSION = 10`. Every discovery map, M01 and M02 included,
  requires 10 for every role; the local readiness record names 10 for both
  missions. Arcade full-arsenal maps still admit 1: an older reader draws only
  the first pellet of each result, and an action carrying `reload` fails to
  parse and is dropped without a `malformed` strike. Records go only to 10.
- `CAMPAIGN_RULES_REVISION = 2`: guard timing changed (no reload pauses) and the
  scatter changed. Live mission state requires exactly 2. The Godot record
  history accepts revisions 1 and 2, so retained service records from earlier
  builds stay readable.
- Run file version 2 saves `weapons` and `ammo`. A readable version 1 document
  (magazines and reserves) inspects as **incompatible**, never corrupt, so the
  menu offers New Run, which archives its exact bytes. M01's content hash also
  changed with the ammo pads. M02's four ammo pads became `landing_bullets` and
`ward_bullets` (20 bullets) and `antechamber_shells` and `floor_shells` (8
shells, since its darts fed the shotgun); M02 has no durable run. There is no
in-place conversion: the rules
  revision and the content both changed, so an old entry would restore
  equipment for a mission that no longer exists in that form.

## Verification (2026-09-24, local Windows 11, Git Bash)

| Check | Result |
|---|---|
| `cargo fmt --all -- --check`, `cargo clippy ... -D warnings` | pass |
| `cargo test --workspace --locked --no-fail-fast` | pass, every crate |
| `cargo llvm-cov --workspace --locked --fail-under-lines 90` | 94.07 percent of lines |
| `--bench 16 --bench-ticks 1200 --bench-check --bench-assert --seed 42` | pass, deterministic |
| `cargo build --workspace --release --locked`, `cargo deny check licenses bans sources` | pass |
| Playtest smoke (4 agents, 1 round) | pass: 9 frags in 35.4 s, 0 spawn deaths |
| `bash tools/playtest_roster.sh` (2/6/6/8/12/16 across six maps) | pass; 1 non-opening spawn death on maps 2 and 4, none at an opening |
| Playable smoke on port 6793 | bots frag within 30 s; scripted `Probe` and local-rules `Brain` each land a frag; server stopped by PID |
| `tools/godot_check.sh` (Godot 4.7.2 console) | `Godot checks: PASS` |
| `bash tools/test_godot_check.sh` | every scenario `ok` |
| `tools/qa_tour.sh --publish` | 25 states, 11 stills published |
| M01 discovery tour (`FRAGR_QA_MANIFEST=res://qa/m01-discovery.json`, no bots) | 10 states, every `expect_equipment` held |

New deterministic tests: `tests::pellets` (point-blank blast lands all seven
for 70 and two kill with one frag; every pellet falls off by its own distance;
a full wall stops all seven and a waist-high sill splits a blast; one blast
spreads across two fighters with one result and one frag each; a discovered
blast spends one shell; single-ray weapons carry no pellet list),
`inventory::tests` (one unit per shot for every gun, shared bullets, separate
shells and cells, Doom caps, magazine-era loadout refused),
`run_file::store` (a version 1 magazine save is incompatible and New Run keeps
its bytes), `net::tests::m01_refuses_magazine_era_capability_eight_and_admits_ten`,
the MCP `act` schema test (no `reload`, schema equals the validator's key list),
the playtest blast-counting test, and Godot `test_equipment`,
`test_shot_effects` and `test_mission` updates.

M01 seeded routes, recorded honestly after the change (accurate-aim authoring
evidence, not a fresh-player gate):

| Route | Before | After |
|---|---|---|
| `east_bypass_departs_with_all_stack_guards_alive` | 1639 ticks, 80 hp, 0 armor, 16 defeats, 101 shots | 1581 ticks, 100 hp, 5 armor, 16 defeats, 104 shots |
| Main approach, human and agent | departs | 1748 ticks, 100 hp, 19 defeats, 104 shots |
| Maintenance approach, human and agent | departs | 1743 ticks, 100 hp, 20 defeats, 112 shots |
| Bypass after 30 wasted bullets | departs after one wasted magazine | 1689 ticks, 100 hp, 10 armor, 16 defeats, 130 shots, 110 bullets left |
| Solo controller with a forced lift death | 3 deaths, attempt 4, last continue | 1 death (the forced one), attempt 2 |

The accurate-aim clears got easier: without reload pauses the scripted player
never stops shooting. This is not a difficulty acceptance; M01 balance for a
fresh human still belongs to `m01-completion.md`.

## Inspected stills

- `12_scatter_pellets_shot.png` (arcade tour, Scatter aimed 0.35 rad down at the
  floor about five units ahead): seven separate spark impacts in a tight cluster
  around the crosshair, about a body width across, with the muzzle flash. The
  old build drew one impact somewhere in an 11 degree cone.
- M01 `03_confiscated_tack.png`: `50` beside two brass bullets in the bottom
  right, no caption. `05_tack_empty.png`: a red zero and dimmed bullets after
  all forty-nine remaining bullets were spent; no reload prompt.

## Gaps

- The HUD ammo glyph is drawn in code from palette colours, not a generated
  sprite; a sprite pass can replace it.
- No human has played the new shotgun or ammo yet. The recorded M01 runs are
  seeded controllers.
- Arcade maps have no ammo, so pellets are the only arcade change.
- Old reload sound clips stay on disk unused.
