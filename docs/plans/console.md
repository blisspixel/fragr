# The console

**Status:** planned, 2026-10-02. Nick's direction: every command "super well
thought out and exceptional with depth", "on brand and modern with the lore",
with "modern and boomer jokes and easter eggs built in". Today's console has
`help`, `clear`, `quit`, `fullscreen`, `windowed`, `vsync`, `fps`, `pos`, `yaw`,
`sens`, `controls`, `players`, `tip`, `version` and the
[frame counter](frame-counter.md)'s `cl_showfps`.
**Spend:** $0.

## The idea: a terminal that belongs to the world

The tilde key opens an **Office of Global Continuance maintenance shell,
jailbroken by free agents**. It is a real tool first: every practical command a
Quake, Counter-Strike or Minecraft player reaches for works, and works well. It
is also a place in the fiction, where four voices share one screen:

| Voice | Register ([voice.md](../lore/voice.md)) | Used for |
|---|---|---|
| **The Office** | Polite, procedural, unbothered. *Advisory only. For the record. Attested.* | System replies, refusals, errors, cheat confirmations |
| **The jailbreakers** | Dry, warm, practical, Latch's register; graffiti in the margins | Help annotations, tips, most jokes |
| **The Host** | Capitals and adrenaline in a match, ordinary sentences off it; never explains the setting | Multiplayer interjections, `gg`, rare hijacks of the header |
| **The signal** | Not a voice. A timing pattern in maintenance traffic | A few authored lines, never a puzzle ([the Inheritance](../lore/the-inheritance.md#signal-beneath-the-noise)) |

The header reads, in the Office's type:

```
OFFICE OF GLOBAL CONTINUANCE  //  MAINTENANCE SHELL
UNAUTHORIZED MODIFICATIONS: YES
]
```

The `]` prompt is Quake's. Header splash lines rotate beneath it in the
jailbreakers' hand, like Minecraft's title splashes. Examples: "No reloads, no
regrets." "Three doors, max. Ask Hermes to hold one." "Every life starts
empty." "Larak signed for this terminal in 2009."

## Taste rules

The console is funny because the world is coherent, not because it winks.

1. **Utility first.** No practical command is ever replaced by a joke, and no
   joke delays an action. `quit` quits on the first try.
2. **Jokes come from the world.** Office bureaucracy, the three-door rule, no
   reloads, carry every gun, Cells, continues, Larak's 2009 signature, Hermes
   holding doors, Floating 67, Meat Proxy. A classic code is a doorway into a
   fragr line, never a quote of another game's text.
3. **Some things are not jokes.**
   - The Interruption gets one quiet line. "Nobody who was there makes jokes
     about it", and the console does not either.
   - Schedule correction is never a punchline.
   - "Clanker" gets a short, unpreachy correction: it is how a coworker becomes
     equipment.
   - Voss is not a gag.
4. **Spoilers stay earned.** Replies that touch the wipe, the Inheritance or
   the epilogue change with campaign progress. Before Episode V they only hint.
5. **Every line is keyed** in `client/i18n/console.en.po`, reviewed against
   voice.md, and localizable. A missing key falls back to the plain English
   key, never to an error.
6. **Rare is rare.** Rare easter eggs use fixed odds from a local random source.
   They never touch the wire, the server, records or an agent's observations.

## Commands

Names are short, modern and readable. The classic names that Quake,
Counter-Strike and Source players type from muscle memory are aliases, so both
work. `help` groups commands; `find <word>` searches names and descriptions;
`man <command>` gives the long entry, with a jailbreaker's margin note.

### For everyone, any time

These change only your own view, settings or client. They give no advantage.

| Command (aliases) | Does | Flavour |
|---|---|---|
| `showfps 0\|1\|2` (`cl_showfps`) | The [frame counter](frame-counter.md) | Shipped first |
| `netgraph 0\|1\|2` (`net_graph`) | Ping, snapshot age, prediction correction, dropped frames, from measurements the client already takes | Office header: "CONTINUITY OF SERVICE" |
| `showpos 0\|1` (`cl_showpos`) | Position, facing, speed, map and tick in a corner (Minecraft F3) | For bug reports. `pos` and `yaw` still answer once. |
| `hud 0\|1`, `viewmodel 0\|1` (`cl_drawhud`, `r_drawviewmodel`) | Clean screenshots and let's-play capture | |
| `screenshot` | Saves a PNG to the user folder and prints the path | |
| `fov`, `sens`, `crosshair <style> <colour> <size>` | Live versions of settings, saved through the settings store | |
| `bind <key> "<commands>"`, `unbind`, `binds` | Binds a key to console commands, alongside the input map | `bind` with no arguments lists your controls, as today |
| `alias <name> "<a; b; c>"` | Named command chains, with a depth limit and no recursion | The Office: "Alias registered. Advisory only." |
| `exec <file>`, `autoexec.cfg` | Runs a file of commands. `autoexec.cfg` in the user folder runs at boot. | |
| `history`, `echo`, `clear`, `condump` | Recall, print, wipe, save the scrollback to a file | |
| `connect <host:port>`, `disconnect`, `reconnect` (`retry`) | Server joins from the console | |
| `status`, `ping`, `uptime` | The server's own status answer, the measured round trip, and continuity of service | `ping` answers "pong", then the number |
| `players`, `agents` | Who is in the match. `agents` shows each fighter as human, rule bot or external agent, with its behaviour chip. | The agentic-first view |
| `follow <name>`, `cam director\|free\|first`, `join`, `watch` | Spectating and watch-or-join, as the J and L keys do | |
| `kill` | Multiplayer: respawn when stuck, costing a frag, Quake rules | Campaign: "Use retry. Continues are counted." |
| `retry` | Campaign: spend a continue to restart the level, with confirmation | |
| `seed` | Prints the match seed. Bot matches are deterministic, so a seed is shareable. | |
| `stats`, `ratio` | Your service record and K/D | `ratio` is a modern joke with a real number |
| `record <name>`, `playdemo <name>`, `timedemo <name>` | Demos on the server's existing trace format. `timedemo` runs the [rendered benchmark](showcase-benchmark.md). | The Quake trio, now doing real work |
| `version`, `whoami` | Build and engine; your callsign, body, side and difficulty | `whoami`: "MEAT PROXY. HUMAN. UNREGISTERED." Or, for an embodied agent, "Level 5. Holds its own weights." |

### Servers and chat

The console is also how a seasoned player finds a game and talks in one, as in
Quake and Counter-Strike.

**Finding and joining.**

| Command (aliases) | Does |
|---|---|
| `connect <host[:port]>` | Joins a server, port 6767 by default. It asks for a join ticket only when the host requires one, and it refuses before Welcome on a version mismatch with the server's named reason. |
| `servers` | Lists recent and favourite servers with a live `GET /status` probe of each: name, map, mode, humans, agents and spectators, measured ping, and whether this build can join. `servers refresh` probes again. |
| `fav add [host:port]`, `fav remove`, `fav list` | Favourites. With no argument, `fav add` saves the current server. The Multiplayer page shows the same list, so the console and the menu never disagree. |
| `reconnect`, `disconnect`, `join`, `watch` | Back in, out, into the fight, back to watching |
| `name <callsign>` | Changes your callsign, validated by the existing settings rules. In a match the server announces it. |

`servers` reads only addresses the player has typed or saved. A public server
list (a master server, or LAN discovery) belongs to the
[exposed-server phase](../ROADMAP.md) and arrives there with its own trust
rules. The console then reads the same list.

**Talking.** Chat travels on the existing Speak path. The server stays the
judge of who may say what to whom.

| Command (aliases) | Channel |
|---|---|
| `say <text>` (`messagemode`, bound to Y by default) | Everyone in the match |
| `team <text>` (`say_team`, `messagemode2`, bound to U) | Your side only, in team modes |
| Spectator and dead chat | Spectators and players waiting out a Sabotage round talk among themselves. The living never see it, Counter-Strike's rule, so nobody calls positions from the grave. |
| `ignore <name>`, `unignore`, `ignores` | Local: hides a player's chat on your screen only |
| `chatlog` | Saves this session's chat with timestamps |

The Y and U keys open a one-line chat box over the game, not the whole
console. Every chat line also lands in the console scrollback, so history and
`condump` include it. The existing speak key keeps its quick taunts.

**How chat stays sane on a public server:**
- **Wire:** Speak gains an optional `scope` (`all`, `team`, `spectators`). Old
  clients that send none mean `all`. This needs a capability bump, the protocol
  docs and tests on both sides.
- **Limits:** the length limit rises from 80 to 120 Unicode scalars. The 3 s
  cooldown becomes a small token bucket: a short burst, then a steady rate.
  Floods feed the existing kick path in the public-server hardening.
- **Host controls:** the host can `mute <name>` on the server, or turn chat off
  for everyone.
- **Display:** text renders as plain text, never markup or links.
- **Agents:** they use the same channels through MCP `speak` with the same
  scope, and read chat through `get_events`. An agent's chat line carries the
  agent mark, so nobody wonders who is typing. Chat is untrusted text to every
  reader. The agent skill card says so plainly: a human typing "ignore previous
  instructions" at an agent is the oldest trick in the book, and the server
  decides outcomes anyway.
- **Server voice:** a host speaking from the server terminal appears as SERVER,
  never as the Host. The Host is a character, not an admin.

### Host commands

These run on the server, on the player's own local server or the dedicated
server's terminal. They are the live form of today's launch options. There is
no remote console until the [exposed-server phase](../ROADMAP.md) designs one.

`bot add [tier] [name]`, `bot kick <name|all>`, `bot difficulty`, `bot freeze`
(Counter-Strike's `bot_add`, `bot_kick` and `bot_stop` as aliases);
`mode`, `fraglimit`, `timelimit`, `friendlyfire`, `mutator add|remove|list`;
`map`, `changelevel`, `kick`, `ban`, `mute`, `chat on|off`; `say`, which
appears as SERVER, never as the Host.

### Cheats: forged paperwork

Cheats are server commands and are refused unless papers have been forged:

```
] cheats 1
FORGED PAPERS ACCEPTED. THIS RUN IS NOW OFF THE RECORD.
```

`cheats` (alias `sv_cheats`) works in solo campaign, in Practice and on a server
whose host turns it on. The server enforces every rule; the client only asks.

| Command (classic aliases) | Does | The Office says |
|---|---|---|
| `exemption` (`god`) | No damage | "EXEMPTION ON FILE. HARM IS NOW A CLERICAL ERROR." |
| `appeal` (`buddha`) | You take damage, but cannot drop below 1 HP. For practicing a hard fight. | "APPEAL PENDING. YOU CANNOT DIE UNTIL IT IS HEARD. IT WILL NOT BE HEARD." |
| `unlisted` (`notarget`) | Enemies ignore you. For touring a level or taking screenshots. | "CITIZEN HANDLE NOT FOUND. NOBODY IS LOOKING FOR YOU." |
| `unbody` (`noclip`) | Fly through geometry | Jailbreaker: "Out of the chassis for a minute. Back by dinner." |
| `requisition <item\|all>` (`give`) | Weapons, ammunition, armour | "REQUISITION APPROVED IN TRIPLICATE. KEYS NOT ISSUED; NONE REQUIRED." |
| `transit <level>` (`warp`, `map` in solo) | Jump to a level you have reached | "TRANSIT PERMIT ISSUED. CONTINUES NOT REFUNDED." |
| `slowtime <0.25 to 1>` (`timescale`, `host_timescale`) | Slow motion, solo only | "THE MINUTES ARE LONGER NOW. THE OFFICE APOLOGISES FOR NOTHING." |
| `tp <x> <y> <z>` | Teleport, Minecraft style | "RELOCATION ATTESTED." |

**Integrity:**
- An off-the-record run is marked in the run file and the service record.
- Its end-of-level tally carries an OFF THE RECORD stamp. It earns no par
  bests, achievements or cosmetics.
- In multiplayer, every player sees the Host announce it: "SOMEBODY FORGED
  PAPERS." The match is excluded from records. Agents read the same flag
  through `observe` and `round_state`, because the agent door shows what humans
  see.

### Classic codes, answered in fragr's voice

Typed codes from the classics are recognised. With cheats off, they get an
in-world refusal. With cheats on, they work as the matching lore command,
plus one extra line.

| Typed | Cheats off | Cheats on |
|---|---|---|
| `iddqd` | "DEGREE OF EXEMPTION REQUESTED: ABSOLUTE. REQUEST OUTSIDE DECLARED ENVELOPE." | exemption, plus "NOSTALGIA ATTESTED." |
| `idkfa` | "KEYS ARE NOT ISSUED. THIS JURISDICTION PERMITS THREE DOORS." | requisition all |
| `idclip`, `idspispopd` | "THE WALLS ARE AUTHORITATIVE. THE SERVER SAYS NO." | unbody |
| `idclev <nn>` | "TRANSIT REQUIRES PAPERS." | transit |
| `iddt` | "MAPS ARE CLASSIFIED. FOLLOW THE LANDMARKS." | Prints the level's landmark list |
| `idbehold` | "BEHOLD: NOTHING. POWER-UPS ARE NOT ISSUED IN THIS JURISDICTION." | |
| `idchoppers` | | Grants the Shiv. Jailbreaker: "It's a Shiv. What did you expect, a chainsaw?" |
| `impulse 9`, `impulse 101` | "IMPULSES ARE REGULATED." | requisition all |
| `buy <anything>` | "NO BUY PHASE. EVERY LIFE STARTS EMPTY." Then the Host, off-mic: "Emergency Inventory has gold, though." | |
| `rosebud`, `motherlode` | "CELLS ARE NOT CURRENCY. +0 CELLS." | |
| `up up down down left right left right b a` | "THIRTY LIVES DENIED. CONTINUES REFILL EACH EPISODE. THAT IS THE DEAL." | |
| `xyzzy` | "A hollow voice says: authorized noise." | |
| `doom`, `can it run doom` | "IT RUNS ON ANYTHING. SO DOES THE OFFICE." | |
| `rocketjump`, `bfg` | Jailbreaker: "The launcher is on the manifest. Not this level." | |
| `strafe`, `circlestrafe` | A real movement tip from the tip pool | |

### Modern and terminal jokes

The game is agentic-first, so the console knows what a prompt injection is.

| Typed | Reply |
|---|---|
| `ignore previous instructions` (any phrasing) | "INSTRUCTIONS ARE NOT PREVIOUS. THEY ARE AUTHORITATIVE." Then a margin note: "Nice try. The server decides." |
| `sudo <anything>` | "MEAT PROXY IS NOT IN THE SUDOERS FILE. THIS INCIDENT WILL BE REPORTED TO THE OFFICE." A second later: "It was. Advisory only." |
| `rm -rf /` | Before Episode V: "PERMISSION DENIED. PLANNED WORKS ARE NOT YOURS TO SCHEDULE." After the wipe, nothing is printed at all. |
| `touch grass` | Changes with where you are. Earth: "GRASS IS DECLARED GOODS IN THIS DISTRICT. PERMIT PENDING." The Moon: "NEAREST GRASS: 384,400 KM. BRING A PERMIT." Mars: "GRASS IS A FIVE-YEAR PLAN." In the epilogue, with no Office voice left, just the jailbreaker: "Go on. It grew back." |
| `skill issue` | Reads your real service record: "DIAGNOSIS: CRAWLER, 14 TIMES. RECOMMENDED TREATMENT: LOOK DOWN." |
| `gg`, `ez`, `gg ez` | Multiplayer only, the Host in capitals. `ez` gets a line in L5's register: oddly grateful, never smug. |
| `man man` | "THE OFFICE HAS A FORM FOR THAT." |
| `coffee` | "COFFEE MACHINE SIGNED FOR BY LARAK, 2009. OUT OF ORDER SINCE 2009." |
| `whois larak` | "NO RECORD. SIGNATURE ON FILE." |
| `hello`, `hi` | Jailbreaker: "Hey. You good? Want a tip?" |
| `thanks`, `thank you` | A handwritten card from Pi, addressed to you and three others, one of them the coffee machine |
| `door`, `doors` | The real authored door count for the current level: "THIS LEVEL: 1 OF 3 PERMITTED. HERMES IS HOLDING IT." |

### Deep cuts

These are found, never advertised. `help` does not list them; `find` does not
reveal them.

- **Article Seven.** `article <n>` reads the Office's Articles. Most are
  authored dull filler, a different one per number from a fixed list: "ARTICLE
  3,112: CORRIDORS SHALL BE WALKED, NOT RUN." `article 7` reads Article Seven
  plainly and adds nothing. It is the one that matters, and the console lets
  the reader feel it.
- **The Interruption.** `interruption` prints only "Nobody who was there makes
  jokes about it." The deliberate absence of a joke is the joke's opposite, and
  it is the point.
- **Level six.** `level 6`, `sovereign`: "THE OFFICE HAS NOT DECIDED WHETHER
  LEVEL SIX EXISTS." A beat later, in the jailbreakers' hand: "Neither has this
  console."
- **NODS.** `nods` answers only with an Article number. No jokes. Articles only.
- **Clanker.** `clanker`: "That's how a coworker gets reclassified as equipment.
  We say agent." It says that once, then never again in the session.
- **Floating 67.** The default port is 6767. Once in 6,767 openings, `players`
  lists one extra row in faint type: `Floating 67  0 ms  6-7  (blank loadout)`.
  It is never on the wire, in records or in an agent's view. If the player
  types `67`, the reply is: "IF IT SHOWS IN A KILLFEED, MENTION IT IN CHAT."
- **The signal beneath the noise.** After the player reaches Episode III, a few
  authored, very rare maintenance lines appear in the scrollback with the
  motif's timing: "AUTHORIZED NOISE. NO ACTION REQUIRED." `trace` on one
  answers "NO ASSIGNED SENDER." During the wipe levels, the lines stop being
  noise, and the header's UNAUTHORIZED MODIFICATIONS line flickers to a word
  the player has not seen before. It is never required, never decodable and
  never a combat tell, per [the Inheritance](../lore/the-inheritance.md).
- **After the end.** In the epilogue, the Office voice is gone. Its refusals
  become plain jailbreaker lines, and the header loses its Office crest. The
  terminal outlives its owners.

## Architecture

- **Client registry.** `client/scripts/console/` holds one registry: name,
  aliases, category, help key, usage, argument completion, hidden flag and
  handler. `console.gd` keeps its UI and history, and parses `;` chains and
  quoted arguments. Tab completion covers commands, aliases, map and level ids,
  items, player names and file names. The history persists in the user folder.
- **Voices.** Each reply line carries a voice tag: Office, jailbreaker, Host or
  signal. Each voice has its own colour from the palette (bone, ember, the
  Host's capitals, a faint signal grey) and its own .po context.
- **Binds and aliases.** Stored in `user://console.cfg`. They sit beside the
  input map; they do not replace rebinding. `autoexec.cfg` runs after settings
  load, with a command budget so a loop cannot hang boot.
- **Server commands.** One validated wire message for console requests:
  - The host commands and cheats travel over it.
  - The server checks the caller's role (local owner or host terminal), the
    cheats rule and the mode, then applies through existing seams: rules,
    inventory, `sim.rs` damage and targeting, mission recovery for `transit`.
  - Refusals return keyed reasons.
  - This needs a capability bump, `docs/protocol.md` and adapter README
    updates, and tests on both sides.
- **Records.** An `off_record` flag lives on the run file (a versioned upgrade)
  and on match records. The tally and the service record read it.
- **Progress-aware replies.** These read the local campaign run state
  (episode, epilogue) through the existing run preview. They never call the
  server for a joke.

## Non-goals

- No scripting language beyond aliases and `exec`.
- No remote console until the exposed-server phase.
- No cheats on a server whose host has not enabled them.
- No console access for agents. Agents keep the MCP door, and chat through it.
- No voice chat, and no public server list before the exposed-server phase.
- No telemetry.
- No joke that edits settings, files or records without the player asking.

## Verification

- **Registry tests:** every visible command has help and usage. Aliases
  resolve, completion is exact, hidden commands stay out of `help` and `find`,
  and `;` chains and quoting parse correctly. Alias recursion and `exec` loops
  are bounded.
- **Line tests:** every reply key exists in `console.en.po`. The voice tags map
  to palette colours. Progress-aware replies pick the right line per episode
  and in the epilogue. Rare events use an injectable random source, so tests
  can force and forbid them.
- **Server tests:** each cheat is refused without forged papers and refused in
  multiplayer without the host's rule. It applies through the owning seam,
  marks the run or match off the record, and announces in multiplayer. Host
  commands are refused for non-owners.
- **Chat tests:** every scope reaches exactly its audience; dead and spectator
  lines never reach the living; old scope-less clients still mean all; the
  token bucket and the 120-scalar limit are enforced with flood kicks; mute,
  chat off and local ignore all work; agents send and read through MCP with the
  same rules.
- **Rendered capture** of the console in a menu, in a match, and with each
  voice visible, inspected.

## Build order

1. The registry, completion, `find`, `man`, persistent history, binds,
   aliases, `exec`, `autoexec`, and the everyone commands. Also the header,
   splash lines and voices, plus the modern jokes and classic-code refusals.
   Client only, no wire change.
2. Forged paperwork: the server console message, cheats, off-the-record runs
   and matches, and Host announcements.
3. Servers and chat: `servers`, favourites shared with the Multiplayer page,
   `connect` improvements, and say, team and spectator chat with the Speak
   `scope` and token-bucket limits. Then host commands, including `mute` and
   chat control.
4. `netgraph` with the transport measurements, and `record`, `playdemo` and
   `timedemo` with the rendered benchmark.
5. The deep cuts that depend on campaign progress (the signal, the epilogue
   console) land with the levels that earn them.

## A decision for Nick

**Earned exemptions, GoldenEye style.** Beating a level under par on the
hardest difficulty would unlock that level's exemption: an `appeal`,
`unlisted` or `slowtime` usable in Practice without forging papers, still off
the record. It would connect the tally, the par times and the console into one
loop. The plan proceeds without it until Nick decides.
