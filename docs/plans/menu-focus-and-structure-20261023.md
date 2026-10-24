# Menu focus and Multiplayer structure (2026-10-23)

Status: **implemented** on branch `wave1/menus` (local evidence below; Windows
evidence not run). Issues: #435 (mixed-input focus and partial highlights) and
#436 (port tagline and Join vs Host flows). Base: `origin/main` `e4cec37`.

## Goal

1. One unambiguous activation target in every menu under mixed mouse,
   keyboard and gamepad input, with a focus mark that is complete on every
   edge and readable by shape as well as colour (#435).
2. Remove the decorative `CONTESTED FREQUENCY  //  PORT 6767` main-menu line
   and turn Multiplayer into a clear choice between finding a match and
   running one, with the selected server owning its status and actions (#436).

## Root causes (reproduced on Linux before the change)

Baseline captures with the pointer resting on one row and the arrows moving
focus to another (`.agents/captures/baseline/`, run on `e4cec37` at the
window size the tiling session gave, 2256x1504):

- **Two rows looked selected.** `boot_menu.gd` `_styled_button` overrode
  `focus`, `hover` and `pressed` with the *same* StyleBox and set
  `font_hover_color` and `font_focus_color` to the same accent. A hovered row
  and the focused row were therefore identical; Enter activated only the
  focused one. The pause menu showed the same fault through the shared
  `MenuTheme`, whose hover and focus were both an accent frame with accent text.
- **Bottom and left only.** That shared override StyleBox set
  `border_width_left = 6` and `border_width_bottom = 2` and no other edges. It
  was the designed shape, not an engine clip. Under the project's
  `canvas_items` stretch from 1920x1080, a 1280x720 window draws the 2 px
  bottom edge at about 1.3 px, so it reads as a fragment.
- **Hidden click focus.** Godot 4.7's default
  `gui/common/show_focus_state_on_pointer_event = 1` hides focus gained by a
  click on non-text controls (Button draws its focus box only when
  `has_focus(true)`), so after a click the next Enter target could be invisible.
  Checked against the 4.7.2-stable `button.cpp` and `ProjectSettings.xml`.
- **Switched-on toggles drew the accent frame.** `CheckButton` and `CheckBox`
  used the accent `pressed` style for their on state, so every enabled option
  in Settings and Host looked selected.

## Decisions

Shared interaction policy (#435 asked for one): **active-input ownership**.

- `client/scripts/menu_focus.gd` (`MenuFocus`, one per viewport via
  `MenuFocus.attach`). Pointer motion of at least `InputDevice.MOUSE_COUNTS`
  over an enabled, visible `BaseButton` with `FOCUS_ALL` moves focus to it.
  A stationary pointer never steals focus. Guards: the first motion after the
  window regains focus only re-anchors; a focused `LineEdit`/`TextEdit` keeps
  focus; a row partly clipped by a scroll container is not taken (taking it
  would scroll the list under the pointer); disabled controls are never taken;
  captured-mouse gameplay is ignored.
- `MenuTheme` owns every state. Focus is a plate framed on all four edges
  (`FOCUS_FRAME` 4) plus a left rail (`FOCUS_RAIL` 14), drawn inside the
  control's own rect with no shadow or expand margin, so clips and neighbours
  cannot cut it. Hover is a 2 px muted frame without rail or accent. Hover and
  focus text are both bone, because Godot draws a focused, hovered button with
  the hover colour; the plate carries focus consistently. Popup menu items keep
  the accent, since their highlight is the selection. Toggles show their value
  through the switch icon, not the accent frame.
- `MenuItem` theme variation replaces the boot menu's per-row overrides.
  Disabled rows keep a dim frame so they read as unavailable buttons.
- `gui/common/show_focus_state_on_pointer_event = 2` so a clicked control
  shows the plate it now owns.
- Back and Escape go through one `_parent_page` map; the boot menu remembers the
  focused control per page by stable name and restores it on return or
  rebuild, falling back to the first usable button in tree order.

Multiplayer structure (#436):

- Main menu: tagline removed, not replaced. Wordmark and navigation remain.
- `multi` is now a choice page: **Find / join a match** and **Run a match**,
  each with one line of explanation. When this app's server is running, a
  card names the running mode and **Manage your match** leads.
- `join` view: accent headings (no button state uses accent text), a
  **Direct address** row with Check host, then one **selected server card**
  (address, match line, Watch, Join, install offer, Save this host), then
  nearby and saved lists. Choosing a row moves the card under that row and
  scrolls it into view; typing a different address moves it back and
  disables Watch and Join until a new check, so a stale check cannot admit a
  different address. List rebuilds keep the card and focus.
- `host` setup: mode, map and the explicit bot policy first, then
  **Rules, LAN and port** (mutators, friendly fire, LAN, port) folded before
  Start. It opens itself when the remembered profile uses any of them, and
  the remembered mutator is now restored. Running state keeps separate
  Watch, Join and Stop server with a line that nothing joins for you.

## Non-goals

No lobby service, account, discovery backend or internet scan. No change to
LocalHost lifecycle, server flags, wire shapes or gameplay defaults (respawn
delay, starting weapon untouched). No new menu scaling setting: Settings
"Large text" applies to the HUD only today, so there is no menu large-text
mode to verify. No `docs/screenshots` publish in this lane.

## Architecture and protocol impact

Client only. New `MenuFocus` seam (recorded in `AGENTS.md`). No protocol, MCP
or server change. Copy changes in `client/i18n/world.en.po`; unused
`HOST_RUN_SECTION` and `HOST_STILL_RUNNING` removed. Player docs updated:
`README.md`, `docs/PLAYING.md`, `docs/HOSTING.md`. Tour config adds a
`multiplayer_join` state and points `multi-status.json` at the join view; the
README `tour_multiplayer_16x9.png` mapping still uses `multiplayer_menu`,
which now shows the choice page.

## Verification

- `client/scripts/test_menu_focus.gd` (new): real viewport input for pointer,
  keys and pad; asserts focus geometry for every button type in both
  contexts, no per-row overrides, stationary-pointer and tiny-bump
  non-theft, pointer then keys then Enter activating the focused row, hover
  drawn as hover only, click activation, d-pad and A, Back focus return,
  rebuild focus, window focus return, disabled actions, text-field ownership,
  partly clipped rows, toggled switches, and the pause menu.
- Mutation checks: disabling `MenuFocus.follow` failed 8 assertions;
  removing the threshold, window re-anchor, text guard and clip guard failed
  their 4 assertions. Both restored.
- Updated `test_frontend`, `test_host_menu`, `test_multiplayer_layout`,
  `test_menu_theme` for the new structure, including stale-check gating,
  card placement and survival across list rebuilds and drops, the running
  card, Escape routing, disclosure state, and the selected card scrolled into
  view for the twentieth saved host.
- `client/scripts/menu_focus_capture.gd` (new, desktop only, parse-checked in
  the suite): renders into an exact-size SubViewport stretched from the
  1920x1080 canvas and prints the focus owner and hovered control per frame.

## Success criteria

- Exactly one control shows the plate, and it is the one Enter or A activates.
- The plate is complete on every edge at first, last and scrolled items.
- A first-time user sees Find / join and Run a match before any address list.
- Watch, Join and Stop stay explicit; starting a match joins nobody.

## Evidence

Linux host (Omarchy, Wayland with XWayland `DISPLAY=:0`), Godot
4.7.2-stable. Captures under `.agents/captures/` (disposable).

| Check | Result |
|---|---|
| Baseline captures, `e4cec37` | Reproduced both symptoms: two accent rows (main) and two framed items (pause); left and bottom only edges |
| `test_menu_focus` | PASS |
| `test_frontend`, `test_host_menu`, `test_multiplayer_layout`, `test_menu_theme` | PASS |
| Rendered captures 1280x720, 1920x1080, 2560x1440 (main, multi, join, join selected, host, host options, settings, pause) | Inspected; one plate per frame, complete edges, hover frame distinct |
| `tools/godot_check.sh` full suite | see status line below |
| Windows renders at 720p/1080p/1440p, OS scaling 125%/150% | **not run** (Linux host). Run `menu_focus_capture.gd` there with `--size` per resolution |
| Physical gamepad | **not run**; pad covered by injected `InputEventJoypadButton` |

## Open questions for Nick

- Focus text is now bone in every state (the plate carries focus). Keep, or
  prefer accent text on the focused row with the hover inconsistency that
  Godot's draw order brings?
- At the wave-end tour publish, should the README multiplayer still show the
  choice page (`multiplayer_menu`) or the join view (`multiplayer_join`)?
