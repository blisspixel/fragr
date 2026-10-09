# Level 19 Planned Works development

Status: **in flight**.

## Goal

Stand up a standalone development graybox for level 19, Planned Works, on the accepted route. The map is not a mission and does not advance a save.

## Lore route

[Level 19](../CAMPAIGN-MISSIONS.md) and the [level plan](../campaign/l19-planned-works.md) already fix the route. Former Union personnel help for a moment in the evacuation concourse and are not absolved. Home's roofs from level 5 are marked for demolition. Latch leaves the player's side. That departure is not an escort failure and not a new objective.

The route is the evacuation concourse, then the changed home streets, then the level 5 loop in reverse. A ground route always works. Level 5, in [No Forwarding Address](../campaign/m03-no-forwarding-address.md) and `server/maps/m05_no_forwarding_address.json`, crosses the roof loop from the west water tanks toward the east roof, then down through the workshop and the tram trench to the freight platform. This graybox walks the street under those roofs from the east side back toward the tanks. The trench mouth is the written exit toward the waterworks. It is not a door into level 20.

## Graybox

`server/maps/test/m19_planned_works_development.json` is version 1, map id 1019, name `Planned Works (development)`, equipment `discovery`, and LF only. It has no mission key, so `campaign_mission_id` stays empty.

The concourse is a walled hall opening north onto the changed street. West and east roof masses echo the level 5 pair, with both water tanks on the west roof and a steel bridge over the center street. White enamel bars sit on both roofs. A market stall, the court meal table, and a dark clinic post sit on the changed street. A trench channel continues north.

Ground landmarks, all at foot height zero:

- `evacuation_concourse` and `concourse_crossing`
- `changed_home_street`
- `roof_loop_east`, `marked_roof_street`, and `roof_loop_west` (east to west, the reverse of the level 5 roof crossing)
- `latch_departure`, on the ground beside the tanks
- `demolition_marks`, in the street under the marked roofs
- `trench_mouth`

Two existing Sweepers hold the concourse crossing. No other actor is placed.

## Unbuilt

Jetpack. Paver. Latch departure rules. Connected mission. Save. Menu.

Also unbuilt: Collector, work-strip damage, former-Union help as behavior, secrets, doors, the clock, and the brief. No existing enemy stands in for the Paver or the Collector. The departure landmark is only the ground beside the tanks. Sitting, the three lines, and the run to the waterworks are not simulated. M05 files were not edited.

## Architecture

No new mission id, wire type, save field, or menu entry. Loader rejection rules are unchanged. The integration test reads an empty mission state through `GameState`. `campaign_mission_id` stays crate-private.

## Verification

```
cargo fmt -p fragr-server
cargo test -p fragr-server --locked --test m19_development -- --test-threads=1
```

`cargo fmt -p fragr-server` completed with exit 0. The development test passed: 1 passed, 0 failed, finished in 0.08s after a debug build. The map file, the test, and the accessor edit are LF only.

## Spend and safety

$0. No asset generation. No hosting change.

## Success

The development file loads, map id is 1019, the campaign mission id is none, the landmarks exist, and ordinary walking reaches them on the ground without a jump. That does not finish level 19.
