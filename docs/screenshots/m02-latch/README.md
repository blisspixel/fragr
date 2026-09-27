# M02 Latch ward evidence

These four unedited 1280 x 720 frames came from the successful 17-state live
tour at `.agents/qa/m02-latch-live-evidence/` on 2026-09-27 at 15:13 UTC. The
tour used Godot 4.7.2-stable, OpenGL Compatibility, and an AMD Radeon 780M on
Windows. It connected to a local release server loaded from
`server/maps/m02-persons-unknown.json` with no bots. The source manifest and
client/server logs remain in that ignored tour directory. Run the tour with:

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
comprehension, difficulty acceptance, finished character art, and a fighting
companion remain open. The second bay uses a detached capture camera within the
joined local session, not a separate spectator client. The 17-state source
manifest also records dock departure and server record status `complete`.
