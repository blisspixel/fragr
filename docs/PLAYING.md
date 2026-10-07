# Playing fragr

[Back to the README](../README.md) | [Campaign contract](CAMPAIGN.md) |
[Current build order](ROADMAP.md)

## Choose a game

**Recall Notice** is the local solo campaign development mission. Build the
server (`cargo build -p fragr-server --release --locked`), run
`godot --path client`, then choose **Single Player > Recall Notice** and a
difficulty. The client starts its own server on loopback. Find Latch's transfer
record in transfer control, after dispatch, recover weapons from the Annex, and
leave by the custody lift. The objective card leaves after a few seconds. A
corner line keeps the bearing until you are at the panel.
Assisted, Standard and Severe change enemy timing; health, damage and finite
supplies stay consistent. M01 has an optional Shiv secret. **Persons Unknown**
continues the run through the M02 ward, with Latch's rescue and optional patient
evacuation. Its independent practice entry remains available alongside the
durable **Continue Run** path. These missions still need fresh-player acceptance.

**Scheduled Service** is the level 3 development prototype. Choose **Single
Player > Practice and Development > Scheduled Service: rail yard prototype**
to start an independent practice child. Clear the freight-yard crews, use
the car roofs or ground flanks, shoot the red transmitter pod after its guards,
then clear and deliberately board the locomotive. Latch releases optional
recall cars after their guards fall and you approach. Those rescues never block
departure. Arrival and train departure currently use reader-paced story pages.

**Notice to Vacate** is the level 4 development prototype. Choose **Single
Player > Practice and Development > Notice to Vacate: Development** for an
independent practice child, or **Continue Run** after completing Scheduled
Service. Defend Low Water's notice board, tram street, market and habitation
court. Flying Notaries commit to an aimed burst: move behind cover or interrupt
the tell, then watch the harmless wreck fall to its actual support surface.
The HUD counts photographs confirmed by the server. Clear the clinic approach
and aim at its control to open the optional shutter with **Use**; approaching
after the clinic is clear releases the patients. Rescue and patient travel never
block the main route. Clear the court and gather the living party at the roof
stair, then aim at its control and **Use** to depart. Arrival and departure use
reader-paced pages; dismissing an arrival waits for held gameplay input to
release before combat starts. Fresh-player pacing and mission acceptance remain
open.

**No Forwarding Address** continues through level 5's workshop, finite grenades
and moving freight tram. **Port of Entry** starts Episode II at the lunar port,
with a found Railgun and Turret flanks. **Declared Goods** continues through
level 7's curfew town and Sniper lesson. **Custodian of Record** brings level 8's
archive, Proximity Mine, Auditor and optional custody rescues. **Passenger
Manifest** is level 9: release the Common Carrier crew and fight to the boarding
hatch. **Common Carrier** is level 10 aboard the ship, with ordered encounters,
bridge controls and a finite remote armory. All ten have independent practice entries and connected saved-run
progression. These remain development prototypes, with final art and
fresh-player acceptance open. Levels 11 through 20 of the twenty-level
campaign remain in development. The [campaign contract](CAMPAIGN.md) and
[roadmap](ROADMAP.md) own the current scope and build order.

**Calibration** is a separate Episode 0 arena challenge. Run
`./tools/solo_scrap.sh` from the repository root. It starts the Host-led
challenge with four named bots. Set `FRAGR_SOLO_BROADCAST=0` for plain Solo
Scrap practice. On Windows, run the shell wrapper from Git Bash. To launch
the two processes yourself:

```bash
cargo run -p fragr-server --locked -- --bind 127.0.0.1:6767 --bots 4 --solo-broadcast
godot --path client res://scenes/main.tscn -- --solo
```

**Multiplayer** connects to a shared server. **Run a server** starts Team
Deathmatch or 5v5 Sector 9 Sabotage with the bundled server. **Join a server**
is a separate address. Check host reads the address you typed and leaves it
there. Choose Watch or Join after the match line comes back. A host you check,
watch, join, or save stays on this computer. Scan this network asks which
machines answer the game port. It checks this computer first, then the rest of
each adapter's /24, and it does not search the internet. A server that does
not announce can still appear. The address field still reaches any host,
including one outside that scan. If this client is behind the host, the page
can install the latest published build, check `SHA256SUMS.txt`, and rejoin
that host. The latest published build may still be older than the server.
Watch and Join stay available. A server you
started in this app stays on the run page, with its own Watch, Join and Stop.
Host controls default to this computer only; enable LAN access to invite
peers using your LAN address and selected port. Leaving or returning to the
menu preserves the match; **Stop server** or closing the app ends your owned
host.

