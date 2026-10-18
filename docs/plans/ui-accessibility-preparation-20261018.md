# Accessibility preparation and next-session handoff

Status: **planned**, [#414](https://github.com/blisspixel/fragr/issues/414)
within [#418](https://github.com/blisspixel/fragr/issues/418). No feature
implementation has started. Base: reviewed green main `63185e3`, PR #423,
published v0.89.0 with three verified desktop packages. The
[Full build order](../ROADMAP.md#full-build-order) owns sequencing.

## Goal and boundaries

Complete the existing Accessibility tab with Screen flashes (Full, Reduced,
Off; default Reduced), HUD scale (75-150%), Text size (Standard, Large) and
Team colours (Standard, High contrast). Reduced motion already shipped in
#412 and must remain independent. Do not expose controls before their effects
work. Issue #414 remains open until all its acceptance criteria have evidence.
No wire, combat, movement, save, renderer-pin or dependency changes are planned.
Use retained assets and native UI geometry at $0, with no generation credits.

Preserve FragrSettings' validated store, draft, save/cancel and failed-write
behavior, and the shared boot/match SettingsPanel. Old files receive defaults;
invalid enums and nonfinite scale values fail safely. Live changes preserve
accepted identities, notice payloads, full admitted lifetimes, Host receipts,
scoreboard scroll and dismissal input ownership.

## Screen effects and committed incoming damage

Use one composited edge presenter and one shared rolling budget of at most
three admissions per second across damage, spawn, NODS, episode success/failure,
warmup and podium. Reduced opacity stays at or below 0.25. Event impulses use
an exact two-physical-pixel perimeter, independent of HUD scale. Off clears
immediately; rejected impulses do not restart, extend or queue an effect.
Keep the tiny admission history across preference changes, map/round retirement
and replacement HUDs. Remove legacy independent overlays/timers. Failure uses
danger red, with no magenta. Preserve independent directional marks, optics,
muzzle/world effects, actual fire cadence and server damage.

Coalesce HP-loss and positive Hit receipts by accepted local UUID and snapshot
tick before rate admission, including while Off. Snapshot precedes Event on
the server socket. Preserve armor-only damage and environmental HP loss without
inventing a bearing. Name-only Respawn events cannot establish personal
ownership. Actual accepted body entry/resurrection owns spawn presentation.

Capture the eligible first-person listener before the snapshot can remove its
body. Consume final resolved shot traces with that captured context; allow the
terminal marker's existing decay through later non-first-person snapshots,
without starting pass-by audio. Explicit role/map/retry/connection changes
still reset it. This repairs the observed final-hit teardown defect rather
than weakening spectator or loading ownership checks.

## Scaling and text

Use an immutable shared style and explicit owner reflow, not CanvasLayer
scaling, mutation of cached Themes or blind recursive font multiplication.
Large HUD body text uses 32 base units instead of 24, then HUD scale once;
display type scales its own authored size once. Menu Large text needs explicit
body roles and wrapping/scrolling, without gameplay HUD scale. Reticle,
viewmodel, incoming bearings and physical screen edges retain their own sizes.

HudRegions remains the placement owner. Actual measured bounds must cover
Conquest's five sites, tickets and majority hint, all other mode facts, vitals,
finite ammo/explosives, vehicle guidance, campaign prompts/recovery, results,
departure review and the full standings. At the largest style, use measured
side lanes and compact arrangements. Cosmetic map/radio content yields before
essential facts. Preserve CombatFeed's stored entries and presentation clocks
when allocating visible height; its destructive set_limit is not a reflow API.
Measure after width and text shaping settle, with bounded owner callbacks.

## Team marks and world plates

Keep bone small lettering on the dark Union plate and the Free plate with its
existing amber edge. Distinguish absolute teams with a solid danger-red Union
mark and an open bone Free mark, both in opaque ink gutters. Relative
OURS/THEIRS and the self-row backing remain separate meanings. Unknown teams
receive no invented mark; bodies, optics, flags and world faction colors retain
their existing owners.

For Label3D backings, retain the established label path and a depth-tested
transparent sibling Sprite3D, with matching transform, billboard, pixel_size
and far scale. Bake the gutter/mark into a bounded cached texture. Obtain the
settled text plane from generate_triangle_mesh, not the billboard cube returned
by get_aabb; add outline padding. Positive Sprite3D offset Y is preserved,
while image Y is inverted separately. Prepare text/backing geometry before
frame_pre_draw, then project the complete padded union using camera axes and
inherited global scale. Preserve overlap selection, flag reservations, local
first-person hiding and opaque-world occlusion. Headless geometry checks need
a directly callable seam because headless emits no frame_pre_draw.

## Retained preparation evidence

Private receipts are under `.agents/ui-event-tiers-20261018/` and
`.agents/ui-palette-20261017/`. They are diagnostic preparation, not shipped
accessibility features or human acceptance:

- A bounded native Repeater capture uses ordinary finite pickups and Action
  inputs, zero bots and seed 42. It contains 15 ordered trace/Hit pairs every
  two ticks, seven armor-only contacts, a lethal omitted body and an actual
  60-to-45 shooter round pool. It ends at tick 114 and proves no respawn.
  Native build: `c5546fe57d6b1971d2ab33295d4ac14414718cd4`, source-tree identical
  to merged `63185e3`. The actual GameManager baseline counts 14 bearings, then
  clears them on lethal tick 90. Promote the exact receipt and provenance into
  deterministic QA before implementing the fix. A separate exploratory
  NetClient-dispatch harness has an unresolved ownership/setup difference and
  is not an accepted baseline.
- Actual X11 Compatibility/llvmpipe windows at 720p, 1080p and 1440p prove a
  two-pixel NinePatchRect perimeter with zero interior alpha and maximum 0.2392
  opacity. This is an API experiment, not an integrated flash or HiDPI proof.
- Actual maximum-font Conquest, Unicode feed and jeep-guidance measurements
  identify layout pressure. Their manually assigned prototype omits complete
  mode headers, vitals and equipment and does not prove whole-HUD fit.
- Flat swatches under Machado 2009 full-severity simulation, linear sRGB
  clipping and Lab/D65 CIE76 give red/bone mark separation of 54.53 protan and
  55.53 deutan. This exceeds the acceptance floor 25; the proposal's claim of
  at least 55 in both cases is slightly high. Both bone lettering colors have
  separation zero. Bone on dark Union red has 7.14:1 contrast. Red marks on ink
  have 4.49:1 normal and 3.14:1 protan contrast. These are swatch calculations,
  not measured rendered readability or accessibility certification.
- Independent read-only reviews cover plate palette, shape size, coordinate
  conversion, deferred geometry and pre-draw ordering. Four-unit open marks
  are too narrow; verify a visible stroke and hole at the smallest presentation.

## Verification and acceptance

Replay the native Repeater receipt through actual Snapshot/Event ownership,
checking all 15 bearings, the lethal marker's lifetime, at most three Reduced
flash admissions per rolling second and zero Off flashes. Include synthetic
otherwise-admissible final damage, duplicate/multiattacker receipts, campaign
zero HP, environment damage, invalid damage, same-name Respawn, wrong UUID,
loading/spectator ownership, rapid mode toggles and replacement HUDs.

Verify persistence and both menus, keyboard/gamepad focus, cancel and failed
writes. Exercise 75/100/150% with Standard/Large text at 720p, 1080p and 1440p,
all five modes, full 64-player standings, Unicode, campaign recovery/results,
explosive stock and nearby/occupied vehicles. Accept live packets while
changing preferences and prove no notice loss, stale geometry or repeated Host
duck. Inspect actual rendered plate/feed/board crops in normal, grayscale,
protan and deutan views, including far/oblique plates, wall occlusion and local
first-person hiding. Verify actual rendered mark separation and open centers.

Run focused and full bounded client checks, retain checker failure detection,
publish and inspect the QA tour and transient sequences, then review the final
diff independently. Green PR/main CI and matching verified desktop packages
precede publication. Keep scripted, rendered, hardware and human gates distinct.

Primary references checked 2026-10-18: [NinePatchRect](https://docs.godotengine.org/en/stable/classes/class_ninepatchrect.html),
[Viewport stretch](https://docs.godotengine.org/en/stable/classes/class_viewport.html),
[pinned Label3D source](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/3d/label_3d.cpp),
[pinned Sprite3D source](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/3d/sprite_3d.cpp),
[Machado et al.](https://pubmed.ncbi.nlm.nih.gov/19834201/), and
[the W3C three-flashes guide](https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold.html).
Game-specific effect tests do not establish general web-guideline conformance.
