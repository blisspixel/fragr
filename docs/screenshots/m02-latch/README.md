# M02 Latch ward evidence

The first ward evidence came from the successful 17-state live tour at
`.agents/qa/m02-latch-live-evidence/` on 2026-09-27 at 15:13 UTC. The tour
used Godot 4.7.2-stable, OpenGL Compatibility, and an AMD Radeon 780M on
Windows. It connected to a local release server loaded from
`server/maps/m02-persons-unknown.json` with no bots. The source manifest and
client/server logs remain in that ignored tour directory. The second-bay
frame below was refreshed by the 2026-09-28 visual route documented later on
this page. Run the original route with:

```bash
FRAGR_QA_MAP_FILE=server/maps/m02-persons-unknown.json \
FRAGR_QA_BOTS=0 \
FRAGR_QA_MANIFEST=res://qa/m02-graybox.json \
tools/qa_tour.sh .agents/qa/m02-latch-live-evidence
```

| Frame | Live state |
|---|---|
| [Ward stopped](ward-stopped.png) | The guard encounter is complete, the correction machine has stopped, and Latch still waits at the frame. |
| [Restraint control](restraint-control.png) | The physical panel offers a live use prompt after the ward is secure. |
| [Second bay open](second-bay-open.png) | Latch has opened the occupied second bay before speaking. |
| [Low Water list](low-water-list.png) | The open bay remains in the world while the recall list names Low Water as next. |

The route uses scripted movement and accurate combat aim. Fresh-player
comprehension, difficulty acceptance, and finished character art remain open.
The companion's combat implementation is in draft review. The second bay uses
a detached capture camera within the joined local session, not a separate
spectator client. The 17-state source
manifest also records dock departure and server record status `complete`.

## Shared Latch chassis review, 2026-09-28

The [visual identity plan](../../plans/m02-latch-visual-identity.md) refines the
shared ward and moving-ally renderer. The final 20-state live route in
`client/qa/m02-latch-motion.json` passed on Windows with Godot 4.7.2-stable,
AMD Radeon 780M OpenGL Compatibility and a local M02 release server, with no
bots. The route inspected the same Latch at the close restraint, second bay and
moving floor position. Source frames and logs are under ignored
`.agents/qa/m02-latch-gallery-final/`. It uses the lowered-sill map from the
[gallery first-view pass](../../plans/m02-gallery-first-view.md).

| Frame | What it shows |
|---|---|
| [Close restraint](latch-close.png) | About one metre from Latch: pale faceted head and dark lower face, square cyan chest patch, individual rust repair on the right forearm, and separate fingers. The first-person gun obscures the feet and the frame clips the top of the head. |
| [Second bay open](second-bay-open.png) | The same figure reaches to the other captive's restraint after the server release. The opened hand and arm read at about five metres; the ward's fixed figure is still the visible Latch in this phase. |
| [Moving ally](latch-floor-observer.png) | A roughly four-metre observer view of the server-owned ally on the processing-floor approach, after the fixed figure has yielded. This rear-side view keeps the pale head, dark joints and unequal arms but does not show the chest patch clearly. |

The handoff strip has sixteen live frames and asserts the transition to one
visible Latch. Skip, retry and late-join projection also have Godot checks.
The same lowered-sill map and new Latch renderer passed the separate
two-state `m02-gallery-first-view.json` route. At the standing entry eye about
21 metres away, the window frames the restraint destination, while Latch is
only a small pale mark amid the cabinet and machine shapes. The nearer window
view reveals the body but the repair, patch and hand pose do not resolve at
that distance. The [gallery comparison](../m02-gallery/README.md) gives the
authoritative layout context. These scripted cameras do not establish that a
new player notices or understands the reunion. That human gate remains open.
