# Remote-charge supply and controls checkpoint

Status: implemented and tested locally, incomplete M11 contract. This checkpoint
does not admit M11 or select a world device model. The reserved capability is 37;
the advertised contract remains 36 until the complete mission is validated.

Authored `remote_mine` grants contain one to six charges. Personal claims are
retained per participant; contested stock has one real claimant and no campaign
respawn. The six-charge inventory is independent of grenades, proximity mines,
weapon ownership and ammunition. Claims report the actual gain at capacity.
Placement follows claims in the ordinary tick, so spending a full inventory
permits a claim on the following tick, rather than retroactively in that tick.

V and the right shoulder place a charge. H and right D-pad trigger armed charges.
The existing action channel, binding migration and glyph lookup own these inputs.
Brief taps survive a failed transport send, while held keys through loading,
story, role changes or paused controls require release before a new request.
Historical custom bindings retain ownership and leave conflicting new defaults
unbound. The quiet HUD has an independent integer count and a strapped-charge
glyph; depletion retains a known zero until the session clears.

## Local verification

- Four actual server supply tests passed in
  `.agents/m11-structure-remote-supply-third.log`.
- Existing equipment and control harnesses each exited 0 with their PASS marker
  and no script/runtime errors in `remote-client-supply-controls-first.log` and
  `remote-controls-final-hud-first.log` under the private `.agents` directory.
- Warning-denied server all-target Clippy passed in
  `.agents/m11-lints-remote-supply-controls.err.log`.
- The existing pickup harness exited 0, clean and PASS, in
  `.agents/remote-pickup-first.log`, including the distinct remote stock label
  and explicit unfinished-art fallback.

The first native receipt retains fixture compilation mistakes. The second
retains the incorrect same-tick capacity expectation, with three passing tests
and one failure. The corrected test asserts the actual next-tick claim ordering;
no inventory limit or claim assertion was relaxed. The earlier complete
workspace Redactor checkpoint remains separate evidence.

## Open gates

Remote pickup words identify its own stock. Its world model, flight/stick/arming
and trigger cues still require a distinct local source and inspected runtime
presentation. The generic pickup fallback is an explicit incomplete art state.
M11 typed facts, ordered encounters, challenge facts, promotion, rendered route,
imported Redactor knife/tell/death poses and final client/package checks remain
open. Existing controls, equipment and mission readiness retain their owning
paths; this is not a second campaign entry point.
