# Competitive, cooperative and community multiplayer

Status: **planned** direction, new format details **proposed**, 2026-10-04.
Spend: $0 for design and local checks. Parent: item 6 of the Full build order
in [ROADMAP.md](../ROADMAP.md). This scopes that item, not a second global queue.

## Goal and current evidence

Build original, readable 5v5 elimination and plant/defuse, then combined-arms
objectives with useful infantry routes. Humans and free agents can also
cooperate against Union forces. Preserve free play, self hosting and community
contributions without requiring paid accounts or model APIs.

Deathmatch, team deathmatch, CTF and Sector 9 Sabotage are built. A local
2026-10-04 ten-agent socket trial finished with five fighters per side, eight
frags, a plant and an attacker elimination win, with no spawn deaths. It did
not exercise defuse, a whole match, human enjoyment or enforced seat caps.
Strict five-per-side admission, standalone elimination, Liberation, vehicles
and automatic abuse bans remain unbuilt.

## Original maps and references

The [compact-map research](../research/compact-map-lessons-20261004.md),
[objective-map research](../research/objective-map-lessons-20261004.md) and
[combined-arms research](../research/combined-arms-map-lessons-20261004.md)
separate documented facts from our design inferences. Learn readable routes,
meaningful exposure and counterplay without copying layouts or assets.
These are playtest hypotheses, not a universal ranking of maps.

Use the existing [map roster](multiplayer-maps.md):

| Scope | Venues | Distinct decisions |
|---|---|---|
| Compact objectives | Sector 9, Low Water, Custody Archive | Industrial crossing, town lanes, interior archive breaches |
| Combined arms | Launch Works, Holdfast Atoll | Freight/service routes, then island anchors with infantry alternatives |
| Cooperative finale | M20-derived Wipe | Persistent takeover disaster and finite isolated resources |

Every site needs useful alternate approaches and a contestable retake.
Landmarks explain location and purpose. Open ground needs choices and cover;
detail must strengthen legibility rather than obstruct navigation. Losing all
vehicles must not strand infantry. Keep civilian materials and local history;
issued Union equipment is black/red, not every wall.

## Competitive contracts

Add an explicit ten-fighter profile with five active seats per side. Define
overflow, team choice, parked resume, replacement between rounds and late join
at the existing Session boundary. Spectators remain welcome. Every control
role uses the same seats and actions; control never implies allegiance.

Plant/defuse extends the existing Sabotage state machine and controllers.
Elimination reuses shared life and round transitions without a charge. Both
need side-swapped trials and validated format facts. No buy shop or reload is
implied. Current Sabotage retains survivor equipment and restarts fallen
players empty; a starting pistol is a proposed alternative pending the
equipment decision, not an implemented change.

## Liberation: cooperative combined arms

Accepted direction: humans and free agents collaborate against Union forces
over objectives, with vehicles, defensive positions and rescues. A locally
controlled rule bot can be an ally. Control method, faction and body type are
separate facts; a synthetic body never establishes enemy status or lesser
personhood. This reflects the setting's varying degrees of freedom.

Start with four allied seats on one connected Launch Works scenario. Eight
seats require separate capacity and readability evidence. Give the initial
scenario a breach, rescue or service objective and a meaningful extraction
choice rather than simply filling a large map with enemies. Specify total
enemy/entity budgets and finite vehicle inventory. A proposed 24-seat PvP
roster is not permission for an additional unlimited AI army.

The server owns progression, enemy intent, seats/exits, damage and resources.
Reuse encounters, navigation, protocol validation and Session's bounded work.
Agents use existing tools and controllers. Before implementation, settle this
mode's failure, reinforcement, retry, leave/resume and completion contracts.
Campaign saves and continues remain separate. No mandatory campaign co-op or
revival system follows from this direction.

Liberation is ordinary Union conflict. [Wipe survival](wipe-survival.md) is
the unexpected AGI takeover catastrophe with persistent pressure and finite
isolated defenses. Share proven systems, while keeping those scenarios and
their resource contracts distinct. Recoloring a connected device cannot make
it immune to takeover.

## Hosting and contribution

[Fair play](fair-play.md) owns non-invasive authority and host controls.
Mixed human/agent play is welcome; skill is not grounds for punishment.
Existing expiring address/CIDR bans support temporary moderation. Optional
automatic bans remain planned, narrowly limited to repeated confirmed abuse,
disabled by default and reviewable. Information minimization and spectator
policy require evidence before claiming wallhack resistance.

[CONTRIBUTING.md](../../CONTRIBUTING.md) describes today's map/source paths.
A future community map package needs strict schemas, budgets, compatible
versions, legal notices and route validation. No workshop or arbitrary
multiplayer map loader is shipped today.

## Acceptance

- Preserve existing CI/gameplay assertions. Test admission, balance, malformed
  state, round outcomes and disconnect/resume through ordinary sockets.
- Prove required routes with authoritative collision and no vehicles. Measure
  contact and rotation per spawn/side, retakes, stalls and spawn deaths.
- Seeded bots establish mechanics; side-swapped human sessions and voluntary
  rematches establish enjoyment. Do not substitute one for the other.
- Inspect first-use and warmed continuous camera routes on actual hardware,
  including corners, roofs, water and vehicles. Record renderer, resolution,
  frame/tick percentiles, traffic and peak actors. Headless success does not
  prove GPU performance or public-server capacity.
- Verify desktop packages and a free self-hosted setup. Community-map loading
  needs its own validation gates before being advertised.

Asset production follows existing briefs and the shared ledger. No extra
subscription, pack, renewal, overage or deployment is authorized here.
