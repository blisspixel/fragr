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
| **Recall Notice** | The first campaign mission in development: enter Annex 67, find Latch's transfer record, fight to the custody lift. Solo runs have three mission-start continues and a local save at mission entry. | **Single Player > Recall Notice** |
| **Calibration** | Episode 0's arena challenge against named bots, with the Host, objectives and an Auditor. | `./tools/solo_scrap.sh` |
| **Multiplayer** | Six arenas for free-for-all or team deathmatch. Arena Duel, Directive 17 and Sector 9 also play capture the flag. Spectators, humans and agents share one server-owned match. | Run a server, then choose **Multiplayer**. |

Single Player also offers the M02 Persons Unknown development route, with
Latch's rescue and saved run carry from M01. Its fresh-player acceptance and
the rest of the campaign remain in progress.
The planned story spans twenty shorter levels in five episodes; its current
contract is in [CAMPAIGN.md](docs/CAMPAIGN.md). Capture the flag is playable on
Arena Duel, Directive 17 and Sector 9; its human playtest is still open.
Larger objective modes remain in the [roadmap](docs/ROADMAP.md).

Source checkouts also include a [Jammer development range](server/maps/README.md)
for the next campaign enemy: a folding transmitter with slow pulses you can
sidestep, interrupt or block with cover. Run `cargo run -p fragr-server --locked
-- --bots 0 --map-file server/maps/test/jammer-range.json`, then connect through
Multiplayer. This range has no campaign save or mission departure.

In the current source checkout, **Scheduled Service** is the level 3 development prototype under **Single
Player > Practice and Development**. Fight through a daylight freight yard,
free optional recall cars, shoot
the guarded transmitter pod and deliberately board the train. A completed M02
run can continue into it with its existing equipment and remaining continues.
Its authored route and automated evidence remain separate from fresh-player
acceptance and final mission polish. See the [prototype plan](docs/plans/m03-scheduled-service-prototype.md).

The source checkout's **Notice to Vacate** adds the level 4 prototype in Low Water: defend the market,
bring down flying Notaries, open the optional clinic shutter and leave through
the habitation court's roof stair. **Continue Run** carries a completed M03 run
into M04 with its body, equipment, health, armor, remaining continues and recall
car choices. Its separate **Practice and Development** entry preserves your
campaign save. Completing M04 retains the run for **No Forwarding Address**.
Compatible historical v2, v3, v4 and v5 saves explicitly upgrade to v6
on resume, with their exact prior bytes archived. This is an implemented
development prototype, with fresh-player acceptance still open. See the
[M04 plan](docs/plans/m04-notice-to-vacate-prototype.md) and
[save behavior](docs/PLAYING.md#solo-runs-and-local-records).

**No Forwarding Address**, the level 5 prototype, continues across Low Water's
roofs, workshop, tram trench and freight platform. Counted hand grenades bounce
on server-owned geometry and explode on a fixed fuse. Free Splice and the
workshop captives, take the moving tram or walk its service aisle, then confront
the Heavy Sweeper and board the carrier. Earlier recall-car, clinic and photograph
choices carry into M05 and its retries. Departure records released workers
separately from those physically aboard and leaves the run pending the unbuilt
lunar **Port of Entry**. Fresh-player and difficulty acceptance remain open.
See the [M05 plan](docs/plans/m05-no-forwarding-address-prototype.md).

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

These four stills show the current development build. The
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
