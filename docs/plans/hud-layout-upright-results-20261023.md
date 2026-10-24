# HUD top-band collisions and upright result cards (#437)

Status: **implemented** on branch `wave1/hud-layout` (local evidence below; not
yet merged). Wave 1 of the October 23 Windows playtest round.

## Goal

The October 23 Windows playtest reported two things: text overlapping at the top
of the HUD, and post-match text that is visibly angled. This plan covers both.

1. The top HUD band keeps its text apart: corner match facts, centered match
   facts, frag feed and notices, the frame counter (`show_fps` 1 and 2) and the
   benchmark status banner. This holds at every supported HUD scale and text
   size, and nothing is shrunk to fit.
2. Essential result copy (winner, score, reason, next line) stays upright on one
   baseline in standard and reduced motion. The stamp motif may keep a tilt only
   on decorative ink. No tilt, scale or stamp border carries over into a later
   card.

## Non-goals

- The post-death coloured box and lifecycle issue in the #437 comment. The
  death-lifecycle lane owns it. See "Overlap with the death-lifecycle lane"
  below for one shared finding.
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
  ink. The upright worn border wraps the drawn text plus 10 units. Only the faint
  offset impression is tilted, at most 2.5 degrees, and less on wide cards, so
  its corner moves at most 6 units and never crosses the text. Reduced motion
  lands the ink at rest. The stamp follows its card: it retires (hidden,
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
   benchmark rather than pushed below the banner? Hiding changes the measured
   scene relative to earlier reports, so this lane kept it visible.
2. At 150 percent HUD with large text the corner state line ellipsizes
   ("SPECTATING //..."), so the center keeps a readable width. Is that the
   preferred trade-off, or should the corner wrap to two lines?
3. The stamp impression tilt is now decorative and small (about 0.6 degrees on
   a full-width card). Keep it, or retire the tilt entirely?

## Status and evidence

- 2026-10-23: implemented on `wave1/hud-layout`. Logs: `.agents/hud-layout/*.log`,
  `.agents/focused/*.log`, `.agents/godot-check.log` (Godot checks: PASS).
  No Rust changed, so the cargo gates were not rerun for this lane.
- Next: wave-end tour publish and Windows confirmation from the reporter.
