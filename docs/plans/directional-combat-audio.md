# Directional combat audio

**Status:** planned, 2026-10-03. Nick: "make sure the sound has like 3d so if
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
