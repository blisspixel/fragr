# M02 ward and processing-floor soundscape

**Status:** in flight, [draft #280](https://github.com/blisspixel/fragr/pull/280), 2026-09-27. Follows the [processing-floor roster draft](m02-processing-floor-roster.md). M02 remains a development mission until fresh-player route and fight review passes.

## Goal and why

Make the M02 correction ward and processing floor readable by sound. The ward machine should establish a disturbing physical presence, then fall quiet when the server confirms its guards are defeated. The restraint release should sound like a real mechanism before Latch opens the next bay. The processing floor needs its own spatial machinery bed without masking the Crawler warning, enemy tells or dialogue.

The [accepted M02 brief](../campaign/m02-persons-unknown.md) puts the machine stop before the reunion and Low Water reveal. [Voice canon](../lore/voice.md) reserves what people say. This pass adds no improvised dialogue, music, faction slogan or joke about captives.

## Scope

| Cue | Target length | Trigger and position | Priority |
|---|---:|---|---|
| Ward machine loop | 2.0 s loop | Active ward, near the restraint frame | Establish place, below combat and speech |
| Ward machine stop | 1.0 s one-shot | First server-confirmed `ward_secured` transition | Audible silence after a mechanical decay |
| Restraint release | 1.4 s one-shot | First `companion_released` transition at Latch's restraint, then at the second bay when its door starts opening; reuse for the optional side ward | Physical latch, no success fanfare |
| Floor machinery loop | 2.6 s loop | Processing machinery island | Low, local texture that leaves the Crawler cue clear |

Do not add a new server event. The client already receives validated M02 mission facts. `client/scripts/m02_ward.gd` owns the ward and side-bay transitions and clears its scene on map change. Reuse the existing `Effects` bus and spatial player pattern in `client/scripts/game_manager.gd`. Initial snapshots, reconnects, retries, skipped scenes and map changes must initialize or stop sounds without replaying one-shot cues. Muted settings and missing assets remain usable. The Rust server retains all outcome authority.

## Asset production and spend gate

Prepare one spec for the four named effects in `tools/audiogen/specs/`, with fixed durations and no retries or variations. The current tool estimates sound effects at 40 credits per second, so seven seconds estimate to 280 credits. Cap a potential pilot batch at 320 credits, run `--dry-run`, check quota before and after, and record the actual debit in the asset manifest and this plan. An estimate is not a dollar charge: confirm the account plan and overage settings, verify that the date-bound $20 build authorization still covers the submission, and keep total external charges within the repository's $50 cap. No generation, cloud resource, top-up or overage is part of this planning commit.

Current provider documentation is inconsistent: the [sound effects overview](https://elevenlabs.io/docs/overview/capabilities/sound-effects) says 40 credits per specified second, while the [API-specific help article](https://help.elevenlabs.io/hc/en-us/articles/25735337678481-How-much-does-it-cost-to-generate-sound-effects) says 20. Use the higher rate until a live quota read establishes the actual debit. The API accepts one effect per request with a fixed duration; `tools/audiogen` already writes prompt, model, format and duration into `audiogen-manifest.json`.

Distribution needs a separate check before committing generated WAVs. ElevenLabs' [August 2026 prohibited-use policy](https://elevenlabs.io/use-policy) forbids distributing Sound Effects output on a standalone basis, including isolated audio files. A public source repository exposes raw assets individually, so an ElevenLabs pilot should stay in ignored local diagnostics until the distribution basis for this repository is clear. The [Sound Effects terms](https://elevenlabs.io/sound-effects-terms) and account terms also apply. If that gate remains unclear, use original offline-baked effects with documented source and zero API spend. Preserve required third-party notices.

## Implementation order

1. Record the current silence and caption behavior in a first-person M02 tour. Check the ward's machine animation, the server-owned stop, Latch's release and the side-bay release separately.
2. Prepare and validate the four-effect spec and an original offline fallback. Dry-run the API spec without network submission. Inspect the source or pilot output before choosing what ships.
3. Add spatial playback at the existing M02 presentation seam. The initial state sets loop activity and never emits a one-shot. A later transition plays once. A new attempt, map clear or scene skip stops or reinitializes players safely.
4. Keep the machine bed below speech and enemy cues. Verify distance falloff from the gallery, ward, side return and processing floor. The machine stop must create a perceptible contrast without an abrupt click.
5. Update audio provenance, import metadata and the plan with chosen assets, actual costs, captured state transitions and honest listening notes.

## Verification and acceptance

- `test_m02_ward.gd` covers initial snapshot, live transition, duplicate state, retry, late spectator, map clear and missing-file behavior. Godot import, script checks and each harness PASS marker must be clean.
- A first-person Standard and Severe tour reaches the ward stop, release, side room and departure with the intended sounds and captions. Inspect screenshots and listen to the recorded sequence on real hardware; a headless PASS cannot establish mix quality.
- The floor bed never drowns the Crawler scrabble or combat tells. There is no duplicated stop or release after reconnect, retry or scene skip.
- Asset files load in Godot, stay within practical packaged size, and have a manifest entry or original source recipe. No player runtime API request is introduced.
- Rust and workspace checks stay green; unfiltered coverage remains at or above 90 percent. No cloud apply or new external charge occurs without the exact spend and distribution gates above.

## Opt-in mix capture

Add a bounded `record_audio_seconds` state to the existing visual tour. It records the actual game mix from the Master bus into a 16-bit WAV under the ignored `.agents/qa/` run directory, then removes its temporary recording effect before the next state. The tour records duration and PCM level and fails on empty or silent output. A short no-combat M02 spectator route compares the active ward machine from clear antechamber and ward positions. This measures the change in the live spatial mix; it does not replace listening or establish the full combat mix. A later first-person run can use the same opt-in state around the machine stop and restraint release. No gameplay protocol, asset, API call or external spend changes.

Godot 4.7.2-stable API checked against the official [AudioEffectRecord](https://docs.godotengine.org/en/stable/classes/class_audioeffectrecord.html), [AudioServer](https://docs.godotengine.org/en/stable/classes/class_audioserver.html) and [AudioStreamWAV](https://docs.godotengine.org/en/stable/classes/class_audiostreamwav.html) references on 2026-09-27. Recording on Master captures the mixed buses before the final Master fader, so the WAV is not a speaker-level measurement. The effect is for developer QA only and is removed after each bounded capture.

The first local capture put the near camera against the machine face, so its dark still was rejected and the camera moved to a clear ward position. The final two-state tour used a real M02 server with zero fighters, radio off, and the active ward loop. Command from Git Bash: `FRAGR_QA_MANIFEST=res://qa/m02-ward-audio-levels.json FRAGR_QA_MAP_FILE=server/maps/m02-persons-unknown.json FRAGR_QA_BOTS=0 FRAGR_PORT=6834 tools/qa_tour.sh .agents/qa/m02-ward-audio-final`. It passed with a clean Godot log and restored the Master effect count after each capture. The antechamber WAV was 3.01 seconds, 48 kHz stereo 16-bit, RMS 0.000591 and peak 0.001129. The ward WAV was 3.01 seconds in the same format, RMS 0.001957 and peak 0.003723, a 3.31-times RMS increase. Both camera stills were inspected for clear geometry. The full pinned `tools/godot_check.sh` passed after this tour addition. The WAVs remain in ignored local QA output for listening; these numbers show a relative level change, not a judged loudness, hardware output or combat balance. External spend remains $0.

## Handoff

The four-effect [request spec](../../tools/audiogen/specs/m02-ward-sfx.json) is prepared with local ignored output. `cargo run -p fragr-audiogen --locked -- --dry-run batch --spec tools/audiogen/specs/m02-ward-sfx.json --max-credits 320` validated all four requests and estimated 80 + 40 + 56 + 104 = 280 credits. It made no API request, wrote no WAV, and incurred no external charge.

The public draft uses four original offline-baked effects from [the deterministic Godot recipe](../../client/assets/audio/m02/bake_soundscape.gd), with file hashes, levels and durations in [the asset manifest](../../client/assets/audio/m02/soundscape-manifest.json). The existing M02 ward presenter plays them from validated mission-state transitions on the spatial `Effects` bus. Latch's first restraint, the later second-bay opening and the optional side ward each have a local mechanism cue. A first snapshot or retry starts only the current machinery beds; late joins, duplicates, skips and map clear do not replay old one-shots. The focused `test_m02_ward.gd` state test passed under Godot 4.7.2-stable. Godot import and loop metadata passed; the two loop seam jumps measure 0.001648 and 0.001160 full scale. Total WAV data is 336,176 bytes. No external asset charge was incurred.

Listening and the in-game mix are still open. This environment could inspect waveforms and measure levels but could not audition audio. The next pass must hear both difficulties in a first-person route, check the ward stop and restraint at their positions, and make sure the floor bed leaves the Crawler warning and speech clear before this plan is accepted.
