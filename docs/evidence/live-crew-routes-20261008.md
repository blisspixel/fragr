# Live crew routes, October 8

Implemented locally. The [owning plan](../plans/live-character-presenters-20261008.md)
and [machine receipt](live-crew-routes-20261008.json) distinguish ordinary mission
inputs from the earlier [controlled character fixtures](live-character-fixtures-20261008.md).
Both owned routes completed on the frozen native executable, with clean final
logs, numeric exit 0 and the driver's explicit `LocalMatch.IDLE` retirement check.
No paid requests or new credits were used.

| Route | Entry | Completed states | Bounded cast samples | Moving samples | Distinct actual left-leg poses |
|---|---|---:|---:|---:|---:|
| M09 | Standard development child, ordinary finite human kit | 27/27 | 2,750 | 1,770 | 1,606 |
| M10 | Canonical promotion of labelled historical v12 finite-carry fixture, synthetic body | 28/28 | 3,314 | 0 | 1 |

All 55 captured states have a named live Tern skin, no strip fallback, and feet
matching accepted current mission facts within the unchanged 0.00001 m check.
M09 records 1,729 sampled horizontal position changes and one consistent idle leg
pose across its 980 idle samples. The actual rig changes as the accepted crew
route advances. M10 retains its stationary pilot at `(2, 7.6, -15)`, with zero
walked distance and zero leg-pose changes. Sampling is bounded to at most one
observation per 50 ms; these counts are not exhaustive tick traces or hardware
performance measurements.

The two runs use Godot 4.7.2-stable, Compatibility/OpenGL on the recorded AMD
Radeon 780M, at 1280x720. They bind native SHA-256
`149b6711eb120fea228c6b4bd39f2d19657cae00095dd9fa60a310b6b2ddaf61`
and the byte-identical prepared Tern source
`0f8bfd1c99b1d7c1172eaaa76203d28234a1d3f3db793f6f81bc6b5740fa993f`.
The machine receipt retains launch-time route/driver hashes, current source hashes,
logs, all route artifacts and selected public originals. The inherited QA checker
changed between the first attempts and the final M10 retry as described below;
its pre-correction hash was not independently captured at launch.

Original-size inspection confirms Tern in the M09
[office before release](../screenshots/live-crew-routes-20261008/m09_office.png),
[gallery while moving](../screenshots/live-crew-routes-20261008/m09_gallery.png)
and [distant hatch approach](../screenshots/live-crew-routes-20261008/m09_hatch.png).
The first office view is side-on behind two provisional civilian strips. The
gallery and hatch views retain the actual dark, narrow live body. M10's
[command-deck view](../screenshots/live-crew-routes-20261008/m10_command.png)
shows the stationary live Tern side-on at the console. No missing limbs, detached
surfaces or explosive deformation is observed in those selected originals.

Visibility has a narrower scope than the cast samples. M09 states 01, 10 and 11
do not show Tern, although the current named figure is sampled. M10's
[passenger entry](../screenshots/live-crew-routes-20261008/m10_passengers.png)
shows Latch and provisional passenger strips; Tern is on the upper command deck.
State 24 also shows passengers rather than that pilot. These views do not prove
on-screen Tern motion. The body remains dark in the ordinary mission lighting;
small warm optics, shoulder asymmetry, separate finger animation and verified
console or weapon contact remain open as recorded in the source and fixture
receipts. The other named civilian strips have not been replaced by this work.

The first M10 attempt failed at cabin state 02 with numeric exit 1:
`expected ammo 76.0, observed 20`. Its retained
[HUD original](../screenshots/live-crew-routes-20261008/m10_initial_ammo_failure.png)
shows 20 loaded and 56 reserve. A second, bounded diagnostic replayed the same
first two route states, logged the actual private equipment before the unchanged
assertion, and retained the expected numeric failure. It confirmed bullets 76,
shells 32 and cells 1 in total, with magazines 20/6/1 for Flechette/Scatter/Sniper,
two grenades, three mines and no personal claims.

The cause was an old QA expectation: `ammo` reads ready shots in the selected
magazine, while the private `ammo[]` pools include loaded rounds. The narrow
correction adds validated `pool_rounds` expectations and changes only M10's two
assertion keys: exact cabin pools 76/32/1 and exact cargo bullets 136. A focused
regression preserves ready-magazine semantics, distinguishes 20 loaded from 76
carried, rejects wrong totals and fails closed on malformed expectations. The
final full 28-state route passes with those checks. Finite stocks, combat,
movement inputs, route order and deadlines were unchanged. Both failed attempts
and their original logs remain under the recorded ignored artifact paths.

M09 is an independent development start. Its final current crew aboard flags
remain false, so this receipt does not establish optional crew boarding. M10
starts from the explicitly labelled historical v12 fixture with all five crew in
its retained history, then exercises canonical promotion and ordinary inputs.
It is not a continuous save transferred from this M09 run. No mid-run stock or
mission-state grants are used. This is one Standard route per mission, not fresh
player acceptance, final balance, final art or general platform acceptance.

The launcher observes renderer exit and the script explicitly stops its owned
native child and requires `LocalMatch.IDLE` before success. External native PID
enumeration was unavailable because process executable paths were empty; the
empty child list in the raw M09 receipt is not independent native-retirement
proof. This receipt relies on the explicit source-owned retirement assertion and
clean final logs. It does not kill listeners by port or process name.

Exact launches, with `FRAGR_SERVER` removed from the process environment:

```powershell
$env:FRAGR_QA_DIR = 'C:/GitHub/fragr/.agents/live-buildout-20261008/crew/m09'
$env:FRAGR_LIVE_CREW_MISSION = 'm09'
& 'C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe' --path 'C:/GitHub/fragr/client' --rendering-driver opengl3 --windowed --resolution 1280x720 --script res://qa/live_crew_tour.gd

$env:FRAGR_QA_DIR = 'C:/GitHub/fragr/.agents/live-buildout-20261008/crew/m10-final'
$env:FRAGR_LIVE_CREW_MISSION = 'm10'
& 'C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe' --path 'C:/GitHub/fragr/client' --rendering-driver opengl3 --windowed --resolution 1280x720 --script res://qa/live_crew_tour.gd
```

The ignored bounded launchers retain exact arguments, isolated settings/history
paths, numeric exits and native hash checks before and after each final route.
The diagnostic uses its separately hashed subclass and the unchanged first two
M10 route states. The source preparation, controlled dual-renderer fixtures,
ordinary crew routes and the root-owned full client/package gates retain separate
acceptance scopes.
