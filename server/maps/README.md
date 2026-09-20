# Authored development maps

`m01-recall-notice.json` contains the opening mission's connected blockout and
weapon discovery and a draft introductory encounter. Its two routes, stairs,
balcony, office and lift use normal movement. Enter with fists, find Tack and
Flechette, collect ammunition and reload.
One Clerk and two Sweepers use authoritative attack, hit and death states.
Enemy artwork and animation remain provisional. The physical transfer record
opens the custody lift; the party can then depart together. This ends the current
prototype, not a finished M01 or the rescue. Checkpoints and M02 are not built.

From the repository root:

```bash
cargo run -p fragr-server --locked -- --bind 127.0.0.1:6767 --bots 0 --map-file server/maps/m01-recall-notice.json
```

Connect the ordinary client, agent or spectator to the same server. This mode
has no arcade timer, boss or map rotation. `--map-file` rejects arcade
map selection, Episode 0, rule overrides and rule bots. It is opt-in authoring
support, not the campaign menu's finished first mission.

## Document version 1

- `version`: exactly `1`; `map_id`: a stable integer at least `1000`, reserving
  the arcade roster; `name`: nonempty, at most 80 characters, no controls.
- `half_extent`: playable square radius, 2 through 256 metres. Base floor is
  zero. `ground`: a registered surface kit.
- `solids`: at most 2048 records with `id`, `min: [x,y,z]`, `max: [x,y,z]` and
  `surface`. Minimum bounds must precede maximum bounds; bottom cannot be negative.
  These become canonical finite collision volumes, including ceilings.
- `spawns`: 1 through 128 records with `id`, `feet: [x,y,z]` and `yaw` in radians
  from zero inclusive to one full turn exclusive. Positive Z faces `pi/2`.
- `landmarks`: 1 through 128 named `id` and `feet` records for route validation.
  Every spawn and landmark needs support, full standing clearance and a route
  from the first spawn. Names are shared across all records and must be unique
  lowercase ASCII letters, digits or underscores, at most 64 bytes.
- `equipment`: `discovery` or `full_arsenal` (default). Discovery begins with fists
  and requires client gameplay capability 2, independently of geometry capability.
- `supplies`: at most 128 records, allowed only with discovery. Each has unique
  `id`, supported and reachable `feet`, `claim` (`personal` or `contested`) and
  a strict `grant`: `{"kind":"weapon","weapon":"tack"}`,
  `{"kind":"ammo","pool":"darts","amount":30}`, or `health`/`armor` with
  `amount` from 1 through 100. Ammo amounts cannot exceed pool caps in `WEAPONS.md`.
  Fists cannot be a grant. Personal claims are only for weapons; each participant
  can claim each once per development life. Contested ammo has one winner and a
  ten-second respawn. An additional copy of an owned gun grants reserve without
  forcing selection. Discovery death resets inventory and personal claims.
