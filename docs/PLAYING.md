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
evacuation. Finishing Recall Notice and pressing CONTINUE on the tally starts
that next mission when the saved run names it. Its independent practice entry
remains available alongside the durable **Continue Run** path. These missions still need fresh-player acceptance.

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
progression. The current development build adds **Right of Search**, level 11
on the custody tender, with deliberate Remote Mines, optional transfers and
records, bridge controls and a separate stern exit. **Terms of Cooperation**,
level 12, continues into the Martian habitat. Find the Arc, fight the airborne
Assessor, secure the shelter route and reach the mutual-aid depot before
confirming commitment and departure. Shelter and worker rescues are optional;
resolved shots can damage the pumps. **The Weight of Permission**, level 13,
continues into the foundry with a finite Rocket Launcher, optional worker
releases, machinery hazards and a freight lift. Shoot the machine relay while
leaving the town feed intact, secure the upper gallery, then use the lift with
the whole ready party aboard. If somebody leaves during ascent, the lift returns
for another boarding attempt. **Launch Authority**, level 14, takes the fight
outside to the launch works. Secure the depot and road, use the captured jeep
if you choose, and learn the Walker's warned attacks before its support crews
arrive. Clear the gantry after the machine falls, then use its control with
the whole ready party aboard. The infantry route remains available after jeep
loss. **Civic Pressure Valve**, level 15, opens Episode IV at the stadium with
the finite Article Blade and broadcast booth takeover. **Freedom of Movement**,
level 16, crosses the avenue, green-wave checkpoints and prison bus rescue.
**Peace Without Interruption**, level 17, breaches the Forever Office and
captures Voss alive. **All Systems Normal**, level 18, starts Episode V through
the relief depot, rupture defense, clinic roadblock and evacuation concourse.
All eighteen have practice entries and connected saved progression. These
remain development prototypes, with final art and fresh-player acceptance open.
Connected levels 19 and 20 remain unbuilt. The [campaign contract](CAMPAIGN.md) and
[roadmap](ROADMAP.md) own the current scope and build order.

## Standalone development maps

Standalone source maps explore campaign environments without changing
your campaign save. Build and start one server from the repository root:

```bash
cargo run -p fragr-server --release --locked -- --bind 127.0.0.1:6767 --bots 0 --map-file server/maps/test/m12_habitat_development.json
```

For The Weight of Permission, replace the final path with
`server/maps/test/m13_foundry_development.json`. For Launch Authority, use
`server/maps/test/launch_authority_development.json`. In another terminal, run
`godot --path client res://scenes/main.tscn -- --solo`.

Terms of Cooperation develops the habitat's market, greenhouse flanks,
maintenance bay and pumping court using the earlier weapons and enemies. It
remains the separate historical slice; the connected level 12 above adds the
Arc, Assessor, shelter controls and civilian outcomes. The Weight of
Permission develops the machine hall, supplied maintenance ring, two stairs,
upper ladle galleries and static freight landing. Its Rocket Launcher, authored Assessor encounter,
worker rescues and lift transfer remain unfinished. Launch
Authority develops the freight arrival, depot, captured jeep, broad driving
circuit and gantry defense. Supplies support independent infantry routes.
Its actual mounted-fight acceptance, Walker, coalition departure and campaign unlock remain
unfinished. These maps have no mission tally, save promotion or connected
departure. Their [M12](plans/m12-habitat-development-20261008.md),
[M13](plans/m12-m14-foundry-slice-20261008.md) and
[M14](plans/m14-vehicle-development-20261006.md) plans track acceptance.

For the isolated Continuance Walker encounter, use
`server/maps/test/walker_foundation_development.json`. Collect the Rifle and
Rocket at entry, then use either supplied flank. Clear the stomp ring and move
off the three artillery markers after they lock. Open joint vents mark the
recovery window. The machine's integrity readout follows server damage; shots
against its closed plating are less effective. This range has no campaign save
or level 14 departure. Its [foundation plan](plans/walker-foundation-20261015.md)
separates development checks from the combined battlefield still to come.

## Other games

**Calibration** is a separate Episode 0 arena challenge. Run
`./tools/solo_scrap.sh` from the repository root. It starts the Host-led
challenge with four named bots. Set `FRAGR_SOLO_BROADCAST=0` for plain Solo
Scrap practice. On Windows, run the shell wrapper from Git Bash. To launch
the two processes yourself:

```bash
cargo run -p fragr-server --locked -- --bind 127.0.0.1:6767 --bots 4 --solo-broadcast
godot --path client res://scenes/main.tscn -- --solo
```

