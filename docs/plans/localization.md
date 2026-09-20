# Plan: localization

**Status:** planned, revised 2026-09-19. Basic campaign text/captions arrive with
M01; broader locale rollout remains later.
**Branch:** `feat/l10n-*`
**Spend:** $0 for text. Voiced lines in other languages would go through the approved audio pipeline within the monthly credits.

## Goal

fragr speaks more than English: the basics people expect (English, Spanish, Japanese, German, French, Portuguese, Simplified Chinese, Korean), regional flavours that fit the game's wider world (Canadian French, Australian English), languages that are rare in games and deserve care (Hawaiian, Navajo), and a few constructed or joke languages that fit the lore (an in-world Continuance officialese, a static-corrupted "Dead Air" mode, Esperanto, Toki Pona, pirate, and leetspeak). All text is localised; audio stays English with localised captions until a per-language voice pass is approved.

## Non-goals

- Localising the radio music or the Host voice in this plan. Captions cover them.
- Right-to-left layout in the first pass. Arabic and Hebrew wait for the HUD grid to support mirroring.
- Machine translation shipped as final for real languages. It can draft; a fluent speaker signs off, and for Hawaiian and Navajo a qualified community speaker must review the work; any additional public credit
requires Nick to revise the repository's attribution policy, since these are living languages with communities who care how they are used.

## Design

- **Keys, not strings.** Every player-facing string in the client goes through Godot's `tr()` with a stable key (`hud.health`, `menu.solo_scrap`, `host.round_start.1`). Existing Host/killfeed strings need a deliberate compatibility migration. New
  campaign events carry stable story/objective IDs and parameters, localized by
  the presenter. Agent clients consume typed state rather than parsing translated
  sentences. Never add a second English-string matching path for campaign state.
- **Files.** Godot CSV translations under `client/i18n/`, one column per locale, imported as `Translation` resources. Locale codes follow Godot's list (`en`, `es`, `ja`, `de`, `fr`, `pt_BR`, `zh_CN`, `ko`, `fr_CA`, `en_AU`, `haw`, `nv`, `eo`, `tok`). Joke locales use private-use tags (`x-pirate`, `x-leet`, `x-continuance`, `x-deadair`) so they never collide with a real one.
- **Fonts.** The pixel font must cover every glyph a locale needs. Latin and Cyrillic from the current font; Japanese, Chinese, and Korean from a permissively licensed pixel CJK font added as a fallback in the theme; Hawaiian needs the okina and macron vowels (Latin Extended); Navajo needs ogonek and slashed l plus tone marks (Latin Extended and combining marks), which the HUD font must actually render, checked by the tour.
- **Layout.** German and Finnish strings run about a third longer than English; the HUD grid reserves width or abbreviates by key (`hud.armor.short`). Number and time formats go through locale-aware helpers, not string concatenation.
- **Lore locales.** Continuance officialese is English rewritten as bureaucracy ("Health" becomes "Continuance Index"); Dead Air replaces random glyphs with static blocks and is meant for one match of fun; both are written in-house and are part of the joke, not translation work.
- **Selection.** Settings menu, plus `--locale` on the command line and the OS locale as the default. The QA tour captures the HUD in every locale to catch clipping and missing glyphs.

## Process

1. Extract: use native Godot extraction where applicable and validate the explicit campaign
   text catalog, keys, placeholders and referenced resources. A broad regex over
   every string cannot decide which literals are player-facing. Review that
   semantic boundary; no additional extraction tool exists yet.
2. Draft: draft translations stay explicitly marked in production data and out of the
   public locale list until reviewed.
3. Sign-off: a fluent speaker reviews a locale; the status column flips; follow the existing sole-public-identity policy and required legal notices;
   do not promise additional public credits without Nick's explicit instruction.
4. Tour: the visual QA tour runs the HUD states per locale; clipping and tofu glyphs are findings.

## Rungs

1. Keys and extraction tool; English and Spanish; the settings switch; tour coverage.
2. Japanese, German, French, Portuguese, Chinese, Korean drafts with the CJK fallback font.
3. Canadian French and Australian English; Esperanto and Toki Pona; the two lore locales; pirate and leet.
4. Hawaiian and Navajo with community sign-off.
5. Captions for the Host and the news station.

## Success criteria

- [ ] No unkeyed player-facing literal in the client (CI).
- [ ] Every shipped locale passes the tour with no clipping or missing glyphs.
- [ ] Real languages carry a sign-off status; drafts are not presented as reviewed translations.
- [ ] Hawaiian and Navajo shipped only with community sign-off.
