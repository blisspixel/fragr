# Capture the flag on the maps whose bases match the sides

**Status:** shipped, [#313](https://github.com/blisspixel/fragr/pull/313), v0.64.0, 2026-09-30. A route review after Sector 9 in the [capture the flag plan](capture-the-flag.md). Human balance on the new maps remains open.

## Goal and why

Capture the flag was fixed to Sector 9 until the other arenas had a proven two-base route. Sides already spawn by X: Union in the negative half, Coalition in the positive half. A map can host the mode when each side has a clear stand in its back third, the stands do not sit on a pickup, and a fighter can walk from one stand to the other.

## Design

`MapKind::ctf_stands` is the list. Arena Duel's stands sit in the east and west rooms behind the perimeter walls, at `x = ±63`. Directive 17's stands sit on the outer axis, behind the weapon pads, at `x = ±68`. Sector 9 stays at `x = ±70`. The existing map validator checks the back third, clear ground, pickup clearance and the walk from the origin. A navigation test also walks each new pair with the shared route and one live movement pass.

Compliance Yard stays off. It is the retired records block, and its rooms are not two bases. Reclamation Gulch stays off because its compounds face north and south while the sides spawn on X. Tripoint Works stays off because it has three compounds. Rotation and authored missions stay off. Touch radius, return timer, capture limit and bot policy do not change. In the fiction this remains a staged league scenario.

The tour's home-flag cameras read the live stand. Sector 9 keeps its seven-metre step toward center. Arena Duel uses a three-metre step, because seven metres from x = 63 sits inside the perimeter wall at |x| = 56.

## Non-goals

No Rescue or Sabotage map, no flag rename, no interpolation, and no change to six-a-side bot pacing. Human and spectator acceptance of a full round stays open on every map.

## Architecture and protocol

No new wire field. `docs/protocol.md` records which maps can run the mode. A map without stands is refused before the server binds, and the playtest harness uses the same list.

## Verification and spend

`every_map_validates` covers the stand rules. The navigation test walks both new pairs and keeps the three unsupported maps empty. `ctf_validated_maps_place_stands_and_score_a_carry_home` picks up and scores on each validated map, and leaves the other three without flags. The startup test refuses Compliance Yard, Reclamation Gulch, Tripoint Works, and a rotating playlist. External spend is $0.

## Success

A host can run capture the flag on Arena Duel, Directive 17, or Sector 9. The other three arenas still refuse it. A fighter can walk from each new stand to the other.

## Evidence

`ctf_bases_are_walkable_on_the_validated_maps`, `every_map_validates`, `ctf_refuses_an_unvalidated_map_or_rotation_before_binding` and `ctf_validated_maps_place_stands_and_score_a_carry_home` passed on the debug `fragr-server` tests. Clippy on `fragr-server` and `fragr-playtest` was clean.

Zero-bot tours of `client/qa/ctf.json` passed on Godot 4.7.2-stable, OpenGL, AMD Radeon 780M, without `--publish`. Arena Duel used `FRAGR_QA_MAP=1`, `FRAGR_QA_MODE=ctf`, `FRAGR_QA_BOTS=0`, `FRAGR_QA_SEED=42`, `FRAGR_PORT=6848`. The server logged Arena Duel and both flags stood at `x = ±63`. The west bay shows the Union cloth and the east bay shows the Free cloth, with both home lines in the corner. Directive 17 used the same options on port 6849 and `FRAGR_QA_MAP=3`. The server logged Directive 17 Substation and stands at `x = ±68`. Each flag sits on the outer axis, clear of the weapon pad. The capture card still reads over a joined view. The four home-flag frames are `docs/screenshots/ctf_arena_duel_union.png`, `ctf_arena_duel_free.png`, `ctf_directive17_union.png` and `ctf_directive17_free.png`. These frames are not a human or spectator verdict. External spend is $0.
