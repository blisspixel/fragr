# M04 server prototype

**Status:** implemented, 2026-09-30. Implements the server lane of
[Notice to Vacate](m04-notice-to-vacate-prototype.md). **Spend:** $0.

The later [M05 increment](m05-no-forwarding-address-prototype.md) supersedes
the initial capability 25 and save version 5; current authored missions use
capability 26, unchanged rules revision 3 and strict version 6 upgrades. Earlier
receipts retain their actual tested contract.

## Contract

Map 1004 has six ordered encounter objectives, one optional clinic shutter and
an explicit shared roof departure. The two clinic worlds are prepared before
readiness. Patients follow bounded routes after the optional rescue; their
arrival never gates the exit. Completed M03 choices remain immutable entry
context. Readiness, continues, actions, inventory and saves use existing seams.

The Notary has 50 HP and a raised 1.3 by 0.7 metre box. Its authored hover
volume and short patrol are checked against collision geometry and ordinary
weapon approaches. Flight stops during its committed flash and burst. Three
zero-dispersion Tack rounds use normal combat resolution. The first round
counts one photograph only when it resolves to the original living, active,
ready participant. Dodge, cover, interruption and dry fire cannot invent a
photograph. Later rounds do not count. Existing enemy timings remain unchanged;
the new 24/36, 16/26 and 12/20 tick rows use rules revision 3.

Dead drones fall to authoritative support and leave harmless, nonblocking
wrecks. Future M04 groups are not spawned before their prerequisites, preserving
the lone lesson and bounded mixed encounters. No general air graph, Assessor,
player flight, paid service or new dependency is included.

## Ownership and verification

This lane owns mission/protocol/map/encounter/combat/controller source and
focused tests. Integration owns run storage, recovery, local launch and their
tests. Client and map lanes own presentation and authored content. Existing
M01-M03 authored bytes remain unchanged.

Seeded tests cover strict authoring, raised shot volume, all three timings,
dodge, cover, interruption, photo accounting, bounded hover, falling support,
future-group admission, optional rescue, roof departure and retry. Shared
controller and real socket tests cover geometry-before-state delivery and
capability admission. Focused tests and server Clippy precede parent-coordinated
full workspace checks, coverage and rendered ordinary-input tours. Release
executable changes are serialized with owned local children.

## Evidence

The server implementation includes the six encounter objectives, one optional
shutter with two precomputed worlds, patient movement through shared collision,
immutable recalled-car context, typed clinic prompts and explicit living-party
roof departure. The strict loader proves Notary clearance in both worlds and
rejects degenerate, reversed or overlapping patient routes. Future enemies are
absent until the preceding encounter clears. Latch does not shoot the lone
Notary lesson before the player learns its tell.

The first photograph marker is captured with the committed ray before damage
resolution. This preserves a launched trade when the participant kills the
drone in the same tick, while an interrupted tell counts zero. Raised square
hit volumes and support-owned wreck falls use the shared combat and movement
seams.

On 2026-09-30, `cargo test -p fragr-server --lib tests::m04:: --locked --
--nocapture` passed 14 tests, including actual socket checks of all four bundled
missions with human, agent and spectator readers. Rules revision 3 requires
capability 25 before any game state; retired capabilities 8, 18 and 24 are
rejected. Initial MapInfo precedes Mission and Snapshot, and the clinic geometry
replacement precedes changed facts. The log is
`.agents/m04-buildout-20260930/server-tests.log`.

The first full server-library run found two obsolete revision 2 fixture
assertions. Both were corrected to revision 3. Final
`cargo test -p fragr-server --lib --locked` passed 681 tests, with zero failures
and three existing ignored tests, in 94.44 seconds. This includes the additional
raised-box edge and strict clinic-prerequisite cases. The complete log is
`.agents/m04-buildout-20260930/server-lib-tests.log`.

`cargo clippy -p fragr-server --all-targets --locked -- -D warnings` passed;
its log is `.agents/m04-buildout-20260930/server-clippy.log`. No paid calls or
dependencies were added. Runtime source is frozen for the parent-coordinated
rendered tour and final workspace gates. A scripted clear proves authoring and
integration, not fresh-player acceptance. Rendered acceptance and final
workspace checks were completed by the parent plan: 1167 passing tests, 94.47
percent unfiltered line coverage, clean formatting/Clippy/release and the final
23-state M04 ordinary-input clear. Full mission acceptance remains open.
