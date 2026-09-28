# M02 custody image prototype

**Status:** superseded, local visual candidate rejected after two rendered passes.
**Spend:** $0. No provider request or cloud resource.

## Goal

Let a player inspect a recognisable image of Latch from the observation gallery,
then connect it to the real restrained figure across the ward. The accepted M02
brief asks the gallery to establish the rescue destination before the Shotgun
and Crawler lessons. The first-person entry capture now points toward Latch,
but the figure is still small at about 21 metres. A closer walk to the window
shows a ward guard and still does not give Latch a readable identity.

The image is a physical Union custody record, not a HUD waypoint. It uses the
same source-owned Latch figure that appears on the frame and later moves as an
ally. The figure remains a person: no serial on their body, skull face, Union
red issue, or invented biography. The record is evidence of the institution's
custody, not a claim that the institution owns Latch. Keep the workshop's bone
head, dark joints, muted cyan chest patch, and rust repair on the right arm.

## Candidate and boundaries

- Bake one original RGBA image locally from `LatchView` with pinned Godot and a
  real renderer. Record its source recipe, output hash, and nearest-filter
  import setting. Do not regenerate the M01 opening or call a paid service.
- Mount the image as a small nonblocking screen on the existing gallery
  window structure. The player can walk and aim normally to inspect it. The
  actual Latch and restraint remain visible from the primary entry.
- No new server solid, pickup, objective, protocol field, combat authority,
  camera takeover, prompt, or route. Use the existing M02-specific presentation
  owner. A brief localized label is optional only if visual review shows it
  helps and it does not repeat the objective card.
- Keep the Shotgun on the upper gallery and the first fight in the guard room.
  The lone Crawler and its cue still precede the pack.

## Acceptance and rejection

Inspect unedited 1280x720 frames from the unforced primary entry and a normal
player-controlled inspection position on the gallery. Keep audio muted for
the visual review. The custody image should show the head, cyan patch and
right-arm repair at native resolution, and its placement should direct the eye
to the actual frame. At one metre it should look like an intentional
institutional object, not a floating portrait or an opaque slab. Reject the
candidate if it reads as a cheap sign, obscures Latch or the window, looks like
Union issue, or adds a competing objective.

Source and renderer checks must prove the output exists and matches the recipe.
The primary entry and the player inspection position must keep blocked combat
lines to the three ward guards. All gallery spawns still reach the Shotgun and
service stair; four-seed Shotgun, ordered Crawler cue, and full M02 route tests
stay green. Run the Godot checker and a live visual tour, inspect the contact
sheet and affected frames. This local prototype does not establish a fresh
player's recognition. Near 1.0, an unsteered player who knows the M01 opening,
with Voice and radio muted and no M02 hint, must identify who is restrained,
point to the real frame, and find the Shotgun and stair without coaching.

## Provenance and handoff

The tested bake used `LatchView` as its only figure source, Godot
4.7.2-stable Compatibility on the AMD Radeon 780M, and no external service.
The source recipe recorded hashes while the candidate was live. No credentials
were used.

## Result, 2026-09-28

The first 1.5-metre screen centered on the gallery header dominated the
unforced 1280x720 entry and looked like a floating portrait. The second pass
used a tighter waist-up crop in a 1.12-metre, flush olive-rimmed panel at the
header's side. It was less dominant, but still looked like a portrait sticker.
The actual restrained figure remained a small, visually separate object below
it. Neither pass met the stated in-world identity and destination gate.

Both three-state local tours completed with unforced first frames and no
client script or runtime error. Each server log has the expected incomplete
WebSocket handshake warning from the tour's TCP readiness probe. The
candidate ward harness passed. The captures remain
in ignored `.agents/qa/m02-custody-prototype/` and
`.agents/qa/m02-custody-small/` in this worktree for review. The runtime
placement, bake source, and generated image were removed after rejection.
Full Rust and Godot gates were not run because no runtime change was retained.
No map, combat, route or protocol change was made, and no player recognition
is claimed. A future gallery identity solution needs a concrete spatial or
performance improvement in the real room, followed by an unsteered player
review. This plan does not direct that later work.
