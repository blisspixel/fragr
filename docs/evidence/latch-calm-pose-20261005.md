# Latch calm-pose local candidate

Status: CPU proof only, October 5, 2026. Same-camera rendering, release continuity review and ordinary played acceptance remain open. This is separate from the frozen hand and named-body integration batch.

Base is main `0b03dc2c0a6b6da20262a02d26f9c7579e098e11`. The [plan](../plans/latch-calm-pose-20261005.md) precedes code. The independent private read-only audit reproduces the actual pawn/view transform chain and records 22 actual weighted source samples. Its inspected M07 image and current tracked GLB, view, pawn and old source are byte-identical to image client `94a270f2e406944ced574df2cfe6f0fee12eec16`.

## Bounded candidate and measured preservation

The selected 1.799972 m chassis, material maps, UVs, skin weights, walking clip and attachments remain unchanged. Only the free-left and unarmed-right hand endpoints and elbow poles are calmer. Targets follow actual shoulder displacement during sampled walking; the existing solver keeps fixed segment lengths. Armed and firing right-hand targets/poles remain exactly original, as do all positive release poses and hand turns.

Independent headless measurement gives idle elbow outboard spread 7.30/7.69 cm, compared with original 20.03/21.11 cm. Upper-arm angles from down change from 57/58 degrees to 38/42 degrees. Eight actual following samples give free-left 30.71 to 50.13 degrees and outboard spread 6.36 to 8.34 cm, compared with original approximately 58 to 76 degrees. This is measurement, not visual approval.

An independent old/new 22-sample comparison passes exact selected GLB/view/pawn identities, weighted floor and height at every sample, all sampled release joints, armed right joints and measured grip/offset controls. Armed idle and firing sampled Tack-grip proximity to 837 real dominant hand triangles remains 1.80/3.01 mm, with displaced controls 376/369 mm. Sampled proximity does not prove finger closure or an exact palm contact surface.

The existing owning source harness now checks actual imported arm lengths, torso-side free elbows, an actual old raised-elbow negative control, unchanged head/legs/feet over eight walk phases, original armed/firing right-chain transforms and all weighted release vertices. All existing source skin/clip, Tack registration, resolved flash, expression, actor lighting and near-clip PBR assertions remain.

## Local CPU receipts

Godot 4.7.2 headless import, touched-script parsing and `test_latch_source`, `test_latch_near_clip`, `test_m02_mission` exit 0 with clean logs and each own PASS. Private `.agents/cpu/` retains the import, parse, harness and full-chain measurement logs. The independent comparison is `independent-compare.log`. `git diff --check` passes. No server or GPU process ran for these receipts.

## Open acceptance

At release progress zero the calm candidate differs from the former raised idle; every positive release preserves the prior gesture. This may create a visible zero-to-positive jump. Capture that actual boundary before deciding whether a separate ward context is necessary. Do not accept the boundary merely because all positive poses compare exactly. Review full and player-distance old/new idle, armed, following, firing and release at unchanged height, ordinary light and camera before promotion. Current main remains unchanged.
