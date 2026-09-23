# Changelog

Shipped tags, newest first. A line here is on `main`. Planned work stays in
[docs/ROADMAP.md](docs/ROADMAP.md). Older tags are on the
[releases page](https://github.com/blisspixel/fragr/releases).

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
