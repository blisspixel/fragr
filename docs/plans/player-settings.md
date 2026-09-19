# Player settings

Status: in flight, 2026-09-19. Branch: `feat/player-settings`.
Review: [PR #168](https://github.com/blisspixel/fragr/pull/168).
Spend: $0. No protocol, simulation, dependency, or paid-service changes.

## Goal

Make the controls offered by the retro menus real, persistent, and usable during
a match. The current front menu changes display/audio state without saving it;
the settings file contains unused keys, and sensitivity only works in the console.

Use one shared settings panel and the existing `FragrSettings` store. Draft edits
apply only after a successful save; Cancel and Escape discard them. Validate
types, finite numbers, ranges, and enumerations before values reach the engine.
Retain profile preferences. Retire unused keys instead of implying they work.

Supported controls: mouse sensitivity, invert look, keyboard/stick turn speed,
weapon bob, vertical FOV, windowed/fullscreen, VSync, frame cap, and master/radio/
effects volume. Add actual audio buses and route existing players. Existing
reserved sensitivity and FOV values never affected play, so new explicit keys
start at the currently rendered defaults rather than reinterpret old units.

Share the panel between boot and match menus. Block both mouse and gamepad look
while an overlay is open. Use unscaled mouse motion and accumulate events so aim
does not change with display scaling or drop input between frames. Console
controls must use the same validated persistence path.

Not included: key rebinding, render-quality presets, renderer switching, resolution
selection, predictive movement, authoritative pitch, or the rendered benchmark.

## Verification

Official Godot 4.7 documentation checked 2026-09-19:
[ConfigFile](https://docs.godotengine.org/en/4.7/classes/class_configfile.html),
[mouse motion](https://docs.godotengine.org/en/4.7/classes/class_inputeventmousemotion.html),
[Camera3D](https://docs.godotengine.org/en/4.7/classes/class_camera3d.html), and
[DisplayServer](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html).
Use `screen_relative` for captured aim. FOV is explicitly vertical with KEEP_HEIGHT.
VSync availability depends on the renderer/platform; do not promise its support.

- File round trips, malformed types, nonfinite values, range limits, and failed saves.
- Actual panel save/cancel and shared runtime application to camera and buses.
- Input accumulation, inversion, and overlay blocking, including active gamepad.
- Existing Godot checks and desktop CI; current rendered tour extended with all
  settings tabs and the live-match settings panel. Isolate its settings file.
- Inspect readability, focus, clipping, and return-to-match behavior in captures.

## Acceptance

- [x] Every offered setting survives a fresh store and reaches its runtime reader.
- [x] Cancel never mutates saved or active preferences; failed saves stay visible.
- [x] Scaling does not change mouse counts, and menus cannot move the camera.
- [x] The shared pixel panel works at the boot menu and inside a live match.
- [x] Verified commands, screenshots, roadmap, and limitations are current.

## Implementation and evidence

`SettingsPanel` owns a draft, while `FragrSettings.commit` writes before notifying
runtime readers. Saves write beside the destination before replacement; a failed
write leaves active values unchanged. Unknown keys and wrong types fall back
safely. Numeric inputs require finite values and bounded ranges. Legacy exclusive
fullscreen maps to portable fullscreen. Frame-cap choices include unlimited and
common refresh rates while preserving a custom saved value.

The camera reads explicit `mouse_sensitivity` and `vertical_fov` keys, starting at
1.5 and 75 degrees. The old reserved keys had different units and no runtime reader;
they are ignored. Existing callsign, reticle, bob, and broadcast preferences remain.
The audio layout routes radio separately from weapons, hits, and round cues.
Zero volume mutes the selected bus. Console settings use the same commit path.

Godot 4.7.2 import, script parsing, and all 12 harnesses pass locally. Tests cover
save/cancel, invalid types and nonfinite values, range bounds, failed writes,
camera FOV/aim, audio routing/muting, frame caps, console persistence, and match
menu navigation. Input checks exercise accumulated unscaled motion, mouse and
stick inversion, and overlay blocking. A routing-test fixture isolates its catalog
after random full-track playback exposed an unrelated decoder shutdown race.
The focused test then passed five consecutive clean runs; the full checker passed.

OpenGL Compatibility and Vulkan Forward+ each passed the expanded 18-state tour
on Windows/Radeon 780M. Contact sheets, all settings tabs, and the live-match
panel were inspected; current screenshots were refreshed. Local receipts are
under `.agents/qa/settings-release`, `.agents/qa/settings-vulkan`, and
`.agents/settings-godot-verified.log`. Desktop CI remains the integration gate.

No Rust source changed. The prior verified simulation/benchmark behavior is
preserved. This does not establish rendering on other GPU vendors or complete
key rebinding, render presets, the GPU benchmark, or campaign content.
