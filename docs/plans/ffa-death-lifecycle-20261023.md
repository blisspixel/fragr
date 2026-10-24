# FFA death lifecycle and post-death residue

Status: **implemented**, 2026-10-23, on branch `wave1/death-lifecycle`.
Local evidence is recorded below. Windows rendered reproduction has not been
run, and FFA pacing still needs Nick's decision. Owns
[#441](https://github.com/blisspixel/fragr/issues/441) except the default FFA
respawn duration, plus the
[#437 comment](https://github.com/blisspixel/fragr/issues/437) about a coloured
frame or box left after death or respawn. The top-HUD collision and the
result-text tilt in #437 belong to another lane.

## Goal

A joined arcade player's life has explicit ownership:
alive → down (death camera) → awaiting respawn (server countdown) → alive.
Out (no respawn coming) is the fourth state. Held input never becomes
free-camera flight. It is never sent for a dead body and never preloads the
next life. The death indication names the cause and the actual perspective and
shows the server's countdown. No result-card outline survives its card.

## Root causes found

1. **Unlabelled perspective switch on death (client).** The arcade body leaves
   the snapshot on death, so the client drops first person. The camera then
   fell back to spectator defaults (`follow_mode`, `spectator_first_person`).
   It jumped into some other fighter's eyes, usually a moving bot, with no
   label. `lock_on_frag` refused to chase the killer because
   `spectator_first_person` was true. A player who had once pressed V got free
   flight driven by the same held WASD and stick. Either way the view "kept
   moving forward" after death.
2. **Stale server input into the next life (server).** While dead, the Godot
   client sends no Actions, so the server kept the last pre-death
   `pending_action`. A W held at death walked the respawned body until the
   client re-entered first person. A trigger held at death fired the first
   alive tick, and presses latched while down (use, grenade, mine, reload,
   remote mines) fired on respawn. Shown by mutation: on the old code the new
   server tests fail (body walks, held trigger fires, presses survive).
3. **Preloaded presses (client).** `_input` kept setting `pending_fire`,
   `pending_jump`, `pending_interact` and similar while dead, and the first
   Action of the next life carried them.
4. **The coloured frame (#437 comment).** `StampCard` draws a worn-ink border
   around the result label. Its draw commands are cached and nothing ever
   retired it. After the result banner hid, the orange or red outline stayed
   on screen through the next round start, a death and a respawn. Reproduced
   in a rendered capture (`stamp visible=true`, `target_visible=false`) at
   `.agents/death/before/02_after_banner.png`, `05_respawned.png`. Damage
   `ScreenFlash`, `SealCutPlate` and the sniper scope were inspected. All three
   self-clear on time or with first-person juice, so none is this residue.

## Changes

Server (authoritative):
- `rules.rs`: `FFA_RESPAWN_DELAY_TICKS = 60` and `TEAM_RESPAWN_DELAY_TICKS = 60`,
  read through `RuleSet::respawn_delay_ticks()`. FFA pacing is one constant,
  and changing it cannot move team modes, elimination or the 20-tick spawn
  shield. The default is unchanged (3 s).
- Death (`resolve_fighter_hit_for`): `clear_input()` ends the dead life's
  held movement and queued presses. `fire_latched` keeps a trigger held at
  death latched until released.
- `set_actor_action` while awaiting respawn keeps only the newest held state.
  It drops discrete requests, weapon choice and seat, and sets the fire latch
  from the newest input. Rule bots send empty intent while down, so they are
  never left latched.
- `Ack.respawn_ticks` (optional, unicast): ticks until the respawn attempt,
  present only while awaiting an arcade respawn.

Client (presentation only):
- `LocalLife` (`local_life.gd`) owns the phases, cause (killer, self or
  unknown), and the countdown, re-anchored on every Ack. It never requests or
  admits a respawn.
- `game_manager.gd`: the frag fact or the snapshot that removes the body,
  whichever comes first, ends the life. That stops prediction and local fire,
  drops every pending press and disarms the trigger and devices. No Action is
  sent while down. When the body returns a new life begins: the death view
  ends, the server pose and facing are adopted by the existing snap, and fire,
  jump, grenade, mine, reload and remote mines stay disarmed until released
  if still held.
- `spectator_cam.gd`: `begin_death_view`/`end_death_view`. The camera holds the
  dead eye, or chases the killer while that pawn exists. It reads no movement,
  look or view keys, even while a menu is open, and never takes another
  fighter's eyes. Reduced motion snaps the chase.
- `death_card.gd` plus HUD hooks: three lines below aim, for cause, view
  (`WATCHING <name>` or `YOUR LAST VIEW`) and timing (`RESPAWN IN n`,
  `RESPAWNING`, `OUT UNTIL THE NEXT ROUND`). Strings are in `match.en.po`.
- `stamp_card.gd`: `retire()` resets the label transform it applied, hides
  and redraws. The stamp retires itself the frame its label is no longer
  visible in the tree. `_show_round_banner` retires it before an unstamped
  banner.

## Decisions

- **Held movement resumes.** WASD and the stick held when the body returns
  apply from the live key state on the first new-life Action. That is the
  normal arena-shooter feel, and it is not stale: the server cleared
  movement at death.
- **Discrete actions need a release.** Fire, jump, use, grenade, mine, reload
  and remote mines held across death need a release, and presses made while
  down are dropped. Leaving and speaking still work while down.
- **No interpolation across lives.** The death view never runs after the body
  returns, and first person snaps to the new body (existing `set_fp_mode` and
  spawn-pose adoption).
- Sabotage keeps its teammate watch for fallen fighters. Campaign bodies keep
  their existing zero-health first person and retry path. Neither enters the
  death view.

## Non-goals

No change to the default respawn delay, starting weapon or spawn shield. No
pause-menu or HUD-region rework. No #437 top-HUD collision or result-text
tilt. No new wire message.

## Protocol

Additive: optional `Ack.respawn_ticks`, documented in `docs/protocol.md`
along with the death input rules. Older clients ignore it. Godot validates it
as an exact integer in `[0, 12000]` at the Ack boundary. Agent-visible change:
`act` presses sent while down are dropped, noted in `agent-adapter/README.md`.

## Verification

| Check | Result |
|---|---|
| `cargo test -p fragr-server death_lifecycle` (9 tests) | pass. Mutation without the death clear or the down gate: 5 fail |
| `cargo test --workspace --locked` (`--no-fail-fast` on the last run) | 2175 passed, 5 failed. Every failure is a wall-clock deadline under load average 50+ on 16 cores (six lanes): three `geometry_owned_local_*` runners (30 s deadline while the local server is still starting, `waiting_ready`, before any client or Action exists) and the adapter's `scripted_bot_uses_raised_geometry…` (4 s timeout; the adapter ignores `Ack`). A different subset fails on each run. Alone, the adapter test passes (0.2 s) and 2 of 3 geometry runners pass serially; each runner takes 8–21 s of its 30 s budget. CI on an unloaded runner is the gate. |
| `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --locked -- -D warnings` | pass |
| `test_death_lifecycle.gd` (new harness) | PASS. Mutations (stamp never retires; fire not fenced) fail it |
| Related harnesses: jump_input, spectator_camera, local_prediction, input_pacing, signature_moments, accessibility_hud, event_covers, grenade_controls, local_fire_feedback, status_bar, combat_feed | PASS |
| `cargo llvm-cov` 90% floor | **not run** locally (host saturated by six lanes). New Rust is covered by 9 focused tests; CI enforces the floor |
| `tools/godot_check.sh` | first run: 612 ok, 1 FAIL (`test_combat_feed`, which asserted the retired `lock_on_frag` death watch). Moved the test to the death-view contract (same intent: killer in either fact order, never in Sabotage) and restored the Sabotage-watch guard it caught. Final rerun: recorded in the PR handoff |
| Rendered residue repro `.agents/death/stamp_residue.gd` | before: border persists; after: none (`.agents/death/after/*.png`) |
| Live real-server runs (`.agents/death/live_death.gd`, 6 and 10 bots, licence-to-kill, W and fire held) | see below |
| Windows rendered reproduction | **not run** (Linux host) |
| Controller stick on hardware | **not run**. Stick is covered by the injected `stick_source` in the harness |

Live run observations (`.agents/death/live*/report.json`, PNGs inspected):
- The killer was chased and labelled `FRAGGED BY <killer>` / `WATCHING
  <killer>`. Ack countdowns 52→41→35→4 ticks showed 3→2→1.
- In a second death about 0.8 s after a respawn, past the 1 s shield, the
  card switched killer and recounted.
- After respawn the body moved forward with W still held (intended). Sent
  `fire` stayed false and `just_fired` stayed false for 600 ms with the
  trigger held, and shots began only after a release and fresh press.
- A respawn across a round end showed the legitimate stamped result card;
  no stale card, border or death card appeared after the plain respawns.
- Death-to-respawn spanned 60 server ticks plus spawn retry. Wall-clock gaps
  in the logs are client frame stalls while capturing in an unfocused window
  (no snapshot ticks advance in them).

Untested combinations: Windows; real gamepad; TDM, CTF and Conquest deaths
live (same code path, and the rule value is covered by unit test); Two Lives
elimination live (`OUT` covered by unit test); flash modes standard, reduced
and off with a live death (the residue path is independent of flash mode;
`ScreenFlash` is time-bounded).

## Open questions for Nick

1. FFA pacing: keep 3 s (`FFA_RESPAWN_DELAY_TICKS = 60`) or choose a longer
   value, or add a respawn-ready press? Changing the constant changes FFA
   only, and the countdown follows automatically.
2. Confirm that held movement should resume on respawn while held fire and
   jump need a release.

## Next step

Reviewer opens the PR. After merge, one wave-end `tools/qa_tour.sh --publish`
and a Windows playtest of death with W, fire and stick held.
