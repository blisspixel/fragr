# M08 neutral body registration

Status: in flight, 2026-10-05. Bounded part of the character shot-occlusion
change. This plan precedes implementation. No art, paid request or renderer work.

The archive draws four lower-bay captives and, after two ordered steps, Renn.
Their existing presenter-derived feet have no authoritative contact owner, so
shots and ordinary movement can pass through visible people. Register those
same five living neutral bodies with no invented health, damage, death, rescue
route or mission gate.

Use the validated registered panel placement seam. Renn's feet are the registry
point minus local normal 1.5 m and local right 0.6 m, at host bottom. Held captive
feet are bay-release point plus local normal 0.8 m and local right
`-4.5 + index * 3`, at host bottom. Released waiting feet are freight-departure
point plus local normal 2.5 m plus world `[-3 + index * 2, 0, -3.5]`, at y0.
Preserve existing visibility and release phases, fixed height and contact keys.

Implement a non-wire M08 neutral layout helper and a client mirror, with shared
goldens covering actual panels, all wall faces and nonzero host floors. Reject
missing or duplicate required panels and invalid bounds at the existing map
boundary. Reuse the client helper in the archive presenter and bind it to actual
MapInfo for local prediction; do not add a second civilian position stream.

Owning tests must prove four versus five bodies, hidden/briefing/departed removal,
held/released feet, no extra Orrin body, deterministic stationary contact keys,
matching movement mirror and actual renderer-node feet. Generic nearest-ray,
pulse and no-damage tests remain in the sibling combat lane. Run focused Rust
and headless client gates, then hand off the frozen source for composed full
workspace/client/native checks. No GPU, shared-target overwrite, push or merge.

The measured existing Renn feet overlapped the desk capsule by 12 mm. A bounded
authorized correction changes normal offset to 1.52 m in both owners, placing
Renn 2 cm farther behind the desk with 8 mm clearance. Retain the failed probe.
The same no-wire registration also covers the two actual M06 family-room people
and the M07 window resident, preserving their room/glass enclosure and feet.
The old released outer captive feet also straddled freight crate edges. Their
world-x offsets move from -3/+3 to -2.49/+2.49, leaving 1 cm capsule clearance;
the middle offsets -1/+1 and all z/y positions remain unchanged. Preserve the
failed placement probe and explicit old-position negative controls.
