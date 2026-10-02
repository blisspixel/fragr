# M02 Latch visual identity

**Status:** implemented in draft work, 2026-09-28. Local visual refinement on the stacked M02 development branch. Distant recognition and human perceptual review remain open.

## Goal and reason

Give the fixed ward figure and moving server-owned companion one consistent identity at the restraint, during release, and across the processing floor, then measure its readability from the upper gallery. The current shared `LatchView` is a provisional stack of boxes. Its color alone carries too much identity in distant and muted play.

The historical local pass followed [cast continuity](../lore/cast.md#visual-continuity) and the [art bible](../ART_STORY_BIBLE.md): a practical person-scale free-agent body from the M01 workshop, a compact faceted plain head, worn bone enamel, dark steel joints, one muted-cyan square on the upper chest, and visibly unequal forearms with an individual rust repair on the right. Its implementation remains provisional against the approved look direction below. Hands convey chosen action at the second restraint; issued Union plates and red slits remain a separate design family.

### Identity clarification, 2026-10-01

Latch is a free agent and their own person, with free will, relationships and
personal choices. Their intended visual scale is roughly six feet tall (about
1.8 metres). The scrappy robot body records individual repairs and preferences;
it is not a warbot or a standardized armored military unit. Weapons and the
implemented following/combat behavior do not define the character's identity.
Future references should show ordinary stance, precise hands, chosen utility
details and asymmetric repairs alongside action poses. The current procedural
model remains provisional. This clarification changes no rendered asset,
physics dimensions, restraint pose, gameplay behavior or historical evidence.

The supplied [free-duo reference](../../client/art/characters/references/free-duo-reference.png)
now approves a square monitor head with dark display, light pixel face and thin
antenna, alongside individually repaired bone/steel/rust body parts. Carry the
same screen-expression habits, antenna and personal repairs across Earth,
Moon, Mars, story scenes and future casting. The adjacent free human's subdued
future-cowboy hat, worn utility clothes, rust strap and small neckcloth suggest
two people with limited means, not a standardized warrior pair. This approves
the look direction, not a completed model, voice or animation set. The free
human remains customizable and a selected agent body is not automatically Latch.

## Boundaries

- Keep the Rust server authoritative for Latch's identity, location, phase, fire and ward outcome. The client only poses the shared rendered figure.
- Preserve the existing `LatchView` node paths used by the ward, pawn and checks. Preserve the fixed-to-moving handoff, including skip, retry and late spectators.
- Keep the current M01 opening image and workshop traits as continuity references. This pass makes no final face, voice, age or new faction claim.
- No new runtime dependency, paid generation, cloud resource, gameplay logic or README expansion. Spend is $0.

## Implementation

Refine `client/scripts/latch_view.gd` using small Godot-native geometry and registered materials. Work at two scales: a compact silhouette to evaluate at gallery distance, and a repaired plate, hand detail and release gesture readable near the restraint. Reuse that one class in `m02_ward.gd` and `player_pawn.gd`; add presentation-only pose input for the second-bay action if needed. Keep object count and material count bounded for every view.

Add focused Godot checks for material, geometry, handed repair, actor layers, gesture and handoff. Extend the existing M02 live route or a small companion route to capture gallery, restraint, release and processing-floor states. Inspect actual rendered stills and motion frames in Godot 4.7.2. Record what was visible and any remaining limits; a headless test cannot certify that a new player recognizes Latch.

## Verification and acceptance

- `tools/godot_check.sh` passes with clean logs and each harness PASS marker.
- The M02 route passes with a real loopback server. Gallery, restraint, release, following and observer stills are inspected at 1280 by 720, with the existing single-Latch transition assertion retained.
- Inspect grayscale and normal-color captures for silhouette and allegiance cues. Avoid claims of established human recognition from scripted cameras.
- Run `tools/qa_tour.sh --publish` for the player-visible change, then inspect the refreshed stills. The README keeps its four selected images and links to deeper docs.
- No paid service call or cloud apply. The planned visual work is complete when the shared renderer, tests and documented evidence agree. Human fresh-player review remains a later acceptance gate for M02.

## Local progress, 2026-09-28

The shared `LatchView` now has a six-sided compact head with the workshop still's
pale brow and dark recessed lower face, a square chest patch using the art
bible's muted cyan, exposed dark joints, pale shoulders and shins, and a wider
right forearm with a rust repair and side-facing folded edge. Each hand has
separate segments. The ward release opens the right hand and braces with the
left arm as Latch opens the other captive's restraint. The server-owned moving
ally continues to use that same class. No protocol or simulation field changed.

After stacking on gallery first-view head `e6a43fb`, the two-state real
first-person gallery route and the 20-state M02 motion route passed on a real
loopback server with zero bots. Together they cover the standing gallery eye
at about 21 metres, a long ward view, a one-metre restraint close view, a
roughly five-metre second-bay view, a sixteen-frame handoff strip, and the
moving ally at roughly four metres. The scripted route traversed the
Crawler and guard fights, released Latch through a real Use, and observed more
than ten metres of companion travel. [Inspected stills](../screenshots/m02-latch/README.md)
show the final close, release and moving appearances. The entry view frames the
restraint destination through the new opening, but Latch remains a small pale
mark amid ward equipment at 21 metres. Even the nearer gallery window view
does not resolve the right repair, patch or hand pose. The character's presence
is geometrically visible, while identification as Latch and motive to rescue
remain unproven without fresh-player review.

Focused `test_actor_state.gd` and `test_m02_ward.gd` passed. The latter checks
the right-only repair, square patch, hand gesture, retry reset, and the existing
skip and late observer handoff. It also caps the shared procedural chassis at
40 visual mesh parts. The full `tools/godot_check.sh` passed with clean
logs on Godot 4.7.2-stable before and after the gallery stack. The first
expanded tour attempt failed because an overview camera left the joined
player's aim detached just before Use; a first-person control state was
inserted and the repeated route passed. These
are deterministic authoring and rendering checks, not human
recognition, motion feel or finished character-art approval. External spend is
$0.

The default `tools/qa_tour.sh --publish` also passed all 32 named states. Its
contact sheet was inspected. Those arena and menu states do not contain Latch;
their eight incidental frame differences from bot timing were discarded while
the current selected README stills remained byte-identical. The M02 Latch
evidence lives with the ward screenshots, linked above.
