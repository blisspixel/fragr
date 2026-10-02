# M06 audio batch

**Status:** in flight, 2026-10-01. Four exact jobs generated, settled and
integrated. Decoded playback and caption/fallback checks pass; complete mission
and release gates remain pending. Parent: [M06](m06-port-of-entry-prototype.md).

## Goal and scope

Record the three frozen neutral framing pages from `m06_arrival` and `l06_l07`
plus a quiet six-second interior utility loop. The original text remains the
missing-asset fallback. Keep final-page reader hold, captions, Voice bus routing
and held-input release before readiness. The loop uses the existing bounded
Effects playback. Neither narration nor generic residents establish final
casting for Tern, Voss, Mara or Latch. No music, character dialogue or runtime
API dependency is introduced.

## Contract and budget

Use the existing Rust `tools/audiogen` with
`specs/m06-port-20261001.json`. Account quota was read on 2026-10-01: active Pro,
694608 of 1447196 credits used, 752588 included credits remaining. The voice
catalog confirms the same neutral River ID used by the earlier framing clips.
Credentials stay in the existing ignored integration and never in receipts.

Primary [API pricing](https://elevenlabs.io/pricing/api), checked 2026-10-01,
lists v3 speech at $0.08 per thousand characters and sound effects at $0.12 per
minute. That pay-as-you-go table is a comparison, not a claim about this
subscription's credit settlement. The tool conservatively estimates one credit
per speech character and 40 per second for SFX. Dry-run the exact jobs before
submission, enforce `--max-credits 1000`, and reserve up to four attempts per job
under the existing retry policy. The account allowance comfortably covers the
bounded retries; actual subscription usage is reconciled after the batch.

Use existing included credits only, $0 planned new cash. Retain the ongoing
2026-09-30 round ledger: $20 combined cash cap, $50 repository total, prior 693
included credits and $3 equivalent reserve. Add a conservative $1 equivalent
reserve for this batch, leaving $16 after reserves. Do not enable top-ups or
overages, start another batch or reset the round allowance with the new date.

## Verification and success criteria

Require ordinary committed files and a prompt/model/format manifest entry.
Match every spoken word to its localized caption. Inspect actual decoded
playback, missing-asset fallback, reader completion and skip/readiness barriers
through the existing Godot harnesses. Listen to the small clips and loop before
acceptance; loading alone does not establish suitable performance or mix.
Publish only after the parent mission and complete checks converge. Record
estimate, actual credits, cash charges and retained receipts here.

## Generation receipts

The exact dry run estimated 611 credits: 166, 58 and 147 for the three speech
pages and 240 for the six-second loop. The capped batch wrote all four jobs
without an observed retry. Quota advanced from 694608 to 694860 used credits,
an actual 252 included credits consumed; 752336 remain. New cash charges are
$0. Immediately after this batch, the round totaled 945 included credits and a
conservative $4 equivalent reserve, leaving $16 after those audio reserves.
The later [shotgun refresh](shotgun-sfx-refresh.md) consumed 30 included credits:
the current round total is 975 with a $5 audio equivalent reserve and $0 new
cash charges. Six separately approved image requests reserve $0.274, with
provider billing unconfirmed and the prior uncertain $0.107 retained.
The public pay-as-you-go comparison is $0.02968 for 371 speech characters and
$0.012 for six seconds of SFX, $0.04168 before taxes; it is not a subscription
cash charge. The four-attempt conservative credit reservation was 2444.

Receipts are under `.agents/m06-buildout-20261001/`: `audio-quota-before.log`,
`audio-voices.log`, `audio-dry-run.log`, `audio-batch-live.log` and
`audio-quota-after.log`. The cumulative local ledger is
`.agents/spend/development-20260930.json`. The asset manifest records the prompt,
voice/model and format. No image job, top-up, overage or cloud operation ran.

## Playback receipts

Pinned client checks decode positive PCM energy from the three narration clips,
match their exact caption/manifest text, observe real completion signals,
preserve final-page reader hold and exercise missing-asset fallback on both
new scenes. The utility WAV retains 16-bit stereo 24kHz PCM, with a complete
six-second forward loop. Its player is bounded to the existing Effects path;
narration uses Voice. Focused receipt:
`.agents/m06-buildout-20261001/client-test_campaign_audio-ready.log`.
The actual owned M06 launch also passes the held-fire release barrier before
server readiness. No human listening or final character-performance approval
is claimed. These clips are neutral framing, with final mix/casting review open.
