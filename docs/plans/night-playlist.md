# Night playlist

**Status:** implemented, 2026-10-06. Local tests named in Verification passed.
Not merged, and not a release.

## Goal

A dedicated server stays up until the operator stops it, and between shows it
changes both the map and the mode. `--map-rotate` already walks the six
arenas and keeps the mode. That is not a night's rotation. The built-in list
is the personality of the process. A playlist file is later work, recorded in
[replayability](replayability.md) and [multiplayer modes](multiplayer-modes.md).

## What was wrong

`start_round` moved the built-in map, then respawned only fighters whose
`eliminated` flag was set. A survivor kept the previous coordinates. Those
can sit inside a solid, or outside the next map's half extent.

The mode was chosen once at launch. Capture the flag and Sabotage refused
`--map-rotate`. `map_info` was resent when the map changed, and not when only
the rules changed, so a same-map mode change would leave the client on the
old rules. Leaving a team mode without clearing `team` would make former
teammates unable to hurt each other. Sabotage uses a discovery arsenal.
Leaving that show without refitting the inventory would keep those fighters
spending ammunition on the next scrap map.

## The list

Plain modes, no mutators. Free-for-all uses frag limit 10. Team deathmatch
uses the existing side limit of 25. Both keep the three-minute clock,
compliance ping, and boss. Capture the flag is first to three, with that
clock and without frag limit, compliance, or the boss. Sabotage is the
default short match (halves of 4) and keeps its own clocks. Warmup and the
result delay carry from one show to the next.

1. Arena Duel, free-for-all
2. Compliance Yard, free-for-all
3. Directive 17, team deathmatch
4. Arena Duel, capture the flag
5. Reclamation Gulch, team deathmatch
6. Sector 9, capture the flag
7. Tripoint Works, free-for-all
8. Sector 9, Sabotage

The first `start_round` does not advance. Every later free-for-all, team
deathmatch, or capture the flag round does. Sabotage advances only when its
match is over, so the half-time side swap still happens. The advance runs
before Sabotage records who fell, so a new Sabotage show does not inherit the
previous mode. Sabotage placement stays `place_sabotage_round`. Every other
map change respawns every contestant. Grenades and mines clear when the map
changes. Teams clear when the new mode has no sides. Each new show refits
contestant inventories to that show's arsenal. Sabotage placement still
replaces them for a fresh match, so a carried Sabotage loadout does not
survive into free-for-all.

`--playlist` conflicts with a fixed map, mode, `--map-rotate`, mutators,
limits, campaign, solo, bench, and automatic fill. Startup rejects a slot
whose map cannot host the mode. The listener advertises Sabotage capability
28 and the maximum geometry of the six arenas, and it opens arena seats
rather than the four-seat mission party. Navigation for every arena is
prepared before readiness. `map_rotate` on the state stays false so the old
`next()` walk does not also run.

## Non-goals

A playlist file, mutators per slot, desk control of the next map, Wipe,
measurement numbers, a new mode, and any claim that this is a finished or
exceptionally secure server. The human team deathmatch and 5v5 trial remains
the fun gate.

## Verification

Deterministic tests: a living fighter left outside the next map is on a
walkable spawn of that map; the night list advances map and mode; Sabotage
does not advance until `match_over`; capture the flag on Compliance Yard and
Sabotage off Sector 9 are refused; a same-map mode change queues `MapInfo`
again. Returning to Arena Duel free-for-all restores the arcade arsenal.
A loopback server started with `--playlist` refuses gameplay 27,
accepts 28, and admits more than four fighters. Spend is $0. No cloud apply.

## Success

One process, started with `--bind 0.0.0.0:6767 --bots 4 --playlist`, keeps
serving until the operator stops `fragr-server.exe`. Rounds change map and
mode in the order above. A client that can play Sabotage can stay connected
through the night. The join check is a separate plan:
[join preflight](join-preflight.md).
