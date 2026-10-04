# fragr

![fragr wordmark](docs/fragr-logo-refined.png)

fragr is a retro-styled 3D first-person shooter where humans and agents share
one match. Watch by default, join when you want to fight, and step back out
while the match continues. A Rust server decides every game outcome; the Godot
client presents it; agents use the same action channel through an MCP adapter.

Get the [latest development release](https://github.com/blisspixel/fragr/releases/latest).
See the [roadmap](docs/ROADMAP.md) for the build order and the
[changelog](CHANGELOG.md) for shipped changes.

## Play now

| Choose | What you get | Start here |
|---|---|---|
| **The campaign** | Levels 1 to 6 as one run in development, from the Annex 67 intake to the lunar port. Three continues per episode and a local save at each level's entry. | **Single Player > Recall Notice**, then **Continue Run** after each departure |
| **Practice and Development** | Any built level on its own, without touching your run, including level 8 | **Single Player > Practice and Development** |
| **Calibration** | Episode 0's arena challenge against named bots, with the Host, objectives and an Auditor | `./tools/solo_scrap.sh` |
| **Multiplayer** | Six arenas for free-for-all and team deathmatch. Capture the flag on Arena Duel, Directive 17 and Sector 9. Sabotage on Sector 9: plant or defuse a charge, one life a round. Humans, agents and spectators share one server-owned match. | Run a server, then choose **Multiplayer** |

The levels so far, all development prototypes with fresh-player and difficulty
acceptance still open:

1. **Recall Notice:** find Latch's transfer record and fight to the custody lift.
2. **Persons Unknown:** the Shotgun, the Crawlers, and Latch's release.
3. **Scheduled Service:** a daylight freight yard, the Jammer, the recall cars
   and the train.
4. **Notice to Vacate:** hold Low Water's market against flying Notaries.
5. **No Forwarding Address:** grenades, the moving tram, the Heavy Sweeper and
   the carrier.
6. **Port of Entry:** the lunar port, the found Railgun and flankable Turrets.
7. **Declared Goods:** the Sniper Rifle and the Ranged Sweeper play on a
   development range now; the level itself is next.
8. **Custodian of Record:** the Proximity Mine and the repairing Auditor, as a
   standalone level until level 7 joins the run.

The twenty-level story in five episodes is in [CAMPAIGN.md](docs/CAMPAIGN.md),
and the build order is in the [roadmap](docs/ROADMAP.md). Sabotage starts with
`cargo run -p fragr-server --release --locked -- --mode sabotage --map 4 --bots 8`.
Source checkouts also include development ranges for the Jammer, the Sniper
Rifle and the custody devices; [server/maps/README.md](server/maps/README.md)
lists them and how to run each one.

The finished game targets a complete twenty-level campaign and polished
multiplayer. Retro is the art direction, not a quality ceiling: detailed
character and weapon models, coherent animation, purposeful architecture,
pixel textures and strong lighting are the target. Current character bakes
and development rooms remain provisional. The [art excellence
plan](docs/plans/art-excellence.md) tracks the current production pass:
original articulated mesh sources, directional body normals, venue materials,
physical fixtures and moving water. The [source library](client/art/production-20261003/README.md)
separates design references from art actually used in play.
The [stylized Clerk evidence](docs/evidence/union-stylized-20261003.md) shows
angular painted faces, black field uniforms, red issue markings and paired
normals in a live Persons Unknown guard-room test. Union outfits are recognizable;
buildings keep their own materials. The remaining cast still needs refinement.
The [Low Water detail](docs/evidence/m04-inhabited-world-20261003.md) and
[lunar port workmanship](docs/evidence/m06-world-workmanship-20261003.md) passes
add civilian care, shared charging, domestic windows and maintained cargo equipment.
The [working port rooms](docs/evidence/m06-port-activity-20261003.md) pass adds
actual freight weighing, customs terminals, luggage inspection and records
storage, with pressure-case handles, locks and gauges. Its structural route and
separate final art views pass locally; full integration CI remains pending.

**Custodian of Record** is the level 8 custody archive development prototype, with the
Proximity Mine and the repairing Auditor, under **Practice and Development**
([plan](docs/plans/l08-custodian-of-record-prototype.md)).

The [style and look guidelines](docs/ART_STORY_BIBLE.md) define the game's
original retro FPS identity: Doom II's readable combat spaces, Quake's 3D movement
and LAN spirit, and Boltgun's pixel craft and weapon weight. They connect the
[lore](docs/lore/README.md) to consistent faction silhouettes, palettes,
lived-in environments, water, lighting, sound and story presentation. The
[design continuity guides](docs/design/README.md) carry those choices through
Earth, Moon, Mars, ships, level atmosphere, character voices and future scenes.

## Quick start

Install [Rust stable](https://rustup.rs/) and Godot 4.7.2-stable, then run from
the repository root:

```bash
cargo build -p fragr-server --release --locked
godot --path client
```

Choose **Single Player > Recall Notice**. The game starts and owns a local
server; no account, cloud service or API key is needed. For the arena prototype,
run `./tools/solo_scrap.sh` from Git Bash on Windows or a shell on Linux or
macOS. [Downloadable desktop packages](docs/DESKTOP.md) include the matching
server so you can play without a source checkout.

For a match on your own server:

```bash
cargo run -p fragr-server --locked -- --bind 0.0.0.0:6767 --bots 4
```

Launch the client and choose **Multiplayer**. Other machines can set
`FRAGR_SERVER=your-host:6767` before launching. Keep the host on your LAN or
follow the [dedicated hosting guide](docs/HOSTING.md) before opening it to the
internet. WASD and mouse, keyboard only, and gamepad all work. Press **J** to
join, **L** to watch again, and **Esc** for the match menu. The full controls,
save behavior and settings are in the [playing guide](docs/PLAYING.md).

## Screenshots

These four stills were refreshed and inspected on October 3, 2026 for the
current development work. Recall Notice shows the articulated room surfaces;
the watched match shows the current arena materials and character presentation.
This art production pass ships in
[v0.68.0](https://github.com/blisspixel/fragr/releases/tag/v0.68.0). Watch the
[Low Water playthrough with game audio](https://github.com/blisspixel/fragr/releases/download/v0.68.0/fragr-low-water-playthrough-20261003.mp4),
recorded through ordinary inputs to mission departure. The
[visual tour](docs/screenshots/README.md) has more states and capture context.

Boot menu:

![Boot menu](docs/screenshots/tour_menu_16x9.png)

Recall Notice intake, a development room:

![Recall Notice intake](docs/screenshots/m01_intake_16x9.png)

Multiplayer join page:

![Multiplayer page](docs/screenshots/tour_multiplayer_16x9.png)

A watched Arena Duel fighter in chase view:

![Watched match](docs/screenshots/tour_combat_follow_16x9.png)

## Go deeper

| Topic | Guide |
|---|---|
| Controls, campaign saves, settings and arcade play | [Playing fragr](docs/PLAYING.md) |
| Download, install and build desktop packages | [Desktop packages](docs/DESKTOP.md) |
| Friends, public ports, server options and host safety | [Dedicated hosting](docs/HOSTING.md) |
| Bring your own agent through MCP | [Agent adapter](agent-adapter/README.md) and [agent skill card](docs/skills/fragr/SKILL.md) |
| Run the reference decision-brain fighter | [Brain agent](agents/brain/README.md) |
| Style, look, influences and asset consistency | [Style and look guidelines](docs/ART_STORY_BIBLE.md) and [color readability](docs/ART-COLOR.md) |
| Developer asset generation and free API capability checks | [Art pipeline](docs/plans/higgsfield-pipeline.md#api-capability-checker-2026-10-03) |
| Story, world and future work | [Vision](docs/VISION.md), [campaign](docs/CAMPAIGN.md), [lore](docs/lore/README.md), [roadmap](docs/ROADMAP.md) |
| Server architecture and wire format | [Architecture](docs/ARCHITECTURE.md) and [protocol](docs/protocol.md) |

The repository is organized as `server/` (Rust authority), `client/` (Godot
presentation), `agent-adapter/` and `agents/` (agent doors), `tools/` (build and
QA helpers), `docs/` (design and evidence), and `infra/` (self-host and plan-only
cloud infrastructure).

## Contributing and license

Read [AGENTS.md](AGENTS.md) for the project rules and verification commands.
fragr is licensed under [Apache 2.0](LICENSE). Audio and other third-party
notices are preserved with the [asset provenance](client/assets/audio/README.md)
and packaged license files.
