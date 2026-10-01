# Shotgun sound refresh

**Status:** in flight, 2026-10-01. Replacement requested explicitly. This bounded
asset pass replaces the existing Shotgun fire cue after technical comparison.
The [roadmap](../ROADMAP.md#full-build-order-2026-09-27) owns build sequencing.

## Goal and scope

Give the existing Shotgun one short, physical discharge: a sharp attack, weight
in the low and middle frequencies and a restrained mechanical tail. Keep the
chunky weapon identity in the [art bible](../ART_STORY_BIBLE.md). This is a single
blast, without music, speech, a long echo, cartoon effects or reload mechanics.
No combat, ammo, timing, network, dependency or runtime service change belongs
to this pass.

`player_pawn.gd` loads `res://assets/audio/fire_scatter.wav` through the existing
per-weapon sound table and spatial Effects player. Preserve this path, attenuation
and bus. Keep the previous file in ignored comparison storage until evaluation.
The existing file is a stereo 24 kHz PCM WAV with a 0.8-second duration; its
historical prompt asks for a pump rack. No reload action exists.

## Production and budget

Use the existing developer-only `fragr-audiogen` binary and credential lookup.
Three original variants request 0.85 seconds each, `pcm_24000`, fixed prompt
influence and no looping. The separate spec writes to ignored staging storage,
so generation cannot replace the live library or touch story manifests.

Fresh read-only quota is active Pro, 697,587 used of 1,447,196, with 749,609
included credits remaining. The increase of 2,727 since the earlier M06 batch
predates this pass and is not attributed to these jobs. Exact dry-run estimate,
before/after receipts and job counts belong to this batch's record. Set
`--max-credits 500`; account for the existing maximum four request attempts.
Reserve a separate conservative $1 equivalent within the ongoing round, alongside
its existing audio reserve and bounded image work. Use included credits only,
$0 new cash, no top-ups or overages. The ongoing $20 cash and repository $50
caps do not reset on this date. Coordinate shared ledger writes with integration.

API parameters and current published comparison pricing were checked against
the [official sound-effect reference](https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert)
and [API pricing](https://elevenlabs.io/pricing/api) on 2026-10-01. A published
pay-as-you-go comparison does not establish a cash charge against this subscription.

## Evaluation, integration and evidence

Compare decoded format, actual duration, peak/RMS/DC levels, clipped samples,
leading silence, attack timing and decay against the preserved old cue. Retain
raw candidates and all transforms. Select a strong immediate attack with useful
body and a bounded tail; prepare a mono spatial PCM fallback with conservative
headroom if the raw source needs gain or timing correction. Record exact filters,
source/output hashes, measured levels and the selected prompt/model/format in
asset provenance. Do not claim subjective listening from PCM measurements.

Then use the existing Godot cue/load checks and the final client checker owned
by presentation. Coordinate import and headless checks after its active rendered
tour, with no competing native child or renderer process. Confirm the resource
decodes, has nonzero duration, remains nonlooping and resolves through the actual
Shotgun cue. Inspect rendered combat with the same existing sound route; listening
and final mix acceptance remain distinct evidence if unavailable in this session.
No broad new harness is needed for a reversible asset replacement.

## Results

Generation, comparison and client integration receipts are pending under
`.agents/m06-buildout-20261001/shotgun-*` and `.agents/shotgun-sfx-20261001/`.
