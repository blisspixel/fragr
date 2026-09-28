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
