# M05 bounded tram

**Status:** shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. Child of [M05 prototype](m05-no-forwarding-address-prototype.md). **Spend:** $0.

Implement one real authoritative tram collider translating along a cleared straight Z lane. The authored registered solid is the parked baseline. Geometry carries its index, lower-face center `start` and `end`, speed and activation region. Same X/Y, maximum 24 metres travel, maximum 1.5 metres per second. Mission facts carry phase, lower-face center feet and authoritative tick. The client reconstructs that sole collider from the validated baseline and pose.

Rescue plus actual living active party presence starts a three-second boarding pause, then autonomous travel. A side walking route always remains available. No compulsory escort, rotation, general vehicles, per-tick topology rebuild or new input channel. Conservative prepared navigation excludes the full swept tram lane. Each current collision arena substitutes only the registered tram solid before movement, shots, explosives and enemy visibility.

The planning reservation rises above all authored surfaces plus the normal wall height. Its top cannot become an imaginary continuous one-metre tram deck for a rider's walking route. This volume exists only in prepared navigation. Combat steering receives live physical solids separately, for enemies, server participants, companions and external mission controllers. Existing callers retain their immutable visibility default. Shared external target selection can reconstruct the same live solids from validated M05 facts, without rebuilding topology.

Supported living riders receive the platform displacement before normal movement. Support uses the same center-foot registration as ordinary movement, including standing near a deck edge; clearance sweeps the complete radius and standing body. Jumping and dismounted actors are not carried. Check the swept step against unchanged geometry, body clearance and non-rider bodies. Refuse the entire step on obstruction, reporting blocked, rather than crushing or teleporting anyone. Reset starts the tram at its original parked position. Movement integration and its existing mirrored golden vectors remain unchanged; the separately mirrored carrier helper receives deterministic vectors and focused tests.

Verify live translation and real shot cover, supported rider transport, jump/dismount, actor obstruction, walls/ceiling, bounded travel, final stop, reset and client collider reconstruction. Inspect an actual ordinary-input ride and the walking alternative. A moving decorative mesh does not meet this plan.

## Current evidence

Shared Rust and client carrier goldens cover standing, center-edge support, jumping, airborne actors, support epsilon, full standing clearance, swept walls and bounded deltas. Real-map tests cover translated shot and grenade collision, enemy and external controller visibility, obstruction refusal and resumption, dismount, reset and conservative routes that never use the swept reservation as a continuous deck. The parent owns the serialized workspace and client checker receipts.

The fourth 25-state ordinary-input M05 tour passed with exit 0 against map SHA256 `04764f0d665818454ddedaaf67f1e7984bfea571eaed0181cf521f7fc56d09fe`. The actual dock jump moved from `[3.75, 0.5, 6.000008]` onto `[0.5, 1.0, 6.000002]`. During the five-second ride, 97 supported samples confirmed rider displacement 4.860018 metres and tram displacement 4.860018 metres. Inspected motion frames show the deck and attached dressing translate against the stationary workshop and town. Receipt: `.agents/qa/m05-rooftops-fourth/manifest.json`.

The ride follows clearance of all five trench guards. It proves ordinary boarding and authoritative transport, not boarding under fire, general vehicles or fresh-player route quality. The rest of the ordinary tour uses the static walking alternative and completes shared freight departure. A passenger-modal prompt overlap found during final inspection was corrected in the client before the sixth refreshed capture; it did not change the collider or ride receipt.

The sixth final tour passed all 25 states with exit 0 on the same map. Its normal
dock jump moved from `[3.75, 0.5, 6.000007]` onto `[0.5, 1.0, 6.000001]`; 99
supported samples confirmed both rider and tram travel of 4.800017 metres. The
actual modal, cancellation and final departure were independently inspected,
with all three released workers physically aboard. Receipt:
`.agents/qa/m05-rooftops-sixth/manifest.json`. The earlier fourth ride remains a
historical sample; frame-dependent supported sample counts are not a performance
or fresh-player quality claim.