**Multiplayer** asks one question first: **Find / join a match** or **Run a
match**. Run a match starts Team Deathmatch, 5v5 Sector 9 Sabotage or Holdfast
Atoll Conquest with the bundled server; mutators, friendly fire, LAN and port
fold behind **Rules, LAN and port**. Find / join a match opens the join view:
a direct address with Check host, then the servers on this network and the
ones saved on this computer. Choosing a server moves its card under that row:
the match line, Watch, Join and Save this host belong to that server only.
Check host reads the address you typed and leaves it there. Editing the
address waits for a new check before Watch or Join. Choose Watch or Join
after the match line comes back. A host you check,
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

**Benchmark**, on the main menu, times the frames drawn on this computer. Run
the current preset (about a minute) or compare all three (about two). It
records 28 seconds of its own Larak Lot match with ten bots on a port this
computer picks, then replays that same fight for each preset under an
automated orbit camera. A server you already left running for other people
stays up. Vertical sync and the frame cap turn off for the run, then your
settings return. The match HUD is hidden; the benchmark's own readout names the
step (recording, warming up, measuring), shows overall progress and a live
frame rate. Esc cancels and returns to the Benchmark page.

The result leads with average FPS, the 1% low, the 99th percentile frame time
and frames at 33 ms or more for each preset, then a frame-time timeline.
Details hold the other percentiles, the system and settings, and the last
compatible run from your results folder. Run again, Copy summary and Open
results folder sit beside Back to menu. A new run records a new fight, so
repeat runs before trusting a small difference. The recorded nine-scene
showcase is still ahead.

Choose no bots, a fixed count or automatic fill toward a total fighter count.
Automatic fill gives humans and agents equal priority over eligible filler
bots. If a full Sabotage room cannot safely replace a bot during the current
round, watch and try joining at the next round.
Older releases require a separately started server. The host chooses
the arena and rules. Spectators, humans, agents and rule bots share the same
authoritative match. The current release includes free-for-all and team
deathmatch, six arenas, capture the flag on Directive 17 and Sector 9,
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
**Settings > Controls**; prompts follow the last device used. Custom controls
saved for an older default layout are not carried over: the page says so,
shows the current defaults and keeps them once you save.

Xbox and PlayStation pads share one layout; prompts use the names printed on
the pad in hand (Xbox name first, PlayStation second below).

| Action | Keyboard only | Keyboard and mouse | Gamepad (Xbox / PlayStation) |
|---|---|---|---|
| Move | Up and Down | W and S | Left stick |
| Turn | Left and Right | Mouse, or Q and E | Right stick |
| Strafe | Alt with arrows, or Comma and Period | A and D | Left stick |
| Look vertically | Page Up and Page Down | Mouse | Right stick |
| Center view | End | End | not bound (rebindable) |
| Fire | Right Ctrl | Left mouse | RT / R2 |
| Scope | Z, hold | Right mouse or Z, hold | LT / L2, hold |
| Jump | Space | Space | A / Cross |
| Crouch | Left Ctrl, hold | Left Ctrl, hold | B / Circle, hold |
| Dodge (arena) | Left Shift | Left Shift | not bound (rebindable) |
| Reload | R | R | X / Square |
| Use | Enter | F | Y / Triangle |
| Weapons | [ and ], or 1 through 6 | Wheel, [ and ], or 1 through 6 | LB and RB / L1 and R1 |
| Vehicle seat swap | [ and ] | Wheel | LB and RB / L1 and R1 |
| Throw grenade | G | G or middle mouse | D-pad up |
| Place mine | B | B | D-pad down |
| Remote mine, detonate | V, H | V, H | Left stick click, right stick click (LS, RS / L3, R3) |
| Campaign continue | Enter | Enter | A / Cross after releasing held inputs |
| Speak | T | T | not bound (rebindable) |
| Join or leave | J or L | J or L | A / Cross while watching, or match menu |
| Spectator fighter and view | F and V | F and V | X and Y / Square and Triangle |
| Radio previous and next station | X and C | X and C | D-pad left and right |
| Radio skip track | N | N | Hold D-pad right |
| Radio on or off | M | M | Hold D-pad left |
| Match menu | Esc | Esc | Menu / Options |
| Leaderboard, the whole roster | Tab, hold | Tab, hold | View / Create, hold |
| Menus: choose, back | Enter, Esc | Enter, Esc | A, B / Cross, Circle; D-pad moves |

The radio is background music, like a car radio in a heist film: previous
and next station wrap through a RADIO OFF stop. A small card at the lower right
names the station and the song for a few seconds after every change, and
nothing else of the radio stays on screen during play. The match menu has a
**Music / Radio** area with the station, the full song title, buttons for every
radio control with their current bindings, and the music volume. Switching the
radio back on starts a fresh track; it does not resume inside a song.

