# Campaign transition audio

**Status:** implemented, 2026-09-30. Named-character casting and hardware listening remain open.

## Goal and scope

Give the existing M03 departure, M04 arrival and M04 departure scenes six brief
English narration clips using their exact current caption text. Add a quiet
Low Water drainage ambience for the arrival scene. These are original story
scenes, not a new campaign controller. Reuse ScenePlayer's Voice/Effects buses,
locale fallback, captions, skip, replay and missing-asset behavior. No music,
voice cloning, character redesign, new scene prose or paid runtime integration.

## Lore and casting

Read the [art and story bible](../ART_STORY_BIBLE.md), [voice registers](../lore/voice.md)
and accepted [M04 brief](../campaign/l04-notice-to-vacate.md). A neutral narrator
reads framing; the Host does not become the campaign dispatcher. Do not claim
this is Latch, Mara or Edda's established voice. The selected stock voice is
River (`SAz9YHcvj6GT2YYXdXww`), returned by the actual account voice-list endpoint
on 2026-09-30. No real-person imitation or cloned reference is used.

## Budget and request contract

Nick explicitly authorized existing ElevenLabs credits on 2026-09-30, within
the combined $20 development ceiling and repository $50 total ceiling. Initial
account quota: active Pro, 693915 used of 1447196, 753281 remaining. Logs:
`.agents/m04-buildout-20260930/audio-quota-before.log`, `audio-voices.log`.
Reserve at most $2 of the combined round allowance for this lane; no top-ups,
overages, subscription changes or repeated uncertain generation requests.

Use `tools/audiogen` with `--max-credits 2000` for the exact dry-run-priced batch.
Existing `eleven_v3` requests use one credit per character; the six-second
duration-specified effect estimates 240 credits. Even four attempts for each
request under the existing bounded HTTP retry policy fit 8000 credits, far below
the verified remaining balance. Stop and reconcile if any request is uncertain.
The actual quota delta, rather than an estimate, records usage after submission.
The [current API price](https://elevenlabs.io/pricing/api), checked 2026-09-30,
lists v3 at $0.08 per 1000 characters and effects at $0.12 per minute. This
round draws from already included credits, with no new cash charge. Record the
conservative credit-equivalent reserve separately from actual cash charges.
Existing v3 remains an intentional compatible model choice for this bounded
batch; a new voice-model migration is outside this change.

The [paid-account terms](https://elevenlabs.io/terms-of-use) permit commercial
output use and retain the user's output rights subject to their terms. Keep
request/model/voice/format manifests with the assets. This batch contains no
music and claims no music-library distribution rights.

## Verification and acceptance

Dry-run the exact spec before submission. Preserve before/after quota receipts,
request manifests and source text. Import every MP3/WAV in the pinned client,
verify positive duration and decoded nonzero energy, exact caption/spec pairing,
Voice bus playback, ambience bus/level, locale fallback, missing-asset fallback,
skip stopping playback and no network callback during replay. Run focused scene
harnesses and the full client checker. Capture the actual narrated story scene
with its caption controls. Mechanical loading/playback evidence does not replace
hardware listening review; record that limit explicitly.

## Implementation and focused evidence

The exact six clips and six-second runoff bed are committed with their request
manifest. The three scene manifests use `{locale}` narration paths, existing
English fallback, narration timing and a one-second hold. The final page still
waits for the reader. Only M04 arrival uses the runoff, on Effects at -22 dB.
Its explicit import preserves stereo 24 kHz 16-bit PCM and loops the full asset.
No source caption, speaker label, campaign packet or readiness callback changed.

Actual completion exposed a presentation defect: with captions disabled, the
last voiced page stayed hidden after speech ended. ScenePlayer now clears its
speaking state and refreshes text on the existing `finished` signal, before
applying the existing hold or final-page reader wait. The focused regression
seeks near the actual end of each final narration and waits for its real signal.
It failed for all three scenes before this correction; that failure remains in
`test_campaign_audio-end-regression.log`. Missing voice and ambience still give
readable text without an invented automatic completion. Skip stops both buses
and emits completion once. Automated scene trees do not capture the pointer.

Pinned import and explicit loop reimport passed cleanly, exit 0, in
`.agents/campaign-transition-audio-20260930/import-first.log` and
`import-loop-final.log`. After the completion correction, focused checks passed
with their own PASS markers and exit 0: `test_campaign_audio-completion-fixed.log`,
`test_scene_player-completion-fixed.log` and `test_story_scene-final.log` in the
same directory. The scene-player check retains its deliberate invalid-manifest
warning; none of these final checks logged a script or runtime error.

The new harness verifies exact translated captions against the seven-item spec
and manifest, actual nonzero decoded sample windows, durations, asset bytes,
Voice/Effects routing, caption controls, playback position advancing, locale
fallback, hold timing, final-reader behavior and missing-asset fallback. These
headless sample measurements are three decoded windows per asset, not full-file
averages or a listening review:

| Clip | Duration, seconds | Sample-window RMS | Sample-window peak |
| --- | ---: | ---: | ---: |
| M03 departure train | 9.600 | 0.08935 | 0.36283 |
| M03 departure home | 4.960 | 0.08861 | 0.39108 |
| M04 arrival home | 12.080 | 0.04902 | 0.20305 |
| M04 arrival market | 11.920 | 0.12534 | 0.48337 |
| M04 departure stairs | 8.400 | 0.08256 | 0.39473 |
| M04 departure roofs | 7.840 | 0.12094 | 0.79298 |
| Runoff ambience | 6.000 | 0.00789 | 0.08352 |

An isolated Compatibility render on AMD Radeon 780M passed cleanly, exit 0,
`story-rendered-final.log`, with actual Voice and Effects players advancing.
Inspected `arrival-voice-captions.png` shows the actual M04 arrival caption,
page indicator and Back, Skip Scene, Captions and Next controls at 1600 by 900,
without clipping or a named-character speaker label. This proves playback and
visible controls on that renderer. It does not prove voice direction, mix quality,
hardware performance, an ordinary campaign arrival handoff or fresh-player
acceptance. The final integrated client checker passed all 163 scripts and 76
harnesses, including the actual audio completion regression, in
`.agents/m04-buildout-20260930/godot-verified.log`. The ordinary M04 gameplay tour
skips story playback; it is not an additional listening or scene-handoff claim.

The reconciled account quota change is 475 included credits, from 693915
to 694390, with 752806 remaining. The final read matched the prior reconciled
read; receipts are `audio-quota-before.log`, `audio-quota-reconciled.log` and
`audio-quota-final.log` under `.agents/m04-buildout-20260930/`.
The dry-run estimate was 1070 credits under the explicit 2000-credit run cap;
estimates and observed usage are distinct. No new cash charge, top-up or
additional generation request was made. Keep the commercial-use terms and original request
manifest with the assets; no additional authorship credit is introduced.

Pinned APIs checked against official 4.7 documentation on 2026-09-30:
[AudioStreamPlayback](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayback.html),
[AudioStreamMP3](https://docs.godotengine.org/en/4.7/classes/class_audiostreammp3.html)
and [AudioStreamWAV](https://docs.godotengine.org/en/4.7/classes/class_audiostreamwav.html).
