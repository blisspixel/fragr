# Plan: every input device feels right

**Status:** implemented (2026-09-24). Keyboard only, keyboard and mouse, and
gamepad are implemented with headless harnesses; hardware feel on real pads
and high-refresh monitors still needs a person holding them.
**Branch:** `feat/input-all-devices`
**Spend:** $0.

## Goal

"You can play keyboard only, but you can also play keyboard and mouse, or a
controller. All need to work great." Every device produces the same discrete
actions on the same wire. Nothing here changes the server, the protocol or the
120 per second input pacing in `game_manager.gd`.

## Non-goals

- Analog movement on the wire. The server reads four direction bits, so the
  left stick is quantized to eight directions after a radial deadzone.
- Server-side aim assist, hit forgiveness, or a host rule for assist. The
  follow-up for multiplayer lanes is recorded in [`fair-play.md`](./fair-play.md).
- Stick rebinding. The left stick moves and the right stick looks; every
  button, trigger, key and mouse button is rebindable.
- Maker logos. Gamepad glyphs are original 16 pixel sprites generated in code.

## Default bindings

| Action | Keyboard only (right hand on the arrows) | Keyboard and mouse | Gamepad |
|---|---|---|---|
| Move | Up and Down arrows | W and S | Left stick, eight directions |
| Turn | Left and Right arrows | Mouse (Q and E also turn) | Right stick |
| Strafe | Hold Alt with Left or Right, or Comma and Period | A and D | Left stick |
| Look up and down | Page Up and Page Down | Mouse | Right stick |
| Centre view | End | End | Right stick click |
| Fire | Ctrl (either side) | Left mouse | Right trigger |
| Use | Enter | F | B / Circle / East |
| Jump | Space | Space | A / Cross / South |
| Weapons | 1 to 5, [ and ] | Wheel, 1 to 5 | LB and RB |
| Scores (hold) | Tab | Tab | Back |
| Match menu | Esc | Esc | Start |
| Taunt | T | T | Y / Triangle / North |

Choices: both Ctrl keys fire so either hand can shoot. Enter is Use because it
sits beside the arrows and does not collide with anything in play; F stays Use
for WASD players. Alt is the strafe modifier, as in Doom; Comma and Period strafe
without it. Page Up, Page Down and End are the Duke Nukem 3D look cluster.
Start opens the match menu instead of leaving the match; leaving is in that
menu. F also changes the watched fighter while spectating, and A also joins
from spectating: those pairs never apply at the same time, so the conflict
check treats them as separate contexts.

## Architecture

| Piece | Home |
|---|---|
| Rebindable actions, tokens, defaults from `project.godot`, conflicts, InputMap rebuild | `client/scripts/input_bindings.gd` |
| Persisted overrides (`[bindings]`, one string per changed action) and look settings | `client/scripts/settings.gd` |
| Last device for prompts, look source for assist, pad layout from name or vendor | `client/scripts/input_device.gd` |
| Key names, pad names, pixel glyphs, prompt templates | `client/scripts/input_glyphs.gd` |
| Key ramp, radial deadzone, curve, turn boost, stick to eight directions | `client/scripts/look_input.gd` |
| Keyboard and gamepad aim assist | `client/scripts/aim_assist.gd` |
| Camera applies look, assist and centring | `client/scripts/spectator_cam.gd` |
| Strafe modifier and stick movement into Action | `client/scripts/game_manager.gd` |
| Controls (rebinding) and Look pages | `client/scripts/settings_panel.gd`, keyed in `client/i18n/controls.en.po` |

### Keyboard only

Turning ramps from 20 percent to full speed over 0.25 seconds, integrated
exactly, so the angle never depends on frame rate. A one frame tap at 144 Hz
turns 0.22 degrees; a deliberate 80 ms tap turns about four degrees (Doom's slow
first tics gave about five); a hold reaches the Key Turn Speed setting (default
160 degrees per second). Look keys use 60 percent of that rate. Optional
auto-centre levels pitch after 0.6 seconds of walking without a look key.

### Keyboard and mouse