**Benchmark**, on the main menu, times the frames on this computer. It starts
its own Arena Duel match with ten bots and a fixed camera, on a port this
computer picks. A server you already left running for other people stays up.
Vertical sync and the frame cap turn off for the run, then your settings
return. The score separates fast even frames from hitches and from frames that
are slow on their own. A live match changes between runs, so compare the frame
times. The recorded nine-scene showcase is still ahead.

Choose no bots, a fixed count or automatic fill toward a total fighter count.
Automatic fill gives humans and agents equal priority over eligible filler
bots. If a full Sabotage room cannot safely replace a bot during the current
round, watch and try joining at the next round.
Older releases require a separately started server. The host chooses
the arena and rules. Spectators, humans, agents and rule bots share the same
authoritative match. The current release includes free-for-all and team
deathmatch, six arenas, capture the flag on Arena Duel, Directive 17 and Sector 9,
and Sector 9 Sabotage (plant or defuse a charge, one life per round). The optional
5v5 Sabotage profile starts fighters with a Pistol and finite Bullets; stronger
weapons come from the map. See [5v5 host setup](../infra/docs/HOME-LAN.md#optional-5v5-sabotage).
Current mutators include Rail Only, Shotgun Only, Fists Only, Licence to
Kill, Golden Rail and Two Lives mutators. The Host runs the round and reacts
to first blood, streaks and close finishes. See the
[hosting guide](HOSTING.md) to run a server.

## Watch, join and control

The client starts as a spectator when joining a multiplayer match. Press **J**
to join, **L** to return to watching, **F** to change the watched fighter, and
**V** to cycle eyes, chase and free camera. The match continues when you leave
the fighter seat. **Esc** opens the match menu. All actions can be rebound in
**Settings > Controls**; prompts follow the last device used.

| Action | Keyboard only | Keyboard and mouse | Gamepad |
|---|---|---|---|
| Move | Up and Down | W and S | Left stick |
| Turn | Left and Right | Mouse, or Q and E | Right stick |
| Strafe | Alt with arrows, or Comma and Period | A and D | Left stick |
| Look vertically | Page Up and Page Down | Mouse | Right stick |
| Center view | End | End | Right stick click |
| Fire | Right Ctrl | Left mouse | RT |
| Duck | Left Ctrl, hold | Left Ctrl, hold | not bound |
| Reload | R | R | not bound |
| Scope | Z, hold | Right mouse or Z, hold | Left stick click |
| Throw grenade | G | G or middle mouse | LT |
| Use | Enter | F | B |
| Jump | Space | Space | A |
| Campaign continue | Enter | Enter | A after releasing held inputs |
| Weapons | [ and ], or 1 through 6 | Wheel, [ and ], or 1 through 6 | LB and RB |
| Speak | T | T | Y |
| Join or leave | J or L | J or L | A while watching, or match menu |
| Spectator fighter and view | F and V | F and V | D-pad right and Back |
| Radio station, skip track, play or pause | C, N, M | C, N, M | not bound |
| Match menu | Esc | Esc | Start |
| Leaderboard, the whole roster | Tab, hold | Tab, hold | Back |

Hold Tab to list every fighter. The corner keeps the first four while you are watching, and it stays hidden in first person until you hold that key. In a team match, someone on your side is marked OURS and stays bright. The other side is marked THEIRS and warms toward red. A spectator still reads UNION and FREE on the full plate.

Hold Left Ctrl to duck. You get shorter and slower, and a low ceiling keeps you short until there is room to stand. Right Ctrl still fires when one hand is on the arrows. The server decides the stance. An older server ignores the key.

Keyboard turning ramps over a quarter second. Mouse look uses raw counts,
without smoothing or aim assist. Gamepad and keyboard look can use Off, Light
or Standard aim assist, which moves the aim sent to the server; the server
still decides hits. Hold scope on the Sniper Rifle only. It narrows the local
view and slows look, on the mouse and on keys. It does not decide the hit.
The [input plan](plans/input-all-devices.md) records
the behavior and verification.

The numbered weapon order is fists or found Shiv, pistol, shotgun, rifle,
railgun and sniper. Key 4 cycles owned automatic-family weapons when both are
available; the Repeater foundation is not granted in current campaign maps.
The wheel and bracket keys skip guns you do not own. Campaign ammo
is one count per type, and that count includes the rounds in each gun. The
corner shows rounds in the gun, then what is left to load. They add up with
the other guns on the same type. R reloads the gun in hand. The pad is not
bound. An empty gun does not fire while rounds remain in the bag. Pistol and Rifle share
Bullets; Shotgun uses Shells; Railgun and Sniper use Cells. A seven-pellet Shotgun blast
costs one shell. An arcade human spawns with the rifle, shotgun and railgun
already loaded, and a finite bag behind them: 60 more rifle rounds, 18 more
shells and 12 more rail shots. The corner uses the same gun-then-bag pair.
Walking over that gun adds a pickup to the bag. Death puts the spawn kit back.
A weapon-only match still has one gun and no bag to run out of.
Agents and campaign enemies still spend the single count. Stand near a mission
panel and aim at it. The prompt under the crosshair names Use: F with a mouse,
Enter on a keyboard, B on a pad. Q and E turn. Before that aim is true, the
same spot says to aim at the panel. An open arena doorway is walked through.

Grenades have a separate count, up to six, and do not replace the selected
gun. A fresh press throws one device; holding the control does not repeat.
It bounces on real world cover and explodes after two seconds with distance
falloff and solid occlusion. Your own blast can hurt you. Arcade loadouts
start without grenades; authored supply claims provide them where registered.

## Solo runs and local records

Recall Notice offers three mission-start continues per episode. Death presents
an explicit retry; exhausting the allowance ends the run. **Continue Run**
reopens the saved mission entry, including body, difficulty, health, armor,
weapons, ammunition, grenades, mines and remaining continues. It does not resume
a mid-mission position. Leaving for the menu retains that entry; **Start New
Run** archives the previous run after confirmation.

Completing each built mission saves the next destination. Episode II refills
continues once when entering Port of Entry after level 5. Source builds also
refill Episode III once on entering Common Carrier after level 9. Reopening, previewing
or retrying does not refill them. Retry resets the current mission's encounters,
devices and local outcomes while preserving earlier recorded choices.
Practice entries leave the durable campaign save untouched.

Rescuing people and seeing them actually depart are separate facts. The workshop
records release and boarding independently. The archive retains custody and
recovered-mind outcomes. Passenger Manifest keeps an immutable receipt of crew
released and feet actually aboard at departure confirmation. Missing historical
facts stay unknown. In source builds, entering level 10 completes boarding for
the actually released eligible crew without an escort wait, retaining transit
arrivals separately from the original berth receipt. The current pilot Tern is
present even when old transit facts are unknown; optional Edda and Splice require
recorded arrival. Orrin remains a secured backup, without an inferred restoration.
The ship has three inhabited development decks and four ordered fights. Its art,
Repeater discovery, story and fresh-player pacing remain in progress. Level 11
is the saved next destination but is not playable yet. The
[ship prototype plan](plans/m10-common-carrier-prototype.md) explains the boundary.

The local file is `run.json` under the platform user-data `runs` directory:
`%LOCALAPPDATA%/fragr/runs` on Windows,
`~/Library/Application Support/fragr/runs` on macOS, or
`$XDG_DATA_HOME/fragr/runs` (usually `~/.local/share/fragr/runs`) on Linux.
Current source writes version 13 saves; desktop v0.75.0 writes version 12.
Supported historical saves upgrade
strictly, retaining exact original bytes in a content-addressed
`run.prior-<digest>.json` archive. Unknown revisions and magazine-era version 1
saves remain incompatible. A changed mission content hash or rules revision can
also prevent resuming; the old file stays until you choose to archive it.

To recover an archive, close the game, keep a copy of `run.json`, and copy the
archive back as `run.json`. It must still match the installed mission and rules.
Keep client and server from the same release. Migration and compatibility
details belong to the [run file plan](plans/campaign-run-file.md),
[carry plan](plans/m01-m02-run-carry.md) and
[Passenger Manifest plan](plans/m09-passenger-manifest-prototype.md).

The **Service Record** stores the latest 256 campaign, arena and practice
records on this device. It shows kills, deaths, effective damage, time alive,
per-weapon hit counts and mission effort across attempts. You can export
JSON. It is local history, not a public ranking or campaign save.

## Settings and current limits

The boot menu and in-match menu share Controls, Look, Display, Graphics and
Audio settings. Choose resolution, quality, frame cap, VSync, field of view,
supported FSR upscaling, an optional frame counter, sensitivity, stick
response and separate master, radio and effects levels. The tilde key opens a
console; `help` lists its commands, and `cl_showfps 0|1|2` switches the frame
counter. Normal radio startup chooses a random populated
station and a random track. Station and track controls remain available during
play. Save applies a draft; Cancel discards it. The
[display plan](plans/display-quality.md) records renderer behavior.

The current campaign is a development slice. It still needs complete art,
encounter and fresh-player review. The full twenty-level story and conditional
epilogue are [planned](CAMPAIGN.md). Automated route clears and screenshots
do not stand in for a new player's understanding of the mission.
