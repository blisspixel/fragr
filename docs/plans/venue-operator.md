# Venue operator

**Status:** in flight, updated 2026-10-07. The attached desk's bounded
`shows`, `next` and `map` increment is implemented locally under
[host rotation](host-rotation-campaign-bests-20261007.md). Detached access,
venue identity, private doors, host files, votes and the other slices remain
planned. This plan does not replace any running process.

This is the operator rung of [server excellence](server-excellence.md). It
does not add a roadmap queue, and it does not move that plan's next scale
step off the empty measurement pass.

## Goal

A person running a spare machine can name the night, lock the door, see who
is in the room, change the next show, undo a bad ban, and stop the process
cleanly, including after they have closed the terminal they started it from.

The voice of that person is the venue. The league Host calls the match and
does not run the room. An Auditor does not run it either.

## What those servers added, and why

Checked 2026-10-06. Their numbers, tick rates, and account systems are not
fragr's. The reasons are.

| Tool | Where it showed up | Why it exists | Fragr today |
|---|---|---|---|
| A name and a note on the door | Zandronum `sv_hostname` is the master-list name. `sv_motd` is the welcome, used for rules and how to reach the admin, and a player can ask for it again. Source `hostname` is the browser row, and `motd.txt` is the join screen. Minecraft `motd` is the multiplayer list line. | A row that only says the game is not a place. People read the house rules before they sit down. | `GET /status` names the map, the mode, and anonymous counts. It has no venue name and no house line. The Host line is the broadcaster, on purpose. |
| A private door | Zandronum `sv_joinpassword`. Source `sv_password` (empty means public). Minecraft `white-list` for a friends' server, plus `enable-status` so a closed door can still answer a ping. | A forwarded port is a public invitation. The word you tell a friend is a different tool from a ban list. | Join tickets are fighter clearance, and spectators are not ticketed. An allow list is a set of networks. There is no passphrase, so a private night is private only while the port stays unforwarded. |
| A console that is not the server's stdin | Zandronum `sv_rconpassword` lets a client or a small utility run the server from somewhere else. Source RCON shares the game port. Minecraft `enable-rcon` is off by default. The Minecraft wiki says the protocol is not encrypted, the password can be intercepted, and the safe habit is to connect from localhost. | Dedicated servers outlive the terminal. A panel, a second SSH session, or a crash of the launching shell still has to reach the process. A password on a public port is how that door gets stolen. | `--console` reads the process stdin: `who`, `kick`, `ban`, `say`, `stats`. Closing stdin leaves the match up. Desktop Host and a local mission refuse it, because they already lease stdin. A detached night, a service, and a container with no stdin have no desk at all. |
| One file that recreates the night | Source `server.cfg` holds the name, the passwords, and the cycle, and is read again with `exec`. Minecraft `server.properties` is the file the process rewrites defaults into. Quake Live keeps technical settings in the host file and the mode in a factory, so one file cannot silently override the other. | After a crash or a reboot the operator wants the same room, with comments they wrote, without reconstructing a long command. | Launch is a clap command. Bans and allows are already files and reload every five seconds. The night list is compiled in. |
| Change the map without killing the process | Source `mapcycle.txt` and `changelevel`. Zandronum `sv_maprotation`. | Restarting dumps the room, the scores, and anyone who took time to join. | `--map-rotate` keeps one mode. `--playlist` walks a built-in list of maps and modes. The desk cannot point at the next show. Stopping the process starts the night over. |
| A vote while the operator is away | Zandronum `sv_minvoters` and `sv_nocallvote` (votes can be off, or spectators can be excluded). SourceMod `sm_votemap` and `sm_votekick`. | Regulars still want a different map after the admin goes to sleep. A kick vote is the same mechanism, and it is also how a lobby removes the person who is winning. | No vote. Excellent aim, fast reactions, and machine control are not grounds for removal. Humans and agents share the room. |
| Ban, expiry, and taking it back | SourceMod `sm_ban` takes a duration and a reason. `sm_unban` removes a Steam id or an address. `sm_banip` of an arbitrary address is an RCON-level act. | Most removals are temporary, the reason has to be readable next week, and a shared address catches the wrong neighbor. | `server/src/access.rs` already has address and CIDR bans, `expires=`, `reason=`, a strict parse, and a reload that keeps the last good file. The desk can append one live address. It cannot list the file or remove a line. A name is not a ban identity. |
| Quiet, without throwing them out | SourceMod separates kick, ban, and chat. Mute and gag exist so a bad voice is not an automatic removal from a good round. | The fight can stay. The speaker stops. | Speak has a cooldown and a length cap. The only way to stop one person talking is to kick or ban them. |
| A probe that does not join | Minecraft `enable-status` and `enable-query`. Source A2S. `hide-online-players` exists because a ping should not be a roster. | Server lists and process checks need a count. The roster is the operator's business. | `GET /status` is already this, on the game port, and it does not take a slot. `?clients=1` stays anonymous and is answered only from loopback. The night sheet adds three counts. |
| The audience is not the fight | SourceTV uses its own port. Its bug notes record that a game server carrying a large live audience drops its tick. | A delayed relay keeps watchers from playing the future, and keeps the fight process off the broadcast. | [Server excellence](server-excellence.md) already owns the delayed relay and the rule that a friend on the couch stays a direct spectator. This plan does not build it. |
| A saved seat for the admin | SourceMod reserved slots default to zero. One mode keeps a slot free so an admin can still get in. Another kicks the highest-latency non-admin, spectators first. | Someone has to be able to act when the server is full and a player is asking for help. | The cap is 64 connections, spectators included. A home night does not fill it. Kicking a watcher to make a seat is the wrong default. Revisit only if the measurement pass shows the cap is the door. |
| An in-game admin ladder | SourceMod flags split reservation, kick, ban, unban, map, votes, cvars, and RCON. Immunity levels stack on top. | A community with several moderators cannot share one root password. A listened client that holds those flags is also how the room gets stolen. | One machine, one operator: the person who can open the local desk. A fighter's client is not a moderator. |
| File and client checks | Source `sv_pure`. VAC. Minecraft `online-mode`. | Public communities were losing matches to bright skins and modified clients, and they tied identity to an account platform. | [Fair play](fair-play.md) already refuses kernel drivers, client scans, and automatic bans. Skill and agent control are welcome. This plan does not add a check. |
| Why the tick slipped | Minecraft `max-tick-time` restarts a frozen process. Paper's timings and Spark exist so an operator can see which part of the tick grew. | A long-running process fails slowly, and the log from last week is the evidence. | Tick time is already on the status report. The night sheet records the room. The measurement pass records choke apart from a missed tick. This plan does not add a second meter. |
| Stop without a hard kill | Minecraft `stop` saves and exits. Source finishes a map change on a command. A console interrupt does neither. | The operator wants the current round written down, and the people in it told, before the port closes. | End of desk input already leaves the match running. A console interrupt ends the process wherever the round is. There is no "finish this show, then exit." |

