# Client integration and verifier checks

Local verification on October 7, 2026 used Windows, Git Bash and Godot
4.7.2-stable. This is headless correctness evidence. It does not measure
renderer performance or establish another platform's result.

## Complete run and focused repairs

`tools/godot_check.sh` completed project import, all 323 script parses and
all 147 executable harnesses. Import and parsing passed. The first run had
142 passing harnesses and five failures, retained in
`.agents/godot-quality-20261007.log`:

- `test_desktop_host` exposed a real mismatch: automatic Conquest bots were
  offered by the client but refused by the shared native bot-policy validator.
- `test_equipment`, `test_jump_input`, `test_mission` and `test_vertical_aim`
  used input fixtures without the pawn health required by local fire feedback.
  Their printed PASS lines did not hide the runtime errors from the checker.

The native policy now uses the existing automatic-fill path for Conquest.
The four input fixtures supply real pawn state or the health field in their
existing focused mock. The runtime fire guard and strict client admission
were preserved.

Fresh verification used native release SHA-256
`79ea57258ed8aecb322b58d4a6cb94e48075eead600bae885e9d89ca15b7585a`.
The desktop-host harness passed real two-client lifetime checks for TDM,
Sabotage and Conquest, automatic human and agent priority and refill for each
mode, owned-process shutdown and retirement of seven radio decoders. All four
repaired input harnesses passed. The QA combat, audio-retirement and spectator
camera harnesses also passed, with no script or engine error diagnostics.

The final `qa_tour.gd` parse passed at SHA-256
`261b811237043f2efa03c7447b58f6a244ed340415e2f7906f581e7125d49445`.
Its updated camera fixture checks an unobstructed subject, a wall-obscured
subject and a fully enclosed subject. Local logs are
`.agents/godot-desktop-host-final-20261007.log`,
`.agents/godot-quality-final-reruns-20261007.log`,
`.agents/godot-qa-tour-final-parse-20261007.log` and
`.agents/godot-spectator-camera-final-20261007.log`.

The first full run remains a failed run. Focused reruns resolved every reported
failure; the full client gate on the final composed commit remains a CI gate.

## Verifier fault injection

`tools/test_godot_check.sh` now copies the unchanged real checker into a
temporary project containing one ordinary script and two test scripts. The
fixture asserts ordinary-script parsing, discovery of both harnesses, and
exactly three script parses plus two harness executions in successful cases.
The real client checker has no filter, bypass or changed failure policy.

All ten original scenarios remain: normal success, harmless socket diagnostics,
import exit failure, import error output, missing PASS, error followed by PASS,
failed exit followed by PASS, long error output, long successful output and
retained verbose failure identity. The long-output cases still exceed one
mebibyte to exercise pipe handling.

Shell syntax validation and all ten scenarios passed in 71.108 seconds on this
Windows run. The earlier whole-repository fake loop was stopped after more
than six minutes and had completed only its first scenario. This timing is a
local observation, not a cross-platform performance claim. The focused run is
retained in `.agents/godot-checker-final-20261007.log`.

The fixture resolves and checks its physical path under the workspace before
registering cleanup. Creation, execution and cleanup stay in the same shell.
The successful run left no temporary fixture directory. Cost: $0.

## Final visual repairs

The [published tour](../screenshots/README.md) passed 32 states, including an
actual death, normalized respawn and continued firing. Full-size review caught
an obstructed body camera and a populated Multiplayer page that pushed its
title and Back controls outside the card. The corrected page scrolls only its
content. The new layout harness checks empty and full server books, ordinary
Tab focus to the final row, fixed Back and return to the normal menu. It and
the existing frontend and Host-menu harnesses pass. A separate actual local
status-page render refreshed the multiplayer still.

Holdfast's overhead review caught a mismatched distant horizon and cracks
between differently tessellated water patches. The corrected horizon, shore
and patch edges were inspected on the real renderer; the sky and water harnesses
pass. These additions are included in the final platform CI gate, not silently
counted as part of the earlier 323-script run.
