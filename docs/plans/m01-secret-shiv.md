# M01 secret Shiv

Status: **shipped** in #251 (v0.53.0).
Spend: $0 (existing art from the paused draft, no generation). Checked 2026-09-24.

Supersedes the paused draft in PR #203 (`feat/m01-secrets`, 2026-09-20), which
staged a service-panel cache with four precomputed gate worlds on top of the
magazine-era inventory. Main has since moved to one ammunition count per type
(v0.49.0), a durable run file and the optional supply detours (v0.44.0), and
`docs/VISION.md` now says "a boomer shooter, not a door simulator": secrets are
optional, a level has at most three doors, and nothing is a puzzle. This plan
keeps the draft's intent and drops its panel and moving wall.

## Goal

Give Recall Notice its first secret: a Shiv lying in the south pocket of the
confiscation alcove beside the property lockers. A player finds it by walking
in and looking, never by solving anything. It is a pool-less melee weapon,
quicker and harder than fists, and it needs no ammunition. A quiet
`SECRET FOUND` corner line confirms the find and the service record counts it.
Both ordinary routes stay clearable without it.

## Non-goals

- No moving wall, panel, switch, key or door. The alcove is already open; a
  moving panel would spend part of the three-door budget on a hidden room and
  would need the gate seam's precomputed worlds. It stays out.
- No other secrets, no secret total per level, no end-of-mission tally screen.
- No new enemy, no pacing change, no new sound (the cut reuses the existing
  melee presentation rules: no gunfire and no muzzle flash).
- No change to the arcade maps: full-arsenal policy never owns the Shiv.

## Design

| Number | Value | Why |
|---|---|---|
| Shiv damage | 35 | Three cuts kill a bare 100 HP fighter; fists need five. |
| Shiv cooldown | 6 ticks (0.30 s) | Kill in 0.60 s (cuts at 0, 6, 12) against fists' 1.60 s. Inside the 0.6 to 1.2 s band. |
| Shiv reach | 2.2 units | A little longer than fists' 1.8, still arm's length. |
| Ammunition | none | Pool-less like fists. A cut spends nothing and never dry-fires. |
| Placement | `[9.2, 0, -23.2]`, personal claim | 2.2 m from the alcove medkit, so taking the medkit does not take the Shiv, and about 9.5 m from the bay route. |

Picking up a newly discovered weapon draws it, as every discovery pickup does,
so the player sees the blade in hand at once. Slot 1 draws the Shiv when it is
carried and a second press goes back to fists, the way Doom's slot 1 holds the
chainsaw. The weapon wheel keeps the Shiv beside the fists.

## Architecture impact

- `protocol.rs`, `protocol/loadout.rs`: `WeaponType::Shiv`, appended to
  `WeaponType::ALL` at index 5 so the five original record slots keep their
  meaning. `ammo_pool` is `None`. `SHIV_GAMEPLAY_VERSION = 11`.
- `inventory.rs`: `grant_weapon` grants a pool-less weapon as ownership alone;
  a second grant adds nothing. Saved entry equipment carries it unchanged.
- `inventory/controller.rs`: the shared agent controller keeps a loaded gun,
  and draws the Shiv instead of fists only when every gun is dry. It closes to
  its own reach before cutting.
- `maps/authored/supplies.rs`: an optional `"secret": true` on a supply
  definition, carried on `ArenaPickup.secret`. `sim.rs` puts `secret` on the
  pickup event and tells the statistics ledger.
- `protocol/statistics.rs`, `statistics.rs`: `CombatCounts.weapons` has six
  slots and serializes five until the Shiv is used. `secrets` is omitted while
  zero and counts distinct secret ids: `total` over the run, `attempt` this
  attempt, so a restored secret found again after a continue is not a second
  secret.
- `run.rs`, `local.rs`: every discovery map, and both local missions' readiness
  records, require capability 11.
- Agents: MCP `act` accepts `shiv`; `get_events` keeps the `secret` flag. The
  brain parses and names `shiv` and describes it among carried weapons.
- Godot: `equipment_state.gd` (weapon list, slot 1, wheel), `shot_effects.gd`
  (melee reach per weapon), `hud.gd` (viewmodel, thrust, secret cue),
  `player_pawn.gd` and `weapon_pickup.gd` (48 pixel icon held at the 32 pixel
  size), `player_record.gd` and `records_panel.gd` (five or six slots,
  `Secrets found`), `net_client.gd` and `local_match.gd` (capability 11).
