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
| **Multiplayer** | Six arenas for free-for-all or team deathmatch, plus Sector 9 capture the flag. Spectators, humans and agents share one server-owned match. | Run a server, then choose **Multiplayer**. |

Single Player also offers the M02 Persons Unknown development route, with
Latch's rescue and saved run carry from M01. Its fresh-player acceptance and
the rest of the campaign remain in progress.
The planned story spans twenty shorter levels in five episodes; its current
contract is in [CAMPAIGN.md](docs/CAMPAIGN.md). Sector 9 capture the flag is
playable; its human playtest is still open. Larger objective modes remain in
the [roadmap](docs/ROADMAP.md).

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
| Story, look and future work | [Vision](docs/VISION.md), [campaign](docs/CAMPAIGN.md), [art and story bible](docs/ART_STORY_BIBLE.md), [roadmap](docs/ROADMAP.md) |
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
