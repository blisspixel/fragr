# Tern provisional body identity

Status: in flight, 2026-10-05. Read-only continuity review found that M09
selects the human strip for every crew member except Splice. Canon Tern is
an embodied free agent, so the current human fallback is incorrect.

Make the narrow presenter conditional use the existing canonical synthetic
strip for Tern and Splice while Edda and the two human berth crew retain the
human strip. Keep actual crew eligibility, feet, gait, tints, authoritative
state validation and protocol unchanged. Do not claim the shared strip is
finished named-character art or invent a new reference, model or portrait.

Add actual instantiated presenter assertions in the existing M09 mission
harness. The original Tern selection must fail the new assertion; corrected
Tern, Splice, Edda and human crew texture identities must pass with unchanged
map/state/route gates. This is CPU presentation correctness work, no paid
calls, renderer or native authority change. Root owns later integration.

## Focused proof

The original conditional fails exactly the new actual Tern texture assertion
in `test_m09_mission.gd`, exit 1. After including Tern in the synthetic branch,
the same complete owning harness exits 0, error-clean and PASS. Its actual
instantiated Tern and Splice sprites use the canonical synthetic texture;
Edda and both berth crew retain the human texture. Existing cast eligibility,
validated hatch facts, route position and presentation gates remain unchanged.
Logs are retained under `.agents/tern-body-identity-20261005/.agents/` as
`m09-before.log` and `m09-after.log`. Cold headless import exits 0. No hardware
renderer, native child or provider operation was needed. Source is ready for
review, with combined integration and any later named-art selection still open.

## Ship continuity extension

The next local integration review finds the same conditional in `m10_ship.gd`:
only Splice selects the synthetic strip, so the current mandatory pilot Tern
borrows a human body. Extend the same narrow correction to the ship, preserving
unknown historical transit versus current pilot presence and all recorded
passenger eligibility, positions, tints and geometry. First add actual figure
texture assertions to the owning M10 harness and retain the old failure. Then
verify corrected Tern/Splice and unchanged Edda/human crew, including the unknown
history pilot. No server, body-contact authority, map or save change belongs here.
Full combined client and public gates remain required before promotion.

The original ship conditional fails exactly two new actual texture assertions:
Tern with unknown history and Tern with recorded arrivals. Splice and all human
checks remain passing. The corrected conditional then passes the complete M10
owning harness, numeric zero and error-clean, with the existing history,
eligibility, retirement and mission gates intact. Private logs are
`.agents/hand-integration-m10-before-v1.log` and
`.agents/hand-integration-test_m10_mission-v1.log`. This local fix selects only
the established provisional body strip; no named portrait, mesh or authority
fact is created.
