# UI palette and typography

Status: **in flight**. Issue #411 within #418 and the canonical Full build order.
Base: PR #419, main commit 9081b54945086821f05293cebd3efe74b1aa0dba, with
[passing CI](https://github.com/blisspixel/fragr/actions/runs/39101263743).
Spend: $0, retained fonts and
palette. Front end decision C: dark cabinet now, named appearance roles ready
for a later explicit mode decision. No theme selector in this round.

Goal: one canonical palette and intentional type scale across menus and HUD,
with readable 720p layouts and no world-art change. Success requires the issue's
palette, font, contrast and three-resolution acceptance checks, existing input
and lifecycle regressions, independent review and normal release convergence.

## Architecture

Extend MenuTheme with palette-derived chrome roles and named type sizes. Keep
fixed HUD roles distinct from front-end appearance roles; preserve world albedo,
faction colors and Label3D fonts. Runtime constants must match docs/palette.json
under a check, while exported clients remain self-contained.

Separate world consumers of existing MenuTheme.BONE/INK/EMBER and Silkscreen
before changing UI resources. Use a dedicated no-antialias UI FontFile resource
while leaving the existing world font settings intact. Inspect its Godot 4.7
supported properties first. Black Ops One owns display numerals and titles;
Silkscreen owns ordinary labels. Logical 24/48 avoid fractional pixel-grid sizes
at all three requested resolutions. Other allowed sizes need rendered proof.

Migrate the complete UI surface, including main.tscn defaults, dynamic HUD and
menus, late mission prompts, pause/settings, results/history/rewards, story
reader, benchmark views and debug/performance overlays. Color-bearing helper
calls must distinguish UI team/stance semantics from world colors. Leave ammo
pictograms and weapon render art as explicitly scoped exceptions. Replace
control-wide tint multiplication with actual text/style colors.

Muted body text uses an ink backing for 4.5:1 contrast; status marks may use
color beside readable words/numbers. Focus exceeds 3:1 against panels. Opaque
style tests do not replace captures over bright and dark gameplay backgrounds.
Exact luminance calculations: bone/ink 15.34, bone/steel 10.65; accent/steel
5.14; muted/ink 5.37 but muted/steel 3.73; success/ink 5.06 but success/steel
3.52. Danger/ink is only 4.49, below 4.5 without rounding. Small error text
therefore stays bone with a danger border/mark, rather than red body copy.
Canvas scaling can make a nominally large font small at 720p; verify actual
rendered size before relying on the large-text contrast threshold.
No wire, combat, save, map or transport change. Do not combine subsequent
status-bar/feed/accessibility/terminal redesigns into this foundation.
Preserve system glyph fallback for user-authored callsigns/chat outside the
two bundled faces' character coverage. The server accepts bounded Unicode
names. Eliminating unthemed default-font controls must not turn those names
into missing-glyph boxes or introduce an ASCII restriction. Owned English UI
copy uses the intended face; broader localized font coverage remains its own
roadmap work. Check the HUD's nonbreaking spaces with the pixel resource.

## Verification

Check palette parity, contrast pairs, default font inheritance and allowed type
sizes on instantiated UI. Audit color/font literals in scripts and scenes.
Preserve interactions and ownership tests. Inspect long admission errors,
remapped controls, large magazine counts, settings rows, feed, captions, records
and late mission prompts for wrapping/clipping. Capture front end and HUD at
1280x720, 1920x1080 and 2560x1440. Run the complete Godot checker and publish the
visual tour, independent review, green PR and main, then desktop packaging.
Keep physical-controller and fresh-player acceptance separate.

Independent design review: require explicit front-end/gameplay context when
building themes. SettingsPanel installs its own theme and is used in both boot
and pause, so pass its context from the owner; loading/story/results also need
an intentional assignment. InputGlyphs must move from its old bone/ember literals
to canonical fixed HUD roles. "Fixed" means independent of menu appearance,
not preservation of the incorrect swatches. Do not change project-wide default
fonts: NameplateLayout relies on ThemeDB.fallback_font for world labels.
Exercise long binding tokens in all three columns, capture/conflict messages
and the separate pause settings host (currently minimum width 780), not just
the boot column. Include a valid 24-character Unicode callsign through profile
input, roster, feed and records; fallback glyph line heights and caret behavior
need actual control checks beyond the English font specimen.

Review additions: include InputGlyphs' RichTextLabel keycap spans and generated
textures, the console's RichTextLabel/LineEdit, and CrawlerCaption. Keep the
current fixed input glyph palette independent of future menu appearance modes;
its cache currently keys token and controller layout, not appearance.
Exercise lazy HUD damage numbers, radio toasts and station cards. Resolve radio
badge colors through UI roles rather than stations.json's magenta data colors,
without editing names/copy. Use UI-specific team/stance/site colors; shared
MatchRules, ConquestState and StanceChip helpers also paint world actors and
markers. Preserve the existing user-selected reticle amber/cyan settings as an
explicit preference boundary. Recovery prompt glyphs currently use 44px; their
texture scale needs the same grid inspection as text. M15-M18 world presenter
meshes/signals stay outside this migration.

Primary API preflight, checked 2026-10-17: Godot's stable FontFile reference
lists antialiasing, hinting, oversampling and subpixel_positioning as resource
properties; the font guide covers pixel-font rasterization. Preserve the shared
world font's current imported settings when creating the UI-only resource.
https://docs.godotengine.org/en/stable/classes/class_fontfile.html
https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_fonts.html

Do not overlook inherited engine chrome: checkbox/toggle icons, popup arrows,
slider grabbers, scrollbar styles, LineEdit selection/caret and tooltip panels
need explicit palette roles too. Primary references checked October 17:
https://docs.godotengine.org/en/stable/classes/class_checkbutton.html
https://docs.godotengine.org/en/stable/classes/class_optionbutton.html
https://docs.godotengine.org/en/stable/classes/class_spinbox.html
CheckButton exposes checked/unchecked and disabled/mirrored textures; OptionButton
can modulate its arrow to font color. SpinBox owns arrow-state icons and uses
SpinBoxInnerLineEdit for its field. Keep icon geometry pixel-based and cache
generated textures; this needs no asset service.

Baseline evidence: .agents/convergence-20261017/ui-baseline/{720,1080,1440}.
Five current states per resolution (menu, live HUD, profile, audio, controls),
using isolated preferences/run data and llvmpipe. The full 720p controls still
shows small off-grid text in a roughly 440px-wide inner column. Raising its
14px logical labels to the allowed scale must include wider settings columns
and row sizing; token replacement alone will not fit. Preserve scroll ownership
and binding interaction rather than shrinking the type back to old sizes.
An isolated Godot 4.7.2 probe confirms that duplicating the imported FontFile and
setting antialiasing/subpixel positioning/hinting off with oversampling 1 keeps
the original world import unchanged. This avoids duplicating font bytes. The
widest current binding label at logical 24 is DETONATE ARMED CHARGES, 372px;
the existing 250px action column must grow. The ordinary 24px line height is
31px, and a 255 | 999 count takes 141px before margins. This is headless size
evidence only; the three-resolution captures still own raster acceptance.
The isolated renderer comparison now exists at font-probe/font-{720,1080,1440}.png,
captured with llvmpipe under the actual 1920x1080 canvas stretch and inspected.
Logical 24 and 48 give the intended even pixel steps across the three target
sizes. Logical 16 is too small at 720p, and 16/32 hit fractional pixel grids at
720p/1440p. Prefer 24 for body/hints and 48 for larger pixel readouts; the allowed
16/32 values should not become an excuse to shrink overflowing layouts.
This type specimen does not replace rendered acceptance of the actual pages.
The cabinet itself is MenuBackdrop procedural UI, not a world asset. Its tile,
rib, horizon, bolt and stripe colors also need palette-derived theme roles;
retain the existing geometry and deterministic wear. Preserve actual gameplay
world colors while centralizing this front-end background's literals.

## Implemented behavior and review

MenuTheme now owns palette swatches, appearance contexts, type resources and
control chrome. Front-end overrides resolve their context's roles. HUD scenes,
lazy labels, input glyphs and overlays use fixed gameplay roles. Existing world
signs retain their original imported font and ink/bone materials. Reticle
preferences and weapon/ammunition art remain explicit boundaries.

Body text uses logical 24 px; display titles and numbers use Black Ops One's
48/64/96 scale. Wider settings and ammo layouts, wrapped vehicle controls,
radio cards and admission errors, and a larger campaign objective card preserve
readability. Settings retain their own scroll/focus and binding capture flow.
The feed retains its original three-entry lifetime and ownership, with enough
vertical space to keep larger rows above campaign health. The later feed and
status-bar issues retain their separate scope.

Independent review found two regressions during implementation: front-end
explicit colors bypassed the context, and replacing transparent flash colors
with opaque swatches enabled previously invisible washes. Both are corrected.
The existing effective flash opacity is preserved for the comfort-controls
round. Muted pause hints now use bone on steel. A full-suite iteration caught
feed/health overlap and two M02 objectives wrapping; layout fixes pass their
original focused assertions without weakening them.

The new `test_menu_theme` verifies palette parity, contrast, cached independent
contexts, imported-world-font preservation, real menu/HUD font inheritance,
allowed sizes, binding widths, 24-character Unicode input/caret, lazy HUD labels,
radio containment and CTF result containment. Equipment checks retain private
inventory semantics and add full-size magazine/reserve and right-margin checks.
The initial complete checker was interrupted after M10; it is not a passing
full-suite receipt. A subsequent complete run caught CTF and combined-mutator
labels overflowing the old narrow HUD panel. Expanding that panel for the new
type passes all three original containment assertions. The final complete
checker is running again, and the publication tour is being refreshed for the
panel correction. The preceding complete 32-state tour passed and refreshed
fourteen stills. Its contact sheet, menus,
world views and three effect strips were inspected; the
[receipt](../screenshots/tour-20261018-ui-palette.json) retains the observed
states and renderer. The rendered story-player harness also passes, including
Voice/Master mute and caption settings. Story backdrops explicitly inherit the
gameplay context, checked by the existing story harness.

Inspected Linux llvmpipe captures use the actual 1920x1080 canvas stretch:

| Output | Controls | Live joined HUD |
|---|---|---|
| 1280x720 | [controls](../screenshots/ui_controls_720_20261018.png) | [HUD](../screenshots/ui_hud_720_20261018.png) |
| 1920x1080 | [controls](../screenshots/ui_controls_1080_20261018.png) | [HUD](../screenshots/ui_hud_1080_20261018.png) |
| 2560x1440 | [controls](../screenshots/ui_controls_1440_20261018.png) | [HUD](../screenshots/ui_hud_1440_20261018.png) |

Private `proof-extended/{720,1080,1440}` captures cover all settings tabs,
rebinding capture and bottom rows, profile Unicode, host, records, awards,
multiplayer, pause and its separate settings frame. Controlled presentation
fixtures also cover dynamic radio/feed, Conquest, aircraft controls, long
admission errors, campaign results and benchmark tables. Those fixtures are
layout evidence, not completed gameplay routes or hardware measurements.
The separate `render-final` captures use a live local server and joined player.
All asset work in this round reuses retained fonts/art at $0.
Nick's October 18 authorization replaces the historical $5 per-run asset ceiling
with each service's remaining funded or included credits. The updated rule is
recorded in AGENTS.md; native limits need adjustment before any larger asset
batch. No generation or billing change was needed for this UI round.
