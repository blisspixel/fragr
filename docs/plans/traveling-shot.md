# Traveling shot

**Status:** implemented, [draft #302](https://github.com/blisspixel/fragr/pull/302), 2026-09-29. Local evidence is below. It does not start level 3, and it does not cut a release.

## Goal and why

Hitscan resolves in one tick. A later campaign weapon needs a shot that stays in the world, hits what it reaches, and keeps going if the shooter dies. This proves that shot on a non-mission fixture before any mission teaches it.

## Design

The server steps a point along a straight ray. `combat::Ray` already answers what is first on a segment: floor, solid, then a fighter cylinder. The shot does not use `movement::integrate` or `live_step`, so the golden movement vectors stay untouched. There is no gravity, no homing, no bounce, and no splash.

- Speed is half of `movement::TOP_SPEED`: 2.5 metres per second, 0.125 metres on a 20 Hz tick. A walking fighter outruns it.
- Lifetime is 80 ticks: 4 seconds and 10 metres. A miss then disappears.
- Damage is 12, which is not the damage of any current weapon. Impact uses `resolve_fighter_hit` so armor, hostility, frags, and the `Hit` event stay on one path. The shot does not emit `shot_results`, because `ShotTrace.weapon` is a `WeaponType` and this shot is not a gun.
- Direction is fixed at launch from the shooter's yaw and pitch. Later aim does not steer it.
- The shooter id never stops the point, including after that body respawns. A dead shooter whose body is still in the roster does not delete the shot.
- One shot per shooter. A second launch is refused until the first ends. Two shooters can have two shots.
- Bodies skipped by hitscan are skipped here: dead, respawning, companions, inactive mission actors, and spawn shields. A shield does not stop the point. The shooter's own id is also skipped after that body returns to the line.
- A companion's hitscan ray does not strike a participant. This shot does not copy that exception until a companion weapon calls the launcher.
- A round ending or a new round clears shots still in flight.

## Wire

`Snapshot` gains `projectiles`, a list of `{id, x, y, z}`. The field uses serde `default` and is omitted when empty, the same pattern as `shot_results`. `Snapshot` does not deny unknown fields. Old Rust readers ignore the key. The Godot client reads known keys with `data.get` and does not close on an unknown key. No map requires the field, so gameplay capability stays 22. `net_client.gd` keeps sending 22.

The shot is not an `Action` field, not a `CampaignActor` field, and not an authored-map field. Those structs deny unknown fields. Map 1011 exists only inside the test. It is not registered in `maps.rs` and it has no mission.

## Client

`TravelingShots` places one unshaded marker at each server position and removes it when the list is empty or the key is absent. It does not predict or interpolate. Nothing in a live match launches a shot yet, so this PR does not publish a tour still and does not cut a release for the marker.

## Non-goals

No campaign rocket, grenade, mine, or sniper. No `EnemyKind::Jammer`. No edits to Persons Unknown or Scheduled Service. No UDP, interpolation, lag compensation, or tick-rate change. No second physics model.

## Verification and spend

Server tests cover a hit, a wall, a miss that expires, a dead shooter, a shielded body, a target that leaves the line, the per-shooter refusal, floor contact, a non-finite step, round clear, the omitted snapshot key, the shooter's own returned body, and a shooter who has already left. `test_traveling_shot.gd` checks the marker. External spend is $0.

## Result

On 2026-09-29, in the `feat/traveling-shot` worktree:

- `cargo fmt --all -- --check` passed.
- `cargo clippy --workspace --all-targets --locked -- -D warnings` passed. `fragr-server` clippy passed again after the returned-body and departed-shooter tests.
- `cargo test --workspace --locked` passed. The server library reported 624 passed and 3 ignored. The traveling-shot tests reported 13 passed.
- `tools/godot_check.sh` passed on Godot 4.7.2.stable.official.ed1daf0bf, including `test_traveling_shot: PASS`.

External spend was $0. No tour still was published. No live weapon calls the launcher.

## Success

The tests above pass, empty snapshots omit `projectiles`, and no campaign map or weapon list changes. A bot or human match still has no traveling shot until a later weapon calls the launcher.
