# Changelog

Shipped tags, newest first. A line here is on `main`. Planned work stays in
[docs/ROADMAP.md](docs/ROADMAP.md). Older tags are on the
[releases page](https://github.com/blisspixel/fragr/releases).

## v0.47.1 (2026-09-24)

Multiplayer rounds on Directive 17, Sector 9 and Reclamation Gulch no longer
open with fighters standing in each other's rail lanes. Each of those maps
gains sixteen spawn cover pockets, three pickup pads moved a few metres behind
the new blocks, and respawns ignore lanes longer than any gun can reach. Across
sixteen seeded runs on maps 3 to 6, spawn deaths fell from 47 to 7, and none of
the remaining ones happen at the round opening. The playtest now fails a run
with more than one opening spawn death per round.

## v0.47.0 (2026-09-24)

fragr now has downloadable desktop builds. Each tagged release attaches a
Windows, Linux and macOS zip that holds the game with its local server beside
it, so Single Player starts without building anything. Every package carries
the fragr, font, Godot and bundled Rust crate license notices. The builds are
unsigned: Windows SmartScreen and macOS Gatekeeper ask once, and the README
gives the steps. CI unpacks each package and checks that the game finds its
server; a clean-desktop playthrough is still to be recorded.

The game has its own icon, a pixel triangle and eye from the fragr mark, in
the window, the taskbar and the packages. The app is now named fragr, and
settings and the service record move over from the old "fragr Client" folder
on first launch. A startup bug that left Single Player's saved-run preview on
"loading" in exported builds is fixed.

## v0.46.1 (2026-09-24)

The client now explains why a server closed the connection. Idle, flood,
unreadable-message, banned and not-allowed closes each show their own short
localized message on the existing status line. After a kick the client no
longer makes its automatic resume attempt; an idle close still gets its one
ten-second resume, like any dropped connection.

## v0.46.0 (2026-09-24)

A server open to the internet now looks after itself. It pings every session
every 15 seconds and closes one that sends nothing for 45 seconds with
`idle_timeout`; a spectator that is still reading answers the ping and stays.
A sustained message flood closes with `rate_limited`, and repeated unreadable
frames close with `malformed`. Both remove the pawn. A well-formed message of
an unknown type is still ignored, so a newer client is never kicked for it.

Hosts can pass `--ban-list` and `--allow-list` files of IP addresses or CIDR
ranges with optional expiry and reason. Malformed files refuse to start the
server, edits are picked up within five seconds, and a new ban closes a
matching live session. Joins, rejects, kicks, bans and list reloads go to the
`fragr_server::audit` log target without tickets or tokens. The Godot client
does not yet show a message for the new close codes.

## v0.45.0 (2026-09-23)

Single Player now keeps its M01 run after Exit to Menu or closing the game.
Continue Run restores the same identity, difficulty, mission-entry equipment,
and remaining continues. A pending Continue remains pending after restart;
spending it saves the lower allowance before play resumes. Start New Run
archives the previous save after confirmation. An explicit Leave ends the run.

M01 departure freezes the live exit equipment and retains the completed run
as M02 pending, even after its owner disconnects. Invalid or incompatible
bytes stay recoverable. Saves are local mission-entry saves, not mid-mission
checkpoints. The 24-state visual tour, real child restart tests, a free local
M01 clear, and Linux, Windows, and macOS CI passed. M02 is still unbuilt.

Rapid campaign restarts now retire radio playback cleanly before Godot exits.
The restart and radio checks cover the decoder lifetime on all three client
CI platforms.

## v0.44.1 (2026-09-23)

A spectator that stops reading can no longer grow an unlimited server send
queue. Each connection has a bounded outbound queue; a full queue or stalled
socket drops that connection through the usual cleanup. A fighter that asked
for resume keeps its existing ten-second recovery window. The current 32 per
address and 64 global connection caps remain. A twelve-roster local test,
including 16 fighters with 16 spectators, had no snapshot gaps or watcher
disconnects; it does not establish Internet capacity.

The reference agent now asks campaign-specific questions, follows the mission
objective when no visible fight needs attention, limits decisions to carried
weapons, and reports the server's mission outcome and continues. A watched free
rules run cleared Standard seed 67 on its second attempt. Other seeds still
need campaign tuning. The README tour stills were refreshed and inspected.

## v0.44.0 (2026-09-22)

Recall Notice has two optional walking detours: a medkit in the confiscation
locker recess and armor on the maintenance overlook. Neither is needed to
reach the lift. The first-person exploration tour verifies both routes, and
the capture stops if a walking leg fails. The pickup meshes remain provisional.

## v0.43.1 (2026-09-22)

The spectator camera keeps following its fighter while a match menu blocks
controls. A local first-person agent watch captures rendered frames with the
same server-assigned participant ID as its action receipt. Paid Jev requests
reserve budget before sending, so retries and uncertain responses cannot
silently spend the same allowance twice.

## v0.43.0 (2026-09-22)

The Clerk and the Sweeper no longer share one outline. The Sweeper is the wide
bot with the level rifle. The Clerk is the narrower human, and aiming clears
the pistol past the shoulder. The atlases are unshaded local rigs. No new
paid sheet was generated.

## v0.42.0 (2026-09-22)

The mouse wheel, the bracket keys, and 1 through 5 walk the guns you are
carrying: fists, pistol, shotgun, rifle, and railgun. A gun you are not
carrying is skipped. The README shows four stills: the boot menu, Recall
Notice, the multiplayer page, and one watched match.

## v0.41.0 (2026-09-22)

The corner, pickups, the spectator line, and the service record read Pistol,
Rifle, Shotgun, and Railgun. Ammo pads read Bullets, Shells, and Cells. A
sniper rifle, rocket launcher, grenade, and proximity and remote mines are
named as later campaign finds. They are not in this build.

## v0.40.0 (2026-09-22)

The Recall Notice card in the upper right is the introduction. Briefing keeps
it until the mission starts. The find-the-record and lift lines stay for eight
seconds, then the card goes away. The use prompt still appears at the object.
The ending card stays. The published room stills no longer carry that box. The
multiplayer page example is 127.0.0.1:6767.

## v0.39.0 (2026-09-22)

A socket blip no longer deletes the fighter. The app asks to keep the pawn,
retries one dropped connection, and shows "Reconnected." Leave, or switching
back to spectator, removes that pawn immediately. The body stays and can still
be shot. After ten seconds without a return, the pawn leaves. A client that
does not ask still loses the pawn on close. Nothing rewinds the match.

## v0.38.0 (2026-09-22)

A server with no `FRAGR_JOIN_SECRET` still accepts every hello. Set the
variable and a human or agent hello needs a short ticket minted from it.
Spectators can watch without the secret. A refused player sees "This server
refused the join."

## v0.37.0 (2026-09-22)

The multiplayer page reads `GET /status` and shows the map name, whether the
match is an arena or a mission, and the fighter and connection counts. Watch
and Join stay disabled until that line is real. A missing kind is not treated
as an arena. There is no web client.

## v0.36.0 (2026-09-22)

`GET /status` on the game port answers before the WebSocket upgrade and does
not take a connection slot. It reports the map, the round, the tick, and
counts. It does not list callsigns or addresses. One address may hold 32
connections. The process still stops at 64.

## v0.35.0 (2026-09-22)

Incoming frames stop at 64 KiB. A stalled handshake or hello releases its
slot. Inbound text stops after a burst of 64 and 256 per second. A quiet
spectator stays connected.

## v0.34.0 (2026-09-22)

Recall Notice's bypass is its own fight. The records deck can see the custody
lift. Departure names the correction ward. Leaving an owned Single Player run
says the run is abandoned.

## v0.33.0 (2026-09-21)

Portable graphics settings: resolution selection and quality presets through
the shared settings panel.

## v0.32.0 (2026-09-21)

Service records and a quieter combat feed. Corner notices expire on their own.
Pickup notices follow the participant. The default mix keeps the radio present.

## v0.31.0 (2026-09-20)

A local Recall Notice run has three explicit mission-start continues. The
fourth death ends the run. A continue restores the mission entry and does not
rewind the match.

## v0.30.0 (2026-09-20)

Assisted, Standard, and Severe difficulty for a new local campaign. Enemy
tells and recovery change. Health, damage, and supplies stay consistent.

## v0.29.0 (2026-09-20)

Recall Notice continues through records reception, file stacks, sorting,
dispatch, and transfer control.

## v0.28.0 (2026-09-20)

A skippable, reader-paced opening for Recall Notice, and covered spawns at
Tripoint.

## v0.27.1 (2026-09-20)

The first map reaches a client before live broadcasts, including a client that
connects while the server is already running.

## v0.27.0 (2026-09-20)

Single Player launches Recall Notice and owns that server for the run.

## v0.26.0 (2026-09-20)

The transfer record and a shared departure from the custody lift.

## v0.25.0 (2026-09-20)

The intake encounter: Clerks, Sweepers, and the facility around them.

## v0.24.0 (2026-09-20)

Recall Notice starts with fists. The pistol and the rifle are found. Ammunition
is finite and reload is authoritative.

## Earlier

Tags before v0.24.0, including the arena, the adapter, and the first playable
tip, are on the
[releases page](https://github.com/blisspixel/fragr/releases).
