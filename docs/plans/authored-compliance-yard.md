# Compliance Yard: a place worth fighting through

Status: deferred, 2026-09-19. Spatial study, not the campaign opening.
Spend: $0. Owner of current priorities: `../ROADMAP.md`.

Nick requested story planning before campaign map planning. Review all lore and
resolve the story questions in `../CAMPAIGN.md` with him first. The room list
below is a possible arena study only; it does not select the campaign's opening
location, protagonist, mission, or route. Revisit it after the story is settled.

## Finding and goal

The six-map rendered audit confirms Nick's report: the roster is dominated by
large flat floors, repeating barriers, oversized approaches, and weak landmarks.
Reachability, server performance, and combat liveness do not establish level
quality. The previous scale expansion is implemented, but its reference-game
comparisons are design intent, not evidence that the layouts achieve that bar.

Rebuild Compliance Yard first as a compact, authored inspection complex. Keep its
existing identity and original art direction. It should support readable duels,
four-to-eight-player arena fights, human/agent sessions, and later encounter
authoring. Do not call it a completed campaign mission or copy a reference map.

Nick's subsequent clarification prioritizes a complete first single-player level:
start with a fist or knife, discover weapons and ammunition, and fight properly
animated enemies in authored encounters. A revised arena alone does not satisfy
that request. Integrate the spatial work with the first mission and its progression,
then validate arena use separately. The existing `campaign-build-order.md`,
`campaign-e1.md`, `ENEMIES.md`, and `WEAPONS.md` own the larger designs; reconcile
their starting-loadout details with this current direction before implementation.

## Layout brief

- Intake: a short sheltered arrival space, two exits, an obvious route toward
  the sorting court, and a close-range weapon near a commitment point.
- Records: staggered filing aisles and a bent service route. Short sightlines
  favor Scatter; both ends reconnect, so retreat is a route choice.
- Sorting court: the main medium-range meeting point, broken by useful large
  structures rather than scattered waist-high boxes. Keep the origin clear for
  current server events without making it the centre of a giant empty square.
- Inspection gallery: reachable high ground with two ascents and a drop route.
  Rail is exposed here. The gallery overlooks part of the court, never every exit.
- Relay service lane: one deliberate long sightline, interrupted approaches at
  either end, and a side connection back through Records.

Fit these spaces together before choosing the outer extent. No unused apron
around the playable layout. Every regular combat space has two independent exits;
an optional reward recess may have one if the risk is legible. Separate health
and armour routes from the strongest weapon, and protect spawns from immediate
shared sightlines. A spectator overview is useful for navigation review; judge
space, cover, scale, and visual identity from a player's eyes.

## Implementation boundaries

Retain server-owned collision and the shared action/navigation paths. Inspect
`server/src/maps.rs`, `sim.rs`, `navigation.rs`, `client/scripts/arena_cover.gd`,
and existing map validation before changing them. Add authored spawn positions
through the canonical map definition if the ring conflicts with the floor plan;
do not force rooms to serve an arbitrary ring. A small versioned JSON map source
is appropriate if it simplifies explicit layout authoring. Validate it and feed
the existing map representation rather than creating a second geometry engine.

The current heightfield cannot represent ceilings, underpasses, or bridges with
walkable space below. Do not render fake traversable geometry. Roofless industrial
rooms, balconies backed by solid platforms, stairs, and drops work today.
Three-dimensional volumes belong in a separate bounded collision change when an
authored space actually requires them. No paid art is needed to establish flow.

Use large, readable original landmarks and local pixel materials. Room signage,
palette changes, structural silhouettes, and props should explain the place.
Avoid implementation/debug labels in the player interface. Keep frozen voiced
names and the Union/free-agent/Quiet canon intact.

## Evidence and acceptance

- [ ] Draw and inspect the floor plan before committing to detailed geometry.
- [ ] Traverse both directions through each main loop as an ordinary human;
  verify stairs, escape drops, pickups, spawn clearance, and return routes.
- [ ] Deterministic route tests use actual server movement. Validate map data,
  authored spawn safety, and visibility claims that can be checked mechanically.
- [ ] Run duels and four/eight mixed clients, multiple seeds, and rule enemies.
  Inspect engagement distances, dead time, spawn deaths, and stalls. Keep existing
  thresholds. No arbitrary scalar score stands in for fun or level quality.
- [ ] Inspect real first-person movement and combat captures in each named space,
  including OpenGL and Vulkan on the available host. Refresh the published tour.
- [ ] Run repository verification and a regression case on the other maps.
  Record remaining geometry/art/encounter limits, then ship the bounded result.

After this layout holds up in play, revise the remaining roster according to its
actual mode and player count. Larger field maps need bases, terrain, meaningful
objectives, protected approaches, and reasons to cross the open ground. Campaign
maps need authored encounters and progression. Neither follows automatically from
scaling this arena or increasing the server population.
