# Sound pass, 2026-10-02

**Status:** implemented, 2026-10-02; listening and in-game mix acceptance remain open.
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

Two batches ran: `sound-pass-20261002-shotgun.json` (23 requests, 652
estimated credits, `--max-credits 700`) and `sound-pass-20261002-effects.json`
(52 requests, 2,088 estimated, `--max-credits 2200`). Both logs show no retry
and every request wrote a file. Five reviewed 2026-09-19 pilot candidates
(Fists swing, ammunition, health and armor pickups, dry trigger) were reused at
no cost. Selection used the measurements above plus spectrograms for single
versus repeated transients, click spacing, bandwidth and silent or tonal
failures; four requests came back near silent and were rejected.

### Shotgun

The blast mixes five layers: the shot from a shot-and-pump generation (crack
and presence), a round low thump, the decay of a dense full shot, a separate
crack and a quiet steel ring at 0.26 s. A tanh soft clip adds density, then one
gain sets -1.05 dBTP. The pump is cut from the same shot-and-pump generation:
two clacks 125 ms apart, starting 0.22 s after the blast and ending at 0.56 s,
inside the 0.60 s cooldown. The first-person Shotgun has one frame and a
0.10 s kick, so it shows no pump motion yet.

| Cue | Rate | Length | True peak | K50 | Momentary max | First 100 ms RMS | Above 8 kHz |
|---|---|---:|---:|---:|---:|---:|---:|
| Old blast (2026-10-01) | 24 kHz mono | 0.46 s | -1.9 dBTP | -10.6 | -19.2 LUFS | -13.2 dBFS | -18.4 dB, none above 12 kHz |
| New blast | 48 kHz mono | 0.55 s | -1.1 dBTP | -7.3 | -14.7 LUFS | -9.3 dBFS | -16.4 dB, content to 24 kHz |
| New pump | 48 kHz mono | 0.34 s | -7.1 dBTP | -15.0 | -21.2 LUFS | -17.6 dBFS | -15.5 dB |

In the first 150 ms, against the old cue at a similar peak, the new blast has
about 8 dB more below 100 Hz, 6 dB more at 1.5 to 6 kHz and 6 dB more above
8 kHz; 100 Hz to 1.5 kHz is only about 1 dB higher. K50 is the loudest 50 ms of the mono sum after a 38 Hz high-pass and a
+4 dB shelf at 1681 Hz.

### Gun ladder

Every gun plays through the same -4 dB spatial player, so file level is the mix.

| Gun | Before K50 | After K50 | True peak after | Change |
|---|---:|---:|---:|---|
| Shotgun | -10.6 | -7.3 | -1.1 dBTP | rebuilt |
| Sniper Rifle (Level 7) | | -9.0 | -1.3 dBTP | new |
| Railgun | -1.6, +1.2 dBTP | -10.6 | -7.8 dBTP | -9.0 dB |
| Pistol | -23.6 (shared fallback) | -12.0 | -2.0 dBTP | new `fire_tack.wav` |
| Rifle | -11.6 | -12.8 | -1.2 dBTP | -1.2 dB |

### Ranked audit

Frequency of hearing times weakness, highest first. Built rows use existing
authoritative facts only.

| Effect | Before | Now |
|---|---|---|
| Shotgun blast and pump | thin, band-limited, 9 dB under the Railgun | layered blast, pump inside cooldown |
| Pistol fire (also every Clerk shot) | shared fallback at -34.7 LUFS | own cue, -12.0 K50 |
| Gun loudness | Railgun clipping and 16 LU over the Shotgun | ladder above |
| Gun impacts | per-weapon files loaded but never played; Rifle impact near silent | resolved-shot weapon, once per struck body |
| Union windup tells | silent except the Notary fan pitch | Clerk, Sweeper, Heavy Sweeper, Turret on `windup`, cut when it ends; Turret charge follows the actual windup |
| Deaths | silent in the campaign | body or machine fall on the drop to zero health |
| Melee swings | silent | Fists and Shiv, never a Crawler leap |
| Pickups | silent | weapon, ammunition, Cells, health, armor for the watched fighter |
| Dry trigger | visual only | owner cue on a growing `dry_fire_count` |
| Grenade throw | silent | cue when a body first appears after sync |
| Footsteps, landing, jump | silent | open: needs surface lookup and better candidates (the three sequence requests returned one or two steps) |
| Player pain voice | generic hit only | open by choice: no voice work this pass |
| Lifts, tram, gates, objectives, menu | silent except M02 ward | open |

### Level 7 assets (not wired)

| File | Use | Source |
|---|---|---|
| `client/assets/audio/fire_sniper.wav` | Sniper Rifle fire, dry supersonic crack | `l07/sniper_fire_a` |
| `client/assets/audio/sniper/scope_in.wav` | Scope in | `l07/scope_in_a` |
| `client/assets/audio/sniper/scope_out.wav` | Scope out | `l07/scope_out_c` |
| `client/assets/audio/ranged_sweeper/tell.wav` | Glint, then a held targeting tone, 1.18 s | `l07/ranged_tell_d` and `l07/ranged_tell_b` |
| `client/assets/audio/ranged_sweeper/fire.wav` | Ranged Sweeper shot | `l07/ranged_shot_b` |
| `client/assets/audio/l07/curfew_chime.wav` | Four descending tones, 2.9 s | `l07/curfew_chime_b` |

Wiring: `player_pawn.gd` already loads `<kind>/tell.wav` for every
`ActorState.KINDS` entry and stretches `ranged_sweeper` like the Turret, so
adding the kind plays the tell on its windup and cuts it when the windup ends.
A Sniper weapon named `Sniper` picks up `fire_sniper.wav` once it is added to
the pawn's weapon list. The Ranged Sweeper shot needs one line choosing
`ranged_sweeper/fire.wav` for that kind.

### Verification

`test_combat_audio.gd` covers cue formats and lengths, the pump timing against
12 ticks, cancellation on weapon switch or death, melee routing, per-weapon
impacts, tells with repeat and cancel, falls, pickups through the real event
handler and dry-trigger counting. `test_grenade_effects.gd` adds the throw.
Provenance for every cue is in `client/assets/audio/sound-pass-20261002.json`;
the audition page is local scratch in `.agents/audition/index.html`.
PR CI [run 37058097350](https://github.com/blisspixel/fragr/actions/runs/37058097350)
passes every job, including the full headless client check on Linux and the
macOS and Windows portability checks. The first run caught a fixture error in
the new grenade throw check (an unintended extra bounce), fixed in the test.
The local pinned `tools/godot_check.sh` passes import, all 189 scripts and all
89 harnesses with a clean log.

### Spend

Included credits only, $0 cash. This track submitted 75 requests estimated at
2,740 credits (40 per second); the conservative four-attempt ceiling was 10,960.
The shared account moved from 837,582 to 840,976 used across both batches
(3,394, an upper bound that includes any other use of the account) and to
860,681 by 19:02Z with no requests from this track. The closing check at
20:04Z still reads 860,681 used (586,515 remaining).

## Open

Listening and in-game mix acceptance. Viewmodel pump frames. Footsteps and
landing with surface lookup. Lifts, gates, objective and menu cues. The import
preset keeps the existing QOA compression for consistency; a listening pass
should confirm the Shotgun crack survives it.

## Handoff

Local and CI gates pass; PR #322 merges by squash. No further generation is
planned; the open items above are the next sound work.