- `encounters`: optional, discovery only. At most 32 groups, 64 enemies and 64
  entry regions in total. Each group has a unique `id`, nonempty `regions` and
  `enemies`, and optional `after` naming an earlier group. Each region is an
  inclusive feet-position box with finite ordered `min`/`max` bounds inside the
  map. Each enemy has a unique `id`, `kind` (`clerk` or `sweeper`), supported and
  reachable `feet`, and bounded `yaw`, just like a spawn. Unknown fields are
  rejected. No scripts or arbitrary behavior expressions. These maps require
  gameplay capability 3. See [actor semantics](../../docs/protocol.md#campaign-actor-identity).
- `mission`: optional, discovery only, requires capability 5, including party readiness. The registered
  `id` is `recall_notice`. `record` and `departure` each contain `panel` (the same
  authored decoration shape) and `approach` feet coordinates. The panel kinds
  must be `terminal` and `lift_control`, hosted on stationary solids. These panels
  are appended to the shared presentation; do not duplicate them in `decorations`.
  `gate` names one `solid` and a finite vertical `lift` from 0.125 through 16 metres.
  `boarding` is an ordered inclusive `min`/`max` box containing the departure
  approach. Both approaches must stand, see and reach their panels in both gate
  states. Record access must remain open; departure must be unreachable until the
  gate opens. Spawns remain accessible with it closed; other landmarks, supplies
  and enemy placements may be reachable after opening. Both immutable worlds and
  their navigation are validated before binding. No navigation is rebuilt on tick.

M01's Clerk enters around the inspection partition after safe weapon discovery.
The two Sweepers activate after that fight when a participant enters the intake
hall or reaches the upper flank. The records screen and deck conceal their
initial positions. Initial dispatch follows a fixed alarm location for up to
30 seconds; after seeing someone, pursuit remembers their last visible position
for five seconds. Hidden movement never updates that location. These are initial
tuning values. Animation and encounter review continue in
[the active plan](../../docs/plans/m01-intake-encounter.md).

Surface kits: `concrete`, `enamel`, `service_steel`, `records_tile`, `lift_panel`.
They select existing offline materials, never paths, URLs or shader code. The
wire presentation array preserves exactly the solid order. It affects appearance,
not geometry version or collision. Older presenters may use their default kit.

Optional `decorations` attaches thin cosmetic panels to solid faces. For example:

```json
{"solid":"bay_front_header","face":"north","center":[0,0],"size":[5.6,2.1],"kind":"property_sign"}
```

The authoring `solid` is a stable ID, resolved to a validated wire index. The
shared [wire contract](../../docs/protocol.md#mapinfo) defines six face axes,
registered kinds, finite dimensions, host bounds, 128-panel and eight-light limits.
Decorations alone do not add blocking geometry or interactive terminals. Mission
controls explicitly attach authority to their registered panels. Add a solid for
anything that should stop movement or shots. The client supplies original pixel
panels and keyed English text from `client/i18n/world.en.po`; no text, scripts or
resource paths can be embedded in the map.

Files are limited to 1 MiB before parsing. Unknown fields and unsupported versions
are errors. Geometry and navigation budgets are checked before the server binds.
Errors report the reason or parser location without printing file contents.

The source path is never sent to clients. `MapInfo` supplies the validated geometry
and materials. Reloading a map means restarting the host; live content reload and
campaign saves have no implemented contract yet.

## Verification

```bash
cargo test -p fragr-server maps::authored --locked
cargo test -p fragr-server --test authored_maps --locked
FRAGR_QA_BOTS=0 FRAGR_QA_MAP_FILE="$PWD/server/maps/m01-recall-notice.json" FRAGR_QA_MANIFEST=res://qa/m01.json bash tools/qa_tour.sh .agents/qa/m01
FRAGR_QA_BOTS=0 FRAGR_QA_MAP_FILE="$PWD/server/maps/m01-recall-notice.json" FRAGR_QA_MANIFEST=res://qa/m01-discovery.json bash tools/qa_tour.sh .agents/qa/m01-discovery
FRAGR_QA_BOTS=0 FRAGR_QA_MAP_FILE="$PWD/server/maps/m01-recall-notice.json" FRAGR_QA_MANIFEST=res://qa/m01-encounters.json bash tools/qa_tour.sh .agents/qa/m01-encounters
FRAGR_QA_BOTS=0 FRAGR_QA_MAP_FILE="$PWD/server/maps/m01-recall-notice.json" FRAGR_QA_MANIFEST=res://qa/m01-maintenance.json bash tools/qa_tour.sh .agents/qa/m01-maintenance
FRAGR_QA_BOTS=0 FRAGR_QA_MAP_FILE="$PWD/server/maps/m01-recall-notice.json" FRAGR_QA_MANIFEST=res://qa/m01-facility.json bash tools/qa_tour.sh .agents/qa/m01-facility
```

The tour uses human input through a live server, never teleportation. Inspect
all rooms, movement samples and combat sheets. The encounter tour deliberately
observes one Clerk shot before returning fire. The combat driver filters allies,
dead bodies and occluded targets, and fails if the participant dies. Its perfect
aim is a regression tool, not evidence of human difficulty. Set
`FRAGR_RENDER_DRIVER=vulkan` for the second renderer. Do not use `--publish` with
these specialized manifests. The full release
tour remains a separate check. Story and room purposes belong to
[`docs/campaign/m01-recall-notice.md`](../../docs/campaign/m01-recall-notice.md).
