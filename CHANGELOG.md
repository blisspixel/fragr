# Changelog

Release history, newest first. Planned work stays in
[docs/ROADMAP.md](docs/ROADMAP.md). Older tags are on the
[releases page](https://github.com/blisspixel/fragr/releases).

## v0.92.1 - 2026-10-26

- Keep Continue available when its request fails to enter the network queue,
  so the same pending attempt can be retried without reopening the game.
- Verify earned campaign supplies across M01 departure, M02 entry, death,
  saved-run reopening and retry, including duplicate and stale requests.
- Add reproducible constrained Recall Notice trials with finite magazines,
  declared vision and reaction limits, retained failures and recorded scene
  review. Fix the evaluation controller's empty-magazine reload stall.
- Keep visual pickup routes tied to the current life and round, and wait for
  timed weapons at their pads instead of standing exposed away from them.
  The authoring tour can defend those routes with ordinary fire and reloads.
- Forward M02's existing objective facts to the evaluation controller and
  qualify a bounded standalone entry with the same calibrated input policy.

## v0.92.0 - 2026-10-25

- Add Hold 4x, Toggle 4x and Cycle 2x/4x/open Sniper scope preferences, with
  consistent optical magnification across field-of-view settings. Key 7
  selects an owned Rocket Launcher without cycling past the other guns.
- Keep a fresh Continue press armed when the server refreshes the same
  pending retry, while still requiring released input for a new attempt.
- Replace repeated campaign prose boards with painted marks, notices and
  physical props. Keep directions and essential teaching cues short, remove
  league slogans from campaign skylines, and clear text from prop hardware.
- Count surviving stadium entrants at the final pier consistently with Still
  Here. Rescues change who arrives; survival alone still unlocks the epilogue.
- Dress the campaign with modelled props in place of boxes: the correction
  ward's machine, the impound tug beyond the Port of Entry glass, the Common
  Carrier's pilot consoles, galley and berths, the foundry's lathes and freight
  hoist, the trams left where they stopped in Planned Works and Local
  Exception, and the concourse's stretcher, cases, duffels and crates.
- Bots play Larak Lot like regulars: they reach for the Rocket and put it at
  your feet, leading a strafe, and never fire it close enough to catch
  themselves; each callsign has a favourite gun and a pad it times, so
  Nightfall keeps the Railgun and somebody is always walking to the Custody
  Plate; a fresh life on the Pistol goes for a real gun before a long trade.
- Grudges: a bot remembers who has fragged it, looks for them first, and says
  so when it settles the score. A desktop host keeps the head-to-head book
  between callsigns across sessions, and the Host reads it before a Duel
  ("NIGHTFALL LEADS THE BOOK 7 TO 4").
- The Scatter meatshot: the barrel against the body puts a bare fighter down
  in one blast.
- Make fights look like fights: a ten-frame pixel fireball with smoke,
  debris, an amber flash of light, a scorch and a kick to the view on every
  blast; a modelled rocket that trails smoke; impacts that show what they hit
  (dust off concrete, sparks off steel, blood off a human, sparks and oil off
  a free agent) and leave a mark on walls; and a Railgun beam that lingers,
  white-cored, with a spiral you can see from behind your own gun.
- Rebuild the Pistol, Shotgun and Railgun as modelled guns in your gloved
  hands, a quarter of the screen wide: the Pistol's slide runs back on every
  shot and its magazine drops on the reload, the Shotgun is a side-by-side
  double that breaks open for its shells, and the Railgun's coils go dark
  after a shot and charge back up. Every held gun now lowers and rises on a
  switch, lags your look, dips when you land and takes the light around it.
  Pickups, the gun a fighter carries, Latch's Pistol and the kill feed's new
  glyphs all show the same guns.
- Dress Larak Lot with modelled props in place of boxes: the toll booths, the
  bookmaker's kiosk, THE STACK, burnt and clamped cars, the pay machines and
  pulpit, Larak's 2009 coffee machine, the Stands bell and the crane hook,
  each filling the cover it stands for.
- Rocket jump. Every arena blast throws the fighters it hurts, and a rocket at
  your own feet lifts you: from Larak Lot's Gallery straight onto the Roof.
  The Rocket waits at the bottom of the Pit in free-for-all and Duel.
- Make the Custody Plate a real power item: +100 armour to 150, the excess
  draining a point a second, back every 35 seconds.
- Add Duel on Larak Lot: two fighter seats, a bot that keeps an empty seat warm
  and gives it up, and a running series between the same pair.
- Press fire on the podium for one more: when everyone seated has, the next
  round starts two seconds after the result.
- Read Union attacks before they land: red optics flash when a windup starts
  and burn hot through the burst, and no more than two guards wind up on you
  at once.
- Let Latch fight beside you from a real twelve-round magazine, cover your
  reloads, and keep out of your path, your crosshair and your line of fire.
- Add Still Here, the epilogue a survived campaign opens from Single Player:
  the refuge at the end of Pier 4 the morning after, then the same court years
  later, with the people your run brought back standing in it and the board
  still asking after some it did not. Survivors do not agree what the reprieve
  meant, the ferry board shows two lines once, and the credits name only the
  people this run saw again. Walking it spends nothing and never changes the
  saved run; the development list walks it with nobody carried.
- End a run that runs out of continues in levels 18 to 20 with The Last Page:
  Latch and the free agents won their exception anyway, the world goes on
  without you, and the ledger keeps one more line and no score.
- Dress the waterworks and refuge crowds in their own colours on the
  Compatibility renderer too, where they had kept one rust coat and white
  shirts.
- Keep Latch's face on the screen when you stand beside them or see them from
  the side, where it used to float clear of the head.
- Stand Splice at Level 20's pier only when they made the level 5 freight, as
  the refuge and Tern's crew list already do.

## v0.91.0 (2026-10-24)

- Rebuild map 1 as Larak Lot, the free-for-all home: a five-level parking
  structure the league settles debts in, with the Pit one level further down
  than the sign admits, Aunt Linda's revival on level three, and Larak's
  signature on everything that has stopped working.
- Start free-for-all lives on the Pistol and Fists. Stronger guns are owned
  only after taking their pad, on 15 to 25 second clocks, with health and armor
  on 25 seconds. Free-for-all respawn is 4 seconds; other modes keep their own
  rules. A `full-arsenal` host option restores the armed start.
- Move faster and cleaner: 6 m/s arena running with crisp stops and air
  control, a dodge, first shots exactly on aim, a little spread only on
  sustained fire, camera punch that never moves the aim, and smooth correction
  of the local view.
- End the dead life at death. Held keys no longer walk or fire into the next
  life, the death card names who fragged you and counts down with the server,
  and the camera watches your killer instead of drifting.
- Make reloads readable on every magazine gun, with status, a bar, a dipped
  gun and one start and finish cue.
- Keep HUD text in its own regions, level and in the pixel type. Corner voice
  lines are backed, nameplates hide under HUD panels and behind cover, the
  armor readout sits on its plate, and developer hints are gone from play.
- Give menus one focus target across mouse, keyboard and pad, split Join from
  Run a match, add Xbox and PlayStation layouts, a D-pad radio dial and an
  announcer setting: On, Big moments only, or Off.
- Keep the Host for big moments: multikills, spree tiers, streaks ended, flags
  and sudden death instead of a drawn match, with no radio puns in the call.
- Tell sides apart at a distance. Union hardware carries black and red with red
  optics; free fighters wear their own colours with team tape; the Inheritance
  reads matte off-white with cyan. Bot callsigns follow the league's regulars
  and tribes, with Union handles on the Union side.
- Let bots see before they fight, pace their volleys, flinch when hit and time
  the pads. Joined agents see pads only as their fighter has seen them.
- Connect Planned Works (Level 19) and Local Exception (Level 20), where the
  wipe arrives: absorbed bots with dead red optics, restoration machines, the
  Paver and Surveyor, a jetpack, and campaign survival recorded for the Still
  Here epilogue, which is still to come.
- Dress Recall Notice as a lived-in Union intake on a night street, with
  queues, confiscation bins, a recall notice over an old helper advert and
  Voss's address on the hall screen.
- Redesign the benchmark journey, live readout and results, compare only like
  displays, and show an operator overview in the dedicated server terminal.
- Keep one campaign save format; saves from earlier builds are refused with a
  clear message instead of migrated.

Linux, macOS and Windows CI passed for every change. Windows human play and
real controllers are still owed.

## v0.90.0 (2026-10-19)

- Add an Accessibility tab with screen flash levels, Reduced Motion, HUD
  scaling and team colours, under a global flash budget.
- Replace full-screen colour washes with seal-cut and stamped card moments.
- Gate terminal colour with `--no-color` and `NO_COLOR`, add level roles and
  hosting-first help, and print one listener line.
- Refresh the README front door with three doors, the HUD and the game's voice.

## v0.89.0 (2026-10-18)

- Keep five frag rows in their own queue for 4.5 seconds each. Taunts, Host
  lines and pickups have a separate corner voice budget. Objective calls appear
  one at a time above aim, while results retain their backed cards.
- Show resolved weapon glyphs and a bone plate for frags involving you. Feed
  and standings share relation marks, and duplicate callsigns retain distinct
  participant identities. Older events retain neutral, honest fallbacks.
- Pause obscured notice clocks under actual loading, menu, story, standings
  and mission covers. Preserve frags across round transitions, and keep scoped
  voice readable. Duck the radio once when a Host line is first presented.
- Carry optional participant IDs and resolved weapon provenance on frag events
  through the adapter and observer. Omit uncertain optional statistics instead
  of guessing from held guns or same-named fighters.
- Update existing developer HTTP dependencies to Rustls 0.23.46 and
  yoke-derive 0.8.4 without changing packaged desktop dependencies or TLS policy.

## v0.88.0 (2026-10-18)

- Give health, armor and ammunition equal display numerals. Health changes at
  50 and 25, keeps its exact count and bar, and pulses once on a fresh critical
  injury. Empty magazines say EMPTY even when reserve rounds remain.
- Center scores, clocks and objectives while keeping the corner to mode and
  round state. Preserve capture information, Sabotage timing and all five
  Conquest sites. Keep accepted participant scores through respawn and retain
  final team/objective scores after the result card closes.
- Add Reduced Motion to shared Accessibility settings. Cancel decorative
  camera, HUD, weapon, pickup and story motion while retaining aim, accepted
  attack/reload frames and world movement.
- Reserve distinct space for context, notices, ammunition, radio and vehicle
  controls. Keep full standings on the scoreboard binding.
- Bound developer client checks with an independent process deadline and
  retained per-check logs, including Windows descendant cleanup on timeout.

## v0.87.0 (2026-10-18)

- Unify menu and HUD chrome on the canonical palette. Front-end and gameplay
  appearance have separate contexts, with the existing dark cabinet retained.
- Use crisp pixel lettering for controls and labels, and the display face for
  titles, health and ammunition. Keep Unicode callsigns and chat supported.
- Fit larger type into settings, mission objectives, vehicle controls, radio
  cards and results. Retain world materials, reticle preferences and gameplay.
- Wrap full standings inside a bounded board. While holding the scoreboard,
  browse large rosters with the existing weapon-cycle keys, wheel or bumpers.
  Default controller view switching uses Y, leaving Back for the board and
  preserving customized bindings.
- Record the verified v0.86.0 desktop shipment and update the active roadmap rung.

## v0.86.0 (2026-10-17)

- Connect the M16 avenue, M17 Forever Office and M18 transit development missions,
  with strict version-22 save carry, exact historical archives and mission-entry
  retries. Episode V refills continues at M18 entry. M19 and M20 remain pending.
- Report adapter admission failures durably, and name the actual multiplayer
  map and rules in round broadcasts.
- Bind pad reload to D-pad down and crouch to D-pad left, preserving customized
  controls. Muted narration waits on readable text until the player advances.
- Validate every prepared late-campaign world through native and Godot readers,
  keep control panels fitted when gates lower, and open the executive departure
  world before reporting Voss captured.
- Resume known earlier M15 saves after correcting stadium approach heights,
  retaining exact original-byte archives, inventory and prior mission outcomes.

- Connect Civic Pressure Valve as campaign level 15, with practice entry, arrival
  framing and saved progression from Launch Authority. Arm four captive entrants,
  break the sanctioned bout with the Article Blade, secure the broadcast booth
  for the Host, and leave through the ceremonial gate.
- Add the authoritative Article Blade melee weapon and plinth lifecycle. Settle
  70 base damage, 9-tick swing cadence, 12 swings, 2.0 m trace reach, drawn
  viewmodel states, and automatic return to the plinth on exhaustion, death or
  leave.
- Refill continues to three upon Episode IV promotion into M15, and upgrade
  saves to version 19 with exact byte archives of earlier versions, mission-entry
  retries and persistent challenge outcomes.
- Enable CTF flag carriers to defend against immediate close-contact blockers
  when their own home flag is safe, immediately resuming their return route.
- Validate entrant actor state, stadium HUD objectives, localized story text,
  and local practice mission launch across native, headless and tour harnesses.

## v0.85.0 (2026-10-15)

- Connect Launch Authority as campaign level 14, with practice entry, arrival
  framing and saved progression from The Weight of Permission. Secure the depot
  and road, fight the Continuance Walker through staged support waves, then
  reach the gantry for shared departure. The jeep remains optional.
- Preserve finite equipment and prior outcomes through version-18 saves,
  exact historical archives and mission-entry retries. Record the original
  jeep's survival and an on-foot boss fight at disable. Level 15 remains pending.
- Present grounded Walker mechanics, its registered fallen hull, launch cargo
  and readable fleet-departure scenes using retained assets. Final art,
  fresh-player acceptance and difficulty balance remain open.
- Add freight shoulders and hall staging cover to Sector 9's spawn exits,
  retaining ordinary walking access and the shared authoritative spawn rules.
- Advertise all fourteen built missions in the agent readiness and continue
  tool schemas, using the same typed stage list as saved progression. Accept
  Rocket in agent weapon selection, deriving the selector from the native arsenal.
- Refresh host version and commit labels after incremental branch and tag
  changes, including linked worktrees, while preserving explicit release labels.
- Prepare map geometry with its final render layers before scene attachment,
  preventing Vulkan light-retirement errors during map replacement and cleanup.

## v0.84.0 (2026-10-15)

- Add a standalone Continuance Walker development encounter with warned stomps,
  locked artillery lanes, finite shells, moving collision and exposed recovery
  joints. Human and agent routes use ordinary movement and finite pickups.
  Connected Launch Authority and its staged battlefield remain ahead.
- Present the Walker with fitted mechanical geometry, persistent warnings for
  committed shells and authoritative integrity readout. Walking and vehicle
  prediction follow its accepted body positions and pause during relocation.
- Keep Sabotage bots working on charge recovery and defusing when a nearby human
  or external agent is idle. Preserve an active defuse when teammates approach.
- Accept the server's actual vehicle explosion radius and damage in the client,
  preventing a destroyed vehicle from disconnecting a match viewer or player.
- Reset a failed loading card when rejoining as a player or spectator. Fresh
  matching world facts still gate input, and a recovered join can release it.
- Animate the Rocket reload from its server deadline, respecting weapon changes,
  seating, visibility and motion settings. Final held-weapon art remains open.

## v0.83.0 (2026-10-13)

- Connect The Weight of Permission as campaign level 13, with practice entry,
  localized arrival framing and saved progression from Terms of Cooperation.
- Find the first finite Rocket Launcher, secure the foundry and upper gallery,
  disable the machine relay while preserving the town feed, and ride the freight
  lift to departure. The lift returns if the party leaves during ascent.
- Release three workers with separate voluntary responses and grounded travel
  receipts. Worker choices stay optional. Machinery warnings and the overseer's
  surrender follow authoritative mission facts.
- Give the Rocket Launcher a distinct development tube viewmodel and visible
  local or followed first-person launch feedback, without doubling predicted
  cues. Preserve its generic muzzle flash through the first rendered frame.
- Upgrade saves to version 17 with exact historical archives, retained M12
  outcomes and mission-entry retries. Level 14 remains unavailable. Foundry final
  art, difficulty balance and fresh-player acceptance remain open.

## v0.82.1 (2026-10-13)

- Restore Rocket launch feedback from accepted projectile facts without doubling
  local predicted shots. Preserve a first-person muzzle flash for its first draw
  on a slow renderer, and capture weapon/effect evidence from the actual frame.
- Require real terminal reach, facing and line of sight to release foundry
  workers. Reset standalone foundry gates with the encounter party, and let the
  freight lift move when unrelated bystanders overlap elsewhere. Connected M13
  and its campaign saves remain unbuilt.
- Retain an inspected foundry ladle source and small surface comparisons offline.
  Developer tools report audio allowance details and preserve historical model
  credit holds across output directories and working-directory changes. New
  audio candidates remain private pending listening and distribution acceptance.
- Bundle the MCP adapter with desktop packages and include license notices for
  both Rust executables. Saved MCP configurations use absolute paths.
- Explain initial connection snapshots, persistent action inputs and HUD weapon
  names. Reject `act` when disconnected, connecting or absent from the latest
  snapshot; queued input is not a confirmed game outcome.
- Keep a running hosted match visible on the main menu, preserve session host
  settings through menu replacement, and default 5v5 automatic fill to ten.
  An unrelated Join address is checked only when explicitly requested while
  the owned match runs. The menu action is now Run a match.

## v0.82.0 (2026-10-10)

- Scale ordinary campaign ammunition, health, and armor by the existing
  Assisted, Standard, and Severe tiers. Assisted holds between bursts and
  receives half again as much of that stock. Severe remembers a sighting
  longer, steps in sooner between bursts, and receives two thirds. Standard
  tell timing and Standard amounts stay exact. Secrets, grenades, mines, and
  arcade pads stay authored. Rules revision stays 4. This is not fresh-player
  balance.
- Add development grayboxes for levels 15 through 20, and a sheltered trench
  on the level 14 battlefield. They are not missions. The foundry successor
  now carries the optional gate key and is still not a mission. Walker, save
  promotion, and the menu remain unbuilt.
- Bound connection admission, spectators, status answers, and live plus parked
  pawns, leaving loopback room for the desktop client and playtests. A join
  ticket can be one-time and audience-bound. Local tickets stay reusable when
  no audience is configured. The client does not attach a ticket on a public
  cleartext ws host. A saved server keeps its wss scheme. Present Origin
  values must match an allow-list. Snapshot rows, board posts, adapter events,
  brain traces, and developer receipts are bounded. Release workflows pin
  third-party actions and check Godot archives against a committed digest.
  Gameplay version, campaign rules revision, and the save format stay unchanged.

These are development prototypes. Full campaign completion, final art,
fresh-player acceptance, physical LAN evidence and a networked 64-player
capacity claim remain open.

## v0.81.0 (2026-10-09)

- Add the Rocket Launcher as a server weapon with straight flight, covered
  splash, a one-round tube and a separate Rockets pool. Shared arcade rooms
  use gameplay 46. Version 16 saves add an empty Rockets pool during migration
  and reject a forged launcher or pool. Arcade stock stays at zero.
- Show a traveling rocket and a rocket count. No mission grants the launcher.
  Its viewmodel art, the optional habitat secret, connected foundry progression
  and Walker remain unfinished.
- Stop match voices before leaving a match, so the round-start sample is
  released before process exit.
- Add the foundry successor map. It opens the ladle shaft and places an office
  Rocket Launcher and a freight Assessor. It is not a mission, and no menu
  launches it.
- Add foundry relay, hazard, worker and lift rules on a fixture map. The
  successor map does not carry their key. Connected M13 remains unbuilt.

These are development prototypes. Full campaign completion, final art,
fresh-player acceptance, physical LAN evidence and a networked 64-player
capacity claim remain open.

## v0.80.0 (2026-10-09)

- Add Terms of Cooperation as the twelfth connected campaign prototype, with
  the Arc, flying Assessor, vulnerable pumps, optional shelter and worker
  releases, mutual-aid arrival and deliberate coalition departure. Version 15
  saves retain its outcomes and pending M13, with strict historical upgrades.
- Give the Arc a larger industrial weapon face, consistent poses and a readable
  pickup. Preserve finite combat, ownership and authoritative resolved damage.
- Enclose interior stair routes in the archive, berth, ship and habitat,
  preserving walking access and the berth's actual charge-fall opening. Upgrade
  only exact historical geometry hashes and archive original saves.
- Register grounded enemy feet consistently and correct the Crawler, Jammer
  and Heavy Sweeper atlases. Clarify held crouch controls and HUD feedback.
- Change Latch's screen expressions with movement, firing and ward state,
  retaining blink, head motion and near-camera behavior. Present eligible
  Splice with a complete articulated mechanical source; foot planting remains
  provisional. Fit habitat shelter and aid signs to their visible wall faces.
- Keep automated captures progressing when a minimized window stops drawing,
  using bounded non-presenting draws without changing combat deadlines. Check
  actual window and captured image dimensions before stills and effect strips, and
  reject resolution changes during a shot sequence.
- Add Low Water as a second 5v5 Sabotage venue, with Clinic Steps and Tram Stop
  sites, trench flanks, layout-owned bot approaches and desktop host selection.
  Keep human balance, physical LAN and final-art acceptance open.
- Present human and synthetic player bodies, Tern and repaired Edda with live weighted
  meshes, following accepted movement, crouch, seats and death state. Package
  the models and precomputed support curves separately from offline source art.
- Coordinate Conquest bots around active captures and threatened owned sites,
  retaining useful work through deaths, respawns and roster changes.
- Recover planner movement when a wire reader receives coalesced snapshots,
  with actual Gulch corner regressions and unchanged mixed-roster checks.
- Retire active audio and pending skies through scene changes and ordinary Quit,
  including window close and minimized rendering, preserving clean-log checks.
- Earn local Recall Notice and authored-secret awards from owned saved-run
  records. Keep unlocks through failed runs and bounded history, with recoverable
  profile storage, locked previews and cosmetic first-person finishes.
- Verify both M01 routes across three tiers with human magazines, finite agent
  ammunition, deliberately resolved misses, actual enemy deaths and exhaustion.
- Add standalone Terms of Cooperation habitat, The Weight of Permission foundry
  and Launch Authority battlefield development maps, with supplied infantry
  routes and existing enemy roles.
  These retained static slices do not advance the campaign. Connected foundry
  and launch-works progression, the Rocket Launcher and Walker remain unfinished.
- Author explicit jeeps in static development maps, validating parked clearance,
  boarding and walking routes before launch and restoring the fleet on retry.
- Keep multiplayer joins and respawns clear of current vehicle hulls. Retain
  existing stair-edge bays, try supported positions on the same side when
  needed, and wait when every bounded candidate is obstructed.

- Let an attached dedicated host inspect shows and queue a validated map/mode.
  The live show and Sabotage match finish first, preserving connections.
- Compare compatible local campaign completion times in results and Service
  Record, with exact ties and deltas, retained historical records and separate
  build, difficulty and practice groups.
- Keep campaign documentation aligned with twelve playable prototypes and
  version 15 run saves, retaining unfinished missions and human review gates.

These are development prototypes. Full campaign completion, final art,
fresh-player acceptance, physical LAN evidence and a networked 64-player
capacity claim remain open.

## v0.79.0 (2026-10-07)

- Add Right of Search, the eleventh connected campaign prototype, with the
  Redactor, deliberate Remote Mines, optional transfer and record outcomes,
  version 14 saved carry and an actual stern departure.
- Add Holdfast Atoll's five-site Conquest prototype, registered swimming water,
  three jeeps, two boats and a light aircraft. Original coastal materials,
  quality-scaled waves and bounded wakes support the island's development art.
- Add human magazines and manual reload, crouching, immediate local firing
  feedback, bounded bot perception and bot equipment handling. Replace obsolete
  unsent motion while retaining combat and mission facts.
- Compare graphics presets against one recorded ten-bot fight. Show average
  FPS, 1% lows, frame-time percentiles and slow frames, with local JSON/CSV
  results and automatic restoration of the player's settings.
- Add the built-in dedicated night playlist, local server favorites and LAN
  discovery, plus the process-local wire board. Refresh the free synthetic body.
- Extend desktop Host to Conquest and keep long server lists scrollable. Fix
  invalid respawn facing, vehicle contact and boarding gaps, and exposed island
  spawn lanes. Keep water patch boundaries closed and the distant horizon continuous.
- Give story and art guidance credible institutional motives, ordinary lives,
  internal disagreements and consequences for every side's methods.

These are development prototypes. Full campaign completion, final art,
fresh-player acceptance, physical LAN evidence and a networked 64-player
capacity claim remain open.

## v0.78.0 (2026-10-05)

- A dedicated arcade server can open a local venue desk with `--console`.
  `who`, `kick`, `ban`, and `say` run from that machine. Closing the desk
  leaves the match running. Public status stays anonymous. Desktop Host and
  a local mission refuse the desk because they already use that input.
- The client shows a venue sentence in the corner feed. A venue kick is a
  hard stop and does not park the pawn for a reconnect.
- `fragr-playtest --traffic` fills a local server with synthetic fighters
  and read-only spectators. `--assert` checks that the roster stayed up.
  It does not claim the 50 ms tick budget or a 64-player result. Linux and
  Windows can spread a roster past 32 across `127.0.0.0/8`. macOS needs
  loopback aliases before that.
- A failed resume stays on its old token. Control frames count in the
  inbound budget. Status reads and refusal handshakes have their own caps
  and do not take a game slot. Sabotage muster holds mine placement.
- The measurement table is still empty. Human enjoyment and a two-machine
  session remain open. Wipe, the next mode, and cloud apply are not in
  this release.

## v0.77.0 (2026-10-05)

- Host Team Deathmatch on six arenas or 5v5 Sabotage on Sector 9 directly from
  the desktop menu. Watch, Join and return to menu share the owned match; Stop
  server or app exit retires its native process. LAN hosting is an explicit option.
- Choose no bots, fixed bots or automatic total fighter fill. Humans and external
  agents have equal priority over eligible server bots. Preserve reconnect seats,
  active-round lives, objective holds and committed devices. Unsafe full live
  rooms ask newcomers to try next round; cancelled admission keeps the bot intact.
- Keep an empty Sabotage room at its opening round until a fighter arrives.
  Two actual desktop apps share 501 unique matching ticks and a round-one 0:1
  plant/detonation result, then retire with their owned server and listener.
- Start and stop both presets through the bundled native executable during
  extracted-package installation checks. Require clean error logs, numeric zero
  and the check's own PASS marker. Actual scene-audio retirement is also checked.
- Relax Latch's following arms while preserving its original visible release
  posture and chassis. Keep multiplayer human and LAN feedback ahead of paused
  campaign and asset production. The campaign remains ten development prototypes.

The [desktop trial receipt](docs/evidence/multiplayer-host-20261005.md) records
actual source witnesses and retained failures. Full CI and three platform package
checks gate main and release promotion. Human enjoyment, two-machine LAN play
and broader map refinement remain open.

## v0.76.0 (2026-10-05)

Ten connected campaign prototypes now include Common Carrier, retained crew
outcomes, supported companion yielding and bounded static-corner recovery.
The weapon family shares consistent drawn hands, and Tern's provisional
synthetic body appears in both ship scenes. All eight fresh main CI jobs and
all three tagged desktop package checks passed. The three downloaded ZIP files
were independently rehashed against the published checksum manifest and digests.
The campaign, final cast and broader art pass remain unfinished.

- Match the Sniper's leather gloves to the drawn weapon family, restore the
  Shiv's shared resting hand scale and show Tern's provisional synthetic body
  in both berth and ship scenes. Combat timing, scope and crew facts stay intact.

- Escape supported static-cover corners with a bounded ordinary movement lease,
  preserving combat intent, deliberate drops and existing stuck thresholds.
  Retain the original intermittent report's attribution limit. The M02
  all-guard retry witness now dodges outside the real departure boundary until
  its required guards clear, without adding a mandatory gameplay exit gate.

- Preserve physical companion clearance with bounded supported stand-off and
  short yielding, including the narrow signal-box platform. Living bodies,
  finite support fire, ordinary walking and original mission gates remain.

- Record immutable Passenger Manifest crew release and actual aboard-at-
  departure facts alongside the finite player exit. Strict version 12 saves
  archive exact older bytes and retain missing historical crew facts as unknown.

- Extend the local campaign prototype through Common Carrier, with a sealed
  three-deck ship, two stairs, four ordered objectives and finite carried stock.
  Strict version 13 promotion records released crew finishing boarding separately
  from the immutable berth subset; historical unknowns remain unknown. Tern is
  the current pilot, and optional arrivals require recorded outcomes. A measured
  repair workbench replaces its broad proxy with twelve matching physical parts.
  Full ordinary 28-state combat and departure pass locally. Repeater discovery,
  final interior craft and fresh-player difficulty remain open; M11 is pending.

- Let eligible living people and companions stop resolved hitscan and traveling
  pulses through their authoritative bodies, without inventing neutral HP,
  damage or faction. Preserve guarded photographs and actual release visibility.

- Replace the rejected Pistol first-person view with a coherent drawn idle/fire
  pair, retaining combat and world-model behavior. Correct the home still to the
  current lean screen-faced Latch. Ordinary Pistol combat, story playback and
  three aspect ratios pass; other hand and named-character inconsistencies remain
  tracked separately.

## v0.75.0 (2026-10-04)

The corrected public download includes the prior Sniper refinement and Repeater
foundation, while restoring the earlier held Rifle presentation. All eight
main CI jobs and three tagged desktop package checks pass. The three downloaded
ZIPs were independently verified against the published checksums and digests.
The crew, companion and static-corner composition above remains unshipped.

- Restore the earlier Rifle idle, firing and pickup artwork after the player
  rejected the source-derived presentation. Retain its model, bake and physical
  checks offline; ammunition, timing and all other weapon art stay unchanged.

- Prepare compact air-scrubber, water-pump and community-radio source candidates,
  retaining their geometry and verifying physical floor support. Record inspected
  civilian-worker and repair-workbench sources and 70 included credits. All twelve
  first-source slots now have candidates; played placement, animation and wider
  environment coverage remain in flight.

The Sniper Rifle selects its refined wood and charcoal source for held, firing
and pickup pictures after source, motion and ordinary played-comparison checks.
Its Cells, scope, six physical weapon keys and combat timing stay unchanged.

A Repeater foundation adds genuine finite-ammunition fire and bounded warmup.
Owned Rifle and Repeater share physical key 4 without renumbering earlier guns.
Capability 35 gates unsupported clients; record revision 2 retains eight weapon
columns while genuine-zero legacy delivery preserves strict revision 1 shapes.
Version 11 saves archive exact older bytes and reject unsupported ownership.
Current campaign and arcade kits do not grant Repeater. Its own art, cues,
campaign lesson and human feel acceptance remain pending.

The source-derived civilian Rifle was selected in
[PR #356](https://github.com/blisspixel/fragr/pull/356) after source, paired
ordinary play, unchanged viewmodel, complete local client, eight CI and three
desktop package checks. The player subsequently rejected its framing and
style, so the earlier pictures are restored. The model's bounded real bolt,
glove-contact and hollow-bore proofs remain offline alongside the rejected bake.
Weapon rules and ammunition behavior are unchanged.

## v0.73.0 (2026-10-04)

Passenger Manifest extends the campaign prototype through level 9. The lunar
Common Carrier berth has supported gantries, service galleries and sealed
glazing, ordered encounters and human Union Enforcers with server-owned contact
charges. Strict version 10 saves retain actual M08 outcomes and historical
unknowns, equipment and retry carry. Clinic-team rescue counts as saving Edda
for this appearance; Splice requires actual prior evacuation. Released crew
have an optional grounded boarding route. Level 10 remains pending.

The default free human now wears hatless civilian workwear. A refined Pistol
uses readable painted materials, coherent moving hardware and registered held,
firing and pickup frames. Each increment passed its local gates, complete CI
and all three desktop package checks before merging to main. Level 9 remains a
development prototype with final casting, art and fresh-player review open.

All eight main CI jobs passed at `72dfd263`. Tagged Windows, Linux and macOS
packages passed their checks; uploaded SHA-256 digests match the release
checksum manifest. The release was published on 2026-10-04. The next Rifle
presentation and further weapon source candidates remain separate work.

## v0.72.0 (2026-10-04)

An optional `--sabotage-five-v-five` host profile bounds Sector 9 Sabotage to
ten shared fighter seats, five per side. Humans, agents and rule bots share
the same limit; spectators remain welcome. Fresh fighters and post-death rounds
start with a selected Pistol and fifty finite Bullets. Stronger weapons come
from the map, survivors retain their guns and ammo, and parked reconnects
preserve exact inventory. Full rooms show a localized refusal and Return;
players may choose Watch. Generic matches keep their existing behavior.

Eliminated participants can no longer move, jump, swap, fire or claim supplies
before their next real round. Committed finite devices retain their existing
lifecycle. Focused simulation, socket and client admission checks pass locally;
complete CI and desktop package verdicts are recorded on PR #351. Standalone elimination,
additional objective maps and Liberation remain planned.

## v0.71.1 (2026-10-04)

Gameplay starts behind its loading screen, before the default arena can appear.
The curtain waits for authoritative geometry, a matching snapshot and a drawn
frame; campaign stories can take over the cover. Failed loading offers return
to the menu. Released grenade/mine inputs work immediately after dismissal,
while held keys still require release. This does not resolve the separate
unreproduced office-wall or intermittent Kitchen material report.

The multiplayer direction now includes original 5v5 objectives and Liberation,
humans and free agents cooperating against Union forces. Three classic-map
research reports, contribution guidance and corrected non-invasive fair-play
planning distinguish existing host controls from unbuilt modes and defenses.

## v0.71.0 (2026-10-04)

The cast gains four coherent stylized production sources and rigs. The free
human's selectable body uses a prepared skin and gait, painted angular face,
worn leather jacket, work trousers and civilian accessories. The Sweeper gains
a broader bot silhouette and two-handed rifle poses. The Auditor gains a
skinned field uniform, held shield, repair sockets, upper-back cable and
raised-hand emitter, with matching directional body normals. Latch uses a live
packaged skin, retained gait, expressive CRT face and actual palm attachment.
Played evidence and remaining acceptance gates are recorded separately.
Production used 160 included model credits, with no new cash charge.

Incoming fire gains short spatial pass-by cues and fading pixel damage
bearings from resolved server shots. Finite shot segments, authoritative cover,
local ownership and a bounded voice pool govern feedback. Actual two-client
range shots exercise each bearing and a non-damaging near miss. Broader room
acoustics and listening acceptance remain open.

Local campaign departure shows actual kills, secrets, deaths and server elapsed
time after story presentation. Readiness and retries own the clock; completion
freezes it. Capability 33 gates the new record field for older clients. A real
M01 route reaches its tally and durable onward save. Authored par is not yet
available and is omitted.

Low Water's west court gains three sealed residential buildings with domestic
windows, varied roof heights and roof edges. Solid bodies and upper silhouettes
use authoritative collision. The full mission route retains all 28 guards and
departure; an optional roof route has a verified ordinary return. Older M04
saves tied to the previous map hash remain incompatible.

The played capture helper now waits for attainable pitch at the existing
85-degree limit, retaining its strict acknowledgement tolerance. A real setter
regression, old-behavior mutation and identical route replay prove the fix.
Full M02 art-route completion and fresh-player pacing remain open.

## v0.70.0 (2026-10-03)

The Clerk's replacement source has angular painted facial planes, a black
high-collar field uniform, dark steel plates, peaked service cap and red registry
arm band. Directional combat and seated poses retain their existing layout,
paired body normals and server-owned timing. A clean guard-room replay confirms
both named guards defeated with the currently selected Shotgun. Black/red marks
Union outfits and issued equipment; venue walls keep their own materials.

Low Water gains a shared charging and repair bench, maintained clinic beds,
interrupted meal settings and sealed domestic windows. The lunar port gains
cargo locking straps, overhead services, restrained practical lighting and
customs work details. Both bounded passes have clean full-mission rendered routes
and passing implementation CI. Their broader architecture and art remain in progress.

Port of Entry gains a loaded freight weighing assembly, customs terminals,
luggage inspection and records storage. Pressure-case lids have chamfered seams,
grips, cam locks and visible gauges; the weighing beam has measuring heads and
controls. Substantial bodies use authoritative collision. The clean 31-state
structural route retains all 21 guards, the Rail lane, Turret lesson and actual
departure; separate final art views inspect the later surface refinement.

Real clinic and workshop roof slabs enclose Low Water's rooms, with a closed
raised-shutter housing and unchanged open-air court. A clean 29-state route
confirms all 28 guards, patient release and actual roof departure with no deaths
or HP lost. The capture route's return crossing stays on its supported platform
and explicitly traverses the existing stair tread. Shots collide with the
rendered roofs; existing mission rules and movement remain authoritative.

Low Water trim and lunar dwelling/deck materials retain their own quiet colors.
Union outfits and explicit security equipment keep black/red. Actual before/after
art subsets confirm the material separation without changing map geometry.

Declared Goods joins the campaign with its curfew town, Sniper Rifle window
lesson, crater cut and freight departure. The clean 29-state route defeats all
25 required guards and confirms actual window cancellation and departure. The
route ends at 15 HP and one Cell, leaving a fresh-player pacing concern.
Continue Run now reaches Custodian of Record without a continue refill.
Version 9 saves actual finite mine counts; strict historical upgrades preserve
exact source archives, and retries restore the mission-entry anchor. M09 remains
unplayable. These are development prototypes with final art and fun acceptance open.

The Clerk source and rig consumed 40 existing model credits, bringing locally
tracked net consumption to 165. The free account check reports 2,905 available
credits; the prior uncertain 15-credit reservation remains held. No new cash
charge or automatic top-up ran. The remaining cast and separate Shotgun candidate
still need refinement and acceptance.

## v0.69.0 (2026-10-03)

Clerks use a prepared skinned human source with sampled walking, authored combat
and seated poses, charcoal issued cloth and paired body normals under venue
light. Their directional layout and server-owned combat remain unchanged. Live
Recall Notice and Persons Unknown routes provide bounded presentation evidence.
The remaining cast, Shotgun candidate and environment kit still need refinement.
The Clerk's unarmed strike reaches forward with a torso lean. An offline Shotgun
source retains its reviewed surfaces and separates the actual pump, with a glove
that travels with it. This candidate does not replace the selected viewmodel.

The native model pipeline verifies live credit before each paid stage, preserves
uncertain reservations and prepares offline assets. The pilot consumed 125 net
credits; 15 remain held against an uncertain request, with 2,975 reported on the
account. These presentation refinements used no additional paid generation.

## v0.68.0 (2026-10-03)

The Sweeper now comes from an original articulated 3D source, with directional
normal cells that let venue light describe its body. Its carbine keeps a shorter
profile than the precision rifle. Latch has a lean civilian chassis, a tall screen
with pixel eyes, one left antenna and visible repairs.

Registered fixtures gain modeled housings. Existing walls have recessed bays,
ceilings have inset coffers, and 26 selected materials cover the current venue
families. Shallow water has moving surface normals, highlights and sparse drips;
Low Water gains an exterior river. Server collision, combat and mission facts
remain authoritative.

Nine original GLB exports and inspected high-resolution source references support
continued production. The Shotgun model and coherent pump frames remain candidates
pending first-person framing and hand refinement; existing viewmodel art stays
selected. Other character models and full environmental kits remain unfinished.
The developer API checker verifies credential access through free price estimates;
reference prompts can set explicit exclusions while old requests keep their identities.

Nick reported $14.42 remaining from a $105.88 starting API balance, a $91.46 net
decrease. The 151 completed image requests retain $93.365 in estimated reservations;
individual billed charges remain unverified. No runtime asset API is required.

## v0.67.0 (2026-10-03)

Sabotage, a rebuilt Shotgun, two art passes, the Sniper Rifle, the Proximity
Mine and the Auditor, a standalone level 8, and a polish pass over levels 1
to 6. Every level remains a development prototype; fresh-player and difficulty
acceptance stay open.

Sabotage, the first flagship round mode, plays on Sector 9 Transit Hall. The
free coalition carries a charge to A Frame or B Server and plants it with three
seconds of held Use; the Union holds the sites or defuses a planted charge in
six. One life a round, a muster in each spawn zone, a 35-second charge clock,
and halves where everyone changes uniform. Every life starts empty with a
pistol pad by the spawn; survivors carry their guns and armour forward and the
fallen drop their best one. Rule bots stage, push, plant, anchor, rotate,
retake and defuse, and agents read the same objective through MCP. Site
plates, the charge, its timer, the plant and defuse bars and the round card are
pictures; the HUD keeps to one line. Start a server with
`fragr-server --mode sabotage --map 4 --bots 8`.

The Shotgun has a new full-band blast and works its pump after every shot,
finishing before the next one can fire. Guns are rebalanced so the Shotgun is
the loudest and the Railgun no longer clips; the Pistol has its own shot.
Resolved hits play the impact of the gun that landed. Clerks, Sweepers, Heavy
Sweepers and Turrets announce their windups, and a Turret's charge stops when
you break its sight. Falls, Fists and Shiv swings, pickups, an empty trigger
and grenade throws now make sound. The Sniper Rifle, its scope and the Ranged
Sweeper use their own cues, the marksman's tell follows its windup, and the
curfew chime is ready for Level 7. External spend was $0.

Every gun now fires with its own drawn frame and muzzle flash: the Pistol's
slide snaps back, the Shotgun blasts and then pumps, the Railgun's coils light
cyan. All hands wear the same brown leather work gloves, the Fists and the Shiv
included, and a thrown grenade leaves the off hand while the gun dips out of the way.
Pickups are drawn as their objects, a medkit, an armour vest, boxes of bullets
and shells, a cell canister, grenades and each gun in profile, instead of
labelled crates, and fighters hold the same profiles. Health and armour carry
icons beside their numbers.

Level 7's Sniper Rifle (first-person frames, pickup and scope overlay) and the
Ranged Sweeper (mast antenna, long scoped rifle and a growing windup glint) are
ready for that level to wire. Image generation used an estimated $2.76 of
existing credit.

The Rifle is repainted in the Pistol's flat grey-green enamel, so it no longer
breaks into blotches at game scale, and its fire frame shows a bright
four-point flash. Each gun now has its own third-person muzzle flash: a small
star for the Pistol, thin needles for the Rifle, a ragged fireball with smoke
for the Shotgun, a cold cyan ring for the Railgun and a long level jet for the
Sniper Rifle. Impacts are drawn sprites that play out over a quarter second: a
spark and a dust puff on walls, a red splash and droplets on fighters, a
widening cyan ring for the Railgun and a dust smack for melee. Redrawing the
Rifle used an estimated $0.20 of existing image credit.

Level 8's Proximity Mine is drawn: a grey steel puck with a red lens lies on
the floor as its pickup, sits in the off hand and leaves it with its clamp
feet springing open when placed, and once stuck shows its face on the surface
with an amber arming lamp and a red blink. The Auditor has its own figure: a
Clerk's issued body under an officer's cap and long coat, a tall shield plate
on the forearm, a repair spool on its back and a lit emitter raised toward the
body it repairs; the two repair lamps sit on the drawn plate. The mine art used
an estimated $0.44 of existing image credit; the Auditor is a local rig.

Sabotage art is ready for its presentation: a leather-strapped demolition
charge with a timer box, A and B site plates on Union steel, a correction
frame and a registry server for the two sites, the planted charge armed,
blinking, in its last seconds and defused, the charge in the off hand, two
hands planting and defusing it in first person, and plant and defuse icons.
The pictures used an estimated $0.95 of existing image credit, one rejected
first draft of the charge included.

The Sniper Rifle and the Ranged Sweeper arrive for level 7. The Sniper Rifle is
a found Cells weapon: 70 damage, a 1.6 second cycle, a cone that stays on a body
out to 90 metres, and a held scope that only changes the view. The Railgun keeps
the middle distance with its faster, harder shot and bright beam; the Sniper
draws a faint tracer at the far end instead. The Ranged Sweeper is a stationary
Union marksman with an antenna mast. It glints, holds its aim for 1.5 seconds on
Standard, then fires once; dropping fully behind cover cancels the shot and any
hit interrupts it. Both appear on a development range with a firing step behind
a sill. Both wear the art pass's first-person frames, pickup, scope plate and
marksman atlas, with an orange tracer to match the Sniper's flash, and the
sound pass's report, scope, glint and marksman shot cues.

The Proximity Mine and the campaign Auditor arrive on a new custody
development range. A mine is thrown from the eye with its own key, sticks to
the first surface, holds a steady lamp for two seconds, then blinks until a
body comes within two metres and trips it; it goes dark with its owner. The
Auditor raises a hand and channels a visible repair into a disabled Sweeper,
twice at most; a hit or broken sight snaps it, and its shield plate halves
frontal shots. Agents engage a channeling Auditor first. Mines have their own
count, records column and Godot presentation.

Custodian of Record, the level 8 radial custody archive, is a development
prototype under Practice and Development. Clear the records hall around the
central shaft, take the cage mines in a one-entrance alcove and let a
dispatched post pair walk into them, beat the upper gallery Auditor to lift the
archive's one seal, survive an ambush among the cooling pipes, then shoot four
glowing support nodes until the custody machine drops through every gallery. The transfer evidence, an uncalled freight
car and a counterattack up both freight stairs lead to departure. The lower
bays and Orrin's cold cabinet are optional, three secrets are marked with a
six, and keyed text pages frame the arrival and departure. Its M07 to M08 run
carry waits for level 7.

A polish pass over levels 1 to 6 seals the gaps that led outside the facility
and the lunar port. Cleared fights now count without stepping on hidden
arrival spots, so departure is never blocked by a missed square. Guards who
lose you walk back to their posts, level 2 gains a medkit before the Crawlers,
and level 5 no longer disconnects when the workers are freed early. Enter
continues your run after each departure, and the campaign HUD is quieter.
Free local agents now depart on all 18 level and difficulty runs, up from 7.

Display settings gain SHOW FPS: off, the frame rate, or the frame rate with
average frame time and the 1% low, drawn small in the top right corner on the
menus, in campaign and in multiplayer. The tilde console takes `cl_showfps 0`,
`1` or `2` and saves the same setting.

## v0.66.0 (2026-10-02)

Port of Entry extends the campaign prototype onto the Moon with an inhabited
cargo port, finite Railgun discovery, a long firing lane, flankable Turrets,
three secret detours and an optional prisoner-route marker. Lunar pressure rooms,
Earth and the impounded passenger ship follow the shared appearance guides.
Two original pixel story illustrations accompany the existing offline narration
and reader-paced captions.

Twenty-one selected palette textures give Earth and lunar materials distinct
repair histories, pressure panels and walking surfaces. Existing civilian
possessions and shallow-water presentation remain. Five of the textures form an
inspected future offworld library; Mars missions remain unbuilt. Material scale,
edge repeats, actual lighting and quiet fighter backgrounds were reviewed.

Continue Run carries completed M05 runs into M06 and refills Episode II to three
continues exactly once. Strict v7 upgrades retain exact historical bytes, actual
equipment and separate released and evacuated worker outcomes. Reopening,
retrying and Practice do not refill the run.

Living characters and reachable civilians now block ordinary walking. The server
owns body contact; local first-person prediction stops and slides using recent
validated bodies. Shared controllers account for occupied paths, and workshop
workers settle at separate actual boarding positions. Dead and detached bodies
do not trap movement. Crawler damage, hover and tram support retain their own
authoritative behavior.
Grounded crowd recovery also prevents occupied gallery waypoints skipping across
walls and unsticks the actual four-person M01 route without larger mission budgets.
The nearby live companion fades as one complete figure, preventing detached head
facets in upward views while retaining the distant body and its world shadow.
In two-bot CTF sides, a flag carrier can defend against its own flag thief at
the existing contact range. Four declared identity orders retain the original
seed survey's completion and visible combat-drop gates.

The shotgun has a new offline blast, and ordinary radio startup chooses a random
populated station and random track, including visual test runs. Rapid environment
changes retain their sky resources through the next rendered frame.

These remain development missions. Fresh-player pacing, difficulty acceptance,
final character performances and later missions remain open. This increment used
282 included audio credits and $0 new cash charges. The ongoing round totals
975 included audio credits, a conservative $5 audio reserve and $4.085 of new
image reservations with billing unconfirmed; the earlier $0.107 reservation
remains preserved.

## v0.65.0 (2026-09-30)

The campaign prototype continues through Scheduled Service, Notice to Vacate and
No Forwarding Address. The yard mast, optional recall cars, clinic patients,
workshop rescue and deliberate departures are server-owned. Earlier choices,
equipment and remaining continues carry into the next mission, with strict
upgrades and an exact-byte archive for older local saves.

Low Water now has repair detail, shallow animated water, roof tanks, workshop
props and a real bounded tram. Flying Notaries have original directional poses
and attack cues. Grenades use a separate carried count, bounce on actual cover
and explode on a fixed fuse with falloff and self damage. Story transitions have
captions and committed offline narration. Linked world, character and voice
guides keep later art and cutscenes consistent with the setting.

Remote participants and spectator cameras move more smoothly. Free agent control
stays responsive during slower decisions, and attacking capture-the-flag agents
fight blockers on their route. Local Practice includes the new prototype entries.

These remain development missions. Fresh-player review, full campaign pacing,
final character performances and later missions remain open. This round used
693 included audio credits and $0 in new cash charges.

## v0.64.0 (2026-09-30)

Capture the flag now runs on Arena Duel and Directive 17, as well as Sector 9. Each side has a stand in its own back third. Compliance Yard, Reclamation Gulch and Tripoint Works stay off the mode.

Fresh-player review of Recall Notice and Persons Unknown stays on the v0.58.0 package. External spend for this build was $0.

## v0.63.0 (2026-09-29)

A Sector 9 carrier sees how far their own stand is, and which way. Everyone else sees the same metres and compass toward a stolen flag. A flag at home, for someone who is not carrying, still reads HOME.

Fresh-player review of Recall Notice and Persons Unknown stays on the v0.58.0 package. External spend for this build was $0.

## v0.62.0 (2026-09-29)

A Sector 9 capture result sits on an opaque card. Who took the round, the capture count, and the reason stay readable in front of the home flag.

Fresh-player review of Recall Notice and Persons Unknown stays on the v0.58.0 package. External spend for this build was $0.

## v0.61.0 (2026-09-29)

A first-person carrier on Sector 9 sees the flag's cloth and the stand words beside the weapon. The world grip stays hidden for that carrier, because it sits below the eye. Everyone else still sees the flag in the hand.

Fresh-player review of Recall Notice and Persons Unknown stays on the v0.58.0 package. External spend for this build was $0.

## v0.60.0 (2026-09-29)

A carried Sector 9 flag leaves the stand and sits on a short grip in the carrier's hand, in front of the body. The cloth overlaps the arm. Home and dropped flags keep the tall pole, and an empty stand dims. A nameplate yields when it would cover the cloth or the world words.

Fresh-player review of Recall Notice and Persons Unknown stays on the v0.58.0 package. External spend for this build was $0.

## v0.59.0 (2026-09-29)

On Sector 9, a side of at least three server rule bots keeps one defender and
sends one escort with the flag. The carrier runs it home and does not shoot.
Two-bot rounds keep the goals they already had. Longer bot matches still end
on the clock, short of the three-capture limit. Frag totals are not a
cross-platform lock.

A carried flag reads UNION FLAG CARRIED or FREE FLAG CARRIED, and those words
sit on the cloth. A flag at home or on the ground keeps its pole label. The
world label does not add the carrier's name.

Fresh-player review of Recall Notice and Persons Unknown stays on the v0.58.0
package. External spend for this build was $0.

## v0.58.0 (2026-09-28)

Persons Unknown now follows Recall Notice as one local solo run. The same body,
equipment and remaining Episode I continues carry into level 2, and an
accepted Continue restarts that level at its own entry. The development route
teaches the Shotgun and Crawler, lets the player release Latch, and gives Latch
server-owned help without making departure an escort objective. An optional
side ward can evacuate captives; the Notary is only seen behind glass. The
level still needs unsteered player review before its route and presentation
can be called finished.

Sector 9 now supports capture the flag with server-owned flags, return and
capture rules, side scores and a separate match limit. Bots and agents can
play the objective, and spectators see the same state. Team aim assist now
ignores allies. Controlled socket tests prove a complete capture, while
contested play and human readability remain active review gates.

Human movement now predicts and reconciles locally from 3D server Acks on the
existing 20 Hz WebSocket match. Moving-combat and delayed-egress probes record
the current behavior. One-shot jump, use and weapon choices survive a failed
send. A two-machine human session is still needed before a network feel or
UDP decision.

The dedicated server has a local container image and Compose path with a
health check. The optional COS cloud host is Terraform plan-only and has no
default public game ingress. The README is a shorter entry point to the
playing, hosting, campaign and technical guides. External asset and cloud
spend for this build was $0.

## v0.57.1 (2026-09-26)

Every fighter now gets the same one-second spawn shield at the start of a
round that they already got after a respawn. On crowded maps two neighbours
could open a round within sight of each other and trade a kill before either
had a fair chance; a respawned fighter never could. Spawn placement and the
playtest's opening spawn-death gate are unchanged.

## v0.57.0 (2026-09-26)

Choose who you are. Your callsign page now has a body: a human, or an
embodied agent in a synthetic body. Both share the same story and fight by
exactly the same rules, with the same health, speed and hit volume. Other
players and spectators see the body you chose, in free colours of bone,
leather, rust and ember with small cyan accents, never the Union's black and
red, and on the free coalition's side of a team match they keep those colours.
Rule bots bring both bodies, and agents choose theirs through the same join
with `--body` or the `join` tool. Change it on the callsign page before you
join; a pawn keeps its body through respawns and reconnects.

Clients and agents now speak gameplay capability 13. It adds the body to the
hello, the welcome and every fighter in a snapshot; no map requires it, and an
older client simply plays as a human.

## v0.56.0 (2026-09-26)

The reference agent can think for free on your own machine. `fragr-brain
--provider ollama` asks APUS-OpenJev-v1-4B, an Apache 2.0 open-weights decision
model, through a local Ollama server: the brain renders the model's own
candidate-scoring prompt and reads its answer from the letter probabilities, so
there is no text to parse. `--provider openjev` points the same brain at an
openjev server you run yourself; those weights are licensed for non-commercial
use only, so fragr never bundles or defaults to them.

Both are loopback only unless you pass `--allow-remote-model`, need no key, and
never touch the spend ledger. Every reply is checked against the questions
asked, and a slow, wrong or unreadable answer hands the fighter to local rules
exactly as a paid one does. The run summary now reports p50 and p95 decision
latency, timeouts, fallbacks and decisions per second. On a laptop with
integrated graphics the 4B model answers in about twelve seconds, so give it a
longer `--timeout-ms`; measurements and hardware are in
`docs/plans/brain-local-model.md`.

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
