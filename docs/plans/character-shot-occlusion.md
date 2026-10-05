# Character shot occlusion

Status: in flight. Date: 2026-10-05.

## Problem and bounded contract

Resolved rays currently skip Latch, participant bodies in front of Latch and
spawn-shielded fighters. Traveling pulses also skip protected bodies. Damage
immunity must not make an eligible living body transparent. Reuse the existing
authoritative contact eligibility for fighters and existing reachable civilian
contact feet, rather than inventing NPC health or a second position source.
All guns stop at the nearest actual intersecting eligible body. Dead, absent,
respawning, eliminated, detached and story-inactive bodies retain their existing
contact eligibility. World cover remains authoritative and takes precedence
when closer.

Keep Latch immune to incoming damage and keep spawn shields immune while active.
Preserve existing self-damage from committed explosives and projectile
lifetimes. Friendly-fire rules continue to own damage, separately from physical
obstruction. Humans, agents and rule bots use the same body rule.

Neutral civilian stops use an existing Fighter trace impact with hit false,
no target ID, no target HP and zero damage. Do not invent a health or death
system for those contacts. Collect authoritative civilian contacts once per
combat tick and share them across pellets. Traveling Jammer pulses stop on the
same eligible bodies. Latch's limited-shot preflight must not knowingly fire
through living blockers merely because those blockers are immune.

## Verification

Write owning real-tick tests before the fix and retain their initial failures.
Exercise all six gun families, nearest-body ordering, companion victim and
companion firing, mixed human/agent teammates with friendly fire off/on,
shielded bodies, inactive controls and reachable neutral contacts. Inspect
existing transparency assertions and update only assertions invalidated by the
new explicit contract, retaining route, death and finite-equipment gates.
Add a focused client neutral-impact regression, preserving the wire shape.
Visible provisional figures must share validated authoritative body positions
or have actual enclosing cover proved, rather than being silently excluded.
The M08 registry figure and four captives are a separate bounded registration
pass, with exact visible phase positions and no new health or death rules.
Audit the M06 family window, M07 resident and M02 tableaux under the same rule.
Do not approximate a hovering decorative machine with a grounded human body.

Use a private Cargo target, jobs two and incremental compilation disabled.
Run focused regressions, formatting, denied-warning Clippy and the full locked
workspace suite before integration review. Matching client checks, exact CI
and package evidence remain required before publication. This work does not
change main, paid assets, campaign design or runtime artwork selection.

## Current checkpoint

The original production tree with the first five regressions failed four:
companion transparency, shield transparency, protected-body traveling pulse
and ineligible detached or eliminated bodies. Existing teammate obstruction
already passed. The corrected core subsequently passed ten real-tick tests,
thirteen traveling-shot regressions and sixteen companion regressions. The
client neutral-impact harness also passed with one world impact and no damage
marker. These are focused development results, not final integration evidence.

A later two-test failure came from diagnostic feet placement retaining random
spawn facing for direct pulse launches. Explicit test facing corrected the
fixture, while ordinary Jammer fire and all production gates stayed unchanged.
An intervening build read incomplete neutral registration files and failed to
compile; retain that receipt and wait for the shared source checkpoint before
final compilation. Full workspace, client, neutral registration, renderer,
CI and package acceptance remain open.

## M02 visible tableau boundary

Before any real companion snapshot, the restrained FIRST figure is visible and
exposed inside the ward. During the existing Releasing phase, a real companion
already exists at the server's SECOND feet while the current presenter hides it
and moves its local figure independently. Show the authoritative pawn as soon
as that snapshot exists and hide the old tableau. Preserve the 240-tick phase,
dialogue, restraints, objective state and ordinary input rules. Do not register
a second animated companion or invent NPC health.

The passive Notary has a global ceiling and bay glass, floor and walls. Measure
the actual source mesh with its complete bob/sweep envelope and prove those
world solids enclose it, including elevated and off-axis rays. If enclosure
passes, it needs no extra body. The second captive is exposed from the ward;
its rotated local placement and source figure height need exact accounting,
not a guessed standard humanoid height. A bounded static source-box registration
and a shared validated placement helper may cover that figure without creating
a moving or damageable NPC. Keep the earlier wrong unrotated diagnostic position
as a corrected measurement, not a new canonical foot location.

The bounded implementation now shares twelve original second-captive parts and
their exact rotated transforms, including the existing 12 cm opening movement
derived from authoritative phase-start and snapshot ticks. They are shot-only
geometry, not added world solids or walking bodies. The first real Releasing
pawn takes over visible Latch presentation immediately. Native focused tests
and source goldens pass; the passive Notary's entire mesh/bob envelope is proved
inside actual sealed cover with a removed-glass negative control. Keep those
source results distinct from the pending ordinary rendered release witness and
final full integration checks. The witness also records the actual companion
presenter, packaged skinned source, visible meshes and source hash; technical
3D routing alone does not establish accepted character appearance.

The complete workspace exposed one photograph-fact dependency: making a
protected participant opaque must not make it eligible for a Notary photograph.
Retain the prior positive shield exclusion in the photograph predicate only.
Actual protected bursts remain physical target hits with zero damage; the
owning regression keeps zero photographs, unchanged front and rear HP and the
original dry/invalid controls. The focused correction passes; final full checks
and the ordinary hardware witness remain open.
