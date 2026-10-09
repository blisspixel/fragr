# Live character presenters

Status: implemented locally, 2026-10-08. Nick explicitly chose live animated 3D character
meshes after reviewing the retained model inventory. This extends the existing
art-excellence and campaign rungs in the roadmap's single full build order.

## Goal and bounded scope

Present the existing free-human and free-synthetic player bodies as live weighted
skins, and give Tern the same named live body in M09 and M10. Reuse the prepared
sources and retained walking animation. Preserve nearest pixel surfaces, each
body's civilian identity, the current first-person weapons and Latch's established
presentation. Edda's skin repair, Splice's mechanical pivots and the remaining
enemy roster need separate source and motion acceptance.

The current cast sources already exist. The character specialist prepares Tern
offline, with an independent geometry/skin audit. The integration owner packages
accepted compact sources and supplies one reusable live presenter. No paid image,
model or audio request belongs to this increment.

## Architecture and authority

Reuse LatchSource's retained-clip sampler, bone transforms and two-bone helpers.
Runtime presenters must not load excluded offline art scripts or raw downloads.
One allowlisted source registry maps local body ids to packaged GLBs. Unknown
wire bodies remain rejected at PlayerBody; missing presentation assets retain the
existing strip fallback. The boot preview may retain its strip while the moving
pawn uses its matching model.

PlayerPawn retains remote interpolation, local prediction, authoritative health,
body identity, weapons, side labels, first-person hiding and camera ownership.
The live skin follows the same accepted feet and facing. Pose only the weighted
skin for travel, crouch, seated presentation and resolved death; no client
collision, inventory, shot, respawn or mission simulation is added. Keep ordinary
body size at combat distance and do not enlarge a hit flash into a false target.
Carried weapon and muzzle presentation must stay attached to the actual pose,
with speculative feedback retaining its existing confirmation/cancellation path.

M09 and M10 keep their strict geometry/state validation and current survivor
rosters. Their figure containers may hold a typed Node3D presenter or the existing
strip fallback. Only validated current facts establish Tern's presence, feet,
release and ship-pilot placement. Unknown passenger history still shows only the
current pilot. Derive travel animation from accepted displacement; transitions
and stale state must not invent walking. Unproven console hand contacts, separate
finger motion and rescue gestures remain open rather than being implied by a rig.

No protocol/API, capability, campaign-rules, save-format, native dependency or
server-authority change is required by the character work.

## Verification and acceptance

- Bind packaged sources to retained prepared-source hashes and check actual
  skeletons, skin weights, walking keys, texture budgets and legal metadata.
- Prove weighted idle/walk deformation, stable supported feet and adult scale,
  facing, hand attachment, instance-local materials, actor light layers, crouch,
  death/respawn, seat state, near views and first-person visibility.
- Retain body allowlist/role/team validation and M09/M10 unknown-history,
  survivor roster, release, boarding, retry and map-retirement checks.
- Inspect real neutral/dim renderer motion and ordinary-input multiplayer and
  M09/M10 captures. Keep stills, sampled motion, actual played routes and human
  acceptance distinct. Run the full client gate and refreshed standard tour
  after final integration. Run relevant native gates for concurrent level and
  Conquest changes separately from presentation-only checks.
- Check exported resource loading without offline art sources. Other desktop
  platform execution, hosted CI and published packages remain release gates;
  local selection is an implemented development change until those pass.

Record exact commands, source and executable hashes, failures and corrections in
the owning evidence. The earlier October 8 composed checks predate this new
live-character increment and do not establish its correctness.

The first renderer review reproduced fixed-Y carried sprites discarding accepted
gun pitch even though the parent transform followed it. Constrain the profile's
camera-facing plane to the accepted gun axis, with a stable end-on/no-camera
basis and measured image-space grip offset. Recheck steep up/down views without
claiming individual finger contact. Independent failure probes also reproduced
a stale carried anchor after a missing replacement model and a resolved muzzle
cue hidden with a dead shooter's carried root. Restore strip ownership on load
failure and preserve resolved flashes independently of living weapon visibility.
Retain those failures and exercise the actual pawn hierarchy in regressions.

The first ordinary M10 replay exposed an older QA expectation interpreting its
76-round carried pool as the current 20-round magazine. Preserve both finite
counts and the unchanged route. Add an explicit validated `pool_rounds` check
through the existing equipment checker, and migrate only M10's two carry/stock
assertions after observing the exact wire facts. Keep ready-shot assertions
distinct and add a magazine-versus-total regression with negative controls.
Retain the failed attempt; no stock, aim, fight or timing change follows.

## Local result

The [composed receipt](../evidence/live-buildout-composition-20261008.md)
records the final 336-script, 155-harness client gate, 32-state standard tour,
native/network regression and Windows exported-resource smoke. All pass.
The [dual-renderer fixtures](../evidence/live-character-fixtures-20261008.md)
exercise actual weighted vertices and visible carried pitch, with retained
negative controls. The [ordinary crew routes](../evidence/live-crew-routes-20261008.md)
pass 27 M09 and 28 M10 states. Tern follows accepted movement in M09 and remains
stationary as the M10 pilot; visible originals are identified separately from
off-camera samples. M10 uses a labelled historical fixture promoted through the
canonical run loader, rather than a continuous save from that M09 replay.

All three packaged bodies and support curves load from the Windows export
without excluded offline art. Local selection is complete for this bounded
increment. Open palms, pronounced stride, driver contacts and Tern's lighting,
optics, shoulder details and console contact retain their specific art gates.
Other platform execution, integration, publication and human acceptance remain
open. No additional model generation was needed.

## Spend and remaining work

The contact-gait investigation separately traces current civilian placement:
validated mission facts reach M05Town, M09Berth and M10Ship, then
`CivilianFigure.place_feet` assigns the accepted position directly. PlayerPawn's
existing smoothing is a separate path. A held-placement synthetic probe must
not be described as an ordinary rendered observation. The next bounded civilian
presentation increment must test actual mission-update cadence, initial and
lifecycle placement, walking, stairs and turning. Any cosmetic interpolation
must retain accepted server feet for contacts and outcomes, snap new or reset
figures deliberately, and preserve complete-source fallback. Prospective reuse
of the existing player smoothing has its own ignored controls; it is not wired
into current civilians and does not settle gait quality.

$0 new cash and zero paid calls. Use existing models and committed audio. Do not
enable top-ups or overages. The wider named cast, enemy conversions, mission art,
human handling, two-machine LAN and finished twenty-level campaign remain in
their existing owning plans.
