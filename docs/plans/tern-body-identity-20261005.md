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
