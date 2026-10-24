# HUD top-band collisions and upright result cards (#437)

Status: **in review** on branch `wave1/hud-layout` (local Linux evidence below;
not yet merged). Wave 1 of the October 23 Windows playtest round. Windows
confirmation from the reporter is open.

## Goal

The October 23 Windows playtest reported two things: text overlapping at the top
of the HUD, and post-match text that is visibly angled. This plan covers both.

1. The top HUD band keeps its text apart: corner match facts, centered match
   facts, frag feed and notices, the frame counter (`show_fps` 1 and 2) and the
   benchmark status banner. This holds at every supported HUD scale and text
   size, and nothing is shrunk to fit.
2. Essential result copy (winner, score, reason, next line) stays upright on one
   baseline in standard and reduced motion. Per Nick's decision on #437 ("no
   tilted text, anywhere"), nothing on a card is rotated: not the copy, not the
   backing and not the stamp ink. The stamp keeps its feel through border,
   colour and a brief ink-only settle. No scale or stamp border carries over
   into a later card.

## Non-goals

- The post-death coloured box and lifecycle issue in the #437 comment. The
  death-lifecycle lane owns it. See "Overlap with the death-lifecycle lane"
  below for one shared finding.
- The "visual review of published tour stills" comment on #437 (host/chat
  backing, nameplate font, kill-feed icon spacing, the stale team still and
  `qa_tour.sh` regenerating every published file). That comment needs a tour
  recapture and is not done by this lane, so #437 stays open after this merge.
