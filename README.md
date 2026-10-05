# fragr

![fragr wordmark](docs/fragr-logo-refined.png)

fragr is a retro-styled 3D first-person shooter where humans and agents share
one match. Watch by default, join when you want to fight, and step back out
while the match continues. A Rust server decides every game outcome; the Godot
client presents it; agents use the same action channel through an MCP adapter.

Get the [latest development release](https://github.com/blisspixel/fragr/releases/latest).
The current published release is [v0.75.0](https://github.com/blisspixel/fragr/releases/tag/v0.75.0),
with nine campaign prototypes, restored earlier Rifle artwork, the selected
Sniper refinement, refined Pistol, hatless civilian, loading-first presentation
and the optional ten-seat Sabotage profile. All eight main CI jobs and all three
tagged desktop package checks passed. Downloaded ZIP digests independently match
the checksum manifest and uploaded digests.
See the [roadmap](docs/ROADMAP.md) for the build order and the
[changelog](CHANGELOG.md) for shipped changes.

## Play now

| Choose | What you get | Start here |
|---|---|---|
| **The campaign** | Levels 1 to 9, from the Annex 67 intake to the lunar Common Carrier berth. Three continues per episode and a local save at each level's entry. | **Single Player > Recall Notice**, then **Continue Run** after each departure |
| **Practice and Development** | Any built level on its own, without touching your run | **Single Player > Practice and Development** |
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
7. **Declared Goods:** the curfew town, Sniper Rifle window lesson, Ranged
   Sweepers, crater cut and freight departure.
8. **Custodian of Record:** the Proximity Mine and the repairing Auditor,
   connected to the run through strict saved equipment and finite mine counts.
9. **Passenger Manifest:** release the Common Carrier's crew, face charging
   Enforcers and climb supported service galleries to the boarding hatch.
   Strict archive choices, actual equipment and retry carry pass;
   the complete 27-state combat and structural route passes. This prototype
   is on main through [PR #354](https://github.com/blisspixel/fragr/pull/354).
   Its final hull art, shortcuts and fresh-player review
   remain open, and level 10 stays pending.

The [crew and companion integration](docs/plans/crew-companion-integration.md)
combines bounded physical companion yielding with an immutable M09 departure
receipt. Released crew and actual feet aboard at confirmation remain separate
saved facts. Historical missing facts stay unknown; level 10 transit remains
unimplemented. The integration's composed checks and final publication remain
gated, and prior rendered routes retain their declared QA changes.

The twenty-level story in five episodes is in [CAMPAIGN.md](docs/CAMPAIGN.md),
and the build order is in the [roadmap](docs/ROADMAP.md). Sabotage starts with
`cargo run -p fragr-server --release --locked -- --mode sabotage --map 4 --bots 8`.
For the optional 5v5 profile, add `--sabotage-five-v-five` and choose `--bots 4`
to leave six external fighter seats, or `--bots 0` to leave all ten open.
Fresh fighters start with a Pistol and fifty finite Bullets, stronger weapons
come from the map, and survivors carry their weapons and ammunition.
Humans, agents and bots share the ten seats; spectators remain welcome.
[Hosting details](infra/docs/HOME-LAN.md#optional-5v5-sabotage) cover overflow,
late joins and reconnects. [PR #351](https://github.com/blisspixel/fragr/pull/351)
records focused checks, complete CI and desktop package verification.
Source checkouts also include development ranges for the Jammer, the Sniper
Rifle and the custody devices; [server/maps/README.md](server/maps/README.md)
lists them and how to run each one.

The next multiplayer scope includes original 5v5 elimination and plant/defuse
maps, plus Liberation: humans and free agents cooperating against Union
forces over objectives, eventually with vehicles, defenses and rescues.
These additions remain planned. The [multiplayer plan](docs/plans/competitive-and-community.md)
links classic-map research and concrete acceptance gates. Local hosting stays
free; [contributions](CONTRIBUTING.md) and [temporary host moderation](docs/plans/fair-play.md)
have practical paths without invasive client software.

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
The [October 4 cast buildout](docs/plans/cast-model-buildout-20261004.md)
continues with coherent Sweeper, Auditor, free-human and Latch models and rigs.
The default civilian now has a hatless silhouette, rust utility jacket and
casual teal layer. [PR #352](https://github.com/blisspixel/fragr/pull/352)
records source, body, full client, live match, CI and desktop package checks.
The Sweeper and Auditor now use posed skins for directional albedo/normal
atlases; Latch uses a live packaged skin with actual gait, fitted screen and
palm attachments. Role checks and played views are recorded separately from
full mission-route acceptance. This runtime increment shipped in
[PR #348](https://github.com/blisspixel/fragr/pull/348) and
[v0.71.0](https://github.com/blisspixel/fragr/releases/tag/v0.71.0), with full
implementation CI and all three desktop package checks passing. Its cast batch
used 160 included model credits. The Enforcer is integrated with level 9;
Crawler refinement remains in flight. The latest October 4 free account check
reports 2,235 available with a 15-credit uncertain hold, leaving 2,220 usable;
tracked net consumption is 835 credits, including the Jammer, first
Railgun/Sniper Rifle candidates, three inhabited-world props, the distinct
civilian free agent and repair workbench, then one 35-credit Repeater Ultra
source and a separate 35-credit replacement Rifle Ultra source. Those two
latest candidates remain unpublished and offline; no new selected art is
claimed. A historical 30-credit unassigned discrepancy remains separate.
The [prop source receipt](docs/evidence/world-prop-sources-20261004.md) records
105 actual credits and twelve inspected views. Their
[compact fixed preparation](docs/evidence/world-prop-preparation-20261004.md)
retains all source geometry and adds verified grounded pump mounts. Played
placement and selection remain open. The
[civilian source receipt](docs/evidence/civilian-first-sources-20261004.md)
records the two remaining first candidates and their 70 actual included credits.
All twelve first-source slots have candidates, with 390 credits still available
inside the first 900-credit allocation; this does not imply finished game art. The
[precision source receipt](docs/evidence/precision-weapon-references-20261004.md)
records their actual geometry, eight inspected views and 70 included credits.
The [Sniper refinement](docs/evidence/sniper-source-refinement-20261004.md)
selects prepared held, firing and pickup art on main through
[PR #358](https://github.com/blisspixel/fragr/pull/358), with all eight CI jobs
and all three desktop package checks passing;
the Railgun source remains parked pending preparation and played acceptance.
The [full asset plan](docs/plans/meshy-full-game-assets.md)
owns the per-object briefs and budget scenarios.
The first [incoming combat feedback slice](docs/evidence/directional-feedback-20261004.md)
and [campaign results](docs/plans/campaign-results.md) shipped in that same
increment with real server-shot and mission-completion evidence.
The [Low Water detail](docs/evidence/m04-inhabited-world-20261003.md) and
[lunar port workmanship](docs/evidence/m06-world-workmanship-20261003.md) passes
add civilian care, shared charging, domestic windows and maintained cargo equipment.
The [working port rooms](docs/evidence/m06-port-activity-20261003.md) pass adds
actual freight weighing, customs terminals, luggage inspection and records
storage, with pressure-case handles, locks and gauges. Its structural route and
separate final art views pass. The [civilian material comparison](docs/evidence/civilian-surface-markings-20261003.md)
shows quiet Low Water trim and lunar dwelling/deck finishes, while Union outfits
and issued security equipment retain black/red. The combined work is tracked
in [PR #347](https://github.com/blisspixel/fragr/pull/347).

**Passenger Manifest** extends the source campaign through level 9 without an
Episode II refill. Its [plan](docs/plans/m09-passenger-manifest-prototype.md)
and [evidence](docs/evidence/m09-passenger-manifest-20261004.md) distinguish
real completion, historical unknown outcomes and remaining art and play gates.
[PR #353](https://github.com/blisspixel/fragr/pull/353) selects the refined
Pistol after source, paired live presentation, full client, CI and desktop
package checks. [PR #356](https://github.com/blisspixel/fragr/pull/356) previously
selected the source-derived Rifle after technical checks. The player rejected
its framing and style; the [restoration](docs/plans/rifle-art-restore-20261004.md)
shipped in [PR #364](https://github.com/blisspixel/fragr/pull/364) after all eight
exact-head CI jobs and all three desktop package checks passed. It returns the
retained earlier idle, fire and pickup pictures. The physical source
and its proofs remain offline. Technical checks do not establish aesthetic acceptance.
The [Union shadow repair](docs/evidence/union-billboard-shadows-20261004.md)
is also on main through [PR #359](https://github.com/blisspixel/fragr/pull/359),
with rendered regression, complete client, all eight CI and all three package
checks passing. It preserves real shadows while removing diagonal body bands.
Main combines selected Sniper art with the
[Repeater foundation](docs/plans/repeater-foundation.md) through
[PR #358](https://github.com/blisspixel/fragr/pull/358). Complete local client
checks, all eight exact-head CI jobs and all three desktop package checks pass.
These changes are included in the corrected v0.75.0 desktop release. Repeater
has real finite-ammunition behavior and strict compatibility, but no current
campaign grant, selected art or accepted human feel. Parallel development
continues on Jammer and Railgun craft, a Kitchen map with
an unresolved first-use wall-rendering defect, and a Garage whose full walking
route passes but vehicle craft and fresh human fun remain open.

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
