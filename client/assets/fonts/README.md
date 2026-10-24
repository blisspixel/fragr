# Menu type

`BlackOpsOne-Regular.ttf` is the menu display face, distributed under the SIL
Open Font License in `OFL.txt`. Source: the `ofl/blackopsone` directory in the
[Google Fonts repository](https://github.com/google/fonts/tree/main/ofl/blackopsone),
retrieved 2026-09-19. Preserve the license with exported distributions.

`silkscreen/Silkscreen-Regular.ttf` supplies pixel lettering for controls and
settings. Source: `ofl/silkscreen` in the same repository, retrieved 2026-09-19.
Its separate SIL Open Font License is in `silkscreen/OFL.txt`.

`MenuTheme` duplicates the imported Silkscreen resource for UI, disables
antialiasing, subpixel positioning and hinting, and uses logical 24 or 48 px
for even pixel steps at 720p, 1080p and 1440p. The original import remains the
world-sign resource. System glyph fallback remains enabled for player-authored
Unicode names and chat. Black Ops One owns front-end display titles and the
match HUD's large numerals (health, armor, ammunition) at 48, 64 or 96 px.
Every word on the match HUD, including death, objective, round and result
cards, is Silkscreen in capitals through `MenuTheme.pixel_text`; nameplates
and other world tags use the same face through `MenuTheme.world_text`.
`test_hud_type` holds that rule. Neither face replaces the project-wide
default font.