- Menu hierarchy and button focus (#435, #436). Benchmark result-screen UX.
  Gameplay defaults (respawn delay, starting weapon).
- Publishing the tour to `docs/screenshots`. That happens once, at the end of the
  wave.

## Reproduction (before the fix, main `e4cec37`)

`client/scripts/qa_hud_layout.gd` builds the real `main.tscn` HUD, the real
`PerformanceOverlay` and the real `BenchmarkRun` banner. Each window size gets
its own SubViewport of exactly that pixel size. The project's
`canvas_items`/`expand` stretch is reproduced through `size_2d_override`
(Hyprland tiles real windows, so `root.size` is not honoured on this host). Each
state saves a PNG and a JSON measurement of drawn text bounds. The bounds come
from each label's font, wrapped lines and full canvas transform.

Baseline run: `.agents/hud-layout/baseline` has 180 states and 330 problems.
Every problem below appears in an inspected still.

| Symptom | Where | Root cause |
|---|---|---|
| Benchmark banner text interleaved with center match facts and over the first frag rows | every size, all scales | `benchmark_run.gd` puts an 840-wide wrapping banner at y 12 on layer 80. `HudRegions` puts the center chip at `origin` (16) and the feed at 20. Neither knew about the other. |
| `show_fps` 2 readout runs past the right edge ("1% LO") and sits on the first frag row | every size | The label is right-anchored with a 352 box and grows to the right (444 wide) off-screen. The feed starts at y 20, under the 31-tall label. |
| Center facts drawn under the frag feed and notices, and corner state under center facts | HUD scale 150 percent with large text | `HudRegions` sized the feed (`560 * scale`) and corner (`460 * scale`) without limiting them against the fixed-width center (`view.x - 1200`, at most 720). At 1.5 the feed starts at x 1064, inside the center span 600..1320. |
| Result copy rotated -2.5 degrees after it settles, in both motion modes | every result card | `StampCard.trigger_stamp` rotated and scaled the actual target label. Reduced motion skipped only the scale. |
| A stamp border persists with no card (also seen over later states) | after any stamped card | `StampCard` stayed `visible` and was never redrawn after its label hid, so the canvas kept the cached border. |
| Ink hidden on backed cards | Sabotage and CTF results | `StampCard` was ordered below `RoundBackdrop`, so the opaque backing covered the border. |
| Episode complete, fail and the warm-up fallback skipped card setup | `show_episode_complete`, `show_episode_fail`, `show_warmup_bumper` fallback | They wrote `round_message` directly. Earlier backdrop offsets, transforms and ink could carry into them. |
| A tall unbacked podium card ran into the bottom-left context (controls legend, map chip) at large text | 150 percent large | The card grows both ways from a fixed anchor. Nothing placed it against the context. |

Exact Windows reproduction: **not run** (Linux host). The Windows report has no
recorded build, window size, scale or screenshot. These causes explain the
reported symptoms, and each one reproduces here with the real nodes and fonts. I
cannot prove which of them the tester saw.

## Architecture and changes

All work goes through the existing seams. There is no new HUD, and the wire and
server are untouched.

- `HudRegions` (the one geometry owner) now owns the whole top band:
  - `top_band(width, hud_scale, text_scale)` gives three column widths. The
    center floor is 320 times the text scale (the body font over 24). The sides
    shrink before the center drops below that floor. The 100 percent layout
    keeps the accepted 460/720/560.
  - `column_top()` starts each column (corner, center with the Sabotage pips and
    Conquest header, frag feed with notices) below any reserved rectangle that
    crosses its span.
  - `reserved_regions()` reads a new `hud.top_region_query`. This follows the
    existing `event_region_query` pattern. The answer is untrusted: only finite
    `Rect2` values with area are kept.
  - `place_card()` keeps the shared round card between the corner and reserved
    top text above it and the context or vitals band below it. It moves the card
    the least distance that fits. If the card cannot fit, the context yields
    while the card is up, the same priority centered facts already give cards.
    The shift is undone before every recompute and whenever the card owner
    rewrites offsets, so it never accumulates.
  - `text_bounds()` is the one measure of drawn text through transforms. The
    stamp, the tests and the rendered QA all use it.
- `GameManager._top_band_reservations()` supplies the frame counter and the
  benchmark banner. `PerformanceOverlay.occupied_region()` reserves the widest
  text its mode can print from the moment it turns on. The label now grows
  inward (`GROW_DIRECTION_BEGIN`). `BenchmarkRun.occupied_region()` reports the
  banner after wrapping and is empty when the banner is idle or cleared.
  Benchmark match chrome is pushed below the banner, not hidden. That keeps the
  measured scene unchanged from earlier reports (see open questions).
- `StampCard` no longer touches the label's rotation or scale. It clears any
  stale transform when it stamps. The 106 to 100 percent settle now scales the
  ink. The worn border wraps the drawn text plus 10 units, and its faint offset
  impression sits 2 units down and right. Both are level; the tilt constant is
  gone. Reduced motion lands the ink at rest. The stamp follows its card: it retires (hidden,
  process off, redrawn empty) when its label hides, is freed or is replaced.
- `hud.gd`: every card goes through `_show_round_banner`. That retires the old
  ink, pulse, transform and tint, and centers the pulse pivot. Episode
  complete, episode fail and the warm-up fallback now use it with a held (0 s)
  lifetime. Expiry retires the ink with the card. The ink is ordered between
  the backing and the copy.

## Verification

| Command | Result |
|---|---|
| `qa_hud_layout.gd` rendered (DISPLAY=:0, Vulkan), baseline main | 180 states, **330 problems** (see table above) |
| `qa_hud_layout.gd` rendered, this branch: 1280x720, 1920x1080, 2560x1440, 2560x1080; HUD 75/100/150 percent with standard and large text; spectator, player, warm-up, benchmark, FPS off and detail, busy feed, FFA/Sabotage/tall Sabotage/fail results, ordinary card after results, expiry; standard and reduced motion | 380 states, **0 problems**, `.agents/hud-layout/after4` |
| Live capture: real `fragr-server` with 6 bots, full `main.tscn` spectating with FPS detail on, at 1280x720/100, 1920x1080/150 large, 2560x1440/100 (`.agents/live_capture.gd`) | 18 stills, no measured overlaps, result cards at rotation 0. Stills inspected. |
| `test_hud_layout.gd` (new) | PASS. A mutation check (label tilt restored, feed reservation removed) fails it with 16 errors |
| `test_signature_moments.gd` (updated: copy upright, ink settles) | PASS |
| `test_status_bar`, `test_accessibility_hud`, `test_performance_overlay`, `test_benchmark`, `test_benchmark_comparison`, `test_combat_feed`, `test_event_covers` | PASS |
| `tools/godot_check.sh` (full, after `cargo build -p fragr-server --release --locked`) | PASS: import, every script parse, every `test_*` harness PASS marker |
| Windows rendered reproduction and fixed-build check | **not run** (no Windows host) |
| Gamepad and keyboard on consecutive result cards and back/rejoin | not changed by this lane (cards take no input). Not rerun by hand. |

Stills I inspected: the baseline benchmark at 1920 and 150 percent large; after
the fix, benchmark plus FPS detail at 100 and 150 percent large; Sabotage, tall
Sabotage and FFA results at 1280 and 1920 in both motion modes; FFA at 2560 and
150 percent large; after-expiry; live result and spectator stills.

## Success criteria

- No top text overlaps or leaves the view in any measured combination: met
  locally.
- Result copy is upright with scale 1 at rest in both motion modes, with no
  tilt, scale or ink carried into later cards: met locally.
- Geometry regressions cover the combined layers, dynamic on/off, invalid
  reservations, scaled columns, the stamp lifecycle and card placement: met.
- Windows confirmation from the original reporter: **open**.

## Overlap with the death-lifecycle lane

Before this change, a `StampCard` border stayed drawn after its card hid (stale
canvas commands on a still-visible node). The baseline stills show it as a
broken coloured rectangle over later states. That is a plausible source of the
"coloured frame/box after death" report, but I have not proved it is that
report. This lane retires the ink with its card because #437 item 4 asks for
it. The death-lifecycle lane should confirm against its own matrix and avoid a
second fix in `stamp_card.gd`.

## Open questions for Nick

1. Benchmark: should match chrome (center facts, feed) be hidden during a
   benchmark rather than pushed below the banner? **Decided in wave 2 (#439):
   hidden.** The match HUD is hidden for the whole benchmark and the benchmark
   HUD replaces the banner. It clears the frame counter through the same
   reserved-region rule (`HudRegions.column_top`). The measured scene changed, so
   the result's workload id changed and older results do not compare.
2. At 150 percent HUD with large text the corner round line ellipsizes
   (`SPECTATING //...`), hiding the round state; it also happens on main, at
   every 16:9 size, because the corner is one line by the #412 rule
   (`test_match_rules` asserts `max_lines_visible == 1`). Review tried a
   two-line wrap; it read well in rendered stills but breaks that accepted
   rule, so it was reverted pending a decision. Wrap to two lines, or keep the
   one-line corner? Until decided, this is clipped top text and the first
   acceptance item is not fully met.
3. Long callsigns in the frag feed still ellipsize (`EXTREMELY LONG C...`) as
   on main. That is the feed's existing per-row rule, not a collision; the tour
   review comment on kill-feed spacing should decide whether it changes.

Resolved in review: the decorative impression tilt is removed under the "no
tilted text, anywhere" decision.

## Status and evidence

- 2026-10-23: implemented on `wave1/hud-layout`. Logs: `.agents/hud-layout/*.log`,
  `.agents/focused/*.log`, `.agents/godot-check.log` (Godot checks: PASS).
  No Rust changed, so the cargo gates were not rerun for this lane.
- 2026-10-23, independent review (second commit): removed the remaining
  impression tilt, added a HUD-wide check that every visible canvas item in
  the HUD is level after each result, episode and ordinary card in both motion
  modes (a mutation that tilts the stamp by 0.04 rad fails it six times). A
  two-line corner wrap was tried and reverted (see open question 2). Reran
  `test_hud_layout`,
  `test_signature_moments`, `test_status_bar`, `test_accessibility_hud`: PASS.
  Rendered `qa_hud_layout.gd` on DISPLAY=:0 (Vulkan, Radeon 780M): 380 states,
  0 problems (`.agents/review/qa2`); stills inspected at 1280x720 and 2560x1080
  with 150 percent large text, and FFA and tall Sabotage results.
  `tools/godot_check.sh` after `cargo build -p fragr-server --release --locked`:
  see the PR verification table. Live server capture was not rerun in review.
- Not done in this lane: tour publish (`tools/qa_tour.sh --publish`, wave end),
  the tour-still review comment, the death/respawn residue matrix (death
  lifecycle lane), and keyboard, mouse and gamepad passes over back, menu and
  rejoin with result cards (cards take no input; not rerun by hand).
- Next: wave-end tour publish and Windows confirmation from the reporter.
