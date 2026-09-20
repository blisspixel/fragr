# Radio and music canon refresh

**Status:** local pilots produced, 2026-09-19; listening, captions, distribution
review and integration remain. No live assets replaced. Nick requested a rebuilt
talk station and music aligned with the refined world. Radio remains optional
entertainment while playing.
**Canon:** [show formats](../lore/the-frequency.md), [voice](../lore/voice.md),
[world](../lore/README.md). Historical production: [radio-stations.md](radio-stations.md).

## Evidence and limits

The committed manifest contains 140 music tracks across seven stations, 40 spoken
news clips and three news beds/stings. The music specs request 100 vocal tracks
and 40 instrumentals. Source scripts contain 44 original items, including four
match templates, plus 14 later scripts; this is not 58 shipped talk clips.
There are also 12 Chancellor and 10 epilogue manifest entries outside the radio.

Reviewed song directions show a strong arena/meta emphasis: frags, respawns,
scoreboards, killfeed glitches, the same map names and repeated Host sales jokes.
Examples include `radio/hiphop/13-so-back-so-over`,
`radio/country/16-respawn-me-gently` and `radio/edm/16-gold-and-water-filters`.
This is the main mismatch with a larger inhabited world, not proof that every
track is unusable. `radio-news-scripts.json` also predates the two distinct shows.
The epilogue script still prescribes a radio-led static ending with no cutscenes;
it is superseded by the played collapse and coda.

These are source findings, not a listening verdict. The manifest records prompts,
not reliable verbatim lyrics. Actual singing, intelligibility, musical quality,
clipping and unintended phrases need listening review before keep/retire decisions.

## Editorial disposition

| Material | Next action |
|---|---|
| Talk station | Rebuild around the commercial show and separate value-for-value duo; retain a legacy clip only after direct fit and listening review |
| 100 vocal music specifications | Rewrite the library direction toward ordinary lives, work, attachment, independence, absurd institutions and offworld culture. Some league songs can remain as a small recognizable subset |
| 40 instrumental specifications | Audition before replacing; a compatible instrumental need not be regenerated because its prompt mentioned an old map |
| Three news beds/stings | Check show identity and mix; keep only if they support the new voices |
| Chancellor recordings | Audit against the English-to-German opening and accurate captions; do not label an old German-only clip the completed opening |
| Epilogue recordings | Retire as the campaign's mandatory ending. Reuse only a compatible fragment with explicit era and context, without making radio the story's resolution |

Keep genre choice fun. Rock can be defiant or ridiculous; country can tell an
ordinary relationship story; hip-hop can be boastful or observant; dance can be
about dancing. Chill need not mourn the plot. World Service should reflect
specific musical traditions with care. Lock In can be mostly instrumental.
Not every song needs a faction, campaign name, joke, secret or lore lesson.
Pre-wipe music cannot knowingly recount the catastrophe. Aftermath playlists
may reuse older music as surviving culture without turning every station mournful.

## Playback contract

Players choose talk, music, another station or off during normal play. Keep the
choice through ordinary transitions where technically possible. A short scene
may duck radio for essential voice and then restore it. Station browsing and
skipping should not trap the mouse or pause a live server. Caption talk and show
track/program identity; no objective requires finishing a segment. Test solo,
co-op, spectator and agent sessions with the radio muted as well as playing.

The current `client/scripts/radio.gd` and audio settings are the canonical path.
Inspect its manifest selection and scheduling before introducing episode order,
era tags or a new station. A two-person exchange must play in order, not as
randomly shuffled standalone lines. The existing `tts` batch item accepts ordered
`lines` with separate `voice_id` values and renders one multi-voice clip. Use that
path for the duo; the scripts converter also supports host/caller exchanges.

## Production and budget

The existing Rust tool already defaults to `music_v2_5`. Current
[composition-plan documentation](https://elevenlabs.io/docs/eleven-api/guides/how-to/music/composition-plans)
supports explicit sections and lyrics; the repository currently sends prompt-based
music requests. Add typed composition support only if the pilot needs it, preserving
validation, credit limits, manifest receipts and offline tests.

Write complete talk scripts and a small varied set of song pilots first. Produce
staged candidates under gitignored `.agents/`, listen and revise before replacing
the committed library. Do not overwrite existing assets or their provenance with
new prompts. Accepted audio needs its own manifest entry and matching captions.

The read-only quota command now succeeds after the key permission change. The
2026-09-19 check reported 655,335 credits used of 1,447,196, leaving 791,861; reset
is October 6 at 07:51 Pacific. Nick approved using this quota for improved effects,
talk and music. Recheck around each batch, pass an explicit estimate cap, and keep
headroom for retries and other account use. No top-ups or overages. The cap checks
estimates, not provider billing; reconcile actual usage before continuing.

First production pass: two talk pilots capped at 4,000 estimated credits and two
two-minute music pilots capped at 3,600. Candidates stay in `.agents/audio-refresh/`.
The [effects pass](audio-effects-refresh.md) has its own bounded specification.

Published [music model terms](https://elevenlabs.io/eleven-music-model-specific-terms)
restrict music-library/repository distribution on self-serve plans and separately
define restrictions for commercial games across multiple platforms. Applicability
to raw assets in this open repository needs confirmation before public replacement
or bulk generation. A paid plan alone does not establish an Apache-2.0 grant.
Keep the existing historical assets intact while resolving the distribution basis;
do not silently rewrite their legal status or promise unrestricted reuse.

## Completion evidence

Local pilot receipt: two talk clips (89.44 and 77.36 seconds) and two music clips
(120.03 seconds each) decode successfully through FFmpeg. The talk uses one
commercial presenter and a distinct two-voice conversation. The song pilots are
`Last Bus Home` and instrumental `Night Freight`, from the tracked refresh specs.
These are candidates, not approved performances or exact sung transcripts.
All four radio candidates also load in Godot 4.7.2 with nonzero duration. The
isolated check does not prove station integration, captions or the combat mix.
The existing audio tool's 59 offline tests pass; all four new batch specifications
also pass its dry-run validation with explicit caps.

The combined effects/talk/music run moved observed usage from 655,335 to 660,698
credits, leaving 786,498. Provider counters updated after a delay; this account
delta is not an itemized invoice. Logs, manifests and measurements are under
`.agents/audio-refresh/`. The music needs mastering headroom: decoded `Night
Freight` peaks slightly above full scale. Raw outputs remain unchanged.

Per-asset keep/replace decisions after listening; reviewed scripts/lyrics; measured
duration and level/clipping checks; verified budget receipts and distribution basis;
Godot load/playback tests; captions and program order; in-game listening through
combat, menus, scene ducking, station changes and reconnects. A new set of MP3s
without these checks is not a finished radio rebuild.
