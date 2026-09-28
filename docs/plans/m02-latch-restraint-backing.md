# M02 Latch restraint backing

**Status:** superseded, 2026-09-28. Rejected after a rendered study on the natural entry draft at `e9d3a5f`. External spend: $0.

## Goal and reason

The unforced primary gallery view now frames Latch's first restraint, but their pale figure is small against pale ward walls and equipment. Give that first restraint a restrained dark-steel backing so the existing Latch silhouette separates from its immediate background. The second restraint already has a backing. The first one should read as imposed Union equipment, not as part of Latch's natural chassis.

## Scope and boundaries

- Add only presentation geometry under the existing first-restraint node in `client/scripts/m02_ward.gd`. The Latch renderer, map solids, server mission state, combat and wire stay as they are.
- Use the current institutional materials and world visual layer. No glow, objective marker, new runtime dependency, generated asset, paid call or cloud action.
- Keep the backing behind Latch from the primary gallery and ward approach. Inspect oblique and close views so it does not hide Latch or look like an impassable shortcut.
- Keep the existing release, retry, skip and fixed-to-moving companion handoff intact. A fixed restraint can remain after Latch departs.

## Evidence and acceptance

The proposed check was a focused `test_m02_ward.gd` assertion for placement, bounded size, material and world layer. The evidence route was the same `client/qa/m02-natural-entry.json` no-look arrival, with color and grayscale inspection at 1280 by 720, plus the existing live Latch motion route.

The candidate was only worth keeping if the unforced entry gained clear separation without making the nearby restraint or release worse. That bar was not met. This study does not establish fresh-player recognition, fun or completed M02 art. The human perceptual gate remains open.

## Rendered study and decision

Three placements were tested locally on Godot 4.7.2-stable, OpenGL Compatibility and an AMD Radeon 780M. The first sat inside the authoritative `restraint_frame` solid at x=8 to 9 and was hidden. A thin inset moved ahead of that solid and behind Latch, then shifted to align more closely with the gallery view. Both visible candidates affected only a small dark patch beside the distant figure. The final unforced image differed from the same-head baseline in about 500 of 921,600 pixels, concentrated in a roughly 27-pixel-high band near the lower window edge. At native size, neither the color nor grayscale frame made Latch clearly distinct from the machinery.

The exact-map no-look entry QA passed on the last candidate. The 20-state live Latch route also passed, including real ward victory, Use at the restraint, second-bay release and 10.34 m of server-owned companion travel. Its close restraint capture made the inset look like a broad black void behind Latch, reducing room cohesion. The long ward and release views offered no clear gain. Local comparison frames and logs are under ignored `.agents/qa/m02-backing-entry-candidate3/` and `.agents/qa/m02-backing-motion-candidate/`. The focused ward test passed after a float tolerance correction. The candidate client and test edits were then reverted. The full Godot checker and standard tour were not run on a rejected, reverted visual change.

No backing is proposed for integration. The next readability decision should start from the measured sightline and actual Latch projection in the unforced frame, then test a visual concept before treating it as a build rung. Any new candidate must preserve the map's collision and the close release composition.