The **Announcer** setting, in the match menu and in Settings > Audio, chooses
which Host calls reach the voice row: **On** (all of them), **Big moments only**
(the calls the server marks big, listed under Settings below) or **Off**. Off
also stops the radio dipping for the Host. Frags, objectives and result cards always show.
Announcer volume sets the Host's own audio bus; the Host's calls are text
today, so the slider has nothing to play until the voice is recorded.

Hold Tab to list every fighter. While holding the board, use the weapon-cycle
keys, wheel or controller bumpers to scroll a large roster. The board shows
your current bindings. Release it to restore ordinary weapon selection.
Mode and round stay in the corner; accepted scores, clocks and objectives sit
above the view. Five frag rows have their own top-right queue and remain for
4.5 seconds each. Voice below them carries taunts, Host lines and your pickups.
Objective calls appear one at a time above aim. Loading, menus and other actual
covers pause obscured notice clocks. Feed and standings use the same relation
marks, with a bone plate for frags involving you. Following a fighter does not
make that fighter you, and duplicate callsigns keep distinct standings rows.
In a team match, world nameplates mark
someone on your side OURS and keep them bright. The other side is marked THEIRS
and warms toward red. A spectator still reads UNION and FREE on the full plate.

Hold Left Ctrl, or B or Circle on a pad, to crouch. The camera and body lower, movement slows, and a low ceiling keeps you crouched until there is room to stand. Rebind **Crouch (Hold)** in Settings > Controls if you prefer another key or a gamepad button. Right Ctrl still fires when one hand is on the arrows. The server decides the stance. An older server ignores the key.

Keyboard turning ramps over a quarter second. Mouse look uses raw counts,
without smoothing or aim assist. Gamepad and keyboard look can use Off, Light
or Standard aim assist, which moves the aim sent to the server; the server
still decides hits. Hold scope on the Sniper Rifle only. It narrows the local
view and slows look, on the mouse and on keys. It does not decide the hit.
The [input plan](plans/input-all-devices.md) records
the behavior and verification.

The numbered weapon order is fists or found Shiv, pistol, shotgun, rifle,
railgun and sniper. Key 4 cycles owned Rifle and Repeater; key 5 cycles owned
Railgun and Arc. The Repeater foundation is not granted in current campaign
maps. The wheel and bracket keys skip guns you do not own. Campaign ammo
is one count per type, and that count includes the rounds in each gun. The
corner shows rounds in the gun, then what is left to load. They add up with
the other guns on the same type. R, or X or Square on a pad, reloads the gun in hand.
Under the count, the corner says RELOAD REQUESTED while the press travels,
RELOADING with a filling bar once the server accepts it, then LOADED. A full
gun, an empty bag, a melee weapon or a mode without magazines says so instead.
A swap, death or vehicle seat cancels quietly. The held gun dips while
reloading and one short sound marks the start and the finish.
An empty gun does not fire while rounds remain in the bag. Pistol and Rifle share
Bullets; Shotgun uses Shells; Railgun and Sniper use Cells. A seven-pellet Shotgun blast
costs one shell. In free-for-all every life starts with the Pistol (12 in the
gun, 38 behind it) and Fists. The Rifle, Shotgun and Railgun sit on timed
pads: walk over one to own it, and it comes up loaded. Walking over a gun you
already carry adds to the bag without changing what is in your hands. Death
loses every gun you found; the death card names them, and the next life starts
on the Pistol four seconds later. In team modes, and in a free-for-all hosted
with Full Arsenal, an arcade human spawns with the rifle, shotgun and railgun
already loaded, and a finite bag behind them: 60 more rifle rounds, 18 more
shells and 12 more rail shots. The corner uses the same gun-then-bag pair.
Walking over that gun adds a pickup to the bag. Death puts the spawn kit back.
A weapon-only match still has one gun and no bag to run out of.
Agents and campaign enemies still spend the single count. Stand near a mission
panel and aim at it. The prompt under the crosshair names Use: F with a mouse,
Enter on a keyboard, Y or Triangle on a pad. Q and E turn. Before that aim is true, the
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
Run** replaces the saved run after confirmation. A save from a different build
or a damaged file cannot be continued; the menu says which and offers a new run.

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
is Right of Search, a connected playable tender prototype with the Redactor
and Remote Mines. Its stern departure saves Terms of Cooperation, the connected
level 12 habitat prototype. Its shelter, pump, release and coalition facts
persist through retries and deliberate departure into level 13, The Weight of
Permission. The foundry retains worker choices and actual arrivals separately,
plus machinery harm, relay, surrender and gallery outcomes. Its departure opens
Launch Authority without refilling continues. Level 14 retains the original
jeep's survival and an on-foot Walker fight through its fleet departure, then
saves pending Civic Pressure Valve. Connected M15 through M20 remain unplayable;
the standalone development maps above do not advance that save. The
[tender receipt](evidence/m11-quality-composition-20261006.md) records the route
and remaining acceptance.

