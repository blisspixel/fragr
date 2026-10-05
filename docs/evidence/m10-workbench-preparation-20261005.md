# Common Carrier workbench preparation

Date: 2026-10-05. Status: offline candidate prepared and checked; runtime
placement and art acceptance remain in flight.

The existing inspected raw source SHA256 is
`37c149f3b6c402a349e283f4e49ab3baded27bfba5932a86b058556dc8537682`.
Four working-surface rays measure 0.94246 to 0.94316 m above its bottom.
Uniform scaling using the central ray produces an actual 0.9000001 m worktop,
with total dimensions 1.815294 x 1.135946 x 1.039604 m. The resulting candidate
`client/art/world-props/candidates/repair-workbench.glb` has SHA256
`4b5daf71e1378b13fd281493f7d94feee9da824cd5f93ac2cbd68493d0663783`.
Its required copyright is preserved.

The existing preparation helper gains an exact optional source selector and
the workbench specification. The default still prepares only scrubber, pump
and radio; each resulting GLB is byte-for-byte equal to its original candidate.
An unknown selector exits 1 without producing a model. No existing candidate
or reference is replaced.

Independent raw/export/reimport proof retains all 10,567 triangles, winding,
positions and UVs. Retained scaled source area is 10.54796933 square metres;
prepared area is 10.54796974. Four actual bottom quadrants reach the floor,
without authored support pads. The compact embedded paint/normal maps are
1024 square with nearest filtering and restrained wood/green metal finish.
Finite normalized imported normals preserve direction within a measured
maximum 0.0002434 vector drift (approximately 0.014 degrees). A 0.0005 bound
allows this measured packing precision; independent controls reject reversed
normals and a 0.01-radian rotation. Existing 0.00001 position/UV quantization,
winding controls and grounded-support thresholds are unchanged.

The machine-readable proof is
`client/art/world-props/candidates/repair-workbench-proof.json`.
Positive preparation and independent verification exit numeric zero with clean
logs and their PASS markers. Private diagnostics retain the parse failure,
measured normal-precision failures, corrected proof and original-source repeat
under `.agents/m10-workbench-*` and `.agents/m10-original-props-*`.

The retained candidate stays in the offline library. A byte-identical copy is
now packaged at `client/assets/models/repair_workbench.glb` in the separate
local ship-furnishing increment. Its measured twelve-piece physical host
replaces the prototype's wider, lower opaque bench envelope. Focused body,
support and shot-ray checks pass, including the real knee opening and blocked
cabinet/worktop rays. The source is not shipped or accepted as final room art.

`test_ship_furnishings` passes with clean logs and numeric exit zero, checking
the real packaged source, normal-map and geometry refusal, legacy omitted
heights and unmatched/malformed/other-map fallback. The matching native
`test_m10_local` also passes: it validates actual server-delivered host facts,
exactly twelve replaced proxy pieces, orientation/world light, ambiguous-host
refusal and source retirement on map rebuild, then preserves all existing
finite carry, death/continue, reopen and strict historical byte assertions.

The changed map SHA256 is
`d767c07691a88d810d945db952b7cda6c67ab968b2e1b6161a1f00790eeda49d`;
the optimized private server SHA256 is
`62dc52346df03870a6491b6e323872dd6955dda5e21d04891486d0f1e5fa2f84`.
Private logs retain the focused native/resource and actual process proof at
`.agents/m10-workbench-native-v1.log`, `m10-ship-furnishings-v1.log` and
`m10-workbench-accepted-map-v1.log`. All other 111 native solid shapes and
non-solid authored facts compare equal to the retained prior map; the literal
28-state route stays byte-identical. Actual room lighting, complete composed
client checks, corrected character shot blocking, ordinary full combat route
and exported desktop install checks remain open.

The complete locked workspace run also passes, including 960 server library
tests and all 18 local-child tests, with the same three pre-existing ignored
tests. Workspace formatting and all-target Clippy with denied warnings pass.
The complete log is retained at `.agents/m10-workbench-full-native-v1.log`.
These checks bind the bench checkpoint; the final composition must repeat
source-sensitive gates after character shot-occlusion integration.
