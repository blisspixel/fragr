# Audio assets

Two pipelines feed this directory. Every file is an ordinary asset the client loads by name; nothing here calls a network at runtime.

## Generated with `fragr-audiogen` (ElevenLabs, developer-only)

Sound effects and music produced by `tools/audiogen` (see `tools/audiogen/README.md`). Provenance for each generated file lives in `audiogen-manifest.json` next to it: prompt, model, format, duration, channel count, byte size, generation time. Regenerate with the batch specs under `tools/audiogen/specs/`.

Generated files are owned by the project under the ElevenLabs terms for the account that produced them and are distributed with the repository under its Apache 2.0 license. Sound effects are stereo 24 kHz 16-bit WAV by default (the API returns stereo PCM). Music and the spoken news station are 44.1 kHz MP3.

## Earlier procedural set (retired)

The first effect set was synthesised procedurally and dedicated to the public domain under CC0 1.0 Universal. It has been replaced by generated effects with manifest entries; the old files remain in git history.

The M02 Crawler scrabble is a new original offline procedural cue. `bake_crawler_scrabble.gd` writes the WAV and a deterministic `crawler_scrabble-manifest.json` with its format, fixed seed and SHA-256. Regenerate from the repository root with `godot --headless --path client --script res://assets/audio/bake_crawler_scrabble.gd` using Godot 4.7.2-stable. It makes no external request and has no generation charge. Its caption is localized and remains visible when audio is muted.

The M02 ward and processing-floor machinery set is also original and baked offline. `m02/bake_soundscape.gd` writes four mono 24 kHz PCM WAVs and `m02/soundscape-manifest.json` with a fixed seed, purpose, length, loop flag, level measurements and SHA-256 for each file. Regenerate from the repository root with `godot --headless --path client --script res://assets/audio/m02/bake_soundscape.gd` using Godot 4.7.2-stable. The beds loop forward at their full length; the stop and release play once. No third-party recording, asset service, external request or generation charge is involved. The ward bed is set quieter than the mechanical stop and release, and the floor bed is set below the Crawler warning. Final mix balance still needs listening in a rendered M02 route.

## Files the client loads

The M04 Notary set is original and baked offline.
`notary/bake_soundscape.gd` writes a quiet two-second ducted fan loop, a short
mechanical shutter and a grounded casing impact, with source/output hashes,
PCM bounds and level measurements in `notary/soundscape-manifest.json`.
Regenerate with `godot --headless --path client --script
res://assets/audio/notary/bake_soundscape.gd`, then import on the pinned engine.
Committed presets preserve mono 24 kHz 16-bit PCM and the fan loop. Fixed
spatial Effects pools follow nearby typed actors, resolved shots and actual
registered support contact; late joins do not replay old crashes. Captions
remain available when muted or when a sample is missing. M02's passive Notary
has no combat cue. External spend is $0.

The Jammer launch is an original offline cue. `jammer/bake_launch.gd` writes
the short mono 24 kHz PCM WAV and a source/output hash receipt. Regenerate with
`godot --headless --path client --script res://assets/audio/jammer/bake_launch.gd`
on the pinned engine. Confirmed server launches play through a fixed spatial
Effects pool; the firing pose alone produces no sound. There is no external
request, asset charge or weapon-gunshot substitution.

| File | Used for |
|---|---|
| `fire.wav`, `hit.wav` | Fallback weapon fire and the generic hit (health drops without a resolved shot) |
| `fire_tack.wav`, `fire_flechette.wav`, `fire_rail.wav`, `fire_scatter.wav` | Per-weapon fire |
| `shotgun/cycle.wav` | Shotgun pump cycle, 0.22 s after each blast, inside the 0.60 s cooldown |
| `hit_tack.wav`, `hit_flechette.wav`, `hit_rail.wav`, `hit_scatter.wav` | Impact of the gun a resolved shot names, once per struck body |
| `melee/fists.wav`, `melee/shiv.wav` | Melee swings (never a Crawler's leap contact) |
| `clerk/tell.wav`, `sweeper/tell.wav`, `heavy_sweeper/tell.wav`, `turret/tell.wav` | Union windup tells, `<kind>/tell.wav`, cut off when the windup ends |
| `down/body.wav`, `down/robot.wav` | Authoritative fall to zero health; the Notary keeps its crash |
| `pickup/weapon.wav`, `ammo.wav`, `cells.wav`, `health.wav`, `armor.wav` | The watched fighter's pickups |
| `dry_fire.wav` | The owner's dry trigger |
| `grenade/throw.wav` | A grenade first seen in flight |
| `fire_sniper.wav`, `sniper/scope_in.wav`, `sniper/scope_out.wav` | Level 7 Sniper Rifle, not wired yet |
| `ranged_sweeper/tell.wav`, `ranged_sweeper/fire.wav` | Level 7 Ranged Sweeper, not wired yet; the tell loads once the kind exists |
| `l07/curfew_chime.wav` | Level 7 curfew chime, not wired yet |
| `frag.wav` | Elimination stinger |
| `round_start.wav`, `round_end.wav` | Round cues |
| `crawler_scrabble.wav` | Spatial M02 Crawler warning cue |
| `jammer/launch.wav` | Server-confirmed Jammer interference launch |
| `notary/fan.wav`, `notary/shutter.wav`, `notary/crash.wav` | M04 spatial fan, resolved photograph and grounded wreck |
| `m02/ward_machine_loop.wav`, `m02/ward_machine_stop.wav` | Correction ward machinery and its shutdown |
| `m02/restraint_release.wav` | Latch's first restraint, the second bay and the optional side ward |
| `m02/floor_machinery_loop.wav` | Processing-floor spatial machinery bed |
| `radio/<station>/` | Contested Frequency radio tracks, grouped by station id; `radio/stations.json` names the stations |

Loading paths: `client/scripts/player_pawn.gd` (per-weapon fire and hit, pump, melee, tells and falls), `client/scripts/game_manager.gd` (frag, round, Crawler, pickup and dry-trigger cues, and resolved-shot impacts), `client/scripts/grenade_effects.gd` (throw, bounce and blast), `client/scripts/m02_ward.gd` (ward and processing-floor cues), `client/scripts/radio.gd` (radio tracks, discovered through the manifest, never by directory listing). Import presets: keep WAV as samples, MP3 as streams, loop flags off unless the manifest marks a file as looping.

The 2026-10-02 [sound pass](../../../docs/plans/sound-pass-20261002.md)
rebuilt the Shotgun from five full-band 48 kHz layers and added the pump cycle,
the cues listed above and the Level 7 set. New cues are mono 48 kHz 16-bit PCM
one-shots at or below -1 dBTP. `sound-pass-20261002.json` records every layer
(request, spec, source hash, trim, gain, delay, filter), the mix and finish
chains, the target and measured levels and the output hash. The Railgun, Rifle,
Railgun impact and generic hit were only turned down; their previous hashes are
recorded there. The raw Shotgun layers are kept byte for byte, outside the
import, in `client/art/audio/shotgun/`. Listening and in-game mix acceptance
remain separate from these measurements.

Radio controls in the match: C next station, N next track, M radio on or off
(D-pad up, down, left on a gamepad). Ammunition is one count per type, with no
magazines or reload action.
Every switch shows a station card above the track toast. Radio ducks under Host
lines and sits lower while playing; LOCK IN never ducks for combat.

Footsteps, landing, lifts, gates, objective and menu cues are not built yet;
the sound pass plan ranks them.
