# Right of Search fact boundary

Status: implemented and tested locally as an incomplete mission component.
Current capability 36 does not admit M11, and these values do not promote a save
or make the structural study a playable mission.

Six ordered arrivals cover armory, spine, holds, records, counter-boarders and
bridge. Optional transfer release and document reading are separate from the
stern confirmation. Registered panel kinds prevent using the document or
restraint target as departure. Anonymous transfer positions carry no proposed
Sorrel identity or invented rescue history.

Challenge facts retain actual counter-boarding activation, an exact 1200-tick
prototype signal deadline, bridge arrival and a largest single-charge result
bounded by the actual six-member counter-boarder roster. Their eventual sim
writer must count registered eligible lives killed by one resolved blast, with
the same blast identity; this type does not itself prove the writer. Neither
summed blast kills nor depleted HP is accepted as an invented kill receipt.

Brief completion is independent of mission completion. Assisted requires actual
transfer release, Standard also requires three kills in one charge blast, and
Severe also requires bridge arrival strictly before the signal deadline. Equal
deadline arrival misses Severe, while ordinary departure remains possible.
The new timer is provisional. Full route timing and learning are still open.

## Verification

Five focused native boundary tests pass, together with all five existing tender
structural tests, in `.agents/m11-structure-typed-boundary-third.log`. Thirty-two
shared valid/malformed vectors agree with the owning GDScript harness, which
exits 0 with PASS and no errors in `.agents/m11-facts-client-second.log`.
Additional client map cases check panel ownership, extent, body spacing and
below-floor refusal. Present null optional values, unknown history fields,
negative/fractional counts, reordered objectives and invalid clocks refuse.
Final formatter and warning-denied server all-target Clippy pass; the owning
lint receipt is `.agents/m11-lints-typed-facts-first.err.log`.

The first native fixture used the wrong existing Shoot field name; its compile
failure is retained. The first client run caught a JSON numeric-type mismatch
in literal dictionary equality for fresh briefing. The boundary now checks the
already-validated fields semantically, preserving every numeric and exact-key
constraint; the failed log remains separate. No geometry or acceptance
threshold changed.

## Remaining connection

Authoring must validate supported, reachable objective and interaction feet,
real panel shot/use lanes, actual patrol/encounter ordering and transfer contact
clearance before readiness. MissionState, MapInfo, mission/controller, fresh
party use, actual blast writer, version 14 promotion, readable device/Redactor
presentation and complete runtime/package gates are not yet claimed. The
source art remains offline until knife grip, visible tell, death and ordinary
play are accepted.