## What is missing, in the order a home night feels it

The shipped desk is the right first tool and the wrong place. It works only
while the launching terminal is still attached. The night people actually
run is detached, so the operator cannot see the room, cannot remove anyone,
and cannot change the next show without killing the process and starting
the list over.

Build these slices in order. Each one is playable on the current maps. Do
not start a slice by adding a public port, a gameplay bump, or a web page.

### 1. Attach the desk to a process that is already up

`--desk` opens a local control endpoint on a dedicated arcade process.
`--attach` is a second invocation of the same binary that speaks the
existing verbs and does not bind the game port. Closing the attach client
leaves the match running, the same rule stdin already has.

The credential is the operating-system user. On Windows the endpoint is a
named pipe whose access list is the creating user. On Unix it is a socket
file mode `0600` in a directory mode `0700`. The pipe or socket name is
random. A pointer file for that game port, in a user-owned directory, tells
`--attach` where to dial. The pointer holds a path, never a password.
`FRAGR_DESK_DIR` overrides the directory for a test. A second local user
cannot open the endpoint.

There is no TCP listener for the desk, including on loopback. A loopback
port is any local account, and a password on it is the hazard the Minecraft
wiki names. A person away from the machine reaches the desk by logging into
that account and running `--attach`. SSH is the remote channel. This plan
does not add a fragr password protocol.

The game port does not accept desk verbs. They are not `ClientMessage`
values and they are not fields on `Action`. `Action` denies unknown fields,
so a verb smuggled onto a fighter's input would drop the whole action on a
strict server and must not be sent.

