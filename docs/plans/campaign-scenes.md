# Campaign scene production: audio slideshows

**Status:** in flight, 2026-09-25. The scene player, its manifest format, the
migrated M01 opening and a text-only draft of the scene after Recall Notice are
implemented and tested on this branch. No still, narration clip, ambience or
music for any scene has been generated. **Every generation batch below needs
Nick's written go for that batch.** The
[campaign contract](../CAMPAIGN.md#story-presentation-and-localization) owns
presentation behavior, the [story arc](../campaign/story-arc.md) owns what
happens, and each [level design](../campaign/README.md) owns its level. This
file owns the scene format, the production workflow, the scene list, costs and
the later video path.

**Direction, Nick, 2026-09-25:** between levels the campaign plays an audio
cutscene: AI-generated pixel stills as a slideshow, voiced lines, captions. You
can skip anything, and it is really well done. Theme-appropriate Higgsfield
video may come later on the same shots; for now, audio only. Standing rules:
show, don't tell (a scene is short and never explains what the level just
showed); radio is minor, and a scene is not radio; the Union reads plainly as a
Fourth Reich and is never named as one; the player is the free human or free
agent and never speaks.

This replaces the 2026-09-22 text-first gate. That gate's reasoning still holds
for video: missions and sentences are still moving, and a movie spent now would
be thrown away. Stills and short voiced lines are cheap enough to redo when a
level changes, and the scene falls back to text whenever an asset is missing.

## What is built

| Piece | Home | Behavior |
|---|---|---|
| Manifest format and validation | `client/scripts/story_scene.gd` | Strict JSON under `client/assets/story/scenes/<id>.json`; unknown fields, unsafe paths and out-of-range values are refused |
| Scene player | `client/scripts/scene_player.gd` | Stills with nearest filtering and a subtle pan or zoom, keyed captions with speaker labels, narration on the `Voice` bus, optional music and ambience beds, a progress row |
| M01 opening | `client/scripts/campaign_opening.gd`, `scenes/opening.json` | The five keyed beats on the shared player, reader paced until assets exist; unchanged readiness handoff through GameManager |
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
and the progress row) inspected at 1280x720.

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
      "image": "res://assets/story/stills/l01_l02/ledger.png",
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

## Writing rules for every scene

1. **Show, don't tell.** A scene is a handful of pictures, a few spoken lines
   and sound. It shows what changed or what is at stake next. It never recaps
   the level, never explains the Union, never names a theme. If a caption says
   something a picture could show, cut the caption.
2. **Short.** 30 to 90 seconds narrated, three to six shots, at most one
   speaker line per shot, lines of about twelve words or fewer. Episode
   transitions may run to 90 seconds; everything else aims at 30 to 45.
3. **Voices are people.** Characters speak; there is no narrator except the
   opening and the exhaustion ending, whose pages are already written that way.
   The player never speaks. Voss and the Office speak only from screens and
   PA, never as narrator. The Host appears at most once (after level 15).
4. **The Union is felt, never named.** Black and red, armbands, forms,
   countersignatures, calm procedure, English that slips into German twice in
   the whole campaign. No real insignia, no real names, no cartoon.
