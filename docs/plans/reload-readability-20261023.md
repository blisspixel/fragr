# Readable reloads for ordinary guns

Status: **implemented** (2026-10-23, issue #440, branch `wave1/reloads`).
Local evidence is at the end. Not merged.

## Goal

A joined human can tell, without guessing, whether a reload was requested,
accepted, is running, finished, was cancelled, or could not happen. Every
ordinary magazine gun (Pistol/Tack, Rifle/Flechette, Repeater, Shotgun/Scatter,
Railgun, Sniper Rifle, Arc, Rocket Launcher) gets the same contract: an
explicit HUD status line with a progress bar, a modest held-weapon motion, and
one restrained start and one completion sound from audio already in the
repository. Muted audio, reduced motion and head bob off still show the
status.

October 23 Windows multiplayer feedback said reload "eventually works, but
appears to have no sound or animation". Static inspection of `e4cec37`
confirms it: `WeaponArt.ReloadMotion` moved only the Rocket, `reload_frame`
covered only the Arc, no reload cue existed, and the corner number changed
only at completion.

## Non-goals

- No change to magazine sizes, reload ticks, reserve rules, `GAMEPLAY_VERSION`,
  the wire, or any server rule. The server already owns request, deadline,
  cancellation and completion in `server/src/inventory.rs`.
- No local ammunition grant and no locally predicted completion.
- No new or generated audio, no paid asset work. Dedicated reload clips were
  specified in `tools/audiogen/specs/sfx-weapons.json` in September and never
  generated; producing them is a separate decision.
- No new held-weapon art. The Arc keeps its drawn capacitor reset frame; other
  guns use a motion of their existing held frame.
- No change to respawn delay, starting weapon or other gameplay defaults.
- No tour publish and no `docs/screenshots` change (one publish happens at the
  wave end). Inspection captures stay under `.agents/`.

## Trace of one ordinary reload (as built on `e4cec37`)

1. `game_manager._input` latches `pending_reload` on an R/D-pad-down press, but
   only when the last private loadout has `loaded` (`_magazines_live`).
2. `_send_local_action` puts `reload: true` on the next paced action message.
   The server keeps a rising edge (`sim.rs`: `reload_requested |= action.reload
   && !pending_action.reload`).
3. On its next tick the server calls `Inventory::request_reload`. A refused
   request (full, empty bag, melee, already reloading) changes nothing and
   sends nothing.
4. An accepted request bumps the inventory revision; `session.rs` unicasts a
   `loadout` whose magazine entry carries `ready_at` (a server tick).
5. `finish_reload` fills the magazine at `ready_at`; another revision sends a
   loadout without `ready_at` and with the new `rounds`. Death and a real weapon
   change call `cancel_reload` and send a loadout without `ready_at` and
   without new rounds. A vehicle seat drops the edge but lets an accepted
   reload finish.

Request-to-accept is therefore one action send, at most one server tick, and
one loadout delivery. Accept-to-cue is local: the same frame that receives the
loadout. The reload duration itself is the server's tick count, not latency.

## Design

- `client/scripts/reload_cue.gd` (`ReloadCue`, RefCounted, no nodes). A small
  state machine fed only by
  - `request(state, now_usec)`: the reload rising edge actually sent, or a
    press in a mode with no magazines. It evaluates the server's refusal rules
    against the last authoritative loadout (presentation only) and returns
    either pending or a reason: `full`, `no_reserve`, `no_magazine`,
    `unsupported`, `busy`.
  - `observe(state, now_usec)`: each validated private loadout. Emits `start`
    once per `(life epoch, weapon, ready_at)`; `complete` only when that gun is
    still selected, the loadout tick has reached the deadline, and its rounds
    grew; otherwise `cancel`. Duplicate and repeated loadouts emit nothing.
  - `advance(now_usec)`: expires short banners and turns a pending request with
    no acceptance after one second into `not_accepted`.
  - `reset()`: silent clear for swap, death, respawn, disconnect, map change,
    vehicle seat and leaving first person. The first reload seen after a reset
    with no pending request is adopted without a start sound (reconnect or
    vehicle exit), so a late receipt never replays.
  It also records request-to-accept and accept-to-cue in microseconds.
- `EquipmentHud` owns the explicit indication: a status line under the count
  (`RELOAD REQUESTED`, `RELOADING`, `LOADED`, `RELOAD CANCELLED`,
  `MAGAZINE FULL`, `NOTHING LEFT TO LOAD`, `NOTHING TO RELOAD`,
  `NO MAGAZINES HERE`, `RELOAD NOT ACCEPTED`) and a progress bar that fills
  from the accepted tick to `ready_at`. It is not tied to motion settings.
- `WeaponArt.ReloadMotion` covers every magazine gun with a per-weapon dip
  (`reload_dip`): Rocket keeps its existing depth, Arc keeps its drawn frame
  and does not dip, other guns lower about a third of the held frame and
  return as the deadline approaches. The motion is gated by reduced motion
  instead of the head bob setting, matching weapon kick; reduced motion keeps
  the HUD line and bar.
- `game_manager.gd` owns audio and wiring: one `ReloadSound` player on the
  Effects bus. Start reuses `sniper/scope_out.wav` (a swish and dull metal
  tap, the gun coming down) at -10 dB, pitch 0.94. Completion reuses
  `sniper/scope_in.wav` (a small click and metallic slide) at -8 dB, pitch
  1.08. Both are committed ElevenLabs outputs with manifest entries in
  `client/assets/audio/audiogen-manifest.json`. Cancel and unavailable states
  are silent.
- Stale help: the loading tip "Pressing R does nothing. It used to reload."
  is replaced, and the docs that said no reload cue is wired are updated.

## Protocol or API changes

None. No wire, MCP, or settings shape changes.

## Verification plan

- `test_reload_cue.gd` (new harness): pending, accepted start, duplicate and
  repeated loadouts, completion, server cancel, swap, death/reset, late
  receipt after reset, full/no-reserve/melee/unsupported/busy, weapon-only
  unlimited reserve, rapid taps and held R, not-accepted timeout, latency
  receipts, and HUD status and bar with reduced motion.
- `test_rocket.gd` and `test_viewmodel.gd`: motion for every magazine gun,
  Arc frame unchanged, reduced motion mutes motion but not the HUD line.
- `test_equipment.gd`: the game manager sends one reload, plays one start and
  one completion sound, nothing on duplicates, cancel, death, vehicle or
  disconnect.
- `tools/godot_check.sh` full run.
- Rendered Linux captures of start, middle and end frames for common guns
  under `.agents/`, inspected.
- Windows installed build, separate host, and listening: not possible on this
  Linux host; recorded as not run.

## Spend

None. Audio is reused from committed assets.

## Success criteria

- Each ordinary gun shows a readable start, sustained state and completion,
  driven by the authoritative loadout only.
- One start and one completion sound per accepted deadline; no sound on
  duplicates, cancellation, death, disconnect, map change or vehicle.
- Full, empty bag, melee and no-magazine presses give a short silent message.
- Godot checks pass without weakening any check.

## Status and evidence

**implemented** on branch `wave1/reloads` (2026-10-23). Local Linux evidence
only. Not merged.

As built, matching the design above, with two adjustments found during
inspection: the status line is bone (or ember for cancel and impossible
states) because muted grey and olive text read poorly over the arena; the bar
alone turns green on LOADED. The Repeater still has no first-person frame
(pre-existing), so its reload is the HUD line, bar and sound only.

Automated, Godot 4.7.2-stable, Linux:

- `test_reload_cue` (new): PASS, clean verbose log. Covers refusals (full,
  nothing left, melee, no magazines, busy, weapon-only unlimited reserve, spent
  finite arcade bag), every magazine gun's request, start, progress and
  completion, duplicate, stale and repeated loadouts, server cancel, swap,
  completion only on authoritative growth, reset and late receipts,
  not-accepted timeout, rapid taps, held R, HUD line and bar, and the real
  `game_manager` path: one sent edge, one start and one completion sound,
  silence on duplicates, full magazine, death, vehicle seat and disconnect.
  Mutating the dedupe guard fails 7 checks; removing the "rounds grew" guard
  fails 1.
- `test_viewmodel`: PASS with a new check that Tack, Rifle, Shotgun, Railgun,
  Sniper and Rocket each lower by more than 20 percent of the frame with head
  bob off, stay still under reduced motion with the HUD line and bar shown, and
  return to rest at the deadline. Setting the Tack dip to zero fails it.
- `test_rocket`, `test_arc`, `test_equipment`, `test_local_fire_feedback`,
  `test_accessibility_hud`, `test_status_bar`, `test_jammer_audio`,
  `test_shot_effects`, `test_combat_audio`, `test_crawler_cue`: PASS.
- Full `tools/godot_check.sh`: 611 of 612 checks ok, verdict FAIL on one
  harness. `test_local_campaign` timed out on "walking from entry claims the
  pistol on the live server" while the shared host's load average was about
  61 on 16 cores (six parallel lanes). That route does not press reload. Run
  alone afterwards it passed twice with clean logs. CI should confirm.

Live loopback, real `fragr-server --release --bots 0 --map 1` and the ordinary
client through `qa_arc_visual.gd` with `client/qa/reload-readability.json` on a
nested 1280x720 Xwayland display (receipts under `.agents/live-reload/`, not
committed). One ordinary shot, then R:

| Gun | Accepted tick | Deadline | Request to accept | Accept to cue | Rounds | Bag total | Starts | Finishes |
|---|---|---|---|---|---|---|---|---|
| Rifle | 351 | 373 | 55.3 ms | 0.11 ms | 19 to 20 | 79 to 79 | 1 | 1 |
| Shotgun | 431 | 445 | 35.7 ms | 0.11 ms | 5 to 6 | 23 to 23 | 1 | 1 |
| Railgun | 507 | 535 | 61.0 ms | 0.11 ms | 3 to 4 | 15 to 15 | 1 | 1 |

Request to accept is send to accepting loadout on loopback, including up to
one 50 ms server tick; it is not network latency. The samples show RELOADING
from the accepting tick, the bar rising with the server tick, the held frame
lowering to the full dip and returning as the deadline approaches, and LOADED
on the authoritative finish. The inspected full-size Railgun frame shows the
line and bar over the live arena.

Rendered HUD inspection (`.agents/reload-render/`, synthetic accepted
deadlines through the real HUD scene): requested, start, middle and loaded for
Tack, Rifle, Shotgun, Railgun, Sniper, Arc and Rocket; the reduced motion Rifle
(gun still, line and bar shown); and the full and nothing-left refusals. All
were viewed.

Not run:

- Windows installed build, loopback or separate host: not possible on this
  Linux host.
- Listening to the cues: no listening was possible here. Levels are set from
  measured peaks (scope out -5.6 dBFS peak, scope in -5.5 dBFS) and the clips
  are 0.3 s and 0.2 s.
- Rust checks: no Rust changed.

Open decisions for Nick: whether to produce dedicated reload clips (specs
already exist in `tools/audiogen/specs/sfx-weapons.json`) instead of the
reused scope sounds, and whether the Repeater should get a held frame.
