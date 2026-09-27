# Playing fragr

[Back to the README](../README.md) | [Campaign contract](CAMPAIGN.md) |
[Current build order](ROADMAP.md)

## Choose a game

**Recall Notice** is the local solo campaign development mission. Build the
server (`cargo build -p fragr-server --release --locked`), run
`godot --path client`, then choose **Single Player > Recall Notice** and a
difficulty. The client starts its own server on loopback. Find Latch's transfer
record, recover weapons from the Annex, and leave by the custody lift.
Assisted, Standard and Severe change enemy timing; health, damage and finite
supplies stay consistent. M01 has an optional Shiv secret. The M02 ward route
remains a development graybox with an unfinished rescue. This branch adds a
durable Continue Run path into M02 alongside its separate practice entry.

**Calibration** is a separate Episode 0 arena challenge. Run
`./tools/solo_scrap.sh` from the repository root. It starts the Host-led
challenge with four named bots. Set `FRAGR_SOLO_BROADCAST=0` for plain Solo
Scrap practice. On Windows, run the shell wrapper from Git Bash. To launch
the two processes yourself:

```bash
cargo run -p fragr-server --locked -- --bind 127.0.0.1:6767 --bots 4 --solo-broadcast
godot --path client res://scenes/main.tscn -- --solo
```

**Multiplayer** connects to a separately hosted server. The host chooses
the arena and rules. Spectators, humans, agents and rule bots share the same
authoritative match. The current release includes free-for-all and team
deathmatch, six arenas and Rail Only, Shotgun Only, Fists Only, Licence to
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
| Fire | Ctrl | Left mouse | RT |
| Use | Enter | F | B |
| Jump | Space | Space | A |
| Campaign continue | Enter | Enter | A after releasing held inputs |
| Weapons | [ and ], or 1 through 5 | Wheel, [ and ], or 1 through 5 | LB and RB |
| Speak | T | T | Y |
| Join or leave | J or L | J or L | A while watching, or match menu |
| Spectator fighter and view | F and V | F and V | D-pad right and Back |
| Radio station, track, on or off | C, N, M | C, N, M | D-pad up, down, left |
| Match menu | Esc | Esc | Start |
| Show leaders in first person | Tab | Tab | Back |

Keyboard turning ramps over a quarter second. Mouse look uses raw counts,
without smoothing or aim assist. Gamepad and keyboard look can use Off, Light
or Standard aim assist, which moves the aim sent to the server; the server
still decides hits. The [input plan](plans/input-all-devices.md) records
the behavior and verification.

The numbered weapon order is fists or found Shiv, pistol, shotgun, rifle,
railgun. The wheel and bracket keys skip guns you do not own. Campaign ammo
is one count per type with no magazines or reload. Pistol and Rifle share
Bullets; Shotgun uses Shells; Railgun uses Cells. A seven-pellet Shotgun blast
costs one shell. Arcade maps provide the full basic arsenal. A mission control
requires you to stand near it and aim at it before pressing Use.

## Solo runs and local records

Recall Notice offers three mission-start continues. Death presents an explicit
retry; the fourth death ends the run. Exit to Menu retains the run at mission
entry, including a pending continue. **Continue Run** reopens a compatible
save; it does not resume the mid-mission position. After M01 departure, the
same run starts M02 with its saved body, health, armor, weapons, ammunition and
remaining Episode I continues. M02 starts at attempt 1 even if M01 used a
continue. M02 death restarts M02 at its own entry only after you accept the
retry. Completing M02 saves the next destination, Scheduled Service, as
pending; level 3 cannot be launched yet. The separate M02 practice entry has
no durable run. **Start New Run** archives the previous run after confirmation.
The pause menu's **Leave match** returns to the menu and keeps this local
save for Continue Run.

The local file is `run.json` under the platform user-data `runs` directory:
`%LOCALAPPDATA%/fragr/runs` on Windows,
`~/Library/Application Support/fragr/runs` on macOS, or
`$XDG_DATA_HOME/fragr/runs` (usually `~/.local/share/fragr/runs`) on Linux.
The run records ID, difficulty, body, continues and entry equipment. A changed
authored map or rules revision can make an old run incompatible; the old file
stays until you choose to archive it. New Run archives are named
`run.prior-<id>.json`; migration keeps exact prior bytes under a
content-addressed `run.prior-<digest>.json` name.
To recover one, close the game, keep a copy of the current `run.json`, and
copy the archive back as `run.json`. It still must match the installed mission
content and rules. v2 M01 saves from the previous release are migrated on a
valid resume; v1 magazine-era saves remain incompatible. The
[run file plan](plans/campaign-run-file.md) and
[carry plan](plans/m01-m02-run-carry.md) record the format and recovery rules.

The **Service Record** stores the latest 256 campaign, arena and practice
records on this device. It shows kills, deaths, effective damage, time alive,
per-weapon hit counts and mission effort across attempts. You can export
JSON. It is local history, not a public ranking or campaign save.

## Settings and current limits

The boot menu and in-match menu share Controls, Look, Display, Graphics and
Audio settings. Choose resolution, quality, frame cap, VSync, field of view,
supported FSR upscaling, sensitivity, stick response and separate master,
radio and effects levels. Save applies a draft; Cancel discards it. The
[display plan](plans/display-quality.md) records renderer behavior.

The current campaign is a development slice. It still needs complete art,
encounter and fresh-player review. The full twenty-level story and conditional
epilogue are [planned](CAMPAIGN.md). Automated route clears and screenshots
do not stand in for a new player's understanding of the mission.
