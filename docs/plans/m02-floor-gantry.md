# M02 processing floor gantry

**Status:** in flight, 2026-09-27. Stacked after the autonomous Latch escape draft.

## Goal and reason

Put the named processing-floor officer on the existing upper mezzanine, where
the accepted Persons Unknown brief places the priority threat. Today that
Clerk spawns on the ground at `[12, 0, -5]`. The floor has two usable levels,
but the fight does not ask the player to read or use that vertical space.

This is one measured encounter pass, not the full processing-floor roster.
Keep the four current floor enemies, their activation order and the dock fight
while moving the officer to a reachable upper position. Preserve a grounded
escape route and Latch's independent, bounded support.

## Work

1. Record the current Standard and Severe scripted route with ordinary health,
   ammunition, damage and Latch support. Keep it separate from unsteered play.
2. Place the officer on a supported, reachable part of the mezzanine. Check
   sightlines from the floor entry, cover, stair access and the view from the
   upper landing. Change floor geometry only when an actual route or sightline
   check calls for it. Keep the enemy's stable authored ID. Put the existing
   floor-entry medkit on the main passage if ordinary-health runs expose a
   narrow survival margin.
3. Extend seeded server coverage for the loaded map: the officer begins above
   the floor, is supported by authored geometry, and a participant can reach
   the position by the real movement path. Exercise the live fight and retry.
4. Run rendered first-person routes on Standard and Severe with the same
   health and ammo rules. Record player and Latch damage, floor survival,
   encounter duration, position and a full-resolution frame that shows the
   threat above the floor. If a route fails, adjust the encounter or route and
   rerun rather than lowering the checker.
5. Update the M02 brief, roadmap and plan index with what is built and what
   remains. Do not put this level detail in the root README.

## Architecture and contracts

The authored map owns geometry and enemy spawn. Keep `floor_officer` as a
Clerk, keep the server authoritative, and use the existing map validation,
navigation, encounter and tour seams. No new wire message, capability, input
path or client simulation is planned. A map solid changes both collision and
rendering, so validate it in Godot and with authored reachability. Do not
change the campaign difficulty rule revision for this placement-only pass.

## Boundaries and spend

No extra floor enemies, optional captive route, door, Notary fight, Mara
warning, new asset service, cloud apply or paid call. External spend is $0;
the separate $20 build allowance remains untouched. A human must still judge
the Crawler lesson, Latch reunion and processing-floor balance without
guidance before M02 can pass its player gate.

## Acceptance and verification

- Officer is visibly above the player on entry and reachable by the broad
  stairs without jumping or leaving authored bounds.
- The player can clear or pass the fight and depart even if Latch stalls.
  Existing companion no-softlock and participant-fire boundaries remain true.
- Both scripted difficulties complete with ordinary damage and ammo; record
  health before/after, shots or damage by participant and Latch, and any death.
  A scripted pass is authoring evidence only.
- Authored map tests, focused encounter tests, Godot checks, full Rust gates,
  release build and CI pass. A player-facing change requires a refreshed and
  inspected tour. Record unavailable gates and remaining risk explicitly.

## Progress

- 2026-09-27: Source and lore audit identified the ground-level officer as
  the clearest mismatch with the accepted M02 floor design. The existing
  mezzanine and broad steps can host a vertical threat.
- 2026-09-27: Moved `floor_officer` to the upper mezzanine without changing the
  enemy count or AI. A loaded-map test proves support, route completion and a
  floor-entry sightline. The 20-state first-person tour climbed those stairs,
  returned to the floor, defeated the dock guards and departed. The officer
  stayed at server Y 4.0 through the fight; the full-size
  [firing frame](../screenshots/m02-floor-gantry/officer-firing.png)
  shows the live upper threat. The manifest records `floor_officer` in
  `firing` at tick 1406 on the final Severe run. Independent review found no
  remaining map, route or lore issue.
- 2026-09-27: An initial upper-officer Severe route cleared the floor at 5 HP.
  The existing `floor_entry_medkit` was off the direct ward-to-floor path, so
  it now sits just inside the main opening. On the final Standard run, the
  participant had 50 HP at Latch handoff and 80 HP at floor entry; on Severe,
  55 became 85. Those 30-HP gains match the ordinary medkit grant. The pickup
  changes only this authored map and does not add a new resource rule.

### Floor-route measurements

One scripted first-person run per row on Windows 11, Ryzen 7 7840U and AMD
Radeon 780M, Godot 4.7.2-stable OpenGL Compatibility, local release server,
no rule bots. Player aim was accurate and held to the same five-second paced
opening, with ordinary health, damage, ammunition and pickups. `Shots` counts
participant attacks during the floor stage; Latch damage sums resolved floor
ShotResults. Start HP varies with the earlier rooms and real-time route timing,
so these rows are observations, not a controlled difficulty comparison.

| Map state | Difficulty | Floor HP start to end | Player shots | Latch damage | Result |
|---|---|---:|---:|---:|---|
| Ground officer baseline | Standard | 50 to 10 | 18 | 20 | Cleared, departed |
| Ground officer baseline | Severe | 100 to 85 | 14 | 40 | Cleared, departed |
| Upper officer, pickup off path | Severe | 75 to 5 | 13 | 60 | Cleared, departed; margin too thin |
| Upper officer, pickup on path | Standard | 80 to 35 | 15 | 40 | Cleared, climbed, returned, departed |
| Upper officer, pickup on path | Severe | 85 to 35 | 12 | 40 | Cleared, climbed, returned, departed |

The final Standard and Severe routes each confirmed four floor deaths, one
living participant, an authoritative Latch hit, and a complete mission record.
The two [inspected frames](../screenshots/m02-floor-gantry/README.md)
show the firing officer and the usable upper path. Unsteered play and final
balance remain open; no automated route can close that gate. External spend
remains $0.

Local `cargo fmt --all -- --check`, workspace Clippy with warnings denied,
workspace tests, the focused loaded-map test after the pickup move, and the
pinned Godot checker passed. The standard 32-state tour ran with `--publish`
and passed; its arena and menu stills were inspected, with no changed surface
to replace among the four README images. The final 20-state M02 routes passed
on both difficulties and the two representative frames were archived above.
The final combined CI run and any remaining gates will be recorded before
this draft is marked implemented. The full floor roster, optional captives,
maintenance loop, Notary tableau and unsteered human gate remain later M02
work.
