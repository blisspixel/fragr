# Directional combat audio

**Status:** in flight, 2026-10-04. Nick: "make sure the sound has like 3d so if
being shot at you can hear direction."
**Spend:** $0 for the code. Any new near-miss or impact source sounds go through
`tools/audiogen` on included credits.

## What exists

Every fighter's fire, hit, windup tell and fall sounds play from an
`AudioStreamPlayer3D` on that fighter's pawn (`player_pawn.gd`), on the Effects
bus with distance attenuation. Crawler scrabbles are spatial too. A shot from
your left already pans left and fades with distance. Pickups, the scope and dry
fire are deliberately non-spatial, because they are your own.

What is missing is the feeling of being shot at: knowing the direction and the
danger of fire you did not see.

## Goal

Every incoming shot gives direction through three signals, as the fun bar asks
of every hit: audio, a visual cue, and the HUD.

1. **Near misses.** A resolved shot whose path passes within about 2 m of the
   local camera plays a short supersonic crack or whiz at the closest point of
   its path. This is computed from the server's existing `ShotTrace`. Each weapon
   family has its own character (pellet zips, rifle crack, Rail hiss), and
   the cue is rate limited so a firefight does not become noise.
2. **Damage direction.** Taking a hit shows a pixel-art arc at the screen edge
   toward the shooter, fading over about a second. The hit thud pans toward
   the source rather than playing centred.
3. **Occlusion.** A spatial source behind solid geometry, by a ray against the
   authoritative map solids at a bounded rate, gets a low-pass and a small
   volume cut. A shot through a wall sounds behind the wall.
4. **Space.** Per-venue reverb sends (tight interiors, open yards, the lunar
   port's pressurized halls) keep the tails short and readable. Exterior
   lunar vacuum carries contact and suit sound only, per the
   [effects refresh](audio-effects-refresh.md).
5. **Mix check.** Verify the panning law and attenuation on headphones and
   stereo speakers. If Godot 4.7 offers a better panning or HRTF option for the
   pinned renderer and platforms, check it against the documentation and
   evaluate it.

## Non-goals

- No server change. Direction comes from facts the client already receives.
- No sound that reveals information the player could not otherwise have, such
  as footsteps through floors at unrealistic range.
- No paid middleware.

## First bounded slice, 2026-10-04

Build incoming pass-by cues and a restrained pixel damage bearing together.
Reuse the strict resolved trace parser in `shot_effects.gd`, the validated
MapInfo geometry and the existing line-of-sight helper in `aim_assist.gd`.
The server already carries the resolved source, stopped segment and pellets;
its positive committed damage includes armor. Zero damage, another target,
missing traces and HP changes alone cannot establish a damage bearing. The
source remains the resolved origin even when the shooter has died or moved.

The new presenter owns a bounded Effects voice pool and a separate pointer-free
HUD overlay. Its local human owner and first-person camera are explicit; roles,
map replacement and disconnect clear the voices and indicators. A final traced
hit can briefly indicate the committed damage before death; dead spectators
cannot start pass-by audio. Bearings follow the current view during their fade.

Pass-by candidates stay on the finite resolved segment, within 2 m, beyond
the muzzle and before the stopped endpoint. Repeated pellets share one cue per
shooter, with a bounded global cadence. A short connector from the closest point
to the listener must pass authoritative solid visibility before audio starts.
This narrowly prevents through-cover pass-by disclosure. It does not implement
the broader occlusion filter goal above.

There is no dedicated committed pass-by recording. Bake short deterministic
mono 48 kHz noise accents offline in GDScript, with distinct pellet, rifle and
Rail envelopes, and commit their source recipe and WAVs. Runtime only loads
those files; there is no synthesis or paid operation during play. They remain
subject to listening acceptance.

Acceptance for this slice: strict boundary failures, cardinal and diagonal
bearings with yaw and pitch, segment endpoints and radius, actual target and
zero-damage ownership, scatter aggregation, walls and raised slabs, snapshot
deduplication, cadence, bounded voices, fade and teardown. Inspect rendered
four-direction examples and keep synthetic presentation examples distinct from
an actual server-resolved play check. Directional impact thuds, general
occlusion/low-pass, venue reverb, vacuum sound, HRTF evaluation and headphone/
speaker listening remain open. No whole-plan completion claim follows from
this slice.

The pinned 4.7.2 binary exercised the node properties in the harness. The
[official AudioStreamPlayer3D reference](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html),
checked 2026-10-04, describes camera-based listening, Effects-compatible bus
routing, stereo panning and explicit stopping. This slice uses that established
spatial player path and does not claim an HRTF implementation.

## Verification

- **Harness tests:**
  - Closest-approach math on known shot paths.
  - The near-miss radius and rate limit.
  - The damage arc angle for shooters at the cardinal and diagonal bearings.
  - Occlusion on and off against a known wall.
- **Rendered capture:** damage arcs from four directions, inspected.
- **Listening note:** a headphone pass with bots firing from each side, behind
  a wall and at range. Like every listening result, it is recorded as
  subjective evidence, separate from automated checks.