The local file is `run.json` under the platform user-data `runs` directory:
`%LOCALAPPDATA%/fragr/runs` on Windows,
`~/Library/Application Support/fragr/runs` on macOS, or
`$XDG_DATA_HOME/fragr/runs` (usually `~/.local/share/fragr/runs`) on Linux.
A build reads only its own save format. A save from a different build, or one
whose mission content has since changed, cannot be continued: the menu says so
and offers a new run, which replaces the old file. A damaged file is reported
the same way. Saves are never converted between builds. Keep client and server
from the same release. The format is described under
[Campaign run file](protocol.md#campaign-run-file).

The **Service Record** stores the latest 256 campaign, arena and practice
records on this device. It shows kills, deaths, effective damage, time alive,
per-weapon hit counts and mission effort across attempts. You can export
JSON. It is local history, not a public ranking or campaign save.

In current development, a completed local mission also shows a best-time
comparison, including ties and the exact improvement or gap. The successful
attempt runs from party readiness to departure, including time dead within
that attempt. Bests compare the same mission, difficulty and exact server
build, with campaign and practice kept separate. They cover retained human
completions on this device. Changing server builds starts a new comparison
group; older or external records remain readable without claiming a best.
No par or global ranking is inferred. Service Record JSON version 3 retains
version 1/2 history and adds independent local award proofs and appearance.

In current development, **Your callsign > Awards and Appearance** shows two
awards. Complete Recall Notice in your saved solo run for ON FILE and a transfer
stamp. Find an authored secret in a saved mission for MARGIN READER and margin
teal paint. All ordinary tiers, bodies and controls qualify. The secret award
survives later failure. Practice, remote play and story replay do not earn these
local solo awards; historical records are not retroactively awarded.

Standard steel and oxide finishes need no unlock. Locked choices can be previewed
before earning them. **Save and back** commits appearance; **Cancel** discards
the preview. Gun paint affects your first-person firearm only. World pickups,
other fighters, ammunition, damage, handling and muzzle effects retain their
normal behavior. The benchmark uses standard paint. Unlocks survive failed
runs and history eviction; they are editable local progress, not authenticated
platform achievements. Campaign-completion and gold awards remain planned.

## Settings and current limits

The boot menu and in-match menu share Controls, Look, Display, Graphics,
Audio and Accessibility settings. Choose resolution, quality, frame cap, VSync, field of view,
supported FSR upscaling, an optional frame counter, sensitivity, stick
response and separate master, effects, announcer, radio and story voice
levels. The tilde key opens a
console; `help` lists its commands, and `cl_showfps 0|1|2` switches the frame
counter. Normal radio startup chooses a random populated
station and a random track. Station and track controls remain available during
play and in the match menu. Save applies a draft; Cancel discards it. The
[display plan](plans/display-quality.md) records renderer behavior.

The Host calls rarely: first blood, a triple frag or more inside three
seconds, a spree, an ended spree, a comeback, the last one standing, a flag
capture, a planted charge, match point and sudden death are the big moments.
A double frag, a lead change, a lifted flag and the golden Railgun are text
captions only. Voiced calls land at least eight seconds apart, and a caption
waits eight seconds after any call. Settings > Audio >
Announcer (also in the match menu) chooses On, Big moments only or
Off, and Announcer volume sets the Host's own bus. Frags, objectives, results
and the sudden death chip always show. Host calls are text until the voice is
recorded; the volume has nothing to play until then.

A clock that runs out level, after somebody has scored, goes to sudden death:
the clock stops and the next score wins. A room where nobody scores for two
more minutes ends level. A Sabotage match level after its extra pair plays one
deciding round instead of a draw.

Reduced Motion stops decorative camera kicks, HUD pulses, weapon and pickup
bob, and story pan/zoom. Enabling it restores resting poses immediately. Aim,
scope, accepted firing/reloading frames, actors and machinery keep their normal
behavior. The held gun's reload dip stops; the corner's reload line and bar stay. Your separate weapon-bob choice remains saved.

Health is bone above 50, ember at 50 or below and red at 25 or below, with an
exact number and a filled bar. A fresh critical injury pulses once unless
Reduced Motion is enabled. Ammunition uses the same numeral size; EMPTY means
the selected weapon has no usable shot, including an empty magazine with rounds
still in reserve. The centered strip follows accepted scores and objectives;
the scoreboard binding opens standings.

The current campaign is a development slice. It still needs complete art,
encounter and fresh-player review. The full twenty-level story and conditional
epilogue are [planned](CAMPAIGN.md). Automated route clears and screenshots
do not stand in for a new player's understanding of the mission.
