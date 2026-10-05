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

The source remains offline and excluded from desktop runtime exports. Its
dimensions do not match the prototype's wider, lower opaque bench envelope.
Removing that visible slab while keeping broad collision would be misleading.
Actual host/casing reconciliation, physical and shot coverage, source lighting,
packaged resource checks and played acceptance are required before selection.
