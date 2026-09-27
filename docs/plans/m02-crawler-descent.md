# M02 Crawler descent

**Status:** in flight, 2026-09-27. Stacked on the stair-top guard room in
[draft PR #269](https://github.com/blisspixel/fragr/pull/269).

## Goal and reason

Teach the Crawler after the upper-gallery Shotgun fight. One low Union chassis
must be heard, seen and dodged on the service stair's lower switchback landing
before the player meets a separate three-Crawler pack with a Sweeper firing up
the next landing. The player can answer with the guaranteed Shotgun, lateral
movement and spacing. This is the accepted M02 order in
[`docs/campaign/m02-persons-unknown.md`](../campaign/m02-persons-unknown.md).

The map at the start of this slice had one straight five-step flight and no
distinct second staging landing. The working draft now authors both encounters
on a shaped descent and gives the Crawler its own low server body. Seeded live
route clears and inspected rendered motion pass. An unsteered player still
needs to test the timing and counterplay.

## Encounter and lore contract

The first Crawler belongs to the Union's constrained bot roster. Its issued
steel, low silhouette and restrained red attack tell must read separately from
the human Clerk, the taller Sweeper and the much later Inheritance machines.
Do not imply that this particular chassis contains a named captive or that
its restricted behavior proves an absence of consciousness. The player is
fighting to reach Latch and may defend themself. The facility's treatment of
captives stays serious; combat barks and captions do not make them the joke.
See [`ENEMIES.md`](../ENEMIES.md#faction-person-and-combat-role) and
[`people-and-agents.md`](../lore/people-and-agents.md#agents-and-bots).

Stage the single Crawler only after the two-Clerk guard room clears. A metal
scrabble from the lower stair and its localized caption precede a visible
crouch. The leap commits to the player's position at the start of that tell,
leaving a lateral dodge and a Shotgun response. The first Crawler has no
simultaneous ranged support. After that fight clears, the next landing wakes
the three-Crawler pack and one Sweeper up the well. This is the first combined
spacing problem, so the pack must not overlap the first learning window or
block every sideways escape. The ward fight remains asleep through both
stair encounters. The accepted sequence is in the
[M02 brief](../campaign/m02-persons-unknown.md#level-2-design-twenty-level-expansion).

At the server's 20 Hz tick, the provisional 12-tick crouch gives 0.6 seconds
between a warning that starts no later than the crouch and the leap. Measure
the jump and recovery against human input, animation and sound rather than
assuming that number feels fair. Keep the locked bearing and a punishable
recovery at every difficulty. A muted player must get the same useful warning
from posture and motion that a hearing player gets from the scrabble.

## Scope

1. Shape a clear lower switchback and a second pack landing without a jump
   requirement for players. Preserve the guard-room pickup order, ward route,
   M02 objectives and all relevant spawn/supply reachability. The first
   trigger wakes one Crawler; the pack has a later separate trigger and includes
   three Crawlers plus one Sweeper. Neither wakes the ward early.
2. Add `EnemyKind::Crawler` and a low authoritative body profile. Use one
   kind-derived source for movement clearance, shot volume, aim centre and
   enemy sight. Standard human/agent body and the GDScript movement mirror
   retain their current constants and golden vectors. Keep Crawler navigation
   on standing-clear routes until a low-topology router is justified.
3. Add a committed crouch, leap and recovery. A Crawler locks the target and
   bearing at windup start, jumps along that bearing, and cannot steer or hit
   through cover after launch. Only the Rust server resolves one bounded
   contact hit per leap. A missed or dodged leap leaves a punishable recovery.
   Hit or death before launch interrupts the attack. Landing and retry end it
   cleanly. A target lost after launch does not redirect the committed leap.
   A contact already resolved by server movement may trade with a shot fired
   later in the same tick.
4. Render an original low issued-steel Crawler with restrained red tell lights,
   distinct crouch, airborne, landing and death poses. Give it its own atlas
   layout: the existing Union atlases are already 25 rows at 4000 pixels and
   cannot absorb two more shared pose rows under the 4096 texture limit.
5. Add a bounded mechanical scrabble cue and localized combat caption before
   the first leap. Caption and visible tell carry the warning with sound muted.
   Duplicate cue deliveries must be deduplicated and captions kept out of the
   aiming area.
   Use a committed offline fallback; no player-runtime paid request.
6. Update protocol, M02 brief, enemy roster, map guide and the single roadmap
   build order with implemented versus planned boundaries. Correct the stale
   Notary and Turret introduction notes in `docs/ENEMIES.md`.

## Architecture and wire

`server/src/protocol/actors.rs` owns the Crawler identity and leap phase.
`server/src/encounters/enemy.rs` owns its target lock, 12-tick provisional
Standard crouch, bounded leap and recovery. The timing is a starting value
to measure, not an accepted difficulty target. Use fixed Crawler timing across
difficulty tiers in this slice; changing existing tier timings later requires
a new `CAMPAIGN_RULES_REVISION` and matching client/run-file checks.

`server/src/movement.rs` owns a kind-derived body profile and retains the
existing standing-body entry points for players, bots and golden vectors.
`server/src/combat.rs` and `server/src/sim.rs` use the same low profile for
server hits and contact. The Crawler may be short, but its collision and damage
must match what a player sees. Movement and contact remain authoritative.

The wire adds a Crawler kind and a leaping phase under gameplay capability 16;
M02's minimum becomes 16 for every role. Capabilities 14 (capture the flag)
and 15 (seated Clerk) are on separate stacked work and must be integrated
before any capability-16 release. `client/scripts/actor_state.gd`,
`enemy_animation.gd` and the local readiness check validate the matching
contract. Preserve old mission and arena compatibility.

The map owns encounter placement and physical landings. Enemy SFX/caption
events follow the existing server event, client audio and i18n seams; no new
combat channel or client authority. `scene_player.gd` handles story scenes,
not live combat captions. The draft emits one `crawler_scrabble` event with a
world position when each Crawler encounter activates. `game_manager.gd` rejects
malformed positions and near duplicate deliveries, and limits playback and
caption to a listener within 24 metres, before using a bounded pool of spatial
Effects voices. `crawler_caption.gd` keeps at most two localized
captions, deduplicates repeats, and does not depend on audio volume. The cue is
an encounter reveal; each later leap still needs its visual crouch tell.
Document the event in `docs/protocol.md` and test both sides.

## Boundaries and spend

This slice does not complete Latch, the ward seal, Notary tableau, M01-to-M02
run carry, optional captives, campaign audio mix or fresh-player acceptance.
It does not alter the CTF branch or merge outstanding PRs. Develop original
art and sound locally first; external asset API and cloud spend budget for this
slice is $0. Any later paid call needs the repository spend gate and explicit
approval before billing.

## Verification and success

- Authoring validation must prove both landings, one-alone-then-pack order,
  Shotgun-before-Crawler order, playable movement through every new solid,
  separate pack/ward activation, and wipe/continue reset across seeds.
- Deterministic server tests must prove the low body fits intended clearance,
  ordinary bodies do not, rays and pellets use the visible height, a locked
  leap cannot home, one contact cannot hit twice, a lateral dodge avoids it,
  cover blocks it, and recovery remains punishable. Prove Assisted, Standard
  and Severe routes without silently altering existing difficulty timing.
- Wire tests must cover older client refusal on M02, unchanged M01/arena
  admission, validated Crawler kind/phase/event on Godot and agent readers,
  and interruption on hit/death before launch. Assert the movement-before-shot
  ordering if a landed contact trades with a same-tick shot.
- Godot headless checks and a live M02 visual tour must show the lone tell,
  actual motion and missed-leap opening, then the later pack from first-person
  and spectator views. Inspect frames and local caption placement; a named
  capture state without the action happening is not evidence. Record sound
  and muted-sound checks separately from geometry and server tests.
- A player who has not read the brief must recognize the low threat, dodge the
  first committed leap, discover that the Shotgun can stop it, and distinguish
  the later pack's close threat from the Sweeper lane. Record deaths, missed
  cues and confusing route choices. This review can reject a mechanically
  correct encounter without claiming the whole mission is complete.
- Run workspace format, Clippy, tests, unfiltered coverage at or above 90
  percent, release build, dependency policy, benchmark, multiplayer smoke,
  mixed-client roster and soak before claiming the slice implemented. Run the
  general visual tour with `--publish` for player-facing changes.

This is a development mission slice. An accurate-aim clear and automated
capture do not pass the unsteered fresh-player gate or prove final difficulty.

## Progress

- 2026-09-27: Compared the accepted M02 beat, current map, server movement and
  combat, and client atlas capacity. Separate lore, server and client reviews
  found that the stair needs another landing and the Crawler needs a real low
  body plus a new atlas layout.
- 2026-09-27: The working draft now has a lone Crawler group after the seated
  guard room and a later three-Crawler plus Sweeper group. Source has a low
  authoritative body, committed leap phases, Crawler atlas and motion,
  capability-16 identity, and a server-origin scrabble event. The client has a
  four-voice spatial pool, a bounded localized caption, and an original offline
  WAV with a deterministic manifest. The Godot 4.7.2 import and focused
  `test_crawler_cue.gd` passed; rerunning its generator reproduced SHA-256
  `18b70a0271c6ee5216988b6dd72a5f3e2b4a26e943f310243053babf1dd3b484`.
  No external generation charge was incurred.
- 2026-09-27: Focused server route tests now clear sixteen enemies, hold the
  lone fight at the grounded switchback, and prove the later pack can navigate
  around cover while its Sweeper fires. The first Crawler's windup now waits
  until the player's eye can see its centre and both sides of the low body;
  an actual-map corner test rejects a partly hidden tell. A retry route
  exposed insufficient on-path health before the processing floor. Measured
  shot timing placed a 30 HP entry pickup at [-1, 0, -5.5], after the route's
  second hit rather than while health was nearly full. The deterministic
  second attempt now survives by 5 HP until the dock pickup; the eastern
  40 HP detour remains. This is provisional authoring balance, not a
  fresh-player difficulty result.
- 2026-09-27: The full 13-state first-person M02 tour reached departure. Its
  authoritative trace recorded the lone Crawler's windup at tick 512, leap at
  524, recovery at 537 and death at 544 with the player's HP at 100 throughout.
  The inspected native windup still shows the crouched low chassis and red tell;
  a named frame is now captured only after its phase was handled and rendered.
  That visual review found a separate first-person camera fault: two smoothing
  passes kept the rendered eye behind stair cover after the server eye had
  rounded it. The camera now snaps to the authoritative eye only when smoothing
  would cross a MapInfo solid, with a focused open-space and covered test.
- 2026-09-27: A final 14-state route reached departure with the revised
  detached observer angle. The strongest active-pack frame under
  `.agents/qa/m02-crawler-spectator-angle/08_crawler_pack_spectator_world.png`
  shows three low Crawlers at different depths while the taller Sweeper fires.
  The final first-person pack windup frame is under
  `.agents/qa/m02-crawler-spectator-final/` and shows the low and tall threats
  together. This is a detached observer camera, not a separate spectator-role
  network session. The full route includes a real leap, recovery and departure;
  the first Crawler did not damage the player in the scripted run. These
  captures show authored behavior, not human readability.
- 2026-09-27: Five unedited, inspected frames from the cue, solo crouch and
  leap, first-person pack, and detached observer pack are published with exact
  capture provenance in the [M02 Crawler visual proof](../screenshots/m02-crawler/README.md).
- 2026-09-27: Local Windows gates passed: workspace format, Clippy, tests,
  94.37 percent unfiltered line coverage, release build, dependency license
  policy, deterministic 16-bot benchmark, four live mode playtests, six-map
  mixed roster through 16 agents, and a 120-second rotating-map soak at 20 Hz.
  The roster recorded two later spawn deaths on each of maps 2, 4 and 5, with
  no opening spawn deaths; all assertions passed. The soak measured 38.1 to
  38.8 MiB RSS and a 0.48 ms lifetime tick p99 on this Windows machine.
  These figures are local checks, not cross-platform or public-host evidence.
  External API and cloud spend for the slice remains $0.
- 2026-09-27: The standard `tools/qa_tour.sh --publish` passed 32 states and
  refreshed thirteen stills under `docs/screenshots/`. The contact sheet,
  first-person HUD and spectator chase were inspected for blank or clipped
  world. The canonical watched-match still now uses an actual live fighter
  chase frame from that tour. This general tour does not replace the M02
  encounter captures.
- 2026-09-27: The full pinned Godot 4.7.2 checker passed after correcting a
  new harness PASS marker and supplying the new caption node to the existing
  shot-effects fixture. Focused cue and shot-effects harnesses passed too.
- Remaining before the slice passes its player acceptance gate: an unsteered
  player's first Crawler encounter and a human muted-sound trial. Sound loading
  and event routing were checked, but no human listening result is recorded.
