# Shotgun sound refresh

**Status:** implemented, 2026-10-01. Local gates passed; CI and release pending.
The explicitly requested Shotgun fire cue is replaced after technical comparison.
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
The replaced file was a stereo 24 kHz PCM WAV with a 0.8-second duration; its
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

Three variants were generated and the heavy-snap candidate replaced the live
cue on 2026-10-01. The previous file and all raw candidates remain in ignored
comparison storage. The selected unmodified source is committed at
`client/assets/audio/shotgun/fire_source.wav`. The existing fire sound path,
Effects bus, -4 dB player gain and 50-metre attenuation bound did not change.
No gameplay source or new test harness was added.

| File | Duration / channels | Peak dBFS | RMS dBFS | First 10 ms RMS dBFS | Strongest 10 ms starts |
|---|---|---:|---:|---:|---:|
| Previous live cue | 0.80 s / 2 | 0.0003 | -15.14 | -36.22 | 70 ms |
| Crack/body raw | 0.84 s / 2 | 0.0003 | -10.70 | -2.73 | 60 ms |
| Heavy snap raw | 0.84 s / 2 | 0.0003 | -15.23 | -3.29 | 10 ms |
| Gritty punch raw | 0.84 s / 2 | 0.0003 | -18.72 | -7.12 | 20 ms |
| Prepared live heavy snap | 0.46 s / 1 | -1.945 | -19.572 | See retained window measurements | Immediate attack retained |

Raw sources all reach full scale. The crack/body candidate has a dense loud
plateau and the longest low-level tail; gritty punch loses its main body by
about 130 ms. Heavy snap supplies an immediate attack and a compact body,
with the last 10 ms window above -40 dBFS beginning at 360 ms. These are
measurement-based selection reasons, not a claim of subjective listening.
The prepared cue has zero full-scale samples and DC offset -0.000025.

Preparation uses float arithmetic before the mono mix and 25 Hz high-pass,
retains the first 0.46 seconds and fades the final 30 ms. A float intermediate
prevents the high-pass overshoot from clipping before the final fixed -6 dB
gain. The final PCM conversion disables encoder metadata. Exact filters,
source/output hashes and request details are in `shotgun/refresh-manifest.json`.
An initial prepared candidate reached full scale after the high-pass; it was
rejected and regenerated from the preserved raw file through the float path.

```powershell
ffmpeg -i client/assets/audio/shotgun/fire_source.wav -af 'aformat=sample_fmts=dbl,pan=mono|c0=0.5*c0+0.5*c1,highpass=f=25,atrim=duration=0.46,afade=t=out:st=0.43:d=0.03' -ar 24000 -c:a pcm_f32le keeper_float.wav
ffmpeg -i keeper_float.wav -af 'volume=-6dB' -ar 24000 -c:a pcm_s16le -fflags +bitexact -flags:a +bitexact -map_metadata -1 fire_scatter.wav
```

The first API request exceeded its 450-character text limit and returned 400,
with no file and unchanged quota. All prompts were shortened before submission.
The final dry run estimated 102 credits, with an explicit 500-credit gate and
a conservative four-attempt estimate of 408. Successful generation showed no
retry. Quota briefly lagged, then changed from 697,587 to 697,617: 30 included
credits for three jobs, 749,579 remaining and $0 new cash. The ongoing round's
recorded included audio usage becomes 975 credits; unrelated earlier account
usage remains separate. The $1 equivalent reservation is retained in the shared
ledger alongside the earlier audio and image records.

Pinned Godot import passes with a clean log. An isolated ignored check loads
the actual player scene, confirms `fire_streams["Scatter"]` resolves the new
mono 24 kHz nonlooping 0.46-second sample, calls its existing muzzle-feedback
path, verifies the existing Effects player and waits for the real finished
signal. It exits 0 with `shotgun_check: PASS` and no script/runtime errors.
Receipts are under `.agents/m06-buildout-20261001/shotgun-*` and
`.agents/shotgun-sfx-20261001/`.

The final pinned client checker passes all 184 scripts and 86 harnesses with
clean exit 0 in `.agents/m06-buildout-20261001/client-whole-contact-final.log`.
The matching M06 tour passes 25 states with clean engine shutdown, and the
standard `--publish` tour in `.agents/qa/m06-standard-contact-final/` passes
32 states and publishes 13 inspected stills. Actual Shotgun muzzle/impact
samples remain visible in the standard strip without sky-fragment regression.
These complete the local integration gates; CI and release remain pending.
Subjective listening, repeated live spatial mix comparison and final mix
acceptance remain unverified; decoded playback alone does not settle them.
