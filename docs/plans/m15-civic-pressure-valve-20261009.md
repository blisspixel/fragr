# Civic Pressure Valve development graybox

Status: **in flight**, 2026-10-09. Spend: $0. This is the first geometry pass for level 15. It is not a mission, not a save stage, and not a finished level.

## Lore route

The accepted route is the one in [CAMPAIGN-MISSIONS.md](../CAMPAIGN-MISSIONS.md) and [level 15](../campaign/l15-civic-pressure-valve.md). Episode IV returns to the capital nine days after Mars. The sanctioned games are the Union's supply line: entrants who lose badly enough, or owe enough, come out as corrections with issued handles. Tonight's games run as scheduled. The entrants hold numbered placards and nothing else. The player arms them. That arming is the rescue beat, and the free side is meant to be visibly larger by the exit.

The place is a ring and bowl around a sunken floor. Arrival is the entrants' pen under the stands, with numbered placards on hooks and a clerk post at the pen gate. The first door is the players' tunnel onto the floor. The Union then closes the arena gates for the bout. Those gates are the second door and one seal. Wardens come in waves: sweepers up the floor lifts around the centre, clerks and an enforcer from the tunnels, notaries overhead as broadcast cameras, then the broadcast booth on the upper ring (two clerks and an auditor). The last wave is the heaviest: a heavy sweeper, an assessor over the floor, and enforcers from both tunnels. Between waves the podium where Voss spoke is still dressed for ceremony. The gates open only when the bout is won. The exit is the ceremonial gate onto the avenue, into level 16.

The stadium's function has to read through the placards and the podium, not through an explanatory caption. The new lesson on the structure table is the Article Blade. That weapon does not exist. This pass does not invent a replacement lesson or a new story.

## This graybox

`server/maps/test/m15_civic_pressure_development.json` is a strict authored discovery map, version 1, map id 1015, name "Civic Pressure Valve (development)". `server/tests/m15_development.rs` loads it. There is no `mission` key, no `m13` key, and no `vehicles` key. `campaign_mission_id` stays empty. The integration test reads that through `GameState` mission state. The getter stays crate-private. No protocol, save, or menu change is attached.

The sunken floor is the base ground. A raised enamel ring stands around it, with a players' tunnel under the south stand and ordinary stairs on the east and west. The centre plinth and four low floor lifts are geometry only. Closed arena gates are two service-steel leaves across the north ceremonial opening. The ring continues over those leaves, so the seal is the ground passage, not a missing stand. Numbered placard posts stand in the pen, including placard 67 on its own hook. A crate marks the arming beat. A podium and a screen sit on the north floor. A booth with a window faces the floor from the east ring. An east concourse turnstile holds one secret armor pickup, the accepted concourse six, not a new secret.

Landmarks name the entry, the numbered hooks, the arming beat, the tunnel, the bowl, the podium, the booth, and the exit in front of the closed gate. Supplies are existing discovery weapons only: a rifle and a pistol, bullets, a shotgun and shells, a medkit, and that armor. Ordered encounters use only established kinds: three pen clerks, three lift sweepers, tunnel clerks and an enforcer, two notaries, booth clerks and an auditor, then a heavy sweeper, an assessor, and an enforcer in each tunnel mouth. Turret and crawler are allowed by the loader and are not used, because this level's waves do not call for them.

## Unbuilt

The Article Blade stays unbuilt. The plinth is empty geometry, not a weapon grant, and this map does not teach twelve swings. Also unbuilt: a connected mission and mission id, save promotion, menu entry, fresh-player acceptance, gate motion, the avenue into level 16, armed entrant actors, the Host's stadium call, and the official or pirate caption track. A passing load is not acceptance of the bout.

## Verification

`cargo fmt -p fragr-server`

`cargo test -p fragr-server --locked --test m15_development -- --test-threads=1`

The loader already rejects an unreachable spawn, landmark, supply, or enemy approach. A failed route is fixed in the geometry. The loader is not weakened to admit this map.
