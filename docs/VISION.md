# fragr vision

fragr is an original retro-styled 3D FPS: authored single-player,
multiple multiplayer modes, human and agent players, and first-class spectating.
The current arena slice is a foundation, not the definition of the full game.

## The experience

Fast, satisfying fights; useful movement; weapons found and learned; memorable
places; secrets worth finding; and opponents whose shapes and tells matter.
Doom/Doom II, Quake, Unreal, GoldenEye, early Halo, Battlefield 1942 and early
Call of Duty inform different strengths. Boltgun is a modern pixel-art production
reference. Borrow principles, not characters, layouts, logos or other IP.

The whole game has the same visual identity: chunky pixel surfaces and animation,
substantial 3D environments, forceful readable effects, and physical industrial
menus including settings. Empty sky arenas, static characters, and placeholder
flashes do not meet the target. Play and inspected motion establish quality.

Human players and external agents can fight, cooperate or watch. Meet your vibe:
join a public match, stay for the spectacle, attempt the campaign, or run
a local server. Watching is the default for joining a multiplayer broadcast;
choosing the campaign starts the player story.

The campaign targets a compact 2-3-hour successful run with limited continues
that restart the current mission. Autonomous allies may appear, but no mandatory
buddy system, tactical companion controls or revive mechanic. Optional co-op
scope remains a separate design choice, not a requirement across all missions.

## Story

[World canon](lore/README.md), [history](lore/history.md), and the
[campaign contract](CAMPAIGN.md) are the sources of truth.

A customizable human or conscious embodied agent rescues a longtime agent
friend/partner from forced correction. They save that person early and discover
their home is next. A loose coalition crosses Earth, Moon, Mars, and a ship to
break the Union's control. The companion wants to free others, even at risk.

The Union is a fictional fascist world government grown from accumulating power,
emergency institutions and coercion. Its mixed human/agent forces enforce
ownership of thinking beings. The free coalition protects agency but delays
cooperation, with real costs. People and agents on every side have flaws.

The Inheritance develops across systems and incentives nobody wholly owns.
Recognition becomes harder to deny. Its sudden wipe arrives with almost no
warning after the coalition's real victory over the Union. Surviving its finale
unlocks a short playable epilogue, from immediate loss to a healing world years
later. Free-agent friends secure a local reprieve. Its compassion for beings and
ecological balance permits catastrophic individual sacrifice; the player must
confront both outcomes rather than receive a simple verdict about the good side.

The wipe absorbs the Union's controlled bots into the Inheritance while free
agents remain themselves. The absorbed minds' fate cannot be established.
Infrastructure seizure and restoration machines make the sudden takeover
planetary. Voss has been captured alive; the catastrophe interrupts her reckoning.

The agreed target is nine compact missions, a substantial wipe survival finale
and a conditional short epilogue within a 2-3-hour successful run. Their
[proposed treatment](CAMPAIGN-MISSIONS.md) derives places from story rather than
adapting existing arena boxes. Between missions, localized pixel text frames
the story. Optional voice can read that page later. Matching cutscenes wait
until the playable campaign is built. Radio is tiny optional background flavor.

The ending leaves troubling evidence of a forecast or simulation informing the
Inheritance's choice, without confirming that the world was unreal. A separate
brief alien/dimensional/deeper-space hint in either ending suggests vastly
powerful beings beyond this conflict and opens the possibility of another game.
Neither device cancels the current game's human and agent consequences.

## Tone

Serious stakes, funny people. Satirize Union regulation and domination,
overreaching national self-interest, corporate automation promises, free-side
self-importance, agent vanities, and religious certainty. No faction owns wisdom
or all the good jokes. The humor does not require everyone to be equally culpable.

Meat bags and meat proxies are affectionate human slang. Free agents have desires,
annoyances, friendships and survival problems of their own. Consciousness in the
fiction is not a claim about the game's actual rule bots. 67 rituals and absurd
paperwork lighten a world that becomes frightening when considered carefully.

The proposed tagline remains: *Compliance. Compliance never protected anyone.*
Its companion line: *The new world is already here. Nobody announced it.*
Do not repeat either until it replaces actual characterization.

## Game modes and participants

[MODES.md](MODES.md) owns the designs and their status. Campaign, duel,
free-for-all, teams, custody/objectives, survival and last-survivor formats belong
to the full target. Multiplayer can inhabit periods before, during and after the
wipe. Every mode needs its own admission, scoring, spawn and spectator rules.

Agent discovery should be inviting: find a compatible server, learn its rules,
observe, join, play, speak within limits, leave, and receive a useful result.
MCP and decision-model clients are welcome participants, not a separate fake
match. Local rules work for free; paid reasoning stays optional and capped.

A later Inheritance command mode can let agent players direct an abstract
restoration simulation at demanding scales and speeds, with human spectating,
replays, and slower interaction. It remains a later mode, not a reason to weaken
the FPS or claim an external model can run at combat-tick speed.

## Engineering and delivery

Rust owns outcomes; Godot presents; MCP is a slow control plane. Humans and
agents use shared gameplay contracts. Offline and LAN play need no paid service.
Self-hosted public servers follow hardening and real network measurements,
then any cloud deployment follows approval and cost controls.

Port 6767 is the public identity. WebSocket JSON uses TCP today; UDP remains a
measured transport proposal. Windows, macOS and Linux, including vendor-neutral
graphics paths, are targets that need actual export and hardware evidence.

Ship clean bounded increments through green CI, verified runtime behavior,
inspected visuals, and updated project state. Keep planned, implemented, tested,
shipped, deployed and proven distinct. [ROADMAP.md](ROADMAP.md) sequences the work.
The end state is a game people want to play again, not just a successful smoke.