Unchanged path: `screen_relative` counts summed in `_input`, applied on the
next frame at 0.022 degrees per count times sensitivity, never multiplied by
delta, never smoothed and never assisted. The Look page shows centimetres per
turn at 800 counts per inch. High-DPI and high-refresh behaviour follow from
that: counts are unscaled by the window's content scale (asserted in
`test_aim_sensitivity.gd`), and all counts that arrive between two paced sends
are in the absolute yaw the next send carries, so a 500 Hz display and an 8000
Hz mouse lose nothing. This was measured by harness, not on hardware.

### Gamepad

Radial deadzone (default 0.12, outer edge 0.95) with rescale, a response curve
on magnitude only (default exponent 1.8), separate turn and pitch speeds
(defaults 240 and 150 degrees per second), and an optional turn boost of up to
80 percent after the stick has sat at its edge for 0.35 seconds. Triggers fire
through the InputMap with a 0.2 deadzone. Menus use the d-pad or left stick,
A to choose and B to go back; LB and RB change settings tabs.

### Aim assist

Off, Light or Standard; Standard is the default. It never runs while the mouse
is the look source: mouse motion claims the look, and only turn or look keys or
gamepad input give it back, so a mouse player pressing W is never assisted.
Only visible hostiles count (Union enemies on a mission map, other fighters in
an arena), within 40 metres, with line of sight tested against the MapInfo
solids by the same slab test the server uses. It only moves the yaw and pitch
the client already sends.

| | Light | Standard |
|---|---|---|
| Vertical autoaim cone (either side, plus the body's own width) | 4 degrees | 6 degrees |
| Keyboard pitch pull (rate per second) | 6 | 9 |
| Yaw pull cone | 2 degrees | 4 degrees |
| Keyboard yaw pull | 2 | 3.5 |
| Gamepad slowdown near a hostile | 0.7 | 0.5 |
| Gamepad pull, only while steering | 1.2 | 2.2 |

Feel, honestly: on the keyboard the vertical help is the big one. It makes
height differences a non-issue the way Doom's autoaim did, and the yaw pull is
small enough that a player still has to turn onto a target; in the live
harness the arrows do the turning and assist tidies the last degree or two.
On a gamepad the slowdown is what a player will notice; the pull is mild and
needs the player to be moving the stick. Neither has been tuned with a person
yet.

### Prompts and glyphs

Prompt copy names actions in braces (`{use}: READ TRANSFER RECORD`). The use
prompt and the continue-after-death card render keycaps on keyboard and 16
pixel glyphs on a gamepad, and switch on the next input from the other device.
Letter layout for Xbox-style pads and XInput, shape layout for Sony names and
vendor id, positional (south, east, west, north) for Nintendo and unknown pads.
The HUD legend, loading card, pause hint and boot menu hint use the same names
as text.

## Verification

| Harness | Covers |
|---|---|
| `test_keyboard_only.gd` | Default keys, ramp and frame-rate independence, strafe, look, centre, auto-centre, keys to the wire |
| `test_keyboard_m01.gd` | Live local M01: menus by arrows and Enter, story skipped with Escape, walk with arrows, strafe keys, turn onto and kill the intake guard with Ctrl, Enter to use |
| `test_gamepad_look.gd` | Radial deadzone, curve at five magnitudes, rates, boost, eight-way movement, camera, settings |
| `test_rebinding.gd` | Tokens, strict parsing, conflicts, persistence, InputMap rebuild, reset, Controls page capture, keyed labels |
| `test_input_glyphs.gd` | Layout detection, device switching, prompt text per layout, glyph sprites, HUD prompt follows the device |
| `test_aim_assist.gd` | Cone, range, line of sight, device gating, gentle frame-rate independent pull, pad friction, mouse untouched |

Plus `tools/godot_check.sh`, `tools/test_godot_check.sh`, and tour stills of
the Controls page and an in-game prompt with keyboard and gamepad glyphs.

## Open

- Real pads: layout names on Linux and macOS drivers, trigger ranges on older
  pads, and stick drift on worn hardware.
- A person playing M01 by keyboard only from start to departure. The harness
  covers the first fight and every action, not the whole mission.
- Assist tuning with players, and the multiplayer lane rule in `fair-play.md`.
- Menu copy on the Display, Graphics and Audio pages is not keyed yet.