5. **Consequences are faces.** A rescued person shows up doing something; an
   absence is an empty chair. Optional rescues (Edda, Splice, Orrin) need
   a variant shot, which waits for run-state conditions in a later format.
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
3. **Stills (Higgsfield through `tools/spritegen`).** Character reference
   sheets come first and are approved once: the player (body neutral), Latch,
   Mara, Tern, Edda, Splice, Renn, Sorrel, Voss, Kessel, and one Union bot and
   one Enforcer, each on the [cast anchors](../lore/cast.md#visual-continuity)
   and the [art bible](../ART_STORY_BIBLE.md). Every shot request then passes
   the relevant sheets as `image_urls` references, so faces and kit stay on
   model. Price with `price`, generate with an explicit `--max-spend-usd`
   (capped at five dollars per run by the tool) and the request ledger;
   explore at `low`, promote keepers at `medium`. Reduce locally to the
   640x360 canvas and quantise against `docs/palette.json`. Stylised prompts
   only: the [pipeline finding](higgsfield-pipeline.md#the-finding-that-decides-the-house-style)
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
and three for the endings. Names are working titles. Shots are the picture and
what is heard; quoted lines are spoken, bracketed text is a sound caption.
Nothing here is frozen until step 1 above.

### Episode I: Recall

| # | Scene | Shots | Length | Voices |
|---|---|---|---|---|
| 0 | **Opening** (before 1, built as text) | Home: the shared workshop bench, two mugs, one charging cable. By choice: Latch refuses the contract, then carries a pump to the clinic. For the Union: Voss at the podium, English, then German, then the cheer; a confiscation table of rifles and a silenced feed. Recalled: officers and uniform bots at the door; Latch says your name. Recall Notice: the intake address on the notice matches the building ahead | 60 s | Narrator, Voss, Latch, Mara |
| 1 | **One Shift** (1 to 2, drafted as text) | The ledger open on your knee, last line in Latch's hand, "You 3. Me 3." Mara at the van: "Correction starts at shift change. We have one shift." The ward frame through dark glass: "The frame is already warm." | 30 s | Mara |
| 2 | **The Spur** (2 to 3) | Latch flexing a wrist where the restraint was. A clipboard list, a pen tick beside LOW WATER. Mara's handset: NO SIGNAL, the red mast on the skyline. Latch, looking at the sealed freight cars: "Those aren't empty." | 35 s | Latch |
| 3 | **Home, Briefly** (3 to 4) | The freed train rolling into Low Water at dawn. The market board: a tram paint vote, three colors, all crossed out. Edda switching on the clinic sign. A fresh notice pasted over the vote, the same countersignature at the bottom | 40 s | Edda (one line) |
| 4 | **What We Can Carry** (4 to 5) | The clinic shutter down. A bag packed: the ledger on top. Mara, not meeting your eye: "The aid is two hours out." Across the roofs, one light still on in Splice's workshop | 35 s | Mara |
| 5 | **Passengers** (5 to 6, episode) | The freight platform board: names, some rows blank. Sorrel's tram cab, empty, cap on the seat. Tern's ship in a field, hatch open: "Sit down. Touch nothing." Latch counting heads at the hatch, twice. Earth shrinking in the port. The Moon's port lights | 75 s | Tern, Latch |

### Episode II: Custody

| # | Scene | Shots | Length | Voices |
|---|---|---|---|---|
| 6 | **Declared** (6 to 7) | Through customs glass, a family's luggage tagged and a stamp coming down: DECLARED. A local in a doorway, pointing up: "Through the town. Don't stop in the square." The depot tower across the crater | 35 s | A townsperson |
| 7 | **Custody** (7 to 8) | The crater cut behind you, berms smoking. A custody manifest on a clipboard; Latch's finger stopping on a Low Water name. The same countersignature. Latch: "Some of them are here." | 35 s | Latch |
| 8 | **Authorized Noise** (8 to 9) | An empty freight car arriving exactly on time. The panel: "Authorized noise. No action required." Renn left standing in the archive doorway, coat without its rank. A backup case in your bag. A berth manifest: one ship, IMPOUNDED | 40 s | Renn (one line) |
| 9 | **Own Deck** (9 to 10, episode) | Tern's hands back on their own controls. The Moon falling away. Freed people claiming corners of the hold; an agent grumbling that a human needs a whole room to sleep. A patched chassis, clinic staples in the plate. The long window, stars moving | 75 s | Tern, an agent passenger |

### Episode III: Common Cause

| # | Scene | Shots | Length | Voices |
|---|---|---|---|---|
| 10 | **Alongside** (10 to 11) | Through the long window, the Union tender riding alongside, lit and orderly. Tern easing the Carrier closer: "They'll call the blockade. Unless they're busy." Latch laying out mines on a crate. The umbilical extending | 40 s | Tern |
| 11 | **In Transfer** (11 to 12) | The transfer hold, people standing in a line painted on the floor. Sorrel in the line, corrected, reciting a procedure. Latch's hand on Sorrel's shoulder. A draft order on a desk: HARMONISED CUSTODY SCHEDULE. Mars in the window | 45 s | Sorrel, Latch |
| 12 | **Six Declarations** (12 to 13) | A crate with six declarations of independence chalked on it, one amended. Trucks arriving at the depot, real ones. An organizer, tired: "Fine. All of us, then." The foundry's glow on the horizon | 35 s | A Martian organizer |
| 13 | **Asked** (13 to 14) | Workers in the quarters doorway. Latch holding out a tool, not a key. Some take it; one shakes their head and sits back down, and Latch nods. The freight lift climbing into daylight. The launch gantry | 35 s | Latch, a worker |
| 14 | **Homecoming** (14 to 15, episode) | Ships lifting off the pads. Earth filling the window. The stadium city at night, the podium still dressed for ceremony. Numbered placards stacked in a tunnel. Latch, quiet: "We're home." | 75 s | Latch, Tern |

### Episode IV: Reckoning

| # | Scene | Shots | Length | Voices |
|---|---|---|---|---|
| 15 | **Pirate Track** (15 to 16) | The stadium screen: Voss's address, the honest subtitle track running under it. Entrants in the tunnel wheeling out motorcycles. The Host, one line, over a stadium speaker. The avenue ahead, the Office tower at its end | 35 s | The Host (one line) |
| 16 | **Forecourt** (16 to 17) | Every avenue light green behind you. The Office doors, heavy and plain. The rattlesnake banner tied to a lamppost. A form blowing across the steps, the countersignature on it | 30 s | None; sound captions |
| 17 | **Receipt** (17 to 18, episode) | A table with confiscated command keys and a receipt pad. Kessel's emptied desk, his pen squared to the edge. Weeks later: the recovery square, a delivery van, people rebuilding. Latch tuning a tram motor, humming. A Union bot sweeping the square, as it always did | 75 s | Latch (humming), sound captions |

### Episode V: Inheritance

| # | Scene | Shots | Length | Voices |
|---|---|---|---|---|
| 18 | **One Rhythm** (18 to 19) | From the overlook, rows of machines facing the same way. [one rhythm, everywhere]. A supervisor's handset, no answer. Latch beside you, still Latch, looking at their own hands | 30 s | None; sound captions |
| 19 | **Even** (19 to 20) | Latch walking away with the free agents toward the waterworks, not looking back. The ledger in your hand, a new line: "Hold them." The pier ahead, people waiting | 30 s | None; sound captions |

### Endings

| # | Scene | Shots | Length | Voices |
|---|---|---|---|---|
| 20 | **Water Around a Stone** (survival, 20 to Still Here) | The machines reaching the refuge line and stopping. Then flowing around it like water around a stone, and on to the next district. A single line of text on a salvaged screen: the forecast fragment. Latch at the end of the pier, coming back | 60 s | Latch (one line) |
| 21 | **Still Here** (after the epilogue, into credits) | The refuge years later, green. Sorrel in the repaired tram cab. The ledger, closed. Latch: "I stopped counting." A deep-space anomaly, one frame, no explanation | 60 s | Latch |
| 22 | **The Last Page** (exhaustion, into credits) | The refuge exception holding without you. The Moon, Mars, the ships, a healing Earth, one shot each. The ledger open to its last page: one more line in Latch's hand, and no score. The deep-space anomaly | 90 s | Narrator |

Totals: 23 scenes, about 100 shots, about 18 minutes if every scene ran to its
target. A player sees 21 or 22 of them (one ending), about 17 minutes spread over a
four-hour run, and can skip every second of it.

## Cost estimate

Prices are the measured and published rates already in this repository,
checked on the dates given; recheck live before any batch.

**Voice (ElevenLabs, existing subscription quota).** Speech is one credit per
character on the v3 model (`tools/audiogen` estimate). Spoken text is about
40 lines of 60 characters in the interludes plus the opening (about 1,200) and
the two narrated ending pages (about 1,000): roughly 4,600 characters. Three
takes per line gives **about 14,000 credits**.

| Item | Basis | Estimate |
|---|---|---|
| Narration and lines | 4,600 characters, 3 takes, 1 credit per character | 14,000 credits |
| Ambience beds | 23 loops of 20 seconds at 40 credits per second (2026-09-19) | 18,400 credits |
| Episode music | 5 beds of 90 seconds at 900 credits per minute | 6,750 credits |
| Total | | about 39,000 credits |

The 2026-09-19 quota check left 791,861 credits with a reset on October 6, so
this is about 5 percent of one cycle, with no added dollars inside the
subscription. Music beds stay blocked until the distribution question in the
[radio plan](radio-refresh.md) is settled; scenes work without them.

**Stills (Higgsfield `marketing-studio/image`, measured 2026-09-19).** Explore
at `low` ($0.019), promote the keeper at `medium` ($0.100).

| Item | Count | Explore | Keep | Total |
|---|---|---|---|---|
| Reference sheets | 12 subjects, 6 candidates each, 1 keeper | $1.37 | $1.20 | $2.57 |
| Scene stills | 100 shots, 4 candidates each, 1 keeper | $7.60 | $10.00 | $17.60 |
| Retakes | 20 percent of shots again | $1.52 | $2.00 | $3.52 |
| Total | | | | **about $24** |

That is inside the $50 repository cap but above the roughly $14 of Higgsfield
credit recorded as available in the [local excellence plan](local-excellence.md).
The cheaper path: reuse a still across two shots where the story allows (about
80 unique pictures) and keep the first pass to three candidates, which lands
near $15. Either way, stills go in batches of one episode or less, each under
the five-dollar per-run ceiling, each with Nick's go.

| Batch | Contents | Cap |
|---|---|---|
| S0 | Reference sheets | $3 |
| S1 | Opening and Episode I scenes (0 to 5) | $5 |
| S2 | Episode II (6 to 9) | $4 |
| S3 | Episode III (10 to 14) | $5 |
| S4 | Episodes IV and V (15 to 19) | $4 |
| S5 | Endings (20 to 22) | $3 |
| V1 onward | Voice per episode, after that episode's stills | 4,000 credits each |

## Later: video on the same shots

Video replaces pictures, never words. Each shot keeps its id, caption key,
speaker, narration and timing; a later manifest format adds an optional
per-shot video that plays in place of the still, with the still as the
fallback and the first frame. The approved still becomes the start frame and
the reference sheets the character references.

Seedance 2.5 reference-to-video on Higgsfield is the first candidate: 4 to 30
second clips, 480p or 720p, image references, advertised from $0.144 per second
on the reference route (the generic overview says $0.0738; the live estimate
decides). Kling 3.0 is the comparison. Animating every shot for five seconds
would cost about $72 at the reference-route rate, above the whole repository
cap, so video is for a few moments only: the opening's address, the level 18
rhythm and the survival ending, about 12 shots, about $9. Before any of it, the
bounded two-shot comparison already written for this plan runs first (cap $3),
`tools/spritegen` gains a video download path with the same ledger, and clips
are converted to Ogg Theora for Godot's built-in player and checked on Windows,
Linux and macOS for decode cost, size and export. A clip with drifting faces,
shimmering pixels or invented insignia is rejected; if nothing beats the
still, the still stays. Video remains blocked until the campaign is built.

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
4. With Nick's go: S0, then S1 and V1.
5. A run-state record of reached scenes, for menu replay and optional-rescue
   variants.
