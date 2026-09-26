# Changelog

Shipped tags, newest first. A line here is on `main`. Planned work stays in
[docs/ROADMAP.md](docs/ROADMAP.md). Older tags are on the
[releases page](https://github.com/blisspixel/fragr/releases).

## v0.55.1 (2026-09-26)

The Recall Notice opening has pictures. The first two pages show Latch at the
workshop bench, and the last shows Annex 67's service entrance at dusk. The
address and the recall stay text pages until their pictures are made in the
black and red Union look; the words on every page are unchanged.

## v0.55.0 (2026-09-26)

Multiplayer has modes now, and the host picks them. `--mode tdm` splits the
server into two sides: the Union in black and red against the free coalition
in bone and ember. Everyone who joins, human, agent or rule bot, lands on the
smaller side, each side spawns in its own half of the map, your own shots cannot
hurt a teammate unless the host adds `--friendly-fire`, and the first side to
25 takes the round. Fighters, nameplates, the scoreboard and the killfeed wear
their side's colours, and a spectator sees the side of whoever they follow.

Six GoldenEye-style mutators stack on either mode with `--mutator`: Rail Only,
Shotgun Only and Fists Only hand everyone one weapon with endless ammunition;
Licence to Kill makes every hit a kill; Golden Rail puts one golden Railgun on
the map that kills in one shot, makes its holder glow, and goes home when they
die; Two Lives gives everyone two lives a round and the last one standing wins.
A chip at the top of the screen names the rules for players and spectators,
and agents read the same rules from `round_state`.

The Host now calls first blood, the end of a streak, a comeback from four down,
the last fighter left on a side and whoever grabs the golden Railgun, in short
lines that rotate so a regular hears them all.

The Railgun's Cells cap rises from 50 to 100. Clients and agents now speak
gameplay capability 12, which every campaign map and every server with a rule
set requires.

## v0.54.0 (2026-09-25)

Finishing Recall Notice now plays a short scene over the departure card: Latch's
ledger, Mara at the van and the correction ward ahead. It is three captioned
pages for now, with pictures and voices to come, and Escape or B skips it. It
plays once and changes nothing about the run.

Story scenes are data now. The M01 opening and every later scene play from a
manifest of shots, each with a still that drifts slowly, a keyed caption with a
speaker label, an optional voiced line and optional music and ambience. A
voiced shot moves on when its line ends; the last shot always waits for you. A
missing picture or clip falls back to the text page you see today, so no scene
ever waits on an asset. The opening reads as before, with a small progress row.

The Audio settings gain VOICE, a separate volume for spoken story lines, and
STORY CAPTIONS. Captions show by default and can be hidden only while a line is
being spoken; C or Y toggles them inside a scene.

## v0.53.0 (2026-09-25)

Recall Notice has its first secret. Step into the far corner of the
confiscation alcove, past the medkit by the property lockers, and you find a
Shiv. It is a knife, not a gun: no ammunition, three quick cuts drop an
unarmoured guard where fists need five, and it reaches a little farther than a
punch. Picking it up draws it, a quiet SECRET FOUND line appears in the corner,
and your service record counts the find. Press 1 to switch between the Shiv and
your fists. You never need it; both routes clear the same without it.

A continue puts the Shiv back in the alcove and takes it out of your hands, and
finding it again is not a second secret. Agents on the MCP door can select it as
`shiv`, and the shared controller reaches for it instead of fists when every gun
is empty.

Campaign clients now need gameplay capability 11. A Recall Notice save from an
earlier version cannot continue: the menu offers a new run and keeps the old
save file beside it.

## v0.52.0 (2026-09-25)

Recall Notice and the Persons Unknown ward are lit like rooms now, not like a
graybox. A warm, readable base light fills every room, the ceiling strip
lights add brighter pools with soft shadows under them, a thin haze gives long
rooms depth, and Union seals burn a small red lamp. Dark steel carries red
warning strips and the enamel walls a red pinline. The black-and-red Union
stays easy to spot: red visors, optics and tell lights glow in any light, the
darkest cloth reads as charcoal, and a faint outline separates every enemy
from the wall behind it. The arenas sit under a warmer, stronger sun with
readable shade behind cover.

Graphics settings gain World Pixels (Native, Fine, Medium, Chunky), an exact
nearest-neighbour upscale of the 3D view that leaves menus and the HUD sharp,
and an optional Palette Dither onto the game's palette. Both are off by
default. Balanced now adds contact shading, fixture shadows and lamp glow;
Performance stays as cheap as before. Frame times are in
docs/plans/look-pass-boomer.md.

## v0.51.0 (2026-09-24)

Play the way you like: the keyboard alone, the keyboard and mouse, or a
gamepad. On the keyboard alone the arrows walk and turn, Alt with an arrow (or
Comma and Period) strafes, Page Up and Page Down look, End centres the view,
either Ctrl fires and Enter uses, so one hand can stay on the arrows. Turning
starts slowly and reaches full speed in a quarter second, so a tap is a small
correction rather than a lurch.

Settings has a Controls page that rebinds every action for keyboard, mouse and
gamepad, warns when a key moves from one action to another, and resets to the
defaults. A Look page holds mouse sensitivity (with centimetres per turn), key
turn speed, stick deadzone, curve, separate turn and pitch speeds, a turn boost
for spinning round quickly, and aim assist.

Aim assist is on Standard by default for keyboard and gamepad look and never
for the mouse. On the keyboard it eases your aim up or down onto a visible enemy
near the crosshair's line, as Doom did, and nudges gently when one is almost
centred; on a gamepad the stick slows near an enemy and pulls a little while you
steer. It only moves the aim you already send, never through cover; the server
still decides every hit. Mouse look is untouched: raw counts, no smoothing.

The sticks now use a round deadzone and a response curve, Start opens the match
menu instead of leaving the match, and the use and continue prompts show the key
you would press, or a small pad glyph in the letter, shape or positional layout
of the pad you touched last.

## v0.50.1 (2026-09-24)

Hosts can see how their server is doing. `GET /status` keeps its existing
fields and adds a health verdict (ok or degraded, with reasons such as slow
ticks, a low tick rate or dropped slow readers) and an operations block with
tick timing percentiles, the real tick rate, traffic per client and in total,
connections by role, uptime and the build version. `fragr-playtest --soak`
runs the real server with bots, agents and spectators for as long as you ask
and fails on a crash, a drop, a degraded sample or memory growth. Two local
soaks of over an hour held tick p99 under 1.6 ms with flat memory; a 24-hour
soak is still to come.

## v0.50.0 (2026-09-24)

The Union now looks like what it is. Clerks and Sweepers wear black cloth and
dark steel with restrained red on visors, optics, armbands and seals, and stand
out against the bone and green interiors of Recall Notice. Their silhouettes
are unchanged, so each still reads by shape first.

Two new Union enemies are built and tested on a development range, ready for
later missions: the Heavy Sweeper, a slow armoured bot whose shoulders flare
before a four-round burst and who staggers only under heavy hits, and the
Turret, fixed equipment that sweeps its head, lights red coils and spins up
before one strong shot that breaking line of sight cancels. Difficulty changes
their warnings and recovery, never their health or damage. Neither is placed
in a mission yet.

## v0.49.0 (2026-09-24)

Guns now work the way Doom does. There are no magazines and no reloading: you
carry one count of each ammunition type and every shot spends one. The Pistol
and the Rifle share Bullets, the Shotgun uses Shells and the Railgun uses Cells,
and the corner shows a single number beside a small ammo sprite for the gun in
your hand. R no longer does anything. Caps are 200 Bullets, 50 Shells and 50
Cells.

The Shotgun is a real shotgun. Each blast is seven pellets in a tight cone, every
pellet hits or misses on its own, cover stops the ones that meet it, and one blast
can hit two people. Up close all seven land for 70 damage, so two blasts drop an
unarmoured fighter. Farther out fewer pellets land and each hits softer. You can
see every pellet's trace and spark.

Recall Notice guards no longer pause to reload either, and its ammo boxes now
hold bullets. A Recall Notice save from an earlier version cannot continue: the
menu offers a new run and keeps the old save file beside it.

## v0.48.0 (2026-09-24)

Single Player has a development entry for the second mission, "Persons
Unknown: ward graybox". Drop from the observation gallery down the service
stair, grab the pistol and the shotgun, and fight Clerks and Sweepers through
the correction ward, the processing floor and the loading dock. There are no
switches or locked doors; the HUD shows one short line at a time, "Find Latch"
and then "Get out". It is an untextured development route: no save, no carry
from Recall Notice, and Latch and the Jammer are not in it yet.

A quick tap of Use or jump is no longer lost on a fast display. The client sent
one action per rendered frame, so at a few hundred frames per second it went
past the server's inbound limit and about half its messages were dropped,
including a tap that lasted one frame. Actions are now paced at 120 per second
and a tap is held until a message carries it.

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