- Art: `client/assets/weapons/viewmodels/wpn_shiv_0.png` and
  `client/assets/weapons/48/shiv.png` from the draft, unchanged, with their
  sources, prompts and hashes in `client/art/weapons/manifest.json` and the
  reproducible `tools/bake_shiv.gd`.

## Saves and compatibility

- The M01 map file changed, so its content hash changed. A Recall Notice run
  saved by an earlier build inspects as incompatible and the menu offers New
  Run, which keeps the old file, as it did for v0.49.0. The run file stays at
  version 2; a saved entry that names `shiv` is readable only by this build.
- Retained service records keep five slots and read as no Shiv use.
- Capability 10 clients cannot enter any discovery map. Arcade maps still
  admit 1, and records still go to 10 or later because arena records never
  carry the sixth slot or `secrets`.

## Verification (2026-09-24, local Windows 11, Git Bash)

New deterministic tests:

- `tests::shiv`: reach past fists and blocked by cover, three cuts against five
  punches with exact kill ticks, a personal secret claimed once per participant
  and counted, strict `secret` parsing, and the shared controller's Shiv choice.
- `tests::m01`: the Shiv pocket is a walking detour in both lift states and is
  the only secret; a deliberate find draws the blade, emits one secret event,
  spends no bullets on cuts, records a sixth slot, and after a continue the
  Shiv is gone, restored in the alcove, found again, and `total` stays 1 while
  `attempt` returns to 1. Every ordinary-route walkthrough (both approaches,
  human and agent roles, the east bypass and the wasted-bullet bypass) now also
  asserts the Shiv was never claimed.
- Inventory, record and wire tests: Shiv ownership, no ammunition, saved entry
  round trip, five-slot history, six-slot and `secrets` round trip, the shared
  `client/golden/player_record_shiv.json` fixture on both sides, capability 10
  refused and 11 admitted, and the adapter's `shiv` action and secret event.
- Godot: equipment validation, slot 1 and wheel order, Shiv shot effects inside
  its reach only, the thrust keeping the gauntlet below the frame with no muzzle
  flash, five and six slot records in history and the service record panel,
  and the capability 11 launch record.

| Check | Result |
|---|---|
| `cargo fmt --all -- --check`, `cargo clippy ... -D warnings` | pass |
| `cargo test --workspace --locked --no-fail-fast` | pass: 873 tests, 0 failed, 2 existing ignored |
| `cargo llvm-cov --workspace --locked --fail-under-lines 90` | 94.11 percent of lines |
| `--bench 16 --bench-ticks 1200 --bench-check --bench-assert --seed 42` | pass, deterministic |
| `cargo build --workspace --release --locked`, `cargo deny check licenses bans sources` | pass |
| Playtest smoke (4 agents, 1 round) | pass: 7 frags in 24.5 s, 0 spawn deaths |
| `bash tools/playtest_roster.sh` (2/6/6/8/12/16 across six maps) | pass |
| Playable smoke on port 6795 | bots frag within 20 s; scripted `Probe` lands a frag; local-rules `Brain` plays 30 s with no provider key in its environment; server stopped by PID |
| `tools/godot_check.sh` (Godot 4.7.2 console) | `Godot checks: PASS` |
| `bash tools/test_godot_check.sh` | every scenario `ok` |
| M01 exploration tour (`FRAGR_QA_MANIFEST=res://qa/m01-exploration.json`, no bots, OpenGL) | 10 states; `secret_shiv_found` and `shiv_thrust` hold `selected: shiv`; the thrust strip shows the blade up for 6 of 8 frames |

Inspected stills: the alcove shows the Shiv icon on its own in the south pocket
beside the medkit; the found state shows the blade in hand with the gauntlet
below the frame and the corner feed reading the medkit, the Shiv and
`SECRET FOUND`, nothing over the crosshair. The first capture held the blade
too small to read, so it is now held at 1.3 times its canvas. The published
still is `docs/screenshots/m01_secret_shiv_16x9.png`.

Gaps: the viewmodel is one idle pose (the thrust is a scale and slide, not an
authored attack frame), the cut has no sound of its own, and the Shiv's balance
against Severe guards is unmeasured. Scripted routes prove access and the clear
without it; they do not prove a new player notices the pocket or enjoys it.
The arena tour was not republished: no arena surface changed.

## Success

Walking into the alcove's south pocket finds the Shiv with one quiet cue; the
blade is in hand and cuts faster and harder than fists for no ammunition; a
continue restores it without counting it twice; ordinary routes never touch it
and still clear; agents and the MCP door read and choose it; the published
exploration tour shows it found and in hand, inspected.
