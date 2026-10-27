# Paver

Status: wave 11 (2026-10-27) answers the open design question by drawing the
Paver upright at the authored proportions of its server volume, rather than
giving it a new low shot volume. The 2026-10-23 sledges (`paver-20261023-v1`,
`-v2`, about 0.55 m tall) stay retained and unselected. The selected source,
its preparation and the presentation seam are recorded in
[`client/assets/models/paver.glb.json`](../../../client/assets/models/paver.glb.json)
and `PaverRig.MODEL_PATH`.
Stable ID: `C-paver`. Parent: [full-game asset plan](../meshy-full-game-assets.md).

## Gate A brief (wave 11)

```text
id:                 C-paver
tool and stage:     spritegen gen (marketing-studio/image medium 2k, Image 1 = the placeholder
                    rig rendered at its authored proportions); meshy-gen meshy-t2, 2k texture, no rig
status:             canon role (L19 brief, ENEMIES.md); model pick HOLD FOR NICK (enemy model pick)

FACTION:            Inheritance restoration machine
  owner, if any:    none (the distributed intelligence; no unit is a person in a uniform)
  issued state:     n/a (no plates, seals or serials to issue or grind off)
PLACE:              wipe (18-20): Earth, changed Low Water tram street, market, workshop roof and
                    tram trench (L19); service road and freight yard (L20)
LEVEL / MODE:       L19 Planned Works (taught alone on the tram street), L20 Local Exception; wipe
PERIOD CHECK:       a practical road-works machine: crawler tracks, a scraper apron, a projector
                    head; unfamiliar construction, never exotic hover tech

CANON LINES:        - "The Inheritance's machines have continuous matte off-white surfaces, no
                      readable serials, unfamiliar construction and muted cyan working indicators."
                      (docs/lore/the-inheritance.md#physical-presence)
                    - "never a killer-robot war, chrome skulls or red-eyed machines (red optics
                      belong to the Union)" (docs/lore/the-inheritance.md, Nick's 2026-10-23
                      clarification)
                    - "The Paver comes alone on Low Water's tram street: a broad matte body that
                      projects a bounded white strip onto the ground, prepares for a readable span,
                      then works everything inside the strip." (docs/campaign/l19-planned-works.md)
                    - "the machines are going to take the district apart and give the ground back
                      to the river" (docs/campaign/l19-planned-works.md, Premise)
                    - "Matte off-white (bone) continuous bodies over ink joints; minimal muted cyan
                      working indicators ... Never a neon faction" (docs/ART_STORY_BIBLE.md)
PROPOSALS USED:     lore-gate P11 interim rule (grayscale capture against the actual wall)

PALETTE:            dominant bone; secondary ink (joints, tracks); accent gunmetal_light (shade);
                    emissive cyan_muted only (lens, two indicators, recovery vent), low energy
  off-palette hex:  none
RESERVED-COLOUR CHECK: black+red no; off-white dominant yes, owned by this faction; red emissive no;
                    cyan emissive yes, owned by this faction, #4A8A92 never brighter

SILHOUETTE:
  at 30 m:          pale broad upright block, wider at the shoulders than a fighter, low dark tracks;
                    no red point anywhere
  at 15 m:          bone body over ink waist and tracks, two shoulder plates, a hooded head with one
                    cyan slot
  at 5 m:           no marks; scraper apron ribs, hinge joints, the slot lens
  against:          absorbed Sweepers (black Union chassis, cyan optics) walking its lines; pale
                    concourse and plaster walls (grayscale check, P11)
SCALE:              server body is the ordinary fighter volume (radius 0.5 m, height 1.8 m,
                    combat.rs FIGHTER_HEIGHT); per-object target W 1.3 (across, with shoulder
                    plates) x D 1.2 (forward) x H 1.75 m, one object; projector lens at 1.64 m and
                    0.3 m forward (paver_strips.gd LENS_HEIGHT, LENS_FORWARD)
MARKS AND TEXT:     no text, no plates; nothing to decal

MOTION / PARTS:     tell parts: projector head (tilts toward the strip during preparation and work),
                    the two shoulder plates (lift and open: the "pauldron tell" in
                    docs/design/wipe-finale-and-mode.md), lens and recovery vent light; body judders
                    on each work pulse; local pivots, no rig
STATES:             idle, moving, windup (preparation), firing (work), recovery, hit, dead; all from
                    the one source, pivots only
REFERENCES:         placeholder render .agents/wave11-inheritance-models/paver-placeholder-threequarter.png
                    (uploaded, art/raw/H-W11/references.jsonl); do not copy any real road machine
PROMPT:             tools/spritegen/specs/h-w11-paver-refs-20261027.json
NEGATIVES ADDED:    red light, red optics, black and red, hazard stripes, rust, stickers, humanoid
                    body, arms, chrome, many panel lines

INTEGRATION SLOT:   PaverRig.MODEL_PATH (client/scripts/paver_rig.gd), presented by EnemyView
COLLISION:          none added; cosmetic only inside the unchanged server fighter volume
CEILING:            Higgsfield $1.00 for the lane (run cap from exact price); Meshy 15 credits
                    (live usable balance 2026-10-27: 30 available, 15 retained hold)
NICK GATE:          yes (enemy model pick); alternates retained for review
```

## Credit reservation and next operation

Before every paid stage, use the existing native free balance checker and
shared account ledger, retain uncertain holds and price the exact options.
Record actual reported consumption. No new cash, renewal, pack purchase,
top-up or overage is authorized by this plan.
