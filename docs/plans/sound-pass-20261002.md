# Sound pass, 2026-10-02

**Status:** in flight, 2026-10-02.
Supersedes the open candidate work in [audio-effects-refresh.md](audio-effects-refresh.md)
and follows the [2026-10-01 Shotgun refresh](shotgun-sfx-refresh.md).

## Goal

1. A Shotgun that feels like the best close-range gun: a full-band crack, a
   weighty body and a short mechanical tail, followed by a pump-cycle cue that
   finishes inside the server cooldown. Loudness-matched against the other guns.
2. Rank every player-facing effect by how often it is heard times how weak it
   is, then improve the top of that list through existing seams.
3. Ready-to-wire Level 7 assets: Sniper Rifle fire, scope in and out, the
   Ranged Sweeper tell and shot, and the curfew chime.

## Non-goals

No gameplay, timing, protocol, damage or cooldown change. No reload action: the
pump cue is the action cycling after a shot, never a reload. No radio, music or
speech work. No faked mechanic: a cue plays only from an event the client
already receives. No new runtime dependency or scripting runtime.

## Facts checked 2026-10-02

The [sound-effects reference](https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert)
still documents `POST /v1/sound-generation`, `eleven_text_to_sound_v2` as the
only model, `duration_seconds` 0.5 to 30, `prompt_influence` 0 to 1 (default
0.3) and `loop`. `pcm_44100` and `pcm_48000` require Pro or higher; the read-only
quota check reports an active Pro tier. `tools/audiogen` already sends this
shape and accepts any `pcm_*` rate, so it needs no change. Candidates use
`pcm_48000`; the 2026-10-01 cue used `pcm_24000`, which cannot carry anything
above 12 kHz.

Scatter `cooldown_ticks()` is 12 at the 20 Hz tick (`server/src/protocol.rs`),
so the earliest next shot is 0.60 s after a blast. The pump cue must end before
then. The first-person Shotgun has one viewmodel frame and a 0.10 s kick, so
there is no pump motion yet.

## Budget

Included ElevenLabs credits only: $0 cash, no top-ups or overages. Track ceiling
25,000 credits. Every batch is dry-run first and carries `--max-credits`. The
tool retries 429 and 5xx up to four attempts, so the conservative worst case is
four times the estimate; the sum of batch estimates stays at or below 6,250.
Raw candidates stay in ignored `.agents/sound-pass-20261002/`. The live library
is never overwritten while evaluating.

Quota before: active Pro, 837,582 of 1,447,196 used (609,614 remaining).

## Evaluation method

Measurements, not listening claims. For every candidate and final cue: sample
rate, channels, duration, true peak (dBTP), maximum momentary loudness (LUFS
over 400 ms), RMS of the first 100 ms, energy above 8 kHz relative to the whole,
DC offset and clipped samples. Spectrogram images confirm attack, bandwidth and
that the pump has two separated clacks. Final cues are mono 48 kHz 16-bit PCM
for spatial playback, true peak at or below -1 dBTP. A local audition page in
ignored `.agents/audition/` lets Nick compare the old cue, finalists and the
integrated pick.

## Results

To be recorded.

## Handoff

2026-10-02 19:02Z: both batches generated (75 requests, 2,740 estimated
credits). Finals are installed under `client/assets/audio/`, the pawn and
manager seams are wired and `test_combat_audio.gd` passes. Remaining:
provenance manifest, README and plan results, full Godot check under the
lock, PR. No further generation is planned.
