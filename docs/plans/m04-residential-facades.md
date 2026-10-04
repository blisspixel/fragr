# M04 west residential facades

Status: **implemented**, 2026-10-04. Base: main `a8611d04`.
Implementation: `098ea633`. [Local evidence](../evidence/m04-residential-facades-20261004.md).
Integration, complete CI and historical-save policy remain with the parent.

The west habitation court currently has personal windows on a five-metre wall,
but no homes behind that wall. Build three adjoining, sealed domestic volumes
aligned with the existing windows at z21, z27 and z35. Their different roof
heights, quiet plaster finishes, maintained window surrounds and repaired roof
edges should explain a shared neighbourhood at ordinary fighting distance.
The north home stays low enough for the communal tank to remain a landmark.

## Scope and authority

- Add substantial home bodies and roof-edge structures behind the existing
  west wall as server-owned solids. Keep the existing court-facing wall,
  windows, balcony lanes, crossing, stairs and departure unchanged.
- A bounded M04 presenter follows exact registered footprints. Surface dressing
  stays inside those bodies or within the existing eight-millimetre wall relief.
  It does not imply doors, accessible interiors, additional cover or use targets.
- Reuse existing Low Water materials and textures. Keep black/red on issued
  outfits and gear. Do not change shared shaders, lighting or backdrop helpers.
- Preserve all mission facts, six encounters, 28 guards, finite supplies,
  clinic worlds, patient routes, deadlines and ordinary-input departure gates.
- No paid calls. Shared documentation and integration remain with the parent.

## Verification and evidence

Before rendering, load both authoritative clinic worlds, replay the existing
ordinary-input routes and arrival tolerance, prove new bodies stop movement and
shots, and check court Notary sightlines and supply/navigation reachability.
Verify exact-footprint restraint and actual final mesh bounds in the existing
M04 client harness. Run the complete client checker with a private matching
native server, preserving logs and each harness marker.

Coordinate the GPU lane before a complete ordinary-input M04 tour. Inspect
ground-court, balcony and departure views, not only a detached overview. Preserve
all original guard, patient, encounter and departure assertions. Record attempts,
map/source hashes, equipment and damage outcomes, actual process cleanup and
remaining art limits in a unique evidence file. Full eventual CI is required
before integration; this branch does not push, merge or release itself.

## Risks and content implications

Higher west geometry could obscure a Notary, make an unintended roof shortcut
or hide the tank. Test actual shot lanes and movement rather than assuming an
outside-wall change cannot affect combat. Three plain boxes would not meet the
visual gate: roof silhouettes, aligned windows and deliberate domestic finishes
must form readable homes. No new rooms, entrances or mission gates are promised.
Authored geometry changes the content hash. Existing run-file hash validation
must remain strict; historical save compatibility needs an explicit integration
decision, not a silently relaxed validator.

## Local result

The 32-state ordinary-input tour passes six probes, all 28 guards, 134 walking
arrivals, clinic release and actual departure. It records zero deaths, 100 HP
lost and 150 armor lost. The north roof is truthfully reachable from the existing
exit-deck jump onto the north wall; native integration proves ordinary return
around the tank. The original stair route remains the live capture route.

Both clinic worlds pass 27 focused unit checks and two real local-child carry
checks. Complete server verification passes 873 unit tests with three existing
ignored, 18 binary tests and 26 integration tests. Server Clippy and formatting
pass. Complete client verification passes 233 scripts, 108 harnesses and all
342 expected labels, with exit zero and clean error logs.

The additional Windows fake-checker sweep was deliberately canceled after its
first scenario passed because repeated shell spawning was slow. Its partial log
is retained, not accepted as the complete verifier self-test. The full normal
Linux CI verifier gate remains required before integration. No renderer or
owned native server remains running.

## Main integration

The implemented slice ships with the combined main integration of
[PR #348](https://github.com/blisspixel/fragr/pull/348).
[Combined evidence](../evidence/game-buildout-20261004.md) records local checks;
fresh implementation and desktop-package CI remain required before publication.
Wider acceptance limits recorded above remain open.
