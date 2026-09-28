# M02 live cue listening gate

**Status:** in flight, [draft #281](https://github.com/blisspixel/fragr/pull/281), 2026-09-27. Follows the [ward soundscape](m02-ward-soundscape.md) draft. M02 remains a development mission.

## Goal and why

Capture the real first-person M02 mix across the Crawler warning, ward machine stop, Latch restraint release and second-bay opening. The existing tour can record steady sound but starts its recorder after walking, combat and interaction, missing these short events. These WAVs are evidence for a human listening review, not an automated claim of intelligibility or fun.

## Scope and architecture

- Add an opt-in, bounded start/end pair to the existing Godot QA tour. Arm on the Master bus before a state walks, fights or uses the mission control; stop and save after a named later state has met its live assertions. Keep the existing ten-second steady-state recorder.
- Permit one active recording at a time, at most 90 seconds. Reject malformed or unmatched manifest pairs before starting a scene. Remove the temporary bus effect on completion and all failure/scene-retirement paths. Keep WAVs and their metadata in ignored `.agents/qa/` output.
- Run a joined human route using the existing M02 evacuation tour as the source of waypoints. A floor Crawler cue must be captured near the floor machinery, not inferred from the earlier stair cue. Do not change gameplay, protocol, mission authority or assets.
- The recorder sees child buses before the final Master fader. Record PCM duration, RMS and peak as diagnostic numbers only. Compare the actual cue sequence by listening on real hardware in both Standard and Severe.

## Verification and spend

Validate start/end syntax, missing close, duplicate open, cross-scene capture and duration bounds in the tour's Godot test harness. Run the pinned Godot checker and a real M02 live route; inspect first-person stills, saved WAV format and clean logs. The eventual human gate records whether the Crawler warning remains distinct over the floor bed, the ward stop creates a useful silence, both mechanisms are audible, and the current unvoiced Latch captions remain readable. Report any difficult or incomplete route as such.

This sprint needs no external API or cloud resource. Spend is $0; do not use the date-bound asset allowance without a new exact-cost approval. Keep the repository's $50 total cap.

## Acceptance

The opt-in capture passes deterministic validation and records the requested live transitions from a joined fighter, with no lingering recording effect or silent/empty WAV. The plan remains in flight until Nick listens on hardware and the Standard and Severe first-person routes meet the soundscape gate.

## Work log

- The tour now accepts paired `record_audio_start` and `record_audio_stop` fields. It arms before walking, combat or use, saves at the closing state, and removes its temporary Master effect. Manifest validation rejects unmatched, overlapping and cross-scene spans and conflicts with the ten-second steady recorder. A 90-second runtime watchdog bounds stalled capture. The existing recorder and the live span share one PCM validation and cleanup path.
- The joined-fighter [listening route](../../client/qa/m02-live-cue-listen.json) follows the proven M02 maintenance and ward path into the processing floor. It asserts the stair and floor Crawler source coordinates, live captions, server-owned ward and restraint stages, and the actual floor Crawler fight. No floor warning is inferred from a remote first-stair event. Its first-person release still faces a nearby panel, so it is audio capture evidence, not visual proof of the restraint opening; the separate evacuation tour supplies that view.
- The first floor pass failed because its observation state had not entered the floor Crawler trigger. Moving the joined fighter to `[0, 0, 11]` produced a floor cue from `[-4, 0, 12]` and a live caption. The initial frame aimed into the floor; the inspected final frame faces the warning lane. Failed tours were kept only in ignored local diagnostics.
- Standard command from Git Bash: `FRAGR_QA_MANIFEST=res://qa/m02-live-cue-listen.json FRAGR_QA_MAP_FILE=server/maps/m02-persons-unknown.json FRAGR_QA_BOTS=0 FRAGR_PORT=6839 tools/qa_tour.sh .agents/qa/m02-live-cues-inspected`. Severe used `FRAGR_QA_DIFFICULTY=severe`, port 6840 and `.agents/qa/m02-live-cues-severe`. Both 21-state routes passed on Godot 4.7.2-stable and the AMD Radeon 780M renderer with clean logs. The contact sheets and floor warning frames were inspected. Each WAV is 48 kHz, stereo, 16-bit PCM, saved locally under the corresponding ignored QA directory. The four files are `06_live_audio.wav`, `10_live_audio.wav`, `15_live_audio.wav` and `20_live_audio.wav` in table order.

  | Captured span | Standard seconds, RMS, peak | Severe seconds, RMS, peak |
  |---|---:|---:|
  | Stair Crawler warning | 4.70, 0.004733, 0.089569 | 4.65, 0.004670, 0.087585 |
  | Ward fight through machine stop | 6.86, 0.024543, 0.401215 | 7.47, 0.025131, 0.394104 |
  | Latch release through Low Water | 6.93, 0.006760, 0.134857 | 6.92, 0.006812, 0.138580 |
  | Floor fight through nearby Crawler warning | 9.60, 0.025370, 0.625153 | 10.14, 0.032724, 0.771423 |

The server-stage assertions prove the route crossed the intended events while the recorder was active. Nonempty PCM does not prove that each one-shot reached the WAV or that a player can hear it in the mix. Hardware listening must decide whether the Crawler cue cuts through machinery, the stop reads as silence and the mechanisms are distinct. Latch and Low Water currently use captions rather than voiced dialogue; their text needs a separate readability check. A fresh-player route remains open. No API or cloud resource was used; external spend is $0.

The full pinned `tools/godot_check.sh` passed after the route and recorder changes, including the `test_qa_combat.gd` manifest validation cases. The ten-scenario `tools/test_godot_check.sh` fault-injection self-test also passed. The first checker invocation ran before this new worktree had its required release server binary and failed unrelated local-launch harnesses; building `fragr-server` in release mode and rerunning the complete checker resolved that setup failure.

## Default-radio comparison

The route above intentionally disables the radio so the original mechanical cues can be inspected. The player radio starts enabled, and the default LOCK IN station does not duck under combat. A separate same-route capture with the radio playing is needed to assess the mix a new player first hears. The static ward probe showed a much larger Master-bus level with radio on, but that level alone cannot establish whether the cues are masked.

Use an opt-in `FRAGR_QA_RADIO_COMPARE=on` override only for a tour state that explicitly requests `radio_off`. The ordinary route remains radio off. Select the committed `radio/lockin/01-push` entry through the existing radio catalog player, using a one-track QA copy of that station so playback and loop-on-finish remain deterministic. Record its title and resource path, and fail if the track stops or changes during the four live captures. Keep the route, difficulty, game settings, and recording bounds otherwise identical. Reject an unsupported override or a tour without a radio-off state, so a misspelled command cannot silently change evidence.

Run the first-person 21-state tour on Standard and Severe with this override and isolated output directories. Compare each radio-on WAV with its radio-off counterpart from the same difficulty, inspect the first-person frames, and retain exact track identity, PCM format, peaks, and any errors in this plan. These are local QA artifacts under `.agents/qa/`, never distributable replacements for source assets. A human must listen on hardware before changing the radio or signing off the soundscape. This slice uses existing committed tracks and incurs no external charge.

The opt-in path selects the existing LOCK IN track `radio/lockin/01-push`, titled "Push Push Push Push", through `Radio.play_random` after reducing the QA station copy to that one catalog entry. The loaded resource remains `res://assets/audio/radio/lockin/01-push.mp3` at all four capture stops. The regular route retains its `radio_off` instruction. `test_radio.gd` proves selection, replay and rejection of a missing track; `test_qa_combat.gd` proves invalid or inapplicable overrides are refused. Both focused harnesses passed under Godot 4.7.2-stable. `git diff --check` passed. The ordinary two-state ward level tour also passed after this change, with radio off, 3.02/3.00 second WAVs and RMS 0.000592/0.001957.

Standard command from Git Bash: `FRAGR_QA_RADIO_COMPARE=on FRAGR_QA_MANIFEST=res://qa/m02-live-cue-listen.json FRAGR_QA_MAP_FILE=server/maps/m02-persons-unknown.json FRAGR_QA_BOTS=0 FRAGR_PORT=6845 tools/qa_tour.sh .agents/qa/m02-live-cues-radio-standard-pass`. Severe used `FRAGR_QA_DIFFICULTY=severe`, port 6846 and `.agents/qa/m02-live-cues-radio-severe`. Both 21-state first-person routes passed with clean client logs. Their contact sheets and floor warning frames were inspected; the warning caption and Crawler lane are visible. All eight WAVs are 48 kHz stereo 16-bit PCM, nonempty, with no full-scale clipped samples. The Master effect was removed at each stop. A prior Standard run on port 6841 failed the existing no-damage first-Crawler assertion after one hit; a run on port 6843 passed that fight but died in floor entry. Those failed attempts are retained in ignored local diagnostics and are not audio-mix verdicts.

| Captured span | Standard radio off RMS | Standard radio on RMS, peak | Severe radio off RMS | Severe radio on RMS, peak |
|---|---:|---:|---:|---:|
| Stair Crawler warning | 0.004733 | 0.054355, 0.252319 | 0.004670 | 0.054533, 0.251099 |
| Ward fight through machine stop | 0.024543 | 0.062675, 0.847717 | 0.025131 | 0.062262, 0.752655 |
| Latch release through Low Water | 0.006760 | 0.057056, 0.268036 | 0.006812 | 0.056853, 0.266052 |
| Floor fight through nearby Crawler warning | 0.025370 | 0.062824, 0.755066 | 0.032724 | 0.062127, 0.655945 |

The music raises whole-span RMS most strongly in the stair warning and Latch spans. Combat routes vary in timing and gunfire, so their RMS pairs are diagnostic rather than level-matched measurements. These numbers, the source and caption assertions, and clean PCM still cannot tell whether the cues are audible over the track. Nick's paired listening review on real hardware remains required. External API and cloud spend for this comparison was $0.

After the radio comparison change (`b4d8b89`), the complete pinned 4.7.2 `tools/godot_check.sh` passed, including the radio and QA tour harnesses. The radio-on floor warning frame and 21-state contact sheet were inspected. The default radio-off two-state regression also passed; its WAVs and the eight radio-on WAVs remain in ignored local QA output.
