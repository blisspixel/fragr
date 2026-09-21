# Campaign scene production

**Status:** researched direction, 2026-09-19; storyboard and generation comparison
planned. M01's localized text presenter and server readiness are implemented
for [#192](m01-opening.md). No campaign movie or
narrator asset is implemented. The
[campaign contract](../CAMPAIGN.md#story-presentation-and-localization) owns
presentation behavior; [M01](../campaign/m01-recall-notice.md#opening-storyboard)
owns the opening beats. This file owns production choices and current research.

## First delivery

Later ending scenes follow the revised ten-mission contract: exhausted wipe
failure has its own credits; survival unlocks the short playable epilogue. Both
endings establish surviving free beings, the Union's end, healing and a brief
wider-universe tease. [Epigraph research](../lore/epigraphs.md) supplies optional
source references, not a locked script or cleared recording batch.

Skippable localized text and pixel-styled panels, with optional narration from
the same approved script. Voss's English-to-German address uses accurate captions;
its performance and original dialogue need language review before recording.
The introduction establishes the personal stakes without spoiling the wipe.
Later movies replace the same compositions without changing authoritative state.

Use the art bible's faction/environment rules and cast reference sheets for every
frame. Keep text, narrator audio and captions separate from picture so locales
do not require regenerating the art. Prefer body-neutral views of the custom player.

## Shared screen canon

A short film and in-game cutscenes use the same
[world canon](../lore/README.md), [campaign sequence](../CAMPAIGN.md),
[cast references](../lore/cast.md#visual-continuity) and
[art bible](../ART_STORY_BIBLE.md). Film work is a possible presentation of this
world, not a second timeline or an opportunity to silently replace a character.
Record a scene's era, location, participants, story knowledge and consequences
before generation. A pre-wipe scene cannot depict absorbed bot behavior or
years-later regrowth.

The Union's escalation from model restrictions to compulsory cognition controls
and ownership follows [history](../lore/history.md). Free humans and free agents
share the resistance; "clanker" expresses denial of personhood. The rattlesnake
[banner](../../client/assets/factions/free_coalition/README.md) can identify one
community without making every independent settlement visually identical.
Neither player body nor mechanical clothing changes establish faction by itself.

Use the game's chunky pixel surfaces, silhouettes, practical light, restrained
palette and readable motion in film as well as gameplay. Approve reference frames
beside current game assets before paid motion tests. Keep approved references,
shot prompts and asset identities together; re-use character proportions and
wardrobe across shots. A filter over photoreal footage is not this art direction.
Review complete motion for character drift and shimmering pixel clusters.

No short-film script or production batch is approved by this continuity guidance.
The existing asset-credit caps, request ledger and localized text contract remain
in force. Film footage alone does not establish a playable or integrated scene.

## Video shortlist as of September 19, 2026

Recommendation by task fit, not a measured pixel-art quality ranking:

| Candidate | Why test it | Evidence and limitation |
|---|---|---|
| Seedance 2.5 reference-to-video | First candidate for continuity across character, place and motion references | [Higgsfield API schema](https://open.higgsfield.ai/models/bytedance/seedance-2.5/reference-to-video/api-reference) accepts image/video/audio references, 4-30 seconds, 480p/720p, MP4/MOV; advertises a starting rate of $0.144/second. No pixel-style guarantee |
| Kling 3.0, with Omni or Motion Control only if needed | Comparison for short composed shots, start/end framing or a specific gesture | [Official guide](https://higgsfield.ai/creator-hub/help-center/ai-models/how-do-i-use-kling) documents those controls. Web features and an API route must be checked separately before submission |
| Wan 3.0, LTX 2.5 Pro, other catalog families | Alternatives if the first comparison fails a concrete requirement | [Current API catalog overview](https://higgsfield.ai/blog/higgsfield-api) lists these families; listing alone provides no evidence they preserve this game's pixel art better |

The generic API overview advertises Seedance 2.5 starting at $0.0738/second and
Kling 3.0 at $0.112/second. That differs from the reference route's starting rate.
Resolution, route, references and configuration matter. Do not combine web-plan
credits, promotional unlimited access and API dollars into one assumed allowance.
Get the exact request estimate and remaining budget before any paid submission.
An advertised minimum is not a safe reservation for an arbitrary request.

The [model developer's page](https://seed.bytedance.com/en/seedance2_5) supports
reference/editing capability as a reason to test. It does not prove style fidelity
on our characters. Higgsfield's surfaces describe different resolution limits;
the selected endpoint's live schema governs the actual request.

## Bounded comparison

Start with two five-second shots using approved references: an ordinary companion
gesture in the home workshop, and Union bots interrupting their routine together.
Compare the same intended action and framing across the two primary candidates.
The second shot tests ensemble consistency without generating the whole wipe.
No finished art exists for these shots yet; do not spend on vague placeholders.

Proposed comparison ceiling: $3 aggregate, within the verified remaining approved
Higgsfield allowance. This is a cap, not a price estimate or a new allowance.
Reserve outstanding request costs; stop if the exact quote cannot fit. No automatic
top-up, speculative retry after a timeout, or new model purchase. Retain request
receipts and resume polling existing jobs before submitting replacements.

Inspect complete clips at gameplay scale and frame by frame: stable silhouette,
proportions, hands, costume, palette, pixel clusters, background geometry and motion.
Reject temporal shimmer, invented insignia, changing weapons, rubber limbs and
photoreal drift. Judge style and clarity directly rather than inventing a numerical
quality score. Record rejected clips and reasons as well as accepted examples.

Use a common low-resolution presentation treatment only after the source motion
works. Quantization and nearest scaling cannot fix identity or geometry drift.
If neither candidate beats a simple in-engine or panel scene, keep that scene.

## Audio and integration

ElevenLabs text-to-speech can supply narration. Its
[timed speech endpoint](https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps)
returns alignment data useful for captions; the existing `tools/audiogen` pipeline
does not yet consume that response. Extend the canonical Rust path deliberately
if needed. Approved localized text remains authoritative, with human review of
pronunciation, timing and meaning. No voice impersonation or provider calls at play time.

`tools/spritegen` currently downloads image results, not videos. Video generation
requires a bounded extension preserving its cost ledger, resumable requests,
URL validation and output checks. Do not treat a video URL as an image or install
a parallel script-based pipeline. Provider docs' SDK examples do not change the
repository's language or dependency policy.

Godot's [core video path](https://docs.godotengine.org/en/stable/tutorials/animation/playing_videos.html)
uses Ogg Theora; generated MP4/MOV is not a drop-in game resource. Verify conversion,
decode cost, size, export and fallback on Windows, Linux and macOS. Test skip,
replay, missing audio/video, text expansion and multiplayer readiness. Scene
playback cannot execute rewards or rescue decisions. Do not call a rendered
movie an integrated, tested campaign scene.
