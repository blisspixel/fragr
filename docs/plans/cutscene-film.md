# Plan: cutscene film, and the slideshow that comes first

**Status:** planned, deferred (2026-09-25). This plan directs no spend. It sits
downstream of the gate in [campaign-scenes.md](campaign-scenes.md), which
decided the between-mission frame is a full-screen pixel text page first and
that Higgsfield video waits until the playable campaign is built. This file
does not reopen that gate; it is the production plan for what happens on each
side of it: the cheap slideshow that can start once wording is frozen, and the
staged, capped path to film once the campaign itself is done.
**Branch:** `docs/cutscene-film-and-modes` for this plan; one `feat/cutscene-*`
branch per stage.
**Spend:** $0 through stage 0. Stage 1 test clips need an explicit hard cap
from Nick, approved before submission, the same discipline as `agents/brain`
and `tools/spritegen`. Nothing in this document is an approval to spend.

## Goal

Put the story in front of the player as cheaply as possible while the campaign
is still moving, and leave a clean, unwasted path to real film once it is not.
Concretely: freeze scripts and shot lists once per scene, produce a narrated
slideshow from that frozen material at near-zero cost, and reuse the identical
shot list for video later rather than re-authoring the scene twice.

## Non-goals

- Any paid video or image submission. That still needs the campaign-scenes.md
  gate to open and a written cap from Nick for each batch.
- Photoreal or filtered-photoreal frames anywhere, slideshow or film. The
  house style (`plans/higgsfield-pipeline.md#the-finding-that-decides-the-house-style`)
  applies to motion the same way it applies to sprites.
- Reopening the spend gate itself. That decision belongs to campaign-scenes.md.
- Baking essential words into a picture or a clip. `CAMPAIGN.md`'s story
  presentation section already forbids this for the text page; this plan
  extends the same rule to every generated frame.
- Cutscenes deciding anything. Presentation never executes a rescue, a reward
  or an objective; the mission and encounter seams stay authoritative.

## Order: the slideshow first, film at the very end

