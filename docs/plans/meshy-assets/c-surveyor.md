# Surveyor

Status: wave 11 (2026-10-27) selects the retained `surveyor-20261023-v1`
candidate (spent 2026-10-23, 35 credits) for `SurveyorRig.SOURCE_SCENE`, with
no new paid stage. `surveyor-20261023-v2` stays retained and unselected. The
preparation and its measurements are recorded in
[`client/assets/models/surveyor.glb.json`](../../../client/assets/models/surveyor.glb.json).
Stable ID: `C-surveyor`. Parent: [full-game asset plan](../meshy-full-game-assets.md).

## Gate A brief (wave 11)

```text
id:                 C-surveyor
tool and stage:     no new stage; re-fit of meshy-7.1 2k candidate surveyor-20261023-v1
                    (reference: H-1a surveyor keeper, 2026-10-23)
status:             canon role (L20 brief, ENEMIES.md); model pick HOLD FOR NICK (enemy model pick)

FACTION:            Inheritance restoration machine
  owner, if any:    none
  issued state:     n/a
PLACE:              wipe (18-20): Earth waterworks sluice catwalks, tower and crane over the
                    freight pier (L20)
LEVEL / MODE:       L20 Local Exception (taught alone over the sluice), later pressure groups; wipe
PERIOD CHECK:       a survey instrument on a tripod and mast: a recognisable working tool of
                    unfamiliar make, no hovering, no faces

CANON LINES:        - "The Inheritance's machines have continuous matte off-white surfaces, no
                      readable serials, unfamiliar construction and muted cyan working indicators."
                      (docs/lore/the-inheritance.md#physical-presence)
                    - "Its local combat units have readable tells and can be defeated; destroying
                      one does not kill the distributed intelligence." (same section)
                    - "an elevated off-white unit on a waterworks tower that projects a mark, a
                      visible disc of light, onto a position ... hit it during its exposed
                      observation phase, when its lens opens wide."
                      (docs/campaign/l20-local-exception.md, Teaches)
                    - "Twelve minutes on a pier against machines that do not hate you"
                      (docs/campaign/l20-local-exception.md, Hook)
PROPOSALS USED:     lore-gate P11 interim rule (grayscale capture against the actual tower)

PALETTE:            dominant bone (head, legs); secondary ink (mast, joints, lens rim); accent
                    gunmetal_light; emissive cyan_muted (indicator band), lens glass pale cyan_light
                    only while the lens is open
  off-palette hex:  none
RESERVED-COLOUR CHECK: black+red no; off-white dominant yes, owned; red emissive no; cyan emissive
                    yes, owned, muted

SILHOUETTE:
  at 30 m:          pale lens head on a thin dark mast over a pale tripod, high on a tower
  at 15 m:          one large dark lens framed in bone, cyan ring
  at 5 m:           no marks; iris shutter opening, folded tripod joints
  against:          the waterworks tower lit from inside; pale sky band (grayscale check)
SCALE:              server body is the ordinary fighter volume (radius 0.5, height 1.8, eye 1.6);
                    one object, W 1.0 x D 1.15 x H 2.0 m with the lens centre at 1.6 m so a shot
                    at the open lens lands inside the authoritative volume
MARKS AND TEXT:     none

MOTION / PARTS:     head (lens housing) pivots on the mast yoke: hit recoil, death droop; authored
                    six-blade iris and lens glass over the generated lens; cyan indicator band
STATES:             idle, windup (lens opening), firing (disc held), recovery, hit, dead
REFERENCES:         art/raw/meshy-pilot-20261003/surveyor-20261023-v1-0.glb and its 2026-10-23 review
                    renders (.agents/review-20261023/models/surveyor-v1-*.png, main checkout)
INTEGRATION SLOT:   SurveyorRig.SOURCE_SCENE (client/scripts/surveyor_rig.gd), lens origin
                    SurveyorRig.LENS_HEIGHT for surveyor_marks.gd
COLLISION:          none added; cosmetic only
CEILING:            0 credits (retained candidate)
NICK GATE:          yes (enemy model pick); v2 retained for review
```
