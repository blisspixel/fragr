# M01 opening stills

The illustrated stills for the Recall Notice opening, played by
`client/scripts/scene_player.gd` from `client/assets/story/scenes/opening.json`:

| File | Shots | Shows |
|---|---|---|
| `workshop.png` | HOME, CHOICE | Latch at the shared workshop bench, dusk window, work lamp |
| `address.png` | ADDRESS | Voss at the podium on the broadcast, the Union seal behind her, one fist raised, the crowd's fists up |
| `recall.png` | RECALL | The workshop door sealed and posted with the recall notice, a dropped mug and wrench, the custody van leaving with Latch behind its bars |
| `annex.png` | PURSUIT | Annex 67 from a side street, the service entrance lit, a blank plate above it |

The player stays outside every frame, so the human and free agent bodies share
these scenes. Nothing is written into a picture; every word on screen is a
catalog key in `client/i18n/story.en.po`.

`manifest.json` records each file's provenance and hash. `workshop.png` and
`annex.png` are paid generations: the manifest keeps each exact prompt, model,
request and source hash, and the sources were reduced to 637 by 360 through
`tools/spritegen reduce --height 360 --no-trim` without palette quantization,
which kept the scene lighting that flat base swatches removed. Other stills
from that batch are held out of the game in `client/art/story/opening/`.

`address.png` and `recall.png` are authored 160 by 90 pixel art in the intake's
palette, drawn by `client/scripts/m01_opening_art.gd` and baked with
`godot --headless --path client --script ../tools/bake_opening_stills.gd`.
They share the records screen's broadcast look and Latch's canonical screen
head, so the opening and the level read as one world. The scene player lays
the text panel over each still's lower middle, so both keep their subject in
the top band and the side columns.

Ownership: the scene manifest chooses shots, images, motion and timing;
`story_scene.gd` validates it; `scene_player.gd` frames the still with nearest
filtering and draws captions. A missing file falls back to the text page and
never blocks the opening. See
[`docs/plans/campaign-scenes.md`](../../../../../docs/plans/campaign-scenes.md).
