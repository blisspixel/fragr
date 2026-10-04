# Civilian surface markings

Recorded 2026-10-03. **Status:** implemented, with
[local evidence](../evidence/civilian-surface-markings-20261003.md).
[PR #347](https://github.com/blisspixel/fragr/pull/347) owns final combined
integration and CI. **Spend:** $0.

## Goal

Low Water rooms and lunar dwellings retain their own maintenance history rather
than inheriting Union warning stripes. Preserve black/red outfits and explicitly
issued equipment. Use existing inspected local textures only.

## Scope and seams

`ArenaMaterials.authored` supplies quiet nonemissive Low Water enamel markings.
`EnvironmentTextures.path_for` separates the lunar town's pressure-bone enamel
and worn walking deck from the existing port/archive material selections. The
town's explicit service-steel equipment retains its dark issued wall finish and
red markings. `ArenaCover` assigns a separate town ground material supplied by
`ArenaMaterials`, so the common street deck has muted markings while issued
walls keep their original material instance. Pressure-bone wall albedo has a
restrained blend at playing distance. No shared shader, geometry, lighting, gameplay or timing changes.
No protocol change or new dependency.

## Verification

Extend the existing environment-material harness with exact civilian/institutional
boundaries, real texture loading and glass/fallback checks. Run complete client
checks against the combined accepted M04, M06 and M07 tree with an isolated matching
native server. Inspect player-height clinic/workshop and town/window views,
recording ordinary input versus detached inspection precisely. Preserve earlier
playthrough evidence; these art subsets do not establish a new complete run.

## Success criteria and remaining gates

Civilian enamel and the lunar town ground no longer emit inherited red warning bands. Lunar dwelling
enamel uses pressure-bone and town decks use worn metal. Port/archive and other
venues, issued steel, actors and map bytes remain unchanged. Focused and full
client checks pass with clean logs. Actual before/after frames support the visual
claim. Parent owns integration CI, public indexes, main and publication.

The preliminary M07 ten-state capture and initial checker log are retained as
intermediate evidence. Final acceptance repeats the town art subset and complete
client checks from the stable final ground/material source.
