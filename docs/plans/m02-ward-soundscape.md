# M02 ward and processing-floor soundscape

**Status:** planned, 2026-09-27. Follows the [processing-floor roster draft](m02-processing-floor-roster.md). M02 remains a development mission until fresh-player route and fight review passes.

## Goal and why

Make the M02 correction ward and processing floor readable by sound. The ward machine should establish a disturbing physical presence, then fall quiet when the server confirms its guards are defeated. The restraint release should sound like a real mechanism before Latch opens the next bay. The processing floor needs its own spatial machinery bed without masking the Crawler warning, enemy tells or dialogue.

The [accepted M02 brief](../campaign/m02-persons-unknown.md) puts the machine stop before the reunion and Low Water reveal. [Voice canon](../lore/voice.md) reserves what people say. This pass adds no improvised dialogue, music, faction slogan or joke about captives.

## Scope

| Cue | Target length | Trigger and position | Priority |
|---|---:|---|---|
| Ward machine loop | 2.0 s loop | Active ward, near the restraint frame | Establish place, below combat and speech |
| Ward machine stop | 1.0 s one-shot | First server-confirmed `ward_secured` transition | Audible silence after a mechanical decay |
| Restraint release | 1.4 s one-shot | First `companion_released` transition; reuse for the optional side ward | Physical latch, no success fanfare |
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

## Handoff

No API request or asset generation has run for this plan. Next: prepare the request spec and offline fallback, then test state-driven playback. Record the selected distribution path before a public asset commit.
