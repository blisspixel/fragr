# M06 freight capture route

Status: implemented, focused headless and final rendered route gates passed.
Updated 2026-10-02.

The first final normal-wrapper M06 capture in
`.agents/qa/final-m06-shipping/` fails after three captured states. Its freight
travel tries to retrace from [-40, 0, -20] to [-40, 0, -28], but stops at
[-41.49595, 0, -19.88476] after 15023 milliseconds walking and 4055 milliseconds
fighting. All four freight guards were already killed, including one actual
Latch support kill. Both owned processes closed; no gallery was copied.

## Established evidence and limits

The stopped feet are just east of the straight west pressure-wall faces at
x -43 to -42. No static convex corner blocks the direct target ray from this
position. `_local_feet` reads the real authoritative participant snapshot,
and `travel` releases movement inputs before every selection. The failure
therefore does not establish a wall corner, leaked strafe or continued firing
at dead guards. The run did not retain the final Latch coordinates or walk
sequence, so a living-body cause is unconfirmed. The later server change
affects only CTF interception; no campaign causality is inferred from its new
binary hash.

A separate concrete authoring constraint prevents simply disabling travel
combat on the old final ingress leg. The dormant `freight_clerk_a` starts at
[-30, 0, -24], directly on the leg from [-30, 0, -28] to [-30, 0, -22]. Living
body contact can stop a quiet participant at z -25, before the encounter's
activation region begins at z -24. The regression must include this actual
registered body, rather than prove static world clearance alone.

## Authorized bounded correction

Keep the exact existing Earth viewpoint and its quiet captured sequence. Set
the freight state's explicit `combat_travel` to false and remove its travel
target list. Replace only that state's ordinary walk with:

1. [-38, 0, -20], an eastward lateral departure from the viewing position.
2. [-38, 0, -28], the open west aisle.
3. [-28, 0, -28], north of the registered cargo block.
4. [-28, 0, -22], inside the actual activation region and clear of the dormant
   Clerk's starting body.

This avoids retracing the wall-side viewing line during travel combat and
defers the first fight until physical entry. The unchanged combat stage still
requires all four named guards, ordinary tell evasion and its existing search
route. Keep all twenty-five states, 15000-millisecond walking limit, strict
0.3-metre horizontal and 0.03-metre height arrival thresholds and the
25000-millisecond combat deadline. Do not modify shared QA, map geometry,
server behavior, body contact, difficulty or inventory. No outcome grants,
teleports, forced ticks or paid calls are allowed.

The first three destinations remain outside the activation box x -34 to -17,
z -24 to -18. The final point is safely inside it. The west aisle lies between
the pressure wall and cargo at x -35 to -31; the north crossing at z -28 clears
the cargo edge at z -27 and the dock bulkhead ending at z -29. Actual standing
movement and body contact must establish the complete legs, not just endpoints.

## Verification

Extend the existing M06 presentation harness with the actual map and capture
manifest. Use shared `MoveStep` and `ActorContact`, all four actual dormant
freight bodies, the unchanged strict arrival predicate and ordinary forward
controls. Prove that the old quiet x -30 leg stops before activation, that every
new leg remains supported and reaches its real endpoint, and that the first
three arrivals are outside while the last is inside the actual region. Include
bounded starting offsets and both body identity orderings where practical.
An invented stationary companion fixture may illustrate clearance, but cannot
stand in for the absent original live coordinates.

Run the existing focused harness with a clean exit, clean error log and its
own PASS marker after source freeze. Then use the unmodified normal wrapper in
fresh `.agents/qa/final-m06-shipping-second/`, seed 42, Standard and zero bots.
Require all twenty-five states, all twenty-one guards, the unchanged strict
phase-causal Turret proof, actual Rail trace, secret claims and `party_departed`.
Record source and binary hashes before and after, retain the first failure and
inspect the captures before refreshing the eight gallery files. Parent owns
the final whole-client checker, protected main CI and release. No renderer or
process may overlap the serialized lease.

## Focused evidence

The exact four-leg quiet route is implemented in the capture manifest. The
existing M06 presentation harness passes with a clean exit and own PASS marker.
Its actual-map regression includes all four dormant freight bodies, both
relative UUID orderings and five bounded arrival offsets. It proves the old
quiet leg stops at z -25 before activation, while the revised legs retain
ground support, at least 0.9999-metre body separation and the original strict
arrival and walking limits. The first three legs never enter the activation
region; the final leg reaches it. This does not identify the absent original
Latch coordinates or claim a reconstruction of the initial travel failure.

Focused receipt: `.agents/m06-buildout-20261001/m06-freight-route-focused.log`.
The subsequent unmodified normal-wrapper capture in
`.agents/qa/final-m06-shipping-second/` passes all 25 states, all 21 named guards
and actual `party_departed`, with exit 0 and no import, engine or script errors.
The current release SHA256 is
`D29AE5E4B0BC3456F370524F87873930A2A8B2C9C8B5DCA09726D7EBAC05BE8A`;
source, wrapper, map and binary hashes match before and after. The participant
record reports zero deaths, zero HP lost, 75 armor lost and one secret claim.
All three secret locations were visited. The actual Rail hit measures
51.991994 metres. Strict Turret proof retains clear Windup 3005, blocked Windup
3007, Recovery 3008 through 3020, original deadline 3031 and no shot verified
through 3032, with unchanged 100 HP. No gate was weakened.

All eight gallery sources, the 25-state contact sheet, twenty-frame Earth view
and actual Turret motion sheet were inspected. The gallery was copied only
after clean completion, with exact matching hashes. Owned server 5188 and
Godot 26652 closed and are absent; the runtime lease was returned. Exact
receipt: `.agents/qa/final-m06-shipping-second/source-receipt.json`. Parent
owns the remaining whole-client check, protected main CI and release.
