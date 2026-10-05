# Shared work-glove source inspection

Status: in flight, 2026-10-05. This is an inspected offline source, not selected
first-person artwork. The restored Rifle pictures remain selected.

The bounded [glove plan](../plans/work-glove-source.md) targets the primitive
hands and long flat sleeves found in Rifle presentation studies. Its one
isolated reference completed with an estimated $0.622 reservation under a $0.65
ceiling. The reference actually depicts a left glove. Its conversion used the
existing native model path and shared durable account ledger, with a 35-credit
and $0.70 equivalent ceiling. No humanoid rig or additional processing was bought.

Model task `01a10c47-becf-7184-928d-76b0e5182d9a` completed and reported 35 credits
consumed. The free post-stage checker reports 2,200 available, 15 still held for
an older uncertain request, and 2,185 usable. This brings tracked consumption to
870 and the first allocation to 545 of 900. Those figures precede later cast
requests; they are a dated reconciliation, not a permanently current balance.

The raw GLB fingerprint is
`96675cb5fc143c2337c396f9b7766e7d6c287fe87b77f04dc6aa3d080c3927f4`.
Actual import contains one fixed mesh, 8,009 triangles, 15,069 vertices, one 4K
albedo with normal and physical material maps, and no bones or animations. Its
unscaled bounding dimensions are 1.1402 by 1.8981 by 0.8711 source units. These
are source measurements, not hand dimensions in metres.

Four views were inspected on the Compatibility renderer with an AMD Radeon
780M. The corrected inspection process exited 0 with clean logs and its own
PASS marker. An initial wrapper failed to retain the process exit handle after
the renderer completed; it was corrected and rerun. The first wrapper failure
does not count as successful verification.

| View | Actual observation |
|---|---|
| [Palm](work-glove-source-20261005/palm.png) | Five distinct digits, reinforced palm and short cuff; visible low-poly facets |
| [Thumb side](work-glove-source-20261005/thumb-side.png) | Separated thumb web and bent finger profile; no floating armor plates |
| [Back](work-glove-source-20261005/back.png) | Angular knuckle transitions need refinement; photographic grain is unsuitable as the final pixel finish |
| [Outer side](work-glove-source-20261005/outer-side.png) | Useful cuff and finger silhouette; grasp does not yet fit a weapon |

The source is suitable for a local articulation trial. Retain and account for
original surfaces and UVs, repair joints where required, mirror with corrected
winding, and measure actual grip, trigger and moving-bolt contacts. Quiet the
material into deliberate pixel clusters and compare every registered pose at
the actual playing size. None of those gates is established by this studio
inspection. Ordinary played comparison, clean shutdown, full client checks,
matching CI and desktop packages remain required before selection.
