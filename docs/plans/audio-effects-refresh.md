# Sound effects refresh

**Status:** first candidate batch in progress, 2026-09-19. Existing effects remain
live. This is asset production and evaluation, not a claim of finished game audio.

## Objective and scope

Give weapons, bodies and spaces distinct physical sounds suited to a chunky retro
FPS. Clear attacks, short tails and recognizable mechanical signatures matter
more than constant bass, sparkle or long cinematic reverb. Use the existing
`tools/audiogen` path; no new provider, dependency or runtime API.

The first 32 candidates cover four gunshots, melee movement and impacts, weapon
handling, armor/world hits, steps and landings, pickups, doors and readable machine
warnings. Earth metal/concrete and offworld grating/regolith receive separate
foley. These are source candidates, not a complete variant library. Do not imply
sound travels through vacuum: exterior world sound requires an atmosphere or
contact/suit presentation consistent with the scene.

Existing runtime seams are `player_pawn.gd` for weapon sounds and
`game_manager.gd` for match feedback. New footstep, door and pickup playback must
use the appropriate authoritative event or presentation movement state. Do not
fake unimplemented reload, door or enemy behavior merely to expose an asset.

## Budget and production

Nick approved existing subscription quota, with no overages. Initial read-only
quota: 791,861 credits remaining. `sfx-refresh-pilot.json` uses explicit durations,
an estimated batch cap of 2,000 credits, and a staged `.agents/audio-refresh/`
destination. The tool's cap is an estimate check; its retry policy allows four
attempts. Keep that headroom, record before/after quota and stop on unexpected
charges or uncertain requests. Never overwrite the live library while evaluating.

```powershell
cargo +1.98.1 run -p fragr-audiogen --locked -- quota
cargo +1.98.1 run -p fragr-audiogen --locked -- --dry-run --max-credits 2000 batch --spec tools/audiogen/specs/sfx-refresh-pilot.json
cargo +1.98.1 run -p fragr-audiogen --locked -- --max-credits 2000 batch --spec tools/audiogen/specs/sfx-refresh-pilot.json
```

The explicit toolchain is installed in the current Windows environment. Other
environments use the repository's supported stable toolchain. Published SFX
pricing checked 2026-09-19 is 40 credits per requested second:
[official documentation](https://elevenlabs.io/docs/overview/capabilities/sound-effects).

## Acceptance and next pass

1. Verify each file decodes, has the intended duration/channel layout, and has no
   unexplained clipping, silence, truncation or unexpected speech/music.
2. Audition old/new shots at matched levels and repeat at actual weapon cadence.
   Check that rapid shots do not smear and nearby combat remains intelligible.
3. Evaluate in Godot with positional attenuation, mix buses, radio and dialogue.
   Mono spatial sources and stereo UI/music have different import requirements.
4. Trim and normalize from preserved originals through a recorded transformation;
   retain request metadata and distinguish raw from accepted assets.
5. Promote only reviewed sounds, add event/load checks, update the asset manifest
   and record the inspected gameplay scenario. More generated files do not prove
   a better mix. Capture remaining variant and integration work here.

No protocol changes or live asset replacements in this candidate batch.

## First pass findings

Produced 32 PCM candidates (1,020 estimated credits), then four comparisons using
simpler prompts, 1.5-second durations and MP3 (240 estimated, 300 cap). All 36
decode. Requested subsecond durations are quantized by the provider by up to
0.02 seconds. This is format evidence, not a listening approval.
All 36 effects also load in Godot 4.7.2 with nonzero duration. The isolated check
uses no live settings or gameplay scene and makes no positional playback claim.

The first denial cue has a severe DC offset (0.878 of full scale) and is rejected.
Several files reach full scale or have very low levels; do not normalize the
whole batch blindly or mistake a decodable file for a finished effect. The
comparison removed the denial cue's large offset but produced very quiet body,
steel and denial sounds. Reassess prompts and audition level-matched candidates;
the comparison does not establish a general MP3-versus-PCM quality advantage.

Measurements and original manifests remain in `.agents/audio-refresh/`. No
candidate is promoted yet. Next: inspect attacks/tails and sound identity, prepare
mono spatial variants with recorded gain/trim decisions, and prove the mix in
game at actual fire cadence before expanding the library.
