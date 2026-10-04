# Contributing to fragr

Start with [README.md](README.md), [AGENTS.md](AGENTS.md) and the Full build
order in [docs/ROADMAP.md](docs/ROADMAP.md). Local play and checks require no
paid account. Rust owns authoritative gameplay; Godot presents it.

Open an issue with a concrete problem, reproduction or map idea. Keep changes
on a bounded branch, explain the resulting behavior and record appropriate
verification in the pull request. Follow repository identity and prose rules.
Preserve third-party licenses and notices.

Campaign maps use the strict schemas in
[server/maps/README.md](server/maps/README.md) and agreed mission briefs.
Multiplayer arenas currently use Rust definitions in `server/src/maps/` and
registration in `server/src/maps.rs`. Client presentation consumes MapInfo;
decorative assets must not silently add blocking collision. No drag-and-drop
multiplayer map loader or workshop is shipped.

Read the [art/story bible](docs/ART_STORY_BIBLE.md) and
[map research](docs/plans/competitive-and-community.md#original-maps-and-references).
Include supported spawns, supply/objective access, clear landmarks and useful
alternate routes. Show ordinary-input playtest evidence and preserve failures
rather than weakening assertions. A screenshot alone does not prove fun.

Run focused checks, then the required verification in AGENTS.md. Keep
diagnostics under ignored `.agents/`; never publish credentials. Asset APIs
are developer-only and use existing budget gates, never CI or player runtime.

Use README commands and the [home/LAN guide](infra/docs/HOME-LAN.md) to host.
Humans, agents and spectators share the server. Temporary host bans are
documented in [fair play](docs/plans/fair-play.md). Cloud and paid services
require separate cost authorization. The project uses [Apache 2.0](LICENSE);
packaged dependencies retain their required legal notices.
