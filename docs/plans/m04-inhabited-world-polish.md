# Low Water inhabited world polish

Status: implemented, 2026-10-03; full CI and main integration pending. This bounded presentation pass follows the
[level 4 brief](../campaign/l04-notice-to-vacate.md),
[Earth direction](../design/earth.md) and [art bible](../ART_STORY_BIBLE.md).

The current market has useful cover and readable signs, but its furniture and
habitation court carry little evidence of ordinary life. Give the existing
repair bench an identifiable shared charging and repair activity, the clinic
maintained care equipment, and the shared table interrupted meal settings.
Dress the court's existing walls with sealed domestic windows and curtains.
Preserve the district's muted terracotta, sage and warm afternoon palette.

All detail belongs to the M04 presenter. Shaped ceramic vessels, cable loops,
worked metal and cloth use the existing model geometry and selected finish
textures. Merge the resulting mesh by finish; do not leave hundreds of small
draw calls. Substantial cover, tanks, furniture, clinic worlds, encounters,
patient feet, routes, pickups and departure remain server owned. Cosmetic
possessions stay on existing furniture; sealed wall motifs project no more
than 8 mm and do not imply new openings or interactions.

Acceptance requires focused map/reconfiguration and boundary checks, a clean
ordinary-input full M04 route, and inspected market, clinic and court captures.
Headless success is not rendered appearance evidence. Full CI, main integration,
fresh-player pacing and finished art acceptance remain separate gates. No paid
service is used by this pass.

## Local implementation

The M04 source and town hook are implemented, with eight merged finish surfaces,
specific shared charging/care/meal arrangements, two maintained beds and nine
sealed domestic windows. Actual-map vertex bounds, the material budget,
custom-map restraint and the existing patient/contact/teardown harness pass.
Import and touched-script parsing are clean. The derived art tour reads the
ordinary M04 route rather than maintaining a second copy.

[Rendered evidence](../evidence/m04-inhabited-world-20261003.md) records the
completed 26-state ordinary-input route and four inspected frames. The initial
run failed its log gate on the known Compatibility sky texture-retirement
signature. Standalone rendering and retirement of the exact possession source
exited cleanly; the full repeated tour also exited cleanly with no errors,
all 28 named defenders, released patients and actual departure. No source
change or weaker assertion was needed. Full CI and main integration remain
pending. The same captures identify missing clinic and
workshop ceilings and thin court frontage for a separate authoritative
architecture increment.
