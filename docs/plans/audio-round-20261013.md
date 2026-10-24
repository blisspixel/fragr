# Rocket feedback and foundry audio candidates

**Status:** implemented, 2026-10-13. This is a bounded parallel production round
under the existing roadmap, not a new campaign sequence.

## Scope

Restore audible Rocket launch feedback through the existing pawn
presenter. The Rocket previously had no fire-stream mapping. Use committed
generic fire as the provisional fallback; do not promote unauditioned recordings.
Arc already has dedicated committed cues and needs no replacement this round.

Prepare four candidates: a compact Rocket launch, a short grounded blast, a
foundry machine warning and a mechanical release latch. Foundry cues remain
staged until authoritative M13 state tells and listening acceptance exist.
Prepare one warm, driving instrumental workshop groove for internal audition.
It should express ordinary free people's practical confidence without turning
every cue into a faction anthem. No narration, voice casting or music-library
replacement is in scope.

## Seams and verification

`player_pawn.gd` keeps the existing spatial Effects bus. `grenade_effects.gd`
retains new validated projectile launches between accepted snapshots, and the
manager consumes them after syncing pawns and before reconciling local fire.
The local prediction receipt prevents a second cue on confirmation. Initial
synchronization, old first-seen projectiles, invalid and repeated snapshots are
silent; reset clears pending launches. A Rocket blocked at its origin and
resolved before any traveling fact retains the existing blast sound only.
Explosion radius cannot safely identify a new Rocket launch.
No protocol, combat, cadence, map or mission authority changes. Extend the native
audio tool's read-only subscription summary to expose extension and current
overage state, preserving unknown fields as unknown. The documented credit
extension value accepts an unsigned count or exactly `"unlimited"`. Test true,
false, absent, null and extension variants offline; run the native crate tests. Check the client import
and existing Rocket presentation harness on the pinned Godot binary.

Candidates use `tools/audiogen` only, with exact specs under its `specs/`
directory and output under ignored `.agents/audio-round-20261013/`. Check decode,
duration, channel count, peak, RMS, DC and silence from preserved originals.
These measurements cannot establish sound identity, comfortable loudness or a
good in-game mix. Listening and cadence/positional mix checks precede promotion.

## Budget and rights preflight

Nick authorized existing funded audio quota on October 13. Root serializes
paid calls across lanes. Four explicit SFX durations total 6 seconds, estimated
at 240 credits by the native tool. A 60-second music candidate estimates 900.
Caps are 240 and 900 respectively, 1,140 combined, with no retries of paid POSTs.
Reserve a conservative $1 equivalent for this audio slice under the $5 per-run
ceiling; no new cash, top-up or overage is authorized. Read live quota before and
after each batch and retain uncertain receipts until reconciled.

