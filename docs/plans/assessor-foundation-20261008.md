# Assessor combat foundation

Status: **shipped** in [PR #375](https://github.com/blisspixel/fragr/pull/375),
released as v0.80.0. This is the heavy drone required by the
accepted [M12 brief](../campaign/m07-terms-of-cooperation.md#level-12-design-twenty-level-expansion)
and [flying-drone contract](flying-drones.md). The connected habitat passes
its complete seventeen-state route and durable departure. Fresh-player and
final-art acceptance remain open. This foundation runs
beside the [Arc](arc-foundation-20261008.md),
[Low Water Sabotage](low-water-sabotage-20261008.md) and
[Edda repair](edda-live-repair-20261008.md) increments under the roadmap's one
build order. Existing Notary behavior and original enemy timings stay intact.

## Actual enemy and attack

Add the distinct `assessor` equipment role with 240 HP, a 2.6 m wide by 1.2 m
high raised target, four fans, two countdown optics, a folding launcher and
rear recovery vents. Its bounded authored hover volume has a 3-7 m underside
band, a grounded ordinary-gun approach, full body clearance and no general air
path search. Reuse the Notary's registered hover and supported fall machinery
with explicit role dimensions. The role is never a renamed Notary or enlarged
ground bot.

The committed attack has three actual visible canisters, six ticks apart.
Windup/recovery are 32/50 ticks Assisted, 24/40 Standard and 18/32 Severe,
following the existing drone plan. Locked aim does not track a dodging player.
Broken sight cancels unlaunched shots; damaging stagger cancels the remaining
volley. Canisters already launched remain committed through owner death.
Thirty canisters bound one spawned drone's stock, with at most six live per
owner and 64 total. Exhausted or refused launch capacity never creates a
hitscan substitute.

Use a finite ballistic projectile with an explicit low-arc solution to the
locked target, bounded speed/gravity and four swept substeps per server tick.
The initial fixed speed is 12 m/s and gravity is 4 m/s squared, with a 24 m
horizontal engagement limit. A low-angle ballistic root must exist before
windup and before an actual launch can spend stock.
Reuse the grenade's radius-expanded surface contacts and covered blast resolver.
Contact with floor, solids, vehicles or a living supported body resolves an
impact immediately. A maximum eighty-tick flight removes an unresolved round;
there is no delayed invisible shot. Initial splash is 45 at the centre,
linearly falling to zero at three metres. The ordinary hostile/friendly,
spawn-shield and mission-active policies still apply. Actual nearest raised
body volume controls splash distance and cover.

Front and underside plates halve traced bullet damage; rear hits during
recovery receive full damage. The new Arc and resolved splash bypass plates.
Resolved impact normals select the front, belly and rear vents. Closed rear
vents halve damage until recovery opens them; side and top faces stay exposed.
Scatter applies that face rule to each resolved pellet before its one armor
commit, so a mixed front/belly/flank result never borrows its first face.
Apply this through the shared damage seam, preserving effective-damage records.
The falling wreck resolves once at supported landing, damaging only living
Union bodies within 1.5 m through actual cover. Participants, companions and
civilians are never wreck targets. The wreck does not block movement. All
canisters, launch stock and pending wrecks use the existing encounter/map/retry
and explicit-leave cleanup ownership. Process ticks and serials never rewind.

## Boundaries and compatibility

Reserve gameplay 43 for the Assessor and its strict snapshot canister facts;
Arc uses 42, connected M12 reserves 44 and Low Water Sabotage uses 45. Older
maps keep their own feature requirements. Clients reject malformed ids,
non-finite positions, unbounded velocity/age and unknown role/state combinations.
The server and client advertise the aggregate implemented capability.

Adding the Assessor timing row advances campaign rules to revision 4. Preserve
unchanged earlier enemy numbers. Explicit historical rules-3 records and earned
proofs remain valid historical evidence; they must not disappear or be silently
rewritten. A live campaign with rules 4 requires a capable reader. Save version
15 strictly upgrades the exact v14 shape through the existing locked writer
and original-byte archive, retaining actual equipment and prior outcomes.
Every older decoder rejects forged Arc ownership despite the widened enum.
New M12 entry initially has no Arc until the actual find. Record compatibility,
save promotion and live admission each require their own focused negative
controls. No alternate readiness, save or server control channel is introduced.

## Presentation and verification

Build an original articulated mechanical presenter with local geometry and
retained materials. Phases follow authoritative deadlines, launch positions,
canister motion, recovery and death. Visual size changes and launcher motion
make windup readable without color or sound. Bounded local countdown, fan and
impact cues use committed audio or authored offline sound; no paid asset stage.
Actual health loss briefly flashes the mechanical skin through the existing
pawn feedback seam, then restores its authored materials without moving it.
Do not let cosmetic shadows, bob, camera effects or rendered projectiles
decide collisions or damage.

Test exact dimensions and all tier windows, finite three-shot locked volleys,
actual traveling impacts, dodge and cover, nearest-body blast, plate faces,
Arc/splash bypass, stagger/cancellation, owner-death commitment, flight/live
caps, cleanup/reset and one-time Union-only supported wreck damage. Strict
authoring rejects clipped hover and unreachable gun approaches. A bounded
ordinary-input lesson must actually find its supplies, fight the new role and
retain native outcomes plus inspected motion at player height. Accurate aim
establishes authoring, not human balance or final art. Final shared native,
client, network, renderer and export gates wait for source freeze.

Connected M12 also needs its shelter, pump, aid, coalition and departure facts,
their retry/carry contracts and ordinary route acceptance. Those receive a
separate bounded mission plan before implementation; this foundation alone
does not unlock the campaign. The broader goal continues after this increment.

## Local verification checkpoint, 2026-10-08

Sixteen focused native cases pass, including all tier windows, actual finite
thirty-round stock, three-round spacing, travel, cover, dodge, plates, mixed
Scatter faces, launch refusals, owner death, cleanup and supported wreck damage.
An actual landing test requires the registered Clerk victim's dead phase in the
same tick. This caught and repaired wreck resolution while the encounter
registry was temporarily taken: damage now resolves immediately after restoring
that registry, so both controller death and M12 squad receipts see the real
membership. Parked fleets and alternate prepared worlds now validate the actual
flying role's dimensions, with a narrower-Notary passing control beside a
wider-Assessor rejected overlap.

The separate development court passes sixteen walking routes and a finite
human `GameSession` lesson: 372 ticks, fourteen Arc shots, one reload, three
launched canisters and three contacts, one 240-HP drone defeated, zero deaths,
zero health loss and 51 armor lost. Inputs find the ordinary forty-Cell pickup,
cross the actual encounter region and dodge the initial volley before firing.
The retained earlier lesson failures did not prove visible travel: one killed a
dormant drone too early and one stopped outside the activation region. The
corrected fixture changes ordinary inputs, never supplies or combat rules.

Focused Assessor and AimAssist client gates pass after a fresh editor import.
The target centre is the actual 0.6 m midpoint of the 1.2 m raised body. The
latest controlled renderer fixture, rig SHA-256
`93854239322ea6beb477d715b357b390483fd6608f266ad3be75527a0e378172`,
records sixteen lighting/phase stills and a sixteen-frame physical windup strip
on an AMD Radeon 780M using the compatibility renderer. All sixteen fresh
full-size originals and the strip were inspected, alongside the preceding
articulated version. The final belly plate touches the
support plane without penetrating it. These are controlled fixtures, not played
combat acceptance. An earlier invalid image-format strip is retained as failed
evidence; it was corrected before the clean captures.

The subsequent ordinary socket and renderer lesson completes all five states:
actual forty-Cell discovery, visible volley, an ordinary reload, the registered
240-HP kill and walking departure with a practice record. The native executable
SHA-256 is `f35a6ce41b1ea3d48d121712df99bfd7e6a86b78b2f93900282f5e0faf1d3cff`.
The actual record contains fifteen Arc shots, fourteen hits, 240 effective
health damage, zero deaths, zero health loss and 29 armor lost, with 25 Cells
remaining. Observations retain six distinct launched canisters and twenty
post-draw frames containing actual canisters. The five full-size original
states and sampled travel originals were inspected. Both owned processes
retired, with numeric zero and clean renderer logs. Earlier failed launch and
blocked direct-exit attempts remain retained; the passing input follows the
existing walkable detour around cover.

This combat receipt contains the first Arc artwork, which was subsequently
rejected for size and style. It establishes the ordinary combat sequence, not
acceptance of those weapon visuals. The articulated Assessor is also development art;
its mechanical fixtures do not establish finished material or art quality.

The subsequent current-art lesson repeats all five ordinary states with the
corrected Arc and enemy presenter. It records fifteen Arc shots, 240 effective
HP damage, one kill, zero deaths, zero health loss, 30 armor lost and 25 Cells
remaining. Nineteen actual post-draw canister frames and all five state originals
were inspected. Both owned processes retire with numeric zero and clean logs
on the same pinned native build. The [presentation receipt](../evidence/presentation-corrections-20261008.md)
binds these current captures separately from the rejected-art lesson. The
practice record is incomplete and establishes no campaign best or reward.

Commands and original attempts remain in
`.agents/assessor-foundation-20261008/`. Connected M12, final shared checks,
listening and human feel remain in flight. No release or final art claim
follows from this checkpoint.

## Spend and ownership

$0 new cash and zero paid requests. Reuse existing assets and native tools.
No top-up, overage, service, dependency, cloud apply, commit or publication.
The combat owner edits Assessor and canisters. Parallel owners retain Arc and
campaign saves, Low Water and connected M12, and Edda file ownership. Shared-file
changes are surgical and builds/renderers are serialized. Preserve all existing
dirty work and every earlier dated receipt.
