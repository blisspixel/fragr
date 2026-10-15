# Campaign, multiplayer and art development round

Status: **shipped**, 2026-10-15. Integration:
[PR #403](https://github.com/blisspixel/fragr/pull/403), release v0.84.0.
This is a bounded composition under the
existing Full build order. Nick requested continued parallel level, multiplayer
and asset work, current research, consistent lore and regular consolidation to
one passing main. The baseline is `902ec8f`, released as v0.83.0. GitHub had no
open issues or pull requests when this round began.

## Goal and ownership

Advance Launch Authority through an actual Continuance Walker encounter, improve
existing multiplayer objective play, and replace the coarse Rocket presentation
with art selected in play. Keep each increment useful and reviewable. Campaign
connection follows the Walker's proven combat and geometry contract; an isolated
range does not establish M14 completion.

- Campaign owns the Walker's strict authored geometry, authoritative attacks,
  damage, relocation, reset and ordinary-action tests. Its first bounded plan is
  [Walker foundation](walker-foundation-20261015.md).
- Multiplayer owns the existing Sabotage bot objective selection. Idle human or
  external-agent proximity must not make all rule bots abandon charge recovery
  or defusing. Actual participant interaction keeps its normal authority.
- Art owns the Rocket idle/fire presentation, retained sources and bounded
  funded production. Walker references follow the actual mechanical dimensions
  and distinct moving parts. Source generation alone is not runtime selection.
- Integration owns client Walker validation, presentation and QA, shared docs,
  account-stage serialization, independent review, full checks and delivery.

No new public mode, cloud deployment, transport rewrite or account system belongs
to this round. Existing campaign saves and development maps retain their identity.

## Design and research

The campaign contract, level 14 brief, art bible and Mars guide own the content.
Teach the Walker alone before combining pressures, visibly lock attack geometry,
provide a useful recovery window and retain supplied infantry routes after losing
the jeep. The Union's issued equipment remains distinct from civilian settlement
materials. Coalition departure must be earned through the encounter, with no
escort timer or new conversation gate.

Primary sources checked October 15:

- [DOOM combat-design presentation](https://www.gdcvault.com/play/1024940/Embracing-Push-Forward-)
  describes aggressive, movement-driven combat. Apply the movement and player
  agency principle within fragr's existing finite ammunition and reload contract;
  do not import another game's economy or identity.
- [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/full-list/)
  supports redundant sensory cues, clear objectives and information that does not
  depend on color alone. Walker danger areas need shape, timing and sound, and
  remain readable with voice muted.
- [Godot 4.7 ArrayMesh reference](https://docs.godotengine.org/en/4.7/classes/class_arraymesh.html)
  is the pinned reference for cached mechanical geometry. Build reusable geometry
  outside the frame loop; animation changes transforms and accepted-state cues.

These are design inputs, not proof of fun. Record ordinary played encounters,
failures, visible counterplay and human feedback separately from automated wins.
Additional API research and exact pricing belong in each production receipt.

## API, protocol and spend

The Walker uses explicit optional map and snapshot facts with a new capability
floor, shared by humans, agents and spectators. Rust owns every attack and hit.
The client strictly validates those facts and mirrors only geometry needed for
presentation and movement reconciliation. Update protocol documentation together.

Use native spritegen and audiogen only. Refresh live allowances before paid
stages, retain the 15-credit uncertain Meshy hold and other unresolved receipts,
price exact requests, serialize submissions and enforce finite credit ceilings
and the existing $5 per-run dollar ceiling. Funded balances do not authorize cash
purchases, top-ups or overages. October 13 observations were 1,870 Meshy credits
(1,855 usable after the hold), 1,160,153 included ElevenLabs credits, and an
unverified reported Higgsfield deposit. They are historical, not live balances.
Public audio selection still needs the distribution and listening gates in the
existing audio plan; do not repeat generation while usable candidates await review.

## Verification and delivery

First reproduce multiplayer defects and prove Walker attack, damage, obstruction,
reset and malformed-boundary behavior. Exercise actual ordinary inputs and finite
equipment. Inspect actual rendered warnings, motion, recovery, death, Rocket rest
and firing, and retain failed captures. A synthetic fixture is labeled as such.

Run locked formatting, clippy, workspace tests, coverage at the unchanged 90
percent floor, release build, dependency checks, relevant live network routes,
roster and soak checks, the complete Godot checker and its self-tests. Publish
and inspect the required visual tour. Independent review covers runtime, strict
boundaries, compatibility, resource ownership and lore consistency.

Deliver through a reviewed PR with passing CI, squash to main, verify main and
package the player-visible change. Return to one clean passing main before the
next production round. Human enjoyment, physical LAN, hardware performance and
finished campaign acceptance remain separate evidence requirements.

## Results

The native account checks on October 15 report 1,870 monthly Meshy credits,
zero permanent credits and the retained 15-credit uncertain hold, leaving 1,855
usable. ElevenLabs reports 24,979 of 1,185,132 included credits used and
1,160,153 remaining. No generation has been submitted in this round. Higgsfield
access and the exact $0.351 candidate price were checked, but its native API
does not report the account's current dollar balance. The bounded image stage
awaits that reading. Local art and gameplay development continue at $0.

The Walker range now clears through native human and agent inputs without
teleports, equipment grants or forced phases. The composed ordinary first-person
OpenGL route also clears at 100 HP, retains 146 Bullets and 10 Rockets, and
observes seven actual reload deadlines. Inspected frames show the locked marks,
open recovery joints, moving body and disabled state. This is automated
authoring evidence, not fresh-player enjoyment or M14 acceptance.

Rendered failures exposed a rejected stomp result, omitted zero-height wire
fields and duplicate static machinery caused by JSON number membership. Shared
boundary and actual-map rendering tests now cover those failures. The earlier
route's uncontrolled strafe also walked behind close cover and self-damaged
with Rockets. The corrected route moves between supplied open flank positions,
uses the Rifle outside recovery and retains the failed run as evidence.

Independent review corrected Rocket ground-graze direct damage, committed
dead-shooter hits, multi-participant activation, stale map binding, vehicle
prediction and warnings that must persist while shells are airborne. Sabotage
objective ownership has reproduced failures and passing human/agent regression
tests. Both ordinary OpenGL and isolated Vulkan routes now pass, as do the
32-state published tour, all 371 client script checks and 176 harnesses,
locked workspace release build, required network scenarios, seven-map roster
and 120-second soak. Final unfiltered native workspace tests pass with 2,074
tests and five intentional ignores; coverage passes at 92.97% of lines against
the unchanged 90% floor. Formatting, workspace Clippy, dependency checks and
the deterministic CPU benchmark pass. Integration and package delivery are tracked by
[PR #403](https://github.com/blisspixel/fragr/pull/403). The
[composition receipt](../evidence/build-round-20261015.md) retains failures and
acceptance limits.