Checked October 13: [SFX documentation](https://elevenlabs.io/docs/overview/capabilities/sound-effects)
states 40 credits per specified second. The
[API pricing page](https://elevenlabs.io/pricing/api) lists $0.12 per minute for
SFX and $0.15 per minute for music ($0.162 for this slice), while credit-based
music estimates remain 900 per minute in our tool. Account billing evidence
must establish which allowance applies before generation; these different
published meters are not interchangeable assertions about actual charges.

[Music terms](https://elevenlabs.io/music-terms), updated October 9 and checked
October 13, permit qualifying indie-game use on Pro but separately restrict
music libraries, including reusable raw output collections. A public source
repository needs a distribution basis beyond the plan name. Keep this music
candidate internal and ignored, with no runtime reference or release inclusion.
Do not apply an Apache-2.0 grant to it.

[ElevenCreative terms](https://elevenlabs.io/creative-terms), Exhibit 4 section 2,
also restrict isolated SFX file and sound-library distribution while permitting
incorporation in games. All new SFX therefore remain ignored candidates too,
pending a basis for this public repository's raw audio distribution. Existing
assets and licenses remain intact; this round does not retrospectively decide
their historical terms.

**Rights decision, 2026-10-23.** Nick decided on 2026-10-23 that new ElevenLabs sound effects and music ship by committing them to the repository with provenance, on the same basis as the [October 2 sound pass](sound-pass-20261002.md) and [`client/assets/audio/README.md`](../../client/assets/audio/README.md): each committed file keeps its `audiogen-manifest.json` entry (prompt, model, format, duration, generation time) and its batch spec. The SFX and music
candidates from this round may be promoted on that basis once they pass their
listening, level and in-engine gates; the internal-only hold above is lifted
for future promotion, not applied retroactively to anything unreviewed.

Live preflight: Pro active, 23,998 of 1,185,132 credits used, 1,161,134 remaining.
Reset is 1793976680 unix. Credit extension eligibility is false, permission true,
maximum extension 250,000 and current overage 0 USD. This is existing account
state, not an instruction to enable billing. Leave settings unchanged, use only
the ample included balance and reconcile after each bounded batch.

## Acceptance

The code slice succeeds when Rocket resolves to an existing nonempty spatial
fire stream and native quota reporting distinguishes unknown from disabled
overage settings. Production succeeds when the bounded requests have retained
manifests and reconciled usage. Generated candidates are not accepted runtime
assets until listening, lore fit and actual play mix are recorded.

## Local evidence

All five native requests completed without retries. Preserved source files,
request manifests, production logs, quota snapshots and FFmpeg measurements
live under `.agents/audio-round-20261013/`. No generated audio was copied into
the public asset library. Requests estimated 1,140 credits; the stable observed
account delta is 981, from 23,998 to 24,979 used, leaving 1,160,153. Two post-run
checks reported the same counter and 0 USD current overage. This is account
reconciliation, not an itemized invoice. No billing settings changed.

| Candidate | Decoded duration | Format | Peak dBFS | RMS dBFS | DC offset |
|---|---:|---|---:|---:|---:|
| Rocket launch | 1.000 s | stereo 48 kHz PCM | 0.0003 | -14.83 | -0.015579 |
| Rocket blast | 2.000 s | stereo 48 kHz PCM | 0.0003 | -11.52 | -0.000462 |
| Machine warning | 1.480 s | stereo 48 kHz PCM | 0.0003 | -16.86 | -0.000115 |
| Release latch | 1.480 s | stereo 48 kHz PCM | 0.0003 | -21.53 | -0.000111 |
| Workshop groove | 60.029 s | stereo 44.1 kHz MP3 | -0.379 | -14.70 | -0.000114 |

All files decode. Every raw SFX touches full scale; the launch also has material
DC offset. They are rejected for direct runtime promotion. Keep the originals
for listening and comparison before deciding on repair or a new request. Lower
playback gain does not restore clipped samples. Music has measurable headroom,
but no listening, originality or gameplay-mix acceptance is claimed. No audio
perception tool was available in this session; human audition remains required.

Validation: 64 native audio tests pass on Rust 1.97.1 with `--locked`. Godot
4.7.2 headless harnesses `test_combat_audio`, `test_rocket`,
`test_local_fire_feedback` and `test_grenade_effects` pass. Rocket tests feed
actual accepted projectile snapshots through the effects/manager boundary into
a real pawn AudioStreamPlayer3D, including predicted-local suppression,
spectator playback, stale/invalid/duplicate rejection and reset. This proves
event routing and sample playback state, not headphone panning or a human mix.
The native `ordinary_tick_snapshot_age_recovers_the_authoritative_rocket_launch_tick`
regression also passes through normal action ingress, `GameState::tick` and
snapshots: launch age is zero, later ages one through three preserve the same
`snapshot.tick - age_ticks` launch tick. The client freshness calculation
therefore follows the server's actual launch-tick hold, not a synthetic age
assumption.

Lore check: the practical launcher and worn foundry machinery follow
`docs/lore/guns.md`; workers' choices remain server facts, never implied by
these sounds. The instrumental brief follows the ordinary-life direction in
`radio-refresh.md`. No artist references, faction anthem, voice performance,
new narrative beat or mandatory listening objective was introduced.
