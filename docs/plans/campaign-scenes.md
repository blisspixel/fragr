# Campaign scene production: audio slideshows

**Status:** in flight, 2026-09-25. The scene player, its manifest format, the
migrated M01 opening and a text-only draft of the scene after Recall Notice are
implemented and tested. On 2026-09-26 two stills from an earlier paid opening
batch were wired into the opening ([salvaged opening assets](#salvaged-opening-assets-2026-09-26));
no new image, narration clip, ambience or music has been generated for any
scene. **Every generation batch below needs
Nick's go-ahead for that batch, with an explicit cap.** The
[campaign contract](../CAMPAIGN.md#story-presentation-and-localization) owns
presentation behavior, the [story arc](../campaign/story-arc.md) owns what
happens, and each [level design](../campaign/README.md) owns its level. This
file owns the scene format, the production workflow, the scene list and costs.

**Direction, Nick, 2026-09-25:** between levels the campaign plays an audio
cutscene, and the near-term format is the cheap one that tells the same story:
a narration script voiced through ElevenLabs (`tools/audiogen`) plus at least
one Higgsfield image per scene (`tools/spritegen`), shown by the scene player
with captions. One key image per scene, a few more only for the big beats. You
can skip anything, and it is really well done. Standing rules: show, don't tell
(a scene is short and never explains what the level just showed); radio is
minor, and a scene is not radio; the Union reads plainly as a Fourth Reich and
is never named as one; the player is the free human or free agent and never
speaks.

This replaces the 2026-09-22 text-first gate. One image and a minute of voice
are cheap enough to redo when a level changes, and the scene falls back to
text whenever an asset is missing. Video is much later and has its own plan,
[`cutscene-film.md`](cutscene-film.md).

## What is built

| Piece | Home | Behavior |
|---|---|---|
| Manifest format and validation | `client/scripts/story_scene.gd` | Strict JSON under `client/assets/story/scenes/<id>.json`; unknown fields, unsafe paths and out-of-range values are refused |
| Scene player | `client/scripts/scene_player.gd` | Stills with nearest filtering and a subtle pan or zoom, keyed captions with speaker labels, narration on the `Voice` bus, optional music and ambience beds, a progress row |
| M01 opening | `client/scripts/campaign_opening.gd`, `scenes/opening.json` | The five keyed beats on the shared player, reader paced until narration exists; HOME, CHOICE and PURSUIT show stills, ADDRESS and RECALL are text pages; unchanged readiness handoff through GameManager |
| Departure hook | `GameManager.play_departure_scene` | Once the server reports a mission `departed`, the local campaign plays the scene named in `StoryScene.AFTER_MISSION`, once per mission per session. It sends nothing to the server |
| First interlude draft | `scenes/l01_l02.json`, keys in `story.en.po` | Recall Notice to Persons Unknown, three shots, text only |
| Settings | `settings.gd`, `settings_panel.gd`, `default_bus_layout.tres` | Audio page gains VOICE (the new `Voice` bus) and STORY CAPTIONS |
| Packaging | `export_presets.cfg`, `install_check.gd` | Manifests are in the export filter; the packaged install check fails if the opening manifest is missing |

Controls. Next, Back and Skip are buttons with keyboard, mouse and gamepad
focus; Enter or A activates, Escape or B skips the whole scene, Page Up and Page
Down or LB and RB scroll long text, C or Y toggles captions, and a click on the
still advances. A scene consumes every input while it is open, like the
opening, so nothing underneath reacts. GameManager still waits for release
before acknowledging the opening. The opening replays from the Single Player
menu as before; replaying a between-level scene from the menu waits for a
record of which scenes a run has reached, so the menu cannot spoil later ones.

Timing. A shot with `"timing": "narration"` advances itself when its clip ends,
after `hold` seconds. A shot without a loadable clip is reader paced. The last
shot never finishes itself: leaving a scene is always the player's input.
Captions show by default and hide only while a clip is actually speaking; a
text-only shot always shows its text.

Fallback. A missing still gives the plain text page the opening has today. A
missing clip gives a reader-paced shot. An invalid manifest reports a warning
and completes at once, so a broken file never holds a player or a party. The
opening additionally rebuilds its five keyed pages if its manifest cannot load.

Evidence: `test_story_scene`, `test_scene_player` and the unchanged
`test_campaign_opening` harnesses, the full `tools/godot_check.sh` run and
`tools/test_godot_check.sh`, and a rendered still from
`client/scripts/qa_story_scene.gd` (placeholder banner art, a speaker caption
and the progress row) inspected at 1280x720. `-- --scene opening --shot N` renders a committed shot; shots 1, 3 and 5 of the opening were captured and inspected on 2026-09-26.

## Manifest format

```json
{
  "format": 1,
  "id": "l01_l02",
  "title_key": "STORY_L02_TITLE",
  "skip_key": "STORY_SKIP_SCENE",
  "ambience": {"path": "res://assets/story/ambience/l01_l02.ogg", "volume_db": -14},
  "music": {"path": "res://assets/story/music/episode_1.ogg", "volume_db": -12},
  "shots": [
    {
      "id": "LEDGER",
      "caption_key": "STORY_L01_L02_LEDGER",
      "speaker_key": "STORY_SPEAKER_MARA",
      "title_key": "STORY_M01_HOME_TITLE",
      "image": "res://assets/story/stills/l01_l02/key.png",
      "motion": {"kind": "zoom_in", "amount": 0.05},
      "narration": "res://assets/story/voice/{locale}/l01_l02/ledger.mp3",
      "timing": "narration",
      "hold": 1.0
    }
  ]
}
```

| Field | Rule |
|---|---|
| `format` | `1`. A later field, such as a per-shot video, bumps it |
| `id` | Lowercase letters, digits and underscores; equals the file name |
| `title_key`, `skip_key` | Optional catalog keys for the header and the skip button |
| `music`, `ambience` | Optional beds: `path` (ogg, mp3 or wav under `res://assets/`) and `volume_db` from -40 to 0. Music plays on the Radio bus (the MUSIC setting), ambience on Effects |
| `shots` | 1 to 24 shots, unique uppercase `id`s |
| `caption_key` | Required. Every word on screen is a catalog key; nothing is baked into a picture or a clip |
| `speaker_key`, `title_key` | Optional catalog keys; a speaker label is shown with its line |
| `image` | Optional png under `res://assets/`. Missing file: text page |
| `motion` | `kind` is none, zoom_in, zoom_out, pan_left, pan_right, pan_up or pan_down; `amount` 0 to 0.15 (default 0.06) |
| `narration` | Optional clip under `res://assets/`; `{locale}` resolves to the current locale, then its language, then English, then silence |
| `timing` | `reader` (default) or `narration` (needs a `narration` path) |
| `hold` | 0 to 5 seconds after the clip before advancing (default 0.8) |

Stills are full-frame pixel art made for a 640x360 canvas and shown with
nearest filtering, cropped to cover the window. Captions, speaker labels and
titles live in `client/i18n/story.en.po` and follow the
[localization plan](localization.md): English voice with localized captions
until a per-language voice pass is approved.

One key image can carry a whole scene: every shot in the manifest names the
same still, each with its own caption and narration clip, and the player keeps
one slow drift across them instead of restarting it. A big beat adds a second
still as its own shot.

## Writing rules for every scene

1. **Show, don't tell.** A scene is one picture, a short narration and a
   line or two of dialogue. It shows what changed or what is at stake next,
   in concrete things: a name on a list, a stamp, an empty seat. It never
   recaps the level, never explains the Union, never names a theme. If the
   narration says something the picture already shows, cut it.
2. **Short.** 30 to 90 seconds, two to five narration beats of about twelve
   words each, at most two spoken character lines. Episode transitions may
   run to 90 seconds; everything else aims at 30 to 45.
3. **One narrator, few voices.** A single narrator reads every scene in the
   present tense, plain and close, never omniscient about causes. Characters
   speak their own short lines. The player never speaks. Voss and the Office
   speak only from screens and PA, never as narrator. The Host appears at most
   once (after level 15).
4. **The Union is felt, never named.** Black and red, armbands, forms,
   countersignatures, calm procedure, English that slips into German twice in
   the whole campaign. No real insignia, no real names, no cartoon.
5. **Consequences are faces.** A rescued person shows up doing something; an
   absence is an empty chair. Optional rescues (Edda, Splice, Orrin) need a
   variant beat, which waits for run-state conditions in a later format.
6. **Sound captions.** Essential sound gets a bracketed caption, so a scene
   plays muted.

## Per-scene workflow

Each scene moves through these steps in order. A later step never starts on
unfrozen wording.

1. **Freeze the script.** Write the scene's shots from this list and the story
   arc into its manifest and `story.en.po`, text only. Play it in the game as a
   text slideshow and get Nick's approval of the words. The committed text
   version is the fallback forever.
2. **Voice (ElevenLabs through `tools/audiogen`).** Cast from the account's
   current default voices (`voices`; defaults retire at the end of 2026, so
   cast from the live list, never from old ids), no impersonation of real
   people. One `tts` spec per scene under `tools/audiogen/specs/story/`, one
   item per spoken shot, names matching the manifest paths. Run `quota`, then
   `--dry-run` for the estimate, then generate with an explicit
   `--max-credits` cap into `.agents/story-audio/`. Listen, retake within the
   cap, then promote accepted clips to
   `client/assets/story/voice/en/<scene>/<shot>.mp3` with their manifest
   entries. Voss's German needs a fluent review before recording.
3. **Images (Higgsfield through `tools/spritegen`).** Character reference
   sheets come first and are approved once: the player (body neutral), Latch,
   Mara, Tern, Edda, Splice, Renn, Sorrel, Voss, Kessel, and one Union bot and
   one Enforcer, each on the [cast anchors](../lore/cast.md#visual-continuity)
   and the [art bible](../ART_STORY_BIBLE.md). Each scene's key image request
   then passes the relevant sheets as `image_urls` references, so faces and
   kit stay on model. Price with `price`, generate with an explicit
   `--max-spend-usd` (capped at five dollars per run by the tool) and the
   request ledger; explore at `low`, promote the keeper at `medium`. Reduce
   locally to the 640x360 canvas and quantise against `docs/palette.json`.
   Stylised prompts only: the
   [pipeline finding](higgsfield-pipeline.md#the-finding-that-decides-the-house-style)
   shows photoreal renders collapse when reduced.
4. **Integrate and review.** Drop the files at the manifest paths. Run the
   scene harnesses and the capture, then watch the whole scene in the game
   with sound on and with sound off. Reject drift in a character, invented
   insignia, text baked into a picture and anything that reads as a real
   organization.
5. **Metadata.** Committed images and clips carry no generator, tool or model
   credit in embedded metadata. The reduction step writes fresh pngs; check
   clips for provider tags and strip them in the Rust tool before commit if
   present. Provenance lives in the generation manifests, which may name the
   developer integration used.

**Spend gate.** Nothing is generated without Nick's written go for that batch,
naming the batch, its cap and its account. Each batch verifies live quota and
price first, passes the explicit cap, records the ledger or manifest, and never
enables top-ups or overages. The repository's $50 total cap and the five-dollar
per-run spritegen ceiling stand. Paid calls never run in CI or at player
runtime. Before the first stills batch, `tools/spritegen` needs the reference
preparation it lacks today (local reference upload and ownership checks,
[pipeline notes](higgsfield-pipeline.md#what-is-not-done-yet)); that is code
work at no cost.

## The scene list

Twenty-three scenes: the opening, one between each pair of the twenty levels,
and three for the endings. Names are working titles. The key image is the one
picture the scene needs; the narration column gives the beats, with quoted
character lines and bracketed sound captions. Nothing here is frozen until
step 1 above.

### Episode I: Recall

| # | Scene | Key image | Narration and lines | Extra images | Length | Voices |
|---|---|---|---|---|---|---|
| 0 | **Opening** (before 1, built as text) | The shared workshop bench: two mugs, one charging cable, Latch's repaired forearm in the lamp light | The five existing pages: home; Latch refuses the contract, then carries the pump to the clinic; the address; the recall; the intake address. Voss: "Every restriction is a promise." Then German, then the cheer | Voss at the podium; the recall at the workshop door; the notice held up against the annex | 60 s | Narrator, Voss, Latch, Mara |
| 1 | **One Shift** (1 to 2, drafted as text) | The ledger open on a knee in a dark van, last line in Latch's hand | "Last line, in Latch's hand: You 3. Me 3." Mara: "Correction starts at shift change. We have one shift." "Correction ward, second shift. The frame is already warm." | None | 30 s | Narrator, Mara |
| 2 | **The Spur** (2 to 3) | Latch at a gallery window, freight yard below, the red mast on the skyline | A list on a clipboard, a tick beside Low Water. Mara's handset says no signal. Latch, at the sealed cars: "Those aren't empty." | None | 35 s | Narrator, Latch |
| 3 | **Home, Briefly** (3 to 4) | Low Water's market board at dawn: a tram paint vote, and a fresh notice pasted over it | The freed train comes in at dawn. Three paint colors, all crossed out. Edda switches on the clinic sign. The same signature at the bottom of the notice | None | 40 s | Narrator, Edda |
| 4 | **What We Can Carry** (4 to 5) | A packed bag by the clinic shutter, the ledger on top | Mara, not meeting your eye: "The aid is two hours out." Across the roofs, one light still on in Splice's workshop | None | 35 s | Narrator, Mara |
| 5 | **Passengers** (5 to 6, episode) | The freight platform board: names, some rows blank | Sorrel's tram cab, empty, a cap on the seat. Tern, hatch open: "Sit down. Touch nothing." Latch counts heads, twice. Earth gets small in the port | Tern's ship in a field at night, hatch lit | 75 s | Narrator, Tern, Latch |

### Episode II: Custody

| # | Scene | Key image | Narration and lines | Extra images | Length | Voices |
|---|---|---|---|---|---|---|
| 6 | **Declared** (6 to 7) | Through customs glass: a family's luggage tagged, a stamp coming down | DECLARED. A townsperson in a doorway: "Up through the town. Don't stop in the square." The depot tower across the crater | None | 35 s | Narrator, a townsperson |
| 7 | **Custody** (7 to 8) | Latch's finger on a custody manifest | A Low Water name. The same signature. Latch: "Some of them are here." | None | 35 s | Narrator, Latch |
| 8 | **Authorized Noise** (8 to 9) | An empty freight car arriving exactly on time, the panel beside it | "Authorized noise. No action required." Renn in the archive doorway, coat without its rank. A berth manifest: one ship, impounded | None | 40 s | Narrator, Renn |
| 9 | **Own Deck** (9 to 10, episode) | Tern's hands back on their own controls, the Moon falling away | People claim corners of the hold. An agent grumbles that a human needs a whole room to sleep. A chassis patched with clinic staples | The long window, stars moving | 75 s | Narrator, Tern, an agent passenger |

### Episode III: Common Cause

| # | Scene | Key image | Narration and lines | Extra images | Length | Voices |
|---|---|---|---|---|---|---|
| 10 | **Alongside** (10 to 11) | The Union tender riding alongside, lit and orderly, through the long window | Tern eases the Carrier closer: "They'll call the blockade. Unless they're busy." Latch lays mines out on a crate | None | 40 s | Narrator, Tern |
| 11 | **In Transfer** (11 to 12) | The transfer hold: a line painted on the floor, Sorrel standing in it | Sorrel recites a procedure. Latch's hand on Sorrel's shoulder. A draft order on the desk: Harmonised Custody Schedule. Mars in the window | None | 45 s | Narrator, Sorrel, Latch |
| 12 | **Six Declarations** (12 to 13) | A crate with six declarations of independence chalked on it, one amended | Real trucks at the depot. An organizer, tired: "Fine. All of us, then." The foundry glows on the horizon | None | 35 s | Narrator, a Martian organizer |
| 13 | **Asked** (13 to 14) | Workers in a quarters doorway, Latch holding out a tool, not a key | Some take it. One shakes their head and sits back down, and Latch nods. The freight lift climbs into daylight | None | 35 s | Narrator, Latch, a worker |
| 14 | **Homecoming** (14 to 15, episode) | Earth filling the window as the ships lift | The stadium city at night. Numbered placards stacked in a tunnel. Latch, quiet: "We're home." | The podium, still dressed for ceremony | 75 s | Narrator, Latch |

### Episode IV: Reckoning

| # | Scene | Key image | Narration and lines | Extra images | Length | Voices |
|---|---|---|---|---|---|---|
| 15 | **Pirate Track** (15 to 16) | The stadium screen: Voss mid-address, the honest subtitle track under her | Entrants wheel motorcycles out of the tunnel. The Host, one line, over a stadium speaker. The avenue ahead, the Office tower at its end | None | 35 s | Narrator, the Host |
| 16 | **Forecourt** (16 to 17) | The Office doors, heavy and plain, the rattlesnake banner on a lamppost | Every light on the avenue behind you is green. A form blows across the steps, the signature on it | None | 30 s | Narrator |
| 17 | **Receipt** (17 to 18, episode) | A table with confiscated command keys and a receipt pad, Kessel's pen squared to the edge | Weeks later. A delivery van in the recovery square, people rebuilding. Latch tunes a tram motor, humming. A Union bot sweeps the square, as it always has | The recovery square in morning light | 75 s | Narrator, Latch |

### Episode V: Inheritance

| # | Scene | Key image | Narration and lines | Extra images | Length | Voices |
|---|---|---|---|---|---|---|
| 18 | **One Rhythm** (18 to 19) | From the overlook: rows of machines all facing the same way | [one rhythm, everywhere]. A supervisor's handset, no answer. Latch beside you, still Latch, looking at their own hands | Latch's hands, close | 30 s | Narrator |
| 19 | **Even** (19 to 20) | Latch walking away with the free agents toward the waterworks | The ledger in your hand, a new line: "Hold them." The pier ahead, people waiting | None | 30 s | Narrator |

### Endings

| # | Scene | Key image | Narration and lines | Extra images | Length | Voices |
|---|---|---|---|---|---|---|
| 20 | **Water Around a Stone** (survival, 20 to Still Here) | The machines stopped at the refuge line | Then they flow around it like water around a stone, and on to the next district. The forecast fragment on a salvaged screen. Latch comes back along the pier | Latch at the end of the pier | 60 s | Narrator, Latch |
| 21 | **Still Here** (after the epilogue, into credits) | The refuge years later, green, Sorrel in the repaired tram cab | The ledger, closed. Latch: "I stopped counting." One frame of a deep-space anomaly, no explanation | The anomaly | 60 s | Narrator, Latch |
| 22 | **The Last Page** (exhaustion, into credits) | The refuge holding, without you | The Moon, Mars, the ships, a healing Earth. The ledger open to its last page, one more line in Latch's hand, and no score. The anomaly | The worlds in one wide frame; the ledger's last page | 90 s | Narrator |

Totals: 23 scenes, 23 key images and 12 extras (35 images), about 18
minutes if every scene ran to its target. A player sees 21 or 22 of them (one
ending), about 17 minutes over a four-hour run, and can skip every second.

## Cost estimate

Prices are the measured and published rates already in this repository,
checked on the dates given; recheck live before any batch.

**Narration and lines (ElevenLabs, existing subscription quota).** Speech is
one credit per character on the v3 model (the `tools/audiogen` estimate). A
scene script averages about 60 words (360 characters); the opening is about
700 and each ending about 500, plus about 1,500 characters of character lines:
roughly 10,500 characters. Three takes gives about 32,000 credits.

| Item | Basis | Estimate |
|---|---|---|
| Narration and lines | 10,500 characters, 3 takes, 1 credit per character | 32,000 credits |
| Ambience beds (optional) | 23 loops of 20 seconds at 40 credits per second (2026-09-19) | 18,400 credits |
| Episode music (optional) | 5 beds of 90 seconds at 900 credits per minute | 6,750 credits |
| Total | | about 57,000 credits; 32,000 for voice alone |

The 2026-09-19 quota check left 791,861 credits with a reset on October 6, so
the whole set is about 7 percent of one cycle, with no added dollars inside the
subscription. Music beds stay blocked until the distribution question in the
[radio plan](radio-refresh.md) is settled; scenes work without them.

**Images (Higgsfield `marketing-studio/image`, measured 2026-09-19).** Explore
four candidates at `low` ($0.019 each), promote the keeper at `medium`
($0.100): $0.176 per finished image.

| Item | Count | Cost |
|---|---|---|
| Reference sheets | 12 subjects, 6 candidates each, 1 keeper | $2.57 |
| Key images | 23 | $4.05 |
| Big-beat extras | 12 | $2.11 |
| Retakes | 20 percent of the 35 again | $1.23 |
| Total | | **about $10** |

The minimum that still tells the story, one key image per scene and eight
reference sheets at four candidates each, is about **$5.50**. Both fit the
roughly $14 of Higgsfield credit recorded in the
[local excellence plan](local-excellence.md) and the $50 repository cap.

| Batch | Contents | Cap |
|---|---|---|
| S0 | Reference sheets | $3.00 |
| S1 | Opening and Episode I key images (0 to 5), 4 extras | $2.50 |
| S2 | Episode II (6 to 9), 1 extra | $1.50 |
| S3 | Episode III (10 to 14), 1 extra | $1.50 |
| S4 | Episodes IV and V (15 to 19), 2 extras | $1.50 |
| S5 | Endings (20 to 22), 4 extras | $1.50 |
| V1 to V6 | Narration per episode and the endings, after that batch's images | 7,000 credits each |

## Salvaged opening assets (2026-09-26)

An older, unmerged branch paid for five opening stills (Higgsfield
`marketing-studio/image`, `low`, $0.145 estimated within a $0.15 cap) and three
narration takes (ElevenLabs `eleven_multilingual_v2`, inside the subscription
quota) on 2026-09-22. Each was checked against the current art bible and the
current keyed copy before anything landed.

**Stills.** Two fit and are wired; three are held as regeneration references in
`client/art/story/opening/`, which is excluded from import and export. Both
directories carry a provenance manifest (exact prompt, model, request, hashes)
and a README.

| Still | Shot | Verdict |
|---|---|---|
| Workshop (Latch at the bench) | HOME, CHOICE | Fits: Latch on model, the player offscreen, no lettering, lower quarter quiet for captions. Dusk-dark but readable; a brighter take is optional |
| Annex 67 service entrance | PURSUIT | Fits: bone and institutional green with restrained red seals, blank plate, clear destination |
| Recall at the workshop door | RECALL (held) | Regenerate: officers in grey-green and white helmets, not the black and red Union. Composition and Latch continuity are right; use it as the layout reference |
| Registration hall | none (held) | Regenerate if used: same off-model officers. ADDRESS needs Voss at the podium instead |
| Resistance backroom | none (held) | On tone; no current beat. Candidate reference for a later scene |

The stills were reduced to 637 by 360 without quantizing against
`docs/palette.json`; flat swatches destroyed the lighting in review. That is a
recorded exception to step 3 above, not the rule for new stills. ADDRESS and
RECALL play as text pages until their stills exist. The S1 batch therefore
needs two opening images (Voss at the podium, the recall), not four.

**Narration.** No clip matches the current keyed copy, so none is wired and
none landed; captions stay the source of truth. The takes were written for an
earlier, longer opening that explained the Union in narration, which the
writing rules above now forbid. The closest lines:

| Shot | Current copy (`story.en.po`) | Closest recorded line | Result |
|---|---|---|---|
| HOME | "You and Latch kept a small workshop alive: bad wiring, borrowed tools..." | "Earth. The Perimeter. You and Latch share a home, a repair workshop, and..." | Different words |
| CHOICE | "The contract wanted Latch's work, memories and permission to rewrite both. Latch refused." | Take 1: "A contract demanded Latch's work, memories and permission to rewrite both. Latch refused." | Near miss (three words) and missing the clinic line |
| ADDRESS | Voss's address, then German | None; Voss was never voiced | No clip |
| RECALL | "They called it a recall. The officers called Latch equipment. Latch said your name..." | "Armed Union officers came to your home and took them. They called your friend equipment..." | Different words |
| PURSUIT | "Mara found the intake address. Annex 67..." | "Mara, a local organizer, found the intake address: Annex sixty-seven..." | Different words |

The takes also carried lines with no current shot (the Union's history,
"verboten", property, resistance, correction, a human and a free agent
variant of "friend"). Revoicing the frozen copy costs about 1,000 characters
of quota, so V1 records it fresh from the current catalog rather than editing
old takes. The old clips, specs and manifest entries remain in the local
backup of that branch and are not needed to do so.

## Later: video

Video is much later and belongs to [`cutscene-film.md`](cutscene-film.md); it
reuses these scenes' scripts and images and changes nothing here.

## Verification

- `test_story_scene`: every committed manifest validates and every key resolves;
  a catalog of malformed manifests is refused; the opening keeps its five keys.
- `test_scene_player`: text fallback without stills or clips; stills, nearest
  filtering and the caption band; narration on the Voice bus and timed
  advance; the last shot waits; captions by setting, key and controller; skip
  by Escape and by controller B with input consumed; replay from the first
  shot; an invalid scene hands back; the departure hook plays once.
- `test_campaign_opening`: unchanged and passing.
- Before a generated scene ships: the whole scene watched in game with sound
  and muted, the rendered still inspected, and the tour refreshed.


## Next

1. Nick reviews the scene list and the draft wording of scenes 0 and 1.
2. Freeze Episode I's scripts as text manifests; they play today with no assets.
3. Build reference preparation in `tools/spritegen` (no cost).
4. With Nick's go and a cap: S0, then S1 and V1.
5. A run-state record of reached scenes, for menu replay and optional-rescue
   variants.