Desktop Host, a local mission, the run preview, a map file, and the bench
still have no desk. They already own stdin, and a campaign run is one
person's session. `--console` stays the attached terminal for a process
that has one. The terminal and `--attach` share one parser. One line is one
verb.

The documented night command gains `--desk`. A process started without it
still has no socket. Do not replace a running process just to turn the flag
on.

### 2. A name on the door, and a word for the people you invited

Two optional strings, set from the environment or from the host file in
slice 3, never from a process listing:

- Venue name, at most 40 Unicode scalars, plain text. Additive on
  `LiveStatus` as `venue`, omitted when empty, schema stays 2. The join
  page shows it above the map. An older client that ignores unknown status
  fields still sees the map and can still watch or join an open night.
- House line, at most 80 scalars, no control characters. The join card
  shows it before Watch or Join. It is a posted notice. It is not a Host
  line, not markup, and not a second `say`.

`FRAGR_VENUE_PASSPHRASE` is 8 to 64 scalars, or a file path via
`FRAGR_VENUE_PASSPHRASE_FILE`. Unset means the door is open. The value is
never logged, never put on status, and never accepted as a command-line
argument. Status gains additive `private: true` when a phrase is set.
Absent means open, so an older host stays joinable and Watch and Join stay
available. A private door does not disable the buttons. The page asks for
the phrase, then the hello carries it.

A wrong or missing phrase on a private door is `join_rejected` before a
seat, for humans, agents, and spectators. Tickets stay what they are.
A host may require both. The home default is the phrase alone. The client
sends the phrase only after status says the door is private, so an open
server never sees the field. Hello already ignores unknown fields. A new
private server tells an old client, in the rejection, that the venue is
private. That rejection is not a version mismatch and does not by itself
send anyone to the release page.

The phrase is not a callsign list. Addresses remain the ban identity.

### 3. One file recreates the night

`--config <path>` loads a UTF-8 file. Lines are `key = value` or comments.
A missing file, a bad line, or an unknown key refuses startup and names the
line. The process does not rewrite the file, so the operator's comments
survive. Without `--config`, today's flags still start a server. When both
set the same key, the command line wins and the log says so.

Keys this file may hold: `bind`, `bots`, `bot_policy`, `fill_target`,
`playlist` (`night` or a path), `ban_list`, `allow_list`, `seed`, `venue`,
`house`, `passphrase_file`, `desk`. `passphrase_file` is a path. The secret
stays in that file.

Keys this file refuses, with the line number: anything that sets a frag
limit, a capture limit, a Sabotage format, a round clock, the tick rate, a
snapshot rate, or a byte budget. The mode owns its clocks. Rate clamps stay
on the measurement ladder until a pass has a number worth setting. Quake
Live's split is the rule: the host file is the machine, the mode is the
show.

Bans keep the access-list parser and the five-second reload. Slice 3 does
not invent a second ban store.

### 4. The next show, and a stop that finishes the one that is live

The October 7 local increment supports a validated next map/mode through the
existing attached desk. It waits for the whole show and then repeats the
manual choice; `next` on a night playlist returns to its automatic order.
The file-backed playlist, mutator selection, bot target changes, reload and
graceful stop described below remain planned.

A playlist file is one show per line: a map token the `--map` flag already
accepts, a mode token, and only the mutators that flag already accepts.
A Sabotage line may say `short` or `match`. A blank line and a `#` comment
are skipped. Startup refuses a show the map cannot host, the same pairs
`--playlist` already refuses. `playlist = night` remains the built-in list.
A bad `reload` keeps the list that is running. Reading the file happens at
startup and on that verb, off the tick.

Desk verbs, all exact and quiet when the name is ambiguous:

- `shows` prints the list and marks the live show.
- `next` arms the following line. The live show plays out, including a
  Sabotage half and its side swap.
- `map <token> <mode>` arms that show as the next one. It does not move a
  pawn who is in a round.
- `bots <n>` changes the fill target between lives. It does not remove a
  human or an agent. Bot-fill still yields a roster seat when a person
  arrives.
- `reload` rereads the playlist and the access files. Access files already
  reload on their own. A bad playlist keeps the old one.
