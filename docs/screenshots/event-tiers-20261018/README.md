# Event tiers, October 18

Godot 4.7.2-stable, X11 through Xvfb, GL Compatibility on Mesa llvmpipe.
These are inspected presentation captures, not hardware performance or
fresh-player campaign acceptance.

- `busy-legacy.png`: flat-background HUD replay of the complete retained
  ten-bot round, with 62 legacy frags, four personal pickups, taunts and streaks.
  No weapon or identity fields were added to its events. The rendered replay
  ran 100.029 seconds and drained every admitted row after its full lifetime.
- `busy-modern.png`: the new complete ten-bot round replay, with 78 resolved
  frags and three personal pickups for the declared Scout Ant view. Its rendered
  replay ran 113.251 seconds, reached two pending rows, retained four visible
  frags at RoundEnd and drained all 78 without rejection or early expiry.
  Both complete event extracts and recording hashes live in
  `client/qa/fixtures/`. The full recordings remain private diagnostics.
- `composed-team.png`: isolated populated HUD layout fixture. Five frags,
  independent voice, own bone plate, shared relation marks, weapon glyphs,
  Unicode/literal-markup names, center call and radio. Event contents are explicit
  fixtures; it is not a played team match.
- `ctf.png`: native eight-bot Sector 9 match, seed 42. Actual accepted call:
  CRACKPOT TAKES THE FREE FLAG.
- `sabotage.png`: native eight-bot Sector 9 match, seed 42. Actual accepted
  THE CHARGE IS DOWN, alongside two frags, Host speech and a fighter taunt.
- `conquest.png`: native twelve-bot Holdfast Atoll match, seed 42. Actual
  VILLAGE: UNION takeover; the snapshot also retains the separate Free-owned
  Server Halls. Calls are serialized in canonical site order.

The three adjacent JSON receipts retain the authoritative state and accepted
payload at each live still. The shared 33-state tour was regenerated and
inspected, publishing its fourteen established stills to the parent directory.
No assets were generated and no credits or cash were spent.
