# M05 narration and grenade audio

**Status:** implemented, 2026-09-30, integration tracked in
[PR #314](https://github.com/blisspixel/fragr/pull/314). Developer-only generation under the already
authorized existing ElevenLabs credits and combined $20 development ceiling.
Reserve an additional conservative $1 equivalent, bringing audio reserves to $3;
new cash charges remain $0. Never enable top-ups, overages or paid runtime calls.

## Goal and contract

Voice the three frozen framing captions in M05 arrival and the Episode I exit,
using the same neutral River stock voice as the earlier transition batch. Add
two restrained spatial grenade sounds: a dry bounce and a compact blast/debris
tail. No character impersonation, new lore, music or claims that released workers
are aboard. Variable passenger status stays unvoiced and server-factual.

The client lane owns scene manifests, keyed captions, Effects/Voice routing,
missing-asset fallback and replay. The shared audio tool owns request validation,
format wrapping and manifests. Use `client/assets/story` as output and preserve
the prior seven requests and assets. Three MP3 clips and two PCM WAV sounds are
the complete batch; no overwrite or rerun of an uncertain submission.

## Preflight and budget

Read current account quota, dry-run the exact five-item spec, require the existing
1500-credit estimate gate and verify four bounded attempts still fit the quota
and reserve. The last settled quota was 694390 used, 752806 remaining; a fresh
receipt is required before submission. Record dry-run estimate, actual final quota
delta, remaining credits and $0 new cash separately. Keep request/model/voice/
format receipts. Use the previously checked compatible `eleven_v3` contract;
[official API pricing](https://elevenlabs.io/pricing/api) and
[commercial-use terms](https://elevenlabs.io/terms-of-use) were checked 2026-09-30
in [the earlier batch](campaign-transition-audio.md). No cloning or real-person
reference is involved. The bounce requests the API's supported minimum 0.5s,
with a short dry transient and quiet tail; blast duration is 0.9s.

## Verification and success

Exact caption/spec/manifest matching, positive decoded sample windows, proper
WAV wrapping/import, spatial bounded Effects playback, Voice locale fallback,
caption/skip behavior and no network callback during replay. Run focused checks
and the full pinned checker. Inspect an actual narrated scene and grenade
sequence. Loading/RMS alone does not prove hardware listening or mix quality.
Record that remaining review rather than certifying it from a waveform.

## Work record

Frozen captions and paths were supplied by the client lane before generation.
The five-item dry run estimated 472 credits under the explicit 1500-credit gate.
The live batch wrote all three MP3 clips and both WAV sounds without retries or
overwrites. Quota increased from 694390 to 694608 used: 218 included credits
consumed, 752588 remaining. This round has now consumed 693 included audio
credits across twelve jobs, with $0 new cash charges and a conservative $3
equivalent reserve. The ignored round ledger and preflight/live/final receipts
are under `.agents/`. Client integration, decoded windows, exact-caption matching,
spatial playback, Voice routing and missing-asset fallback pass the final pinned
checker: 174 scripts and 81 harnesses, including campaign-audio and grenade-effect
checks. Its clean receipt is
`.agents/m05-client-buildout-20260930/godot-full-modal-final.log`. Hardware listening,
final voice performances and subjective mix acceptance remain open; decoded files
and automated playback do not establish them.