- `stop` finishes the live show, logs the reason, then exits 0. `stop now`
  exits without waiting, and the desk says that it did. A console interrupt
  remains a hard stop. The operator sentence is to use `stop` when the room
  is occupied.

### 5. Undo a mistake, and quiet one voice

- `bans` prints address, expiry, and reason. It does not print a name.
- `unban <address>` removes one exact line through the existing access
  writer, atomic replace, then that address is no longer dropped for that
  line. A CIDR entry is removed only by the same text. A failed write leaves
  the file and the room alone.
- `mute <name>` drops that seat's Speak until they leave or `unmute` runs.
  Fire, movement, and the match are unchanged. An agent uses the same mute.
  The audit target gains `mute` and `unmute` with the address and the
  callsign the desk already prints, and without the text they tried to say.
  Kick and ban still remove the pawn. Mute is not a ban and does not write
  the ban file.

No automatic ban. [Fair play](fair-play.md) still owns any later switch for
repeated transport abuse, and that switch stays off.

### 6. The room picks the next map

Off unless the host file says `votes = maps`. A living fighter, human or
agent, can call one map vote. Spectators cannot. The choices are lines from
the loaded playlist, not a path. The vote needs at least two living fighters
and a majority of them. It has a cooldown. The winner becomes the next show
and does not abort the live round. Agents send the vote on the slow control
path, one vote, the same cooldown as a person.

There is no vote to kick, ban, or mute. Score, accuracy, and control role
are not inputs to a vote. If a kick vote is ever proposed, it is a separate
decision and a separate plan.

## Non-goals

- A passworded desk protocol, a LAN listener, or a web panel. SSH to the
  host account plus `--attach` is the remote door.
- Putting kick, ban, map, or `stop` on the tilde console of a client that
  joined someone else's night. On the machine that is hosting, the host
  verbs in [console.md](console.md) call this same desk. Frag limit and
  time limit stay with the mode even there.
- A public directory, a master server, or a hostname that registers anywhere.
- Callsign bans, accounts, and a whitelist of names. The allow list remains
  addresses.
- Kernel checks, client scans, `sv_pure`, and reserved slots that evict a
  watcher.
- Demos, a delayed relay, and snapshot interest. Those stay in server
  excellence and fair play. The desk does not grow a `record` verb here.
- Editing mode clocks, raising the tick, or shipping UDP.
- A second logger, log rotation inside the process, or a phone-home.
- Replacing the running night binary. Slice 1 is source until a launch is
  asked for. A rebuilt binary that speaks a newer gameplay contract would
  refuse the published client.
- Any claim that the server is finished, cheat-proof, or exceptionally
  secure. These tools make the room operable. They do not prove the absence
  of bugs.

## Architecture

Reuse `server/src/desk.rs` as the only verb parser. `--attach` and stdin
both call it. The socket accept loop lives next to the desk, not in the
tick. A desk line that writes the ban file or the playlist uses the same
off-tick path the ban append already uses.

Reuse `server/src/access.rs` for `bans` and `unban`. One store, one reload.

Reuse the playlist walk in `server/src/sim/playlist.rs`. A file is another
source of the same show list. The built-in night list stays the default of
`--playlist` with no file.

Reuse `GET /status` for `venue` and `private`. Do not add callsigns,
addresses, or the phrase. The join page in `client/scripts/boot_menu.gd`
reads those two fields and keeps the rule that a warning or a private door
does not, by itself, disable Watch or Join.

`server/src/main.rs` gains `--desk`, `--attach`, and `--config`. Campaign
and desktop Host keep their conflicts with the desk. `infra/docs/HOME-LAN.md`
gains the `--desk` night command and the SSH-then-attach sentence in the
same change as slice 1. A container with no stdin can mount the desk
directory for the host user. It still does not expose a desk port.

## Protocol

Slice 2 is the only game-wire change.

- `LiveStatus` gains optional `venue` (string) and optional `private`
  (bool, omitted when false). Schema version stays 2. Older JSON still
  parses. A body that contains a callsign is still rejected by the existing
  status size and anonymity checks.
- Hello gains optional `phrase`, omitted when empty. The client includes it
  only when status said `private`. The server compares it in constant time
  and then drops it. Logs, audit fields, and status never carry it.
