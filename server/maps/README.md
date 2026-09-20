# Authored development maps

`m01-recall-notice.json` contains the opening mission's connected blockout and
weapon discovery. Its two routes, stairs, balcony, office and lift use normal
movement. Enter with fists, find Tack and Flechette, collect ammunition and reload.
Encounters, interaction, extraction and checkpoints are not implemented here.
Do not present a successful route or reload as campaign completion.

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

The loader and server support encounter definitions. The committed M01 map still
contains traversal and equipment only while its encounter placement, animation
and live-play proof are in progress in [the active plan](../../docs/plans/m01-intake-encounter.md).

Surface kits: `concrete`, `enamel`, `service_steel`, `records_tile`, `lift_panel`.
They select existing offline materials, never paths, URLs or shader code. The
wire presentation array preserves exactly the solid order. It affects appearance,
not geometry version or collision. Older presenters may use their default kit.

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
```

The tour uses human input through a live server, never teleportation. Inspect
all rooms and movement samples. Set `FRAGR_RENDER_DRIVER=vulkan` for the second
renderer. Do not use `--publish` with this specialized manifest. The full release
tour remains a separate check. Story and room purposes belong to
[`docs/campaign/m01-recall-notice.md`](../../docs/campaign/m01-recall-notice.md).
