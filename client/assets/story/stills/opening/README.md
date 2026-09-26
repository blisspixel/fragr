# M01 opening stills

Two illustrated stills for the Recall Notice opening, played by
`client/scripts/scene_player.gd` from `client/assets/story/scenes/opening.json`:

| File | Shots | Shows |
|---|---|---|
| `workshop.png` | HOME, CHOICE | Latch at the shared workshop bench, dusk window, work lamp |
| `annex.png` | PURSUIT | Annex 67 from a side street, the service entrance lit, a blank plate above it |

ADDRESS and RECALL have no still yet and play as text pages. The player stays
outside every frame, so the human and free agent bodies share these scenes.
Nothing is written into a picture; every word on screen is a catalog key in
`client/i18n/story.en.po`.

`manifest.json` records each exact prompt, model, request, source hash and
derived PNG hash. The sources were reduced to 637 by 360 through
`tools/spritegen reduce --height 360 --no-trim` without palette quantization,
which kept the scene lighting that flat base swatches removed. Other stills
from the same batch are held out of the game in `client/art/story/opening/`.

Ownership: the scene manifest chooses shots, images, motion and timing;
`story_scene.gd` validates it; `scene_player.gd` frames the still with nearest
filtering and draws captions. A missing file falls back to the text page and
never blocks the opening. See
[`docs/plans/campaign-scenes.md`](../../../../../docs/plans/campaign-scenes.md).
