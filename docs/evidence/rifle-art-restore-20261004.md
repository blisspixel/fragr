# Rifle artwork restoration, 2026-10-04

Status: **in flight**. The player rejected the source-derived Rifle framing
and style despite its earlier technical passes. This correction restores the
retained preferred idle, firing and pickup pictures; no paid operation or
weapon-rule change occurs. Complete client, exact-head CI and desktop package
acceptance remain pending.

## Exact earlier artwork

All three restored files have the same git blobs as pre-source-selection
commit `719d3c10`. No image bytes are regenerated or edited. The idle and fire
hashes also match `client/assets/art-pass-2-20261002-manifest.json`.

| Restored path | SHA-256 |
|---|---|
| `client/assets/weapons/viewmodels/rifle_idle.png` | `92b7ef9d7bd8d3216c3967c9ea943aa726b7c04889bb9492ca649f0a6d6cabc0` |
| `client/assets/weapons/viewmodels/rifle_fire.png` | `837e6c05025705111b48a234c36a8515b1253925ec772af0b22759ffe9853099` |
| `client/assets/weapons/pickups/rifle.png` | `18a053a4c21edeba0d7916486d182917be6f531e063bca904d5de38f5648b957` |

Only WeaponArt's three Flechette references change. The source-derived
selection receipt becomes unselected, retaining its original source, presenter,
bake, three pictures and date. The physical source itself is unchanged.
Its geometry, bore, bolt, trigger, glove contact, negative-control and offline
bake assertions remain intact. Selected-boundary assertions now prove the
actual restored resource paths and exact earlier pixels, ordinary fire-to-idle
timing and the world pickup path.

## Local gates

Godot 4.7.2-stable import completes with numeric zero and clean error logs.
`test_rifle_source.gd` and the original `test_viewmodel.gd` both exit zero with
clean logs and their own PASS markers. The canonical opacity, bob, recoil,
swap and three-resolution assertions remain unchanged.

The complete checker uses an owned copy of the unchanged matching private
server, SHA-256 `ec469482cfa336212c4a77e42bdea4fc683ec2d79f772f0310c0ca47056c3a58`.
The historical root native is untouched. Full checker results remain pending;
technical success does not decide subjective art quality.
