# Weight of Permission mission contract

Status: **in flight**, 2026-10-09. Spend: $0. This pass connects the existing
foundry gate rules to the successor geometry. It does not make The Weight of
Permission a mission.

## What this pass implemented

`server/maps/m13-weight-of-permission.json` now carries the optional `m13` key.
`AuthoredMap` prepare accepts it. `campaign_mission_id` stays empty, so the map
is not a mission, a save stage, or a menu entry. The office Rocket Launcher,
four rockets, and the freight Assessor are unchanged. The practice map
`server/maps/test/m13_foundry_development.json` stays byte-exact at SHA-256
`4995b14d93670ff3b5e3711f3b0977205a3c28700d93662c4515047511d31943`. Maps without
an `m13` key are untouched.

The key uses solids and the encounter that were already on the successor:

| Gate fact | Authored place |
| --- | --- |
| Relay | `ring_relay_housing`, the enamel housing beside the feed |
| Protected utility | `ring_water_feed`, the armored town feed, not the relay |
| Quarters | Existing encounter `quarters_approach` |
| Release | New terminal on the interior north face of `quarters_back`. Approach `[-22, 0.3, 7.7]` is standing and within use distance |
| Hazard and bypass | Open floor east of the furnace, `x=27.8..31.4`. Hazard `z=-35.4..-33.2`, bypass immediately north at `z=-32.2..-30.0`. They do not overlap |
| Cycle | 160 ticks, 40 warning, 40 active, with a safe gap |
| Freight deck | New `freight_deck`, 0.3 m thick, `x=-2.2..2.2`, `y=3.3..3.6`, `z=48..50`, on the gallery bridge inside the open shaft |
| Lift rise | Inset `x=-1.6..1.6`, `z=48.4..49.6`, top `14.6`, clear through the split ladle roof |

The 3 m `lift_landing` is still the static landing and is not the deck. One
solid and one terminal were added. The proved landing point `[0, 3.3, 52]`
stays open. The peaceful geometry walk drops `m13` only because it also drops
encounters, and prepare requires the quarters encounter. That walk still crosses
the floor, both stairs, and the landing with the new deck present. It does not
tick hazards.

## What remains before a real mission

Objectives are not implemented. The accepted facts are still
`foundry_entered`, `machine_hall_cleared`, `rocket_found`,
`freight_loop_secured`, `relay_disabled`, `upper_gallery_secured`,
`lift_boarded`, and `party_departed`. There is no save version past the current
M12 document, no menu launch, and no `MissionId`. Pending
`weight_of_permission` must not promote until those exist, and completion must
not promote to an unbuilt level 14. Played release, a ridden successor deck,
hazard presentation, finite human-magazine acceptance, and human review remain
ahead. The Walker belongs to level 14 and was not built.

## Verification

These commands passed on 2026-10-09:

```
cargo fmt -p fragr-server
cargo test -p fragr-server --locked --test foundry_development -- --test-threads=1
cargo test -p fragr-server --locked --lib m13:: -- --test-threads=1
```

`foundry_development` passed 5 tests. `m13::` passed 13 tests, including the
successor load that keeps the gates and an empty campaign id. Spend is $0.