Video comes last, not first. Before then, every cutscene is a cheap narrated
slideshow: the existing full-screen text presenter (`CampaignOpening`,
`client/scripts/campaign_opening.gd`, keyed copy in `client/i18n/story.en.po`)
shown beside at least one approved Higgsfield key image per scene, with
optional ElevenLabs narration through `tools/audiogen` once that scene's
wording is frozen, per [campaign-scenes.md](campaign-scenes.md) and the
[story presentation contract](../CAMPAIGN.md#story-presentation-and-localization).
A scene with no image is still a complete scene; a missing image degrades to
text exactly the way a missing voice line already does.

Film, when its own gate opens, does not get a second round of writing. It
reuses the same frozen script, the same shot list and the same key images as
first and last frame conditioning (below). The slideshow is not a placeholder
to be thrown away, it is stage 0 and stage 1 of the film pipeline, produced
early because narrated stills are worth having on their own.

## The pixel look is baked into generation, not fixed afterward

The sprite pipeline's lesson applies directly: a generator asked for a
photoreal frame and shrunk or filtered later collapses into mud, because value
contrast, not resolution, is what survives reduction
(`plans/higgsfield-pipeline.md#the-finding-that-decides-the-house-style`). The
same discipline governs motion. Every submitted shot carries:

- **A style prompt block**, one fixed paragraph reused verbatim across every
  request: chunky pixel surfaces, restrained palette, practical light, no
  photographic lighting, no motion blur, no lens artifacts. Drawn from
  [`ART_STORY_BIBLE.md`](../ART_STORY_BIBLE.md#visual-grammar) and
  [`ART-COLOR.md`](../ART-COLOR.md).
- **Palette as named color proportions, never hex.** Models honor a hex code
  poorly and drift toward whatever they associate with the nearest named
  color; a proportion block does not. Each shot's palette line names roles
  from [`palette.json`](../palette.json) with a rough share of frame, in the
  same voice `ART-COLOR.md` already uses for faction color: for a Union shot,
  mostly black and dark steel with a restrained red accent; for a free-side
  shot, bone and warm leather with rust and ember, a purple outline note, and
  a small personally chosen cyan or magenta accent; for an Inheritance shot,
  matte bone over ink with a minimal muted cyan working indicator. No new
  swatches invented per prompt.
- **Faction style reference images**, one small approved board per faction
  (Union, free coalition, Inheritance) built from the same faction table in
  `ART_STORY_BIBLE.md#factions-places-and-continuity`, submitted as image
  references on every shot involving that faction.
- **Character reference sheets: four-angle turnarounds** (front, three-quarter,
  side, back) per named cast member who appears on screen, extending the
  existing [character reference contract](../ART_STORY_BIBLE.md#character-reference-contract)
  from a still-image requirement to a motion one. Approved before any shot
  using that character is submitted.
- **A fixed verbatim trait block per character.** The exact silhouette and
  palette anchor line from [`cast.md`'s visual continuity table](../lore/cast.md#visual-continuity)
  goes into every prompt for that character, unparaphrased, every time. Latch
  is always "practical midweight agent chassis, unequal repaired forearm
  plates, worn bone/dark steel, small muted cyan patch," word for word,
  whether the shot is a slideshow still or a video clip. Paraphrasing a trait
  block between shots is exactly the kind of drift a fixed block exists to
  prevent.
- **First and last frame conditioning from approved stills.** The scene's key
  images (the same ones the slideshow already uses) anchor the first and last
  frame of any video shot that replaces them, so film and slideshow never
  diverge in composition.
- **Chaining shots.** One shot's last frame becomes the next shot's first
  frame condition. This is how continuity is bought across a cut without
  relying on the model's memory, and it is the same match-cut discipline the
  rescue-reveal shot (below) depends on.
- **Three to seven targeted negative prompts, where the model supports them.**
  Push against photoreal shading, baked ambient occlusion and specular
  highlights (the same albedo-only argument `plans/art-pipeline.md#the-rendering-contract`
  makes for sprites), invented insignia, modern-day objects, extra limbs,
  visible text, logos or watermarks, and lip-sync artifacts on any face not
  actually speaking on camera.
- **No reliance on seeds.** Neither the models on offer nor Higgsfield's route
  to them exposes a seed that reliably reproduces a result, unlike the sim's
  seeded, deterministic throws. Consistency has to come entirely from
  reference images, the fixed trait block, negative prompts and frame
  chaining, never from "the same seed worked last time."
- **No text inside a generated frame, ever.** All text is an engine caption.
  This is not a new rule: `CAMPAIGN.md` already says essential text is never
  baked into an image or video, and the M01 opening's storyboard already keeps
  essential words out of baked text
  (`campaign/m01-recall-notice.md#opening-storyboard`). This plan removes the
  word "essential": no text at all belongs in a generated frame, including
  incidental signage, because a model cannot render legible in-world text at
  this resolution and a caption already owns that job.

## Shot grammar

| Shot | Use | Reference |
|---|---|---|
| Establishing wide | One per place, sets scale and light before any face appears | Half-Life shows a place before it says anything about it |
| Character close-up at in-game pixel scale | Match the resolution a player already reads that character at in gameplay, never a sudden higher-fidelity face | The stylized-sprite finding: fidelity that does not survive scale is wasted spend |
| Union procedure insert (three shots) | Queue lane, a stamped document, hands and boots | Regime menace through procedure, not a speech (Wolfenstein: The New Order); matches the game's own disarmament-bin and quota-chalkboard props (`campaign/story-arc.md#show-dont-tell`) |
| Rescue reveal, match cut | Confinement cuts to open space on matching motion or framing | The chained last-frame-to-first-frame technique above, used for its clearest payoff |

**Faction color per shot.** The Union: black, dark steel and restrained red.
The free side: bone, leather, rust and ember, with purple and cyan accents.
The Inheritance: matte bone over ink, with muted cyan. These are the same
three rows as `ART-COLOR.md#faction-colour`, restated here as a shot-level
checklist rather than a material spec.

## Cutscene craft rules (research, 2026-09-25)

- **Few scenes, at real turning points.** Doom II tells its whole story in
  four text screens across thirty levels
  ([Doom Wiki, DOOM II](https://doomwiki.org/wiki/DOOM_II)). A scene earns its
  place by marking a turn, not by covering a level.
- **Routine scenes under two minutes, big ones under five, shots four to six
  seconds.** Long scenes are where a narrated slideshow and a budget both die.
- **Show, never narrate.** Half-Life never takes the camera from the player to
  deliver a line a room could say instead
  ([Half-Life, Wikipedia](https://en.wikipedia.org/wiki/Half-Life_(video_game))).
  This is the same rule `campaign/story-arc.md#show-dont-tell` already holds
  every level to; cutscenes do not get an exception.
- **Regime menace through procedure imagery, never a speech.** Wolfenstein:
  The New Order sells the regime through paperwork, queues and inspection, not
  monologue
  ([Wolfenstein: The New Order, Wikipedia](https://en.wikipedia.org/wiki/Wolfenstein:_The_New_Order)).
  The Union procedure insert above is this lesson as a shot list.
- **Ambiguity by omission, for the wipe.** Signalis withholds explanation and
  lets absence carry the dread
  ([Signalis, Wikipedia](https://en.wikipedia.org/wiki/Signalis)). The wipe's
  onset scene should cut away before it explains itself, the same restraint
  `ART_STORY_BIBLE.md` already asks of the wipe's presentation.
- **One unbroken establishing move can beat many cuts.** The Unreal flyby
  opening sells scale with a single continuous camera move rather than a
  montage ([Unreal, Wikipedia](https://en.wikipedia.org/wiki/Unreal_(video_game))).
  Worth one experimental long take per act before defaulting to cut coverage.
- **Avoid cheap photorealism.** Blood's full-motion-video cutscenes are the
  part of that game that aged worst, next to pixel art that still reads today
  ([Blood, Wikipedia](https://en.wikipedia.org/wiki/Blood_(1997_video_game))).
  This is the same argument the sprite pipeline already settled; cutscenes do
  not get to relitigate it.

## Staged spend

Nothing is wasted because nothing later stage depends on redoing earlier work.

- **Stage 0, free.** Frozen scripts (the same beat-table format as the M01
  opening storyboard, `campaign/m01-recall-notice.md#opening-storyboard`),
  shot lists built from the grammar above, faction and character reference
  sheets, palette proportion blocks, and one fixed trait block per on-screen
  character. All local documents and art direction. No API call.
- **Stage 1, three to five test clips on the cheapest model first.** An
  establishing wide, a close-up and an action shot on Wan 3.0 at 480p (about
  $0.025 to $0.05 per second), plus one hero comparison of the same shot on
  Seedance 2.5. Each submission carries its own hard cap that Nick approves
  before it goes out, priced first the way `tools/spritegen`'s estimate step
  already prices images. Nick reviews the results before anything else runs.
- **Stage 2, one full scene**, only if the stage 1 tests pass review on style,
  consistency and cost.
- **Stage 3, the remaining scenes, one approval at a time.** Stop at the first
  sign that quality or cost is slipping rather than finishing a batch on
  momentum.

## Model facts (researched 2026-09-25, re-verify before spending)

Higgsfield's API bills a separate USD balance from web subscription credits,
pay-as-you-go with no subscription required, and funds do not carry meaning
across that boundary: a web plan's unlimited generations do not touch the API
balance and API dollars do not unlock web-only resolutions
([Higgsfield API](https://higgsfield.ai/blog/higgsfield-api)).

| Model | Duration | Resolution / route | References | Notes |
|---|---|---|---|---|
| Seedance 2.5 | 4 to 30 s | 480p/720p via API; 1080p is web-app only | First/last frame plus up to 30 image references | Native audio; about $0.144/s at 480p and $0.324/s at 720p promotional, about $0.206 and $0.462 after roughly 2026-10-01 ([API reference](https://open.higgsfield.ai/models/bytedance/seedance-2.5/reference-to-video/api-reference), [how do I use Seedance](https://higgsfield.ai/creator-hub/help-center/ai-models/how-do-i-use-seedance)) |
| Kling 3.0 | 3 to 15 s | Standard | Element references lock character identity across a scene | About $0.046/s standard promotional, $0.084 after; favor silhouette over lip sync ([how do I use Kling](https://higgsfield.ai/creator-hub/help-center/ai-models/how-do-i-use-kling)) |
| Wan 3.0 | 2 to 30 s | Up to 1080p | Fewer reference fields on Higgsfield's route than Seedance or Kling | About $0.025/s at 480p, $0.05 after; the cheapest route by far |
| LTX 2.5 | | | | Explicit camera movement and fps controls, useful where a shot needs a named move rather than whatever the model defaults to |
| Veo 3.1 | | | | Web-app only; not part of Higgsfield's API catalog as checked |

**Cost model, 22 scenes of 30 to 90 seconds, three takes per kept shot:** Wan
480p about $50 to $149; Kling standard about $91 to $274; Seedance 480p about
$285 to $855; Seedance 720p about $641 to $1,922. About $100 buys the entire
campaign's cutscenes on Wan 480p, or roughly four scenes on Seedance 480p.

**Recommendation by shot type:** establishing wides on Wan (cheapest, and
wides ask the least of any single model); dialogue close-ups on Kling with
element references, favoring silhouette and gesture over lip sync since none
of these models is being asked to nail a mouth; action on Seedance
reference-to-video, where its larger reference budget and native audio earn
their price.

These prices, routes and reference limits are a snapshot. Re-check the live
estimate endpoint and the current model catalog before any submission, the
same discipline `plans/higgsfield-pipeline.md` already requires for images.

## Licensing and policy gates before any spend

- Higgsfield's own terms do not restrict commercial use of outputs and allow
  transferring or sublicensing them to a client
  ([who owns my generations, and can I use them commercially](https://higgsfield.ai/creator-hub/help-center/account/who-owns-my-generations-and-can-i-use-them-commercially)),
  but that page says nothing about whether it flows down the terms of the
  underlying model providers. Treat the underlying provider's terms as
  binding until confirmed otherwise.
- Kling's own terms may separately require permission or branding for
  commercial use; unverified against [Kling's own terms](https://klingai.com)
  as of this research and must be checked before any Kling submission ships
  in the game.
- ByteDance's (Seedance) and Alibaba's (Wan) own output terms are unverified.
- Higgsfield may apply a provenance watermark to outputs; confirm whether it
  survives this pipeline's palette quantization and downscale before it
  matters.
- Higgsfield's content filters cover copyright, IP and political material
  (the help center documents flags for both;
  [why was my generation blocked for copyright or IP](https://higgsfield.ai/creator-hub/help-center)
  lists this as an active policy), and Union propaganda shots (the sanctioned
  games stadium address, the ceremonial avenue) resemble real-world fascist
  imagery closely enough by design that a filter may reject them. Ask
  Higgsfield support before submitting any such shot, rather than discovering
  a rejection mid-batch.

## Integration

No new engine feature is needed for stage 0 or the slideshow: the shipped
`CampaignOpening` presenter already shows keyed text and already tolerates a
missing voice line, per the M01 opening (`plans/m01-opening.md`, shipped in
#193). Showing an approved key image alongside that text is the smallest
addition once stage 1 produces one. Film integration reuses the Godot video
research already logged in campaign-scenes.md: Ogg Theora is the native path,
generated MP4/MOV needs verified conversion, and skip, replay, missing audio
and multiplayer readiness all need their own tests before a clip ships
(`plans/campaign-scenes.md#audio-and-integration`). None of that is required
before stage 0 or stage 1.

## Verification

- Stage 0 deliverables (scripts, shot lists, reference sheets, trait blocks)
  reviewed by Nick and recorded in this plan before stage 1 opens.
- Stage 1 submissions priced against the live estimate endpoint first, capped
  in the same ledgered pattern `agents/brain` and `tools/spritegen` already
  use, with a receipt kept before generation.
- Every returned clip inspected frame by frame for stable silhouette,
  proportions, palette, pixel clusters and motion, using the same rubric
  `campaign-scenes.md#bounded-comparison` already sets out; reject temporal
  shimmer, invented insignia, drifting weapons and photoreal drift.
- No Godot integration test is required until a clip actually reaches the
  presenter; that step gets the headless checks the evidence table already
  requires for client presentation (`AGENTS.md`'s evidence-by-change-type).

## Success criteria

- [ ] Stage 0 groundwork committed: frozen scripts, shot lists, faction and
      character reference sheets, palette proportion blocks and one fixed
      trait block per on-screen character.
- [ ] Stage 1's three to five test clips priced and capped, with Nick's
      written approval on file before any of them is submitted.
- [ ] A written answer from Higgsfield support on political-imagery filters
      before any Union propaganda shot is generated.
- [ ] One full scene (stage 2) produced only after stage 1 passes review on
      style, consistency and cost.
- [ ] Film never precedes the slideshow it replaces; every video shot reuses
      its slideshow's script, shot list and key images unchanged.

## Open questions for Nick

1. The exact hard cap for stage 1, per clip and in aggregate.
2. Whether a Kling branding requirement, if confirmed, is acceptable for a
   shipped scene, or rules Kling out for anything player-facing.
3. Whether to submit the political-imagery question to Higgsfield support now,
   at stage 0, or wait until a propaganda shot is actually queued in stage 1.

## Sources

Checked 2026-09-25.

- [Higgsfield API](https://higgsfield.ai/blog/higgsfield-api): model catalog,
  USD balance separate from web credits, pay-as-you-go billing.
- [Seedance 2.5 API reference](https://open.higgsfield.ai/models/bytedance/seedance-2.5/reference-to-video/api-reference):
  duration, resolution options, reference and audio fields.
- [How do I use Seedance](https://higgsfield.ai/creator-hub/help-center/ai-models/how-do-i-use-seedance):
  up to 1080p on web plans, up to 50 references on the web route.
- [How do I use Kling](https://higgsfield.ai/creator-hub/help-center/ai-models/how-do-i-use-kling):
  3 to 15 second duration, Elements for character identity.
- [Who owns my generations, and can I use them commercially](https://higgsfield.ai/creator-hub/help-center/account/who-owns-my-generations-and-can-i-use-them-commercially):
  Higgsfield's own commercial-use and sublicensing terms.
- [Higgsfield help center](https://higgsfield.ai/creator-hub/help-center):
  content-flagging and copyright/IP policy articles.
- [Kling AI](https://klingai.com): Kling's own terms, unverified for a
  commercial branding requirement as of this research.
- [Doom Wiki, DOOM II](https://doomwiki.org/wiki/DOOM_II): four text screens
  across thirty levels.
- [Half-Life (Wikipedia)](https://en.wikipedia.org/wiki/Half-Life_(video_game)):
  show, never narrate.
- [Wolfenstein: The New Order (Wikipedia)](https://en.wikipedia.org/wiki/Wolfenstein:_The_New_Order):
  regime menace through procedure.
- [Signalis (Wikipedia)](https://en.wikipedia.org/wiki/Signalis): ambiguity by
  omission.
- [Unreal (Wikipedia)](https://en.wikipedia.org/wiki/Unreal_(video_game)): the
  unbroken establishing flyby.
- [Blood (Wikipedia)](https://en.wikipedia.org/wiki/Blood_(1997_video_game)):
  full-motion-video cutscenes aged worst.