- Rejection code `venue_private`, message
  `This venue is private. The door did not open.`
  A bad phrase uses the same sentence, so the reply does not reveal which
  check failed.
- No new gameplay version. An open server accepts a hello that omits
  `phrase`. A private server rejects a hello that omits it, at every role.
- Map votes in slice 6 are a slow client message, denied on a campaign
  socket and on a server with `votes` unset. They are not `Action` fields.
  The exact shape is written into `docs/protocol.md` in that slice, with
  adapter tests, and not before.

Desk traffic is local IPC. It is not in `docs/protocol.md`.

## Verification

Name the test before the slice. Spend is $0. No cloud apply. No paid call.
No tour republish until a player-visible slice is in a release.

1. An attached client receives `who` from a server whose stdin is closed,
   and that server is still accepting game joins afterward. A second local
   principal cannot open the endpoint. A `who` frame on the game port
   returns no roster and does not fill the malformed strike by itself if it
   is simply an unknown type the server already ignores. A known
   `Action` that also carries a desk field still fails the existing unknown
   field rule and is covered so nobody "fixes" it by widening `Action`.
   Desktop Host still refuses `--desk`.
2. Status omits `venue` and `private` when unset. A private server rejects
   a spectator hello with no phrase and admits one with the phrase, and the
   audit line has no phrase. The Godot join harness shows the venue and the
   house line, asks for the phrase, leaves Watch and Join enabled, and does
   not send `phrase` to an open host. `test_server_book.gd` and
   `test_frontend.gd` are the harnesses.
3. A config with a comment and a refused `frag_limit` line exits before
   bind and names the line. A valid file plus a command-line `--bots`
   keeps the command line and logs the override. The file on disk is
   byte-identical after startup.
4. A playlist line `compliance-yard ctf` refuses startup. `next` during
   Sabotage does not skip the half. `stop` exits 0 only after the live
   show's result is logged. `stop now` exits without that wait. `bots`
   does not drop a joined human.
5. `unban` of an address that is only one line lets the next hello through.
   A failed write does not. `mute` drops Speak and still lets that pawn
   fire. The public status body still has no callsign.
6. With votes off, a map vote is ignored. With votes on, spectators are
   not counted, a majority arms the next playlist line, and the live
   Sabotage round still finishes. An agent and a human each have one vote.

Then the crate's normal fmt, clippy, and the focused server tests. The
full server suite and `tools/godot_check.sh` run before a slice is called
done. Slice 2 is the one that changes a screen, so its join-page harness
is part of done. Screenshot publication waits for a release.

## Success

- A detached dedicated process, started with `--desk`, can be operated
  with `--attach` after the launching terminal is gone. The match survives
  the attach client leaving.
- A friend can read the venue name and the house line before sitting, and
  a stranger who has the address still cannot watch a private night.
- The same night comes back from a file after a reboot, with the operator's
  comments intact, and that file cannot retune a mode clock.
- The operator can arm the next show, quiet one voice, undo one address
  ban, and finish the live show before the process exits.
- Public status stays anonymous. The player console gains none of these
  verbs. The measurement pass is still the scale ladder's next step.

## Sources

- Zandronum server variables (`sv_hostname`, `sv_motd`, `sv_joinpassword`,
  `sv_rconpassword`, `sv_minvoters`, `sv_nocallvote`, map rotation),
  checked 2026-10-06: <https://wiki.zandronum.com/Server_variables>
- Valve, Source Dedicated Server (`server.cfg`, `hostname`, the game port
  shared with RCON, SourceTV on its own port), checked 2026-10-06:
  <https://developer.valvesoftware.com/wiki/Source_Dedicated_Server>
- AlliedModders, SourceMod admin commands and reserved slots, checked
  2026-10-06: <https://wiki.alliedmods.net/Admin_commands_(SourceMod)>
  and <https://wiki.alliedmods.net/Reserved_Slots>
- Minecraft Wiki, `server.properties`, including the RCON warning and the
  whitelist, MOTD, and status keys, checked 2026-10-06:
  <https://minecraft.wiki/w/Server.properties>
- Quake Live community server standards. Host file and mode factory stay
  apart: <https://github.com/quakelive-server-standards/quakelive-server-standards>
- SourceTV bug notes, already cited by server excellence:
  <https://developer.valvesoftware.com/wiki/Source_TV_Buglist>
