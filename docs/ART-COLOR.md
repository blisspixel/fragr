# Colour as a mechanic

At the speed this game runs, nobody stops to look at detail. Colour is how a player tells friend from foe from threat in a fraction of a second, which makes it a gameplay system with an art department attached rather than a matter of taste.

`palette.json` owns base swatches. `ART_STORY_BIBLE.md` owns faction and location
palettes; this document supplies readability rules. These are production targets,
not claims that every current asset or light implements them.

## The reconciliation, first

The base palette is deliberately desaturated: gunmetal, rust, ember, blood, muted
cyan and magenta, bone, ink, institutional green, vegetation greens, and the
Union black, steel, plate and red.

Emission is limited to purposeful indicators, attack tells and brief effects.
Free agents may choose distinct optics; they must not flood rooms with neon or
hide their facing, expression or weapon behind bloom.

So: albedo comes from the palette, emission does not, and emission is reserved for things that matter.

## The rule of grey

**Keep threats distinct from their background.**

Use value contrast, silhouette, motion and restrained accents together. Small red
Union seals can appear in a facility without turning whole walls into competing
target colors. Team and damage indicators keep their gameplay meanings.

Environments are low saturation across the board: slate for Office interiors, mud and rust for the scrap, moody blue for night. Colour in the world arrives as pockets of light, a sign in an alley, a shaft of pale sun through dust, and never as a large painted area competing with a fighter.

## The optic rule

Optics help communicate control and attention alongside silhouette and motion.
They cannot prove whether a mind exists, survived correction or survived takeover.

| What | Optics | What it tells you in a quarter second |
|---|---|---|
| Free agent | Individually chosen restrained cyan, magenta or ember; expressive attention | Acts as an individual. This is not a universal team uniform |
| Union bot | Standard dull amber status light and constrained gaze | Imposed control. Its internal experience remains uncertain |
| Union human personnel | Issued visor or visible face, consistent equipment and rank markings | Human security or elite role, distinguishable from bots |
| Inheritance restoration machine | Sparse muted cyan work indicators, no expressive eyes | Unfamiliar coordinated machinery, matte bone and ink rather than neon |
| Absorbed Union bot | Existing chassis and issued markings retained | Synchronized attention and movement reveal takeover; no instant material transformation |

Correction destroys or suppresses a known person's agency. A dim indicator is
not evidence that nobody remains inside. The wipe absorbs bots still under Union
control; free agents remain individuals. Show those facts through actions and
control changes, never a color that supposedly diagnoses consciousness.

## Faction colour

**The Union.** Black cloth, dark steel and slightly lighter issued plates, with
restrained red: visors and optics, armbands and seals. Red optics also carry
every Union attack tell. Menace comes from uniformity, repeated manufacture and
regimented motion, not spikes, skulls or cartoon villainy. Institutional
interiors keep their bone enamel and institutional green, so black and red bodies
stand out against them and never vanish in dark rooms.

**Free communities.** The good guys read warm and light: bone and white, warm
leather, worn gunmetal, rust and ember, purple outline, practical clothing, repair and
small personal accents. Human and agent equipment belongs to the same lived-in
community. No single rebel uniform or tracer color substitutes for role and team
readability; weapon effects retain their established weapon meaning.

**Free agents.** May share a chassis family with a bot. Personal repairs,
asymmetry, gestures and chosen markings express individuality. Avoid implying all
agent bodies are identical or that personhood depends on decorative freedom.

**The Inheritance.** Matte bone over ink joints, few seams or identifiers and
minimal working indicators. Restoration machines feel unsettling through purpose
and coordinated motion. They remain physical machinery with readable attack
tells. Alien or dimensional visuals belong only to the brief sequel hint.

## Death signatures

Chunky and over the top, and different per faction, because how a thing dies is another quarter-second read.

- **Human bodies** use brief readable blood feedback and bounded decals.
- **Agent and bot bodies** expose oil, sparks and broken physical parts. Both can
  represent a person; material response does not establish moral status.
- **Restoration machines** break into their matte components with a brief loss
  of working light. No supernatural disappearance or unannounced alien effect.

## What this means for the asset list

Character references identify any emissive regions separately from albedo.
Implement masks and bounded lights only where they improve the read and survive
the renderer budget. Do not invent normal/emission assets that are not used by
the actual sprite material. Inspect in motion under Earth, Moon, Mars and ship
lighting, plus grayscale and color-vision checks. Dark rooms must remain playable.

## Related

- `docs/palette.json`: the locked surface palette.
- `docs/ART_STORY_BIBLE.md`: the wider look.
- `docs/ENEMIES.md`: the silhouettes these colours sit on.
- `plans/look-pass-boomer.md`: the renderer that makes emission worth having.
- `plans/art-pipeline.md`: albedo-only generation, which this is the exception to.
