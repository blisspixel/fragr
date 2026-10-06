# Exceptional server, multiplayer, and hosting

**Status:** planned, 2026-10-05. Nick set this goal. It sequences inside the
[full build order](../ROADMAP.md#full-build-order). It does not open a second
queue, and it does not replace the current
[multiplayer trial](multiplayer-first-playable.md).

**Spend:** $0 to design, measure, and test. Local and LAN play stay $0. No
cloud account, image publish, or `terraform apply` is authorized by this
plan. Any billable host needs a priced estimate and written approval, inside
the existing spend cap.

## Goal

Make the Rust server and its multiplayer exceptionally good, and make running
that same server a first-class act on a spare machine at home and, later, from
infrastructure templates.

The match is the product. Free-for-all, team deathmatch, capture the flag, and
Sabotage stay on one authoritative 20 Hz process. Humans, rule bots, external
agents, and spectators share it. A larger team battle, up to a measured
64-player map in the spirit of a combined-arms fight, comes only after the
current populations are excellent and the numbers exist.

Wipe is the cooperative defense already accepted for the campaign finale and
for multiplayer. On 2026-10-05 Nick set its player-facing rule from the lore:
hold the refuge while free-agent friends argue for one local exception. When
that clock lands, the machines stop at the refuge line and go on elsewhere.
Everyone still standing is spared. One survivor is enough. A living team is
spared together. The dead are not restored, and the rest of the planet is not
spared. It is not a duel for a single mercy slot, and it is not the older
endless Sweep. The first wrapper remains the proposed four-seat scenario in
[wipe survival](wipe-survival.md). Larger rosters wait on the measurement
ladder below. None of it is built. Home hosting is a
complete product. IaC stands the same server up somewhere else. It is not a
different game, and it is not required to play or to host friends.

## Hosting doors

Every door runs the same `fragr-server` binary or the same container image,
on port 6767, with the same rules and the same admission. The tick stays a
long-lived process. Serverless hosts do not run it.

| Door | Who it is for | Today | This goal |
|---|---|---|---|
| Spare machine at home | A PC on a desk or in a closet, no account | Desktop Host, the dedicated binary, Compose, [Home LAN](../../infra/docs/HOME-LAN.md) | Stays the default and the acceptance path. No Terraform, domain, or cloud account. LAN join is normal. A router forward is optional and documented. |
| Popular small-VM network | A public address without taking on a hyperscaler | [Cheap VPS](../../infra/docs/CHEAP-VPS.md) is prose. No template exists. | One plan-only Terraform root: that provider's ordinary virtual network and one small VM. |
| GCP | The drafted cloud path | [Plan-only COS host](../../infra/terraform/README.md). Never applied. | Keep it. Writing the other roots does not apply it. |
| AWS | Not started | None | Plan-only Terraform: one VPC, one small instance, a tight security group, the same image contract. |
| Azure | Not started | None | Plan-only Terraform: one VNet, one small VM, a tight rule, the same image contract. |

The small-VM provider is **proposed**, not chosen. DigitalOcean (they call the
network a VPC) and Hetzner Cloud both have a maintained Terraform provider and
a simple network around one VM. Pick one before writing that root. Do not
write both. Naming a different provider with the same shape is a one-line
change to this plan, not a new goal.

Home is first-class in these concrete ways:

- The desktop package and a spare machine can host a full match with bots,
  humans, and agents without Docker, a cloud account, or a domain.
- A cloud template must not be the only documented way to host, and it must
  not require a feature the home server lacks.
- The quality bar is a person going from a spare machine to a watched match
  in one sitting, using the current binary or desktop Host. A green Terraform
  test is not that sitting.

## What exceptional means for the server

Checked practice from Quake III, Source and Counter-Strike dedicated servers,
Minecraft and Paper, Unreal relevancy, and the authoritative-FPS writeups
listed below. The working rules:

- Hold 20 Hz until a measurement says the 50 ms budget still has headroom at
  the population being claimed. Sim rate and per-client snapshot rate are
  different knobs. A missed tick is worse than an honest slower rate.
- A late tick finishes, drops the stale outbound snapshot, and schedules the
  next tick. It does not replay missed time as extra combat.
- Path searches and socket writes stay inside a budget. A slow client drops
  or coarsens. It does not stall the match. WebSocket delivery is ordered, so
  a fat frame blocks newer frames for that client.
- Full JSON of every fighter to every connection will not carry a 64-player
  match. Delta from the last snapshot that client applied, then interest and
  rate tiers. Score and round phase stay on a tiny always-relevant record.
  Spectators are a cheaper stream than fighters. The current cap of 64
  connections counts spectators. It is not a 64-fighter claim.
- Hitscan rewind, when it is built, rewinds other players only, against poses
  the server actually sent, with a hard cap. Grenades, mines, and other
  projectiles stay on the live clock. The shooter is shown the server result.
  Clients send intent. They do not report hits.
- Free-for-all, a 5v5 plant/defuse, and a large team battle are different
  products: different maps, clocks, bot jobs, and bandwidth. A stretched
  current arena is not a 64-player map. One process stays correct until a
  stacked fight misses the tick budget. Do not shard one match.
- Rule bots miss, look, and take jobs a person can name. Aim skill is reaction
  delay and angular noise, not extra hit points and not a perfect trace.
  Decisions run slower than the movement tick, staggered. Team play is a
  quota of jobs. Humans and external agents already displace filler bots.
  That stays.
- Rules in force are visible to the player. Fair play stays server authority,
  logs, and shot evidence. No kernel anti-cheat.
- Polish is the ceremony, a room the player can read, and a link that is not
  asked to swallow the whole match. It is not a higher tick. Command rate,
  snapshot rate, and byte budget are three clamps. The mode owns its clocks.
  A public audience does not sit in fighter slots.

## Review rounds

Bug hunts and security reviews repeat for as long as this plan is the goal.
One round does not finish it. Each round names the surface, the defects that
were fixed, the tests that prove the fix, and what was checked and left.
A finding becomes a fix only when a test shows the old behavior and the new
behavior. Limits already written down stay limits until a round changes them
on purpose. These rounds do not replace
[public server hardening](public-server-hardening.md) or
[fair play](fair-play.md).

### Round 1, 2026-10-05: admission, resume, and conduct

Surface: `server/src/net.rs`, `resume.rs`, `session.rs`, join tickets, access
lists, speak and display-name bounds, and human input sequences.

Fixed:

- A resume that claimed the pawn and then lost the socket left that pawn
  attached to a dead client, released its seat, and burned the token. A
  dropped reply and a welcome that fails to send now put the pawn back on
  the old token, the original grace deadline, and the same seat.
- Ping and pong frames did not count toward the inbound budget, so a
  control-frame flood never reached `rate_limited`. They now share that
  budget. A pong that answers the server ping still fits.
- Work before admission, in-flight `GET /status` reads, and refusal
  handshakes had no cap. Classification stops at the connection cap. Eight
  status reads and eight refusal handshakes can be in flight. A status read
  still does not take a game slot, and a refusal does not keep the
  classification permit.
- A status request whose bytes arrived only up to `GET /status` was treated
  as a WebSocket. The classifier now waits for the next byte.

Checked and unchanged:

- Join tickets: role, window, and constant-time MAC. Spectators stay
  unticketed. A forged resume MAC does not open. A second claim with the old
  nonce fails after a successful delivery.
- Speak length, control characters, and cooldown. Display names strip
  controls and stay 24 scalars. Human input sequences reject replays.
- Non-finite aim is ignored. Access lists fail closed on a bad reload.
- `GET /status` still omits callsigns, addresses, tickets, and tokens.
- `look_at` with a player id is server-side aim for every role. Full
  snapshots already expose those positions. It was not changed.

Left for a later round:

- No per-client action throttle beyond the inbound budget. A naive throttle
  would clear edge-triggered jump, use, and weapon latches. See public
  server hardening.
- No trusted forwarded address. Lists see the connecting socket.
- Full snapshots still describe every fighter to every initialized client.
- Pass 1 measurement has not been run.

### Round 2, 2026-10-05: refusal slots and muster weapons

Surface: the ban and allow path in `server/src/net.rs`, and Sabotage muster
in `server/src/sim/sabotage.rs`.

Fixed:

- A banned or unlisted address took a game slot for the whole handshake
  timeout while the server explained the refusal. A listed flood could fill
  the match cap and keep a real player out. Those explanations now use the
  same eight-slot refusal cap as a full server. Past that cap the TCP
  connection drops with no handshake, and a free game slot can still be
  taken. `a_listed_refusal_does_not_hold_a_game_slot` covers the drop.
  `listed_addresses_are_refused_before_any_seat_or_status` still receives
  the explanation when a refusal slot is free.
- Sabotage muster cleared fire and grenade throws, and not mine placement.
  A fighter who already held a mine could put it down before the round went
  live. Muster now clears the place latch the same way it clears a throw.
  The mine and its count stay until the round is live and the fighter
  presses again. `muster_holds_a_mine_the_same_way_it_holds_a_throw` covers
  that. Today's sabotage pads do not grant mines. The sim rule was still open.

Checked and unchanged:

- The round 1 resume rollback, control-frame budget, status cap, and
  full-server refusal cap still pass their tests.
- Status classification still waits for the byte after `GET /status`.
  The exact-path helper was only a second copy of that check, so it is gone.

### Round 3, 2026-10-05: scoring and explosive ownership

Surface: `resolve_fighter_hit`, `damage_lands`, grenade launch and blast,
mine place and trip, capture touch, and sabotage plant, defuse, and outcome.

No further defect became a fix. These stay the current rules:

- A team kill, with friendly fire on, scores nothing for the shooter or the side.
- Spawn shield blocks an incoming blast. The owner's own explosive still hurts them.
- A grenade already in flight survives the owner's death and can still score.
  A mine goes dark when its owner dies, leaves, or is waiting to respawn.
- Explicit leave removes that player's grenades and mines. Opening or ending
  a round clears both.
- Plant and defuse require the right side, a held use, stillness, and the
  site or the charge. A non-carrier cannot plant. Flag touch is a 2.5 m
  horizontal radius and 2.5 m of height, after a short drop grace.

Left for a later round:

- No per-client action throttle beyond the inbound budget. A naive throttle
  would clear edge-triggered jump, use, and weapon latches. See public
  server hardening.
- No trusted forwarded address. Lists see the connecting socket.
- Full snapshots still describe every fighter to every initialized client.
- Bot senses and cheaper snapshots are passes 2 and 5. This round did not
  change them.
- Pass 1 measurement has not been run.

The venue desk below is the operator surface built on 2026-10-05. Bot
targeting and what a snapshot reveals remain the next review surface.
That review does not start the measurement soak.

## Venue desk

An operator of a Counter-Strike or Minecraft server sits at a terminal
while the match is already running. The first quality-of-life tools are
the ones that keep the room without restarting the process.

- See who is in the room. Public status hides names and addresses on
  purpose. The person at the machine still has to know who is fighting,
  watching, parked for a reconnect, or printed on the roster card.
- Remove one person now, by the name the server assigned, and have the
  pawn actually leave. A quiet close parks a resume token for ten seconds
  and tells the player nothing. A kick has to say why and forget the token.
- Keep that address out after a restart. The ban file already reloads.
  The desk appends that same file. A name is not a credential, and a
  shared address can still catch the wrong neighbor.
- Say one ordinary sentence as the venue. Player speak is a personal
  callout with its own cooldown. The on-air Host is a frozen broadcaster
  who never explains the night. Neither voice is the person running it.
- The terminal is not the life of the process. Campaign and desktop Host
  already treat stdin as a lease. A dedicated match has to keep running
  when the desk input closes, including under a service manager that
  never attaches a terminal.

Fragr already had audit logs on `fragr_server::audit`, address bans,
optional join tickets, ten-second resume, and an anonymous status probe.
It did not have a desk.

Built on 2026-10-05. `--console`
opens the desk on a dedicated arcade match. It refuses desktop Host, a
local mission, a map file, the run preview, and the bench. Verbs are
`who`, `kick <name>`, `ban <name> [reason]`, and `say <sentence>`.

`who` prints the assigned name, a kind (`human`, `agent`, `spectator`,
`parked`, or `roster`), the score, and the canonical address when the
desk has seen one. It does not print client ids or ports, and it does
not appear on `GET /status`. An empty room says "The room is empty."

`kick` matches one exact assigned name, including spaces. Two seats with
that name are left alone. A roster bot stays on the card, because a kick
would only make the refill put them back. A live socket closes with
`venue_kick` and the sentence "The venue asked you to step outside."
The pawn is removed, not parked. A parked fighter with no socket is
removed and told, on the desk only, that they are off the floor.

`ban` requires `--ban-list`. The desk resolves one person to the address
it recorded, appends `{address} reason={text}` to that file, and only
then removes them. A failed or already-covered write leaves the file and
the pawn as they were. The live close uses the existing `address_banned`
code. A roster bot has no address. The default reason is "venue desk."

`say` broadcasts `venue_notice` as `The venue: {sentence}`. The sentence
is at most 80 scalars, with no control characters, and the venue waits
one second between lines. It does not impersonate a player, spend that
player's speak cooldown, or rewrite the Host line. The client shows the
server sentence in the corner combat feed. `venue_kick` is a hard stop:
the client does not try to resume a pawn the desk already removed.

The voice is the venue. It is not an Auditor, and it is not a new station.
The Host calling the match stays in capitals. Roster bots are on the card.
The league does not own the room. The person running the night does.

Still later, and still inside this plan rather than a second queue:

- Remote administration. Status, say, map, restart, rotate, kick, and ban
  over an authenticated channel, with a secret that is never logged. A
  passworded remote channel is a larger hazard than local stdin, so it is
  not this cut.
- A private-night passphrase, distinct from join tickets. Tickets are
  clearance for a fighter. They are not a room password a stranger can
  be told at the door.
- A venue name and one line of house rules that a joiner actually sees.
- Naming the next map at the round bell without restarting the process.
  `--map-rotate` already alternates between rounds for modes that allow
  it. The desk cannot choose a map.
- A vote to send someone outside.
- Demos, and a delayed spectator relay. A demo flush stays off the tick.
  The relay is how a public night is watched. A friend on the couch stays
  a direct spectator.
- One server config file instead of a long command line. The file holds
  rates, bans, seed, and the venue name. The mode still owns its clocks
  and its limits.

This desk does not close the limits already written down: no per-client
action throttle beyond the inbound budget, no trusted forwarded address,
no byte-rate budget beyond the frame caps, and full snapshots to every
initialized client. The reconnect-token checkbox and a stranger-facing
TLS session remain open. The next measurement step is still pass 1.

## Synthetic traffic

`--traffic` on `fragr-playtest` starts a local server and fills it with
synthetic fighters and read-only spectators. Fighters send movement and a
held trigger at a chosen rate. They do not pathfind, so the load is the
tick, the shots, and the fan-out. One loopback address holds 32
connections. A roster through 64 uses the next loopback addresses.
Linux and Windows already assign `127.0.0.0/8`. macOS assigns only
`127.0.0.1` until an alias is added, so a roster past 32 there needs
`ifconfig lo0 alias` first. The
report records actions, snapshots, bytes, the tick counters, and health.
`--assert` checks that the roster stayed up. It does not declare the 50 ms
budget met. The measurement table for pass 1 is still empty. A debug run
is a smoke of the generator. A release binary, with the roster and the
machine written down beside the numbers, is what fills that table.

## Polish

Checked again on 2026-10-05 against Source's rate model, Quake Live's split
between a host file and a mode factory, Counter-Strike's separate round
clocks, SourceTV's relay, and Glenn Fiedler's snapshot articles. Their
tick rates and byte caps are not fragr's numbers.

Already the right shape, and not a rebuild:

- The sim stays at 20 Hz. The local human predicts. Other fighters render
  on a bounded 100 ms timeline, two snapshots at this rate, so one late
  frame does not hitch the picture. Source's own networking page warns
  that shrinking that delay, or raising the snapshot rate past what the
  link can carry, is a common way to make the picture worse.
- Warmup already names the map, the roster, and the countdown. Round end
  already has a podium, an MVP, and a Host line.
- A slow reader does not stall the tick. A full outbound queue or a full
  write buffer drops that client. The match continues. The queue still
  holds many world snapshots before that drop. Replacing the stale one
  is pass 5, below.
- Speak, the venue line, and movement already have separate budgets.
  Jump, use, throw, mine, and weapon change stay edge commands. A later
  throttle keeps the edge until the sim consumes it.

Rules from this search. They land in the passes below. They do not add a
pass, and they do not move the next step off the measurement.

- A thin link receives fewer or smaller snapshots. It does not slow the
  room. Today every initialized client gets a full snapshot every tick,
  and the only byte stops are the 64 KiB frame and the 512 KiB write
  buffer. Choke, a snapshot that client did not get because it was
  behind, is a different failure from a missed tick. Pass 1 records both.
- Until the transport can skip a lost packet, each client holds at most
  one unsent world snapshot. A newer snapshot replaces it. Welcome, close
  reasons, round results, scores, and inventory stay in order and are
  never replaced. Disconnecting a flooded queue remains the backstop.
- Positions quantize to what the picture needs. Scores, round phase, and
  inventory stay exact. The delta stays on the current JSON wire. A
  binary snapshot is a later protocol change.
- Interest uses a priority that accumulates until the pawn is sent, then
  resets. Sending only the loudest pawns starves a quiet one. Score and
  round phase stay on the always-relevant record.
- The audience is not the roster. Direct spectators stay inside the
  connection cap for a home night. A public watch uses one delayed relay
  so a watcher cannot play from the future, and so the fight process is
  not also the broadcast. SourceTV's own bug notes record that a game
  server carrying a large live audience drops its tick. Disk writes for
  a demo, a ban line, or a log flush stay off the tick.
- Ceremony belongs to the mode and is visible before the clock starts.
  A future host file does not silently override it. A ready check, where
  the clock waits until enough of the room says ready, is a later
  competitive wrapper. The home scrap night keeps the warmup it has.
  A dead fighter in a round still receives live enemy positions. Locking
  the camera would not close that. [Fair play](fair-play.md) already
  owns the cut, and pass 6 is where the stream changes.
- The player sees one mark for a live room and a late room. The operator
  already has health and tick time on status. A sheet of rate settings
  is not the polish.

## Passes

Each pass is playable and measurable on the current maps. Do not raise the
gameplay target past the previous pass's numbers. The desktop Host trial
remains the fun gate. These passes can proceed beside that review. They do
not wait on a cloud template, and the templates do not wait on a 64-player
claim. Templates stay plan-only the whole time.

1. **Measure.** Split tick time into simulation and encode-plus-send. Soak
   16, 32, and 64 connections on today's maps. Count fighters and spectators
   separately. Record p99, bytes out, write-buffer high water, missed ticks,
   outbound overflows, and how often a snapshot was not queued because that
   client was behind. Count those last two apart from a missed tick, and
   record how often bots are still on a cached path. No rule change. The
   table lives in this file when the run exists.
2. **Bot senses.** Reaction delay, aim noise, a view cone, line of sight, and
   a last-known position. Tiers change only those knobs. Decisions near 10 Hz,
   staggered. Movement stays at 20 Hz. Seeded tests at 8 and 16: no kills
   through walls, a spread of time-to-first-shot, tick time no worse than
   the pass 1 baseline. Keep the four-search-per-tick cap.
3. **Readable jobs.** Free-for-all and team deathmatch use the item clocks and
   the four personalities so they do not all take the same weapon. Sabotage
   keeps its roles, with a measurable quota so a side does not stack one site.
   Humans and agents still take a bot's seat.
4. **Hitscan rewind only.** After the two-machine session and the order in
   [TRANSPORT.md](../TRANSPORT.md). Server-time shots, target poses only, a
   hard cap. Grenades and mines stay in the present. Prove it with a fake
   delay, then with play. Do not raise the tick, and do not start UDP here.
5. **Delta snapshots.** World state from the last snapshot that client
   applied. Inputs stay reliable. At 16 players, still send every pawn.
   Each client keeps at most one unsent world snapshot, and a newer one
   replaces it. Welcome, close reasons, round results, scores, and
   inventory are not replaced. Positions quantize to the precision the
   picture needs. Scores and counts stay exact. The delta stays JSON.
   Measure bytes, including a client that missed an update. A full write
   buffer drops that client and leaves the match on time.
6. **Interest and rate tiers, only if pass 5 shows 16 is tight.** Nearby and
   recently violent pawns stay at 20 Hz. A quiet pawn's priority accumulates
   until it is sent, so it is not starved. Distant, silent pawns update
   slower. A dead fighter in a round does not receive live enemy positions.
   Spectators use the cheaper stream. Then measure 32 fighters on a medium
   map and report it. The connection cap stays a cap. A public audience
   still waits on the delayed relay, not on a larger fighter cap.
7. **One large map that is fun on foot**, inside the existing 16-to-32 sheet
   in [multiplayer maps](multiplayer-maps.md), with more than one fight. The
   stacked-objective soak is the one that counts. Vehicles come after that
   map works on foot.
8. **Say 64 only with numbers.** p99 inside 50 ms with headroom, outbound
   bytes inside the frame and buffer caps, spectators on the cheaper stream,
   and an objective or reinforcement clock authored for that map. That tier
   sits above the current large-map sheet. It belongs with conquest, after
   the exposed-server week. Wipe uses the same budget discipline. Its first
   playable target stays four cooperative seats on the shared scenario, with
   the spared-standing rule above. A larger defense roster is a later measured
   profile, not a silent jump to 64.

IaC rungs, writable as soon as a root can be mocked, and still unapplied:

- Keep the GCP COS draft as the only cloud root that exists.
- After the small-VM provider is chosen, add that one root.
- Add AWS, then Azure, each as its own root with mocked plan tests.
- Order among those three new roots can follow whichever provider Nick names
  first. Home documentation is improved in the multiplayer trial and does not
  wait on any of them.

## IaC rules

- Default network has no world-open game port. A reviewed test may allow a
  short operator list, the same idea as the GCP draft's limit of eight
  IPv4 /32 addresses.
- Secrets stay in the provider's secret store or a host environment variable.
  Never in tfvars, committed state, or the image.
- One VM, one process. No load balancer, Kubernetes, autoscaling group, or
  scale-to-zero tick.
- Templates consume an immutable image digest. They do not build the image
  in the cloud. Publishing that digest is a separate reviewed step. Until
  then, a host may build from the locked source the way
  [Cheap VPS](../../infra/docs/CHEAP-VPS.md) already describes.
- UDP stays closed until [TRANSPORT.md](../TRANSPORT.md) says otherwise.
- CI for a new root matches the GCP job: `fmt -check`, backend-free locked
  `init`, `validate`, and mocked tests. No cloud credentials. No apply.
- The home path has no Terraform.

## Non-goals

- Applying any template, creating an account, or publishing an image.
- Matchmaking, accounts, a server browser, or a web client.
- A second server implementation per cloud.
- Raising the tick rate, or UDP, before the measurement and the two-machine
  session.
- Claiming a 64-player mode before passes 1 through 6 have numbers.
- Replacing the human TDM and 5v5 trial.
- Writing DigitalOcean and Hetzner templates both. One small-VM provider.

## Architecture impact

Server, bot, and snapshot work uses the existing seams in `server/src/sim.rs`,
`session.rs`, `net.rs`, `navigation/`, and `metrics.rs`. Wire changes for
delta snapshots or lag compensation update `docs/protocol.md` in the same
change that ships them. The venue desk below adds one event, `venue_notice`,
and one close code, `venue_kick`. `gameplay_version` is unchanged. Public
`GET /status` stays anonymous.

New Terraform roots, when written, live under `infra/` and follow the GCP
draft's plan-only contract. `infra/README.md` is the hosting index.

## Verification

- Each server pass names its test before the code. Rust tests, the existing
  bench and soak, and a measurement table in this file. A performance claim
  without that table is not done.
- New Terraform roots run in CI the way `infra/terraform` already does.
- Home acceptance is a person starting desktop Host or the dedicated server
  on a spare machine, and a second machine joining. Record the build, the
  mode, and what went wrong.

## Success

- A spare machine hosts free-for-all, team deathmatch, capture the flag, and
  Sabotage with humans, agents, and bots, and the host guide matches what
  that person did.
- The server holds 20 Hz at the population the current rung claims, with the
  table in this file.
- Bots are readable and fair at 8 and 16. A 32-bot run is a report until the
  budget holds.
- GCP, AWS, Azure, and the one chosen small-VM template validate in CI with
  mocked providers. None are applied until spend approval. Home never depends
  on them.

## Sources

Practice checked 2026-10-05, used for the rules above and not as a claim that
those games' numbers are fragr's numbers:

- id Software, Quake III Arena `sv_fps` default 20, rate choke, delta
  snapshots, and a 64-client ceiling with a much smaller default:
  <https://github.com/id-Software/Quake-III-Arena> and Fabien Sanglard's
  network review, <https://fabiensanglard.net/quake3/network.php>.
- Valve, Source multiplayer networking (tick cost, interpolation, hitscan
  rewind) and Counter-Strike 2's subtick description:
  <https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking>,
  <https://www.counter-strike.net/cs2>.
- J.M.P. van Waveren, *The Quake III Arena Bot* (2001), and Michael Booth,
  *The Making of the Official Counter-Strike Bot*, GDC 2004. Aim error,
  reaction time, and a slower think rate than the movement tick.
- Paper and Folia tick and region docs, and Glenn Fiedler on snapshot size,
  priority, and not putting time-critical state on a reliable ordered stream:
  <https://docs.papermc.io/paper/reference/global-configuration/>,
  <https://gafferongames.com/post/state_synchronization/>.
- Unreal Engine replication relevancy: nearby and audible actors, vehicles
  on a different priority, score kept separate from pawns.
- Gabriel Gambetta, *Fast-Paced Multiplayer*:
  <https://www.gabrielgambetta.com/client-server-game-architecture.html>.
- The same Valve networking page, re-read for the polish cut: `rate`,
  `cl_updaterate`, and `cl_cmdrate` are separate clamps, the server never
  sends more snapshots than ticks, and the default interpolation period is
  two snapshots so one loss still has a pair to draw between.
- Quake Live community server standards. A host file holds technical
  settings. A factory holds the mode, so one file cannot silently override
  the other: <https://github.com/quakelive-server-standards/quakelive-server-standards>.
- Glenn Fiedler, *Snapshot Interpolation* and *Snapshot Compression*.
  Snapshots are time-critical and should be skipped rather than waited on.
  Quantize first, then delta:
  <https://gafferongames.com/post/snapshot_interpolation/>,
  <https://gafferongames.com/post/snapshot_compression/>.
  The priority accumulator is in the state-synchronization article already
  listed above.
- SourceTV bug notes. A game server that also transmits to a large live
  audience drops its tick. A relay on another process is the watch path:
  <https://developer.valvesoftware.com/wiki/Source_TV_Buglist>.

## Relationship

Parent items are 1, 7, and 8 of the full build order. This plan does not
supersede [multiplayer-first-playable.md](multiplayer-first-playable.md),
[TRANSPORT.md](../TRANSPORT.md), [cos-container-host.md](cos-container-host.md),
[bot-fill.md](bot-fill.md), or the home and cheap-VPS guides. Those remain
the near doors. Review rounds above repeat beside the passes. Rounds 1
to 3 are recorded. The venue desk and the synthetic traffic generator
are part of this server work. Polish rules from the 2026-10-05 rate, ceremony,
and snapshot search are recorded in this file. The next implementation
step for the scale ladder is still pass 1, the measurement, with no
gameplay change.
