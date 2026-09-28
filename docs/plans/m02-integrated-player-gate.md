# M01 to M02 integrated player gate

**Status:** in flight, 2026-09-28. Test the published
[v0.58.0 Windows package](https://github.com/blisspixel/fragr/releases/tag/v0.58.0)
from `ea0d2bf7b028aa19db3edbe9b23ff3c7d3d223c3`. Preparation spend $0.

## Goal and reason

Prove that the integrated M01 and M02 build behaves as one playable solo run and
learn where a first-time player actually stalls. The scripted route clears,
headless checks and rendered tours prove authoring and runtime contracts. They
do not establish that a player understands the Shotgun, Crawler lessons, Latch
rescue or exit without coaching. Pause new M02 content until that evidence
exists.

## Scope

1. Download the v0.58.0 Windows package and `SHA256SUMS.txt`. Check the archive
   hash before extraction. The package includes its matching Rust server. Run
   the packaged install check with an isolated `FRAGR_RUN_DIR`.
2. Start a fresh local run at M01 and verify the M01-to-M02 transition, body,
   equipment, remaining continues and M02 retry behavior through the packaged
   client. Use the existing gameplay capability 22 boundary and one local save
   path. Record the release tag, source commit, commands and observations. The
   saved departure fixture already has a real source-client automation check;
   its result is supporting evidence, not this fresh-run gate.
3. Have one new player use that package uncoached. Mute spoken radio and voice
   but leave combat sound on. Do not tell them routes, objectives or controls
   beyond the normal menu. Observe and time-stamp first Shotgun claim, the lone
   Crawler and later pack, stalls, deaths, Latch recognition and release, the
   optional side ward, departure and retry. Ask afterward whom they rescued,
   what happened to the other captives, and why Low Water is next. Record their
   words rather than inferring comprehension from a clear.
4. Fix only observed blockers in the owning seams, replay the relevant seeded
   route and visual QA, then repeat the uncoached gate with another fresh
   player. Keep the test record separate from private identity information.

## Architecture and lore boundaries

The Rust server owns objectives, companion behavior, inventory, continues and
shots; the Godot client only presents them. The run file remains the one local
save. Do not add a second campaign control door or client-side mission result.
Latch acts voluntarily after release and is never a forced escort. Optional
captives do not gate departure. The Notary remains an unreachable, noncombat
level 2 glimpse; its first fight belongs to level 4. The Jammer first appears
in level 3. The level has at most one required door.

No protocol change is planned in this gate. If play exposes a real contract
defect, update the owning source, both readers, tests and `docs/protocol.md`
together before issuing a fixed package.

## Verification and success

- The release archive matches its published checksum and `--check-install`
  passes with no script/runtime errors.
- One fresh-run M01-to-M02 transition and one M02 retry preserve server-owned
  body, equipment and continue counts in the local run record.
- The observation log names the exact build, session conditions, timestamps,
  player explanations, stalls and deaths. A clear without comprehension keeps
  the gate open. A scripted clear does not substitute for the player session.
- Any observed fix passes focused tests, pinned Godot checks and the affected
  first-person route; full CI runs at its PR head. Do not weaken the 90 percent
  workspace coverage floor.

## Spend and release gate

This local player gate costs $0 and uses no asset API or GCP resource. Any
future priced operation needs written approval and must stay within the $20
build-sprint allowance and the repository's total $50 cap. v0.58.0 is already
released; any player-visible fix follows the normal PR, CI and release path.

## Current record

The published Windows archive is 622,536,156 bytes. Its SHA-256 is
`3e2434f542b1870a5ba357288b543239cb6cc4587ab26b2c9a78f2b7b28548f4`,
matching the release's `SHA256SUMS.txt`. It contains `fragr.exe`, the matching
`fragr-server.exe` and all six required notice files. On Windows, the unpacked
game returned exit 0 and `fragr install check: PASS` from `--headless --
--check-install` with a fresh absolute `FRAGR_RUN_DIR` and no script errors.
The exact download and check log are under ignored
`.agents/player-gate-v058/`. The [main CI run](https://github.com/blisspixel/fragr/actions/runs/36444024937)
passed on attempt 2 after the first hosted roster attempt stalled and was
cancelled. The [tag package workflow](https://github.com/blisspixel/fragr/actions/runs/36444484929)
passed all three desktop package smoke jobs. These checks prove packaging and
the built-in install probe, not a played M01-to-M02 transition.

Historical draft preparation: a local Windows preview at
`bad8236118c9e70705b84b335928cdb97dc7199b` passed export and install
smokes. Its ignored files were removed with the superseded worktree; v0.58.0
is the retained test target. An exported `--script` attempt did not return and
was stopped, so it is not transition evidence. The source Godot campaign
harnesses and Rust route tests passed on the parent draft. A played, packaged
M01-to-M02 transition remains open.

The source-client carry check now exercises a validated synthetic M01 departure
through a real M02 local child, a second child restart, ordinary movement to
the first guard encounter, death, another restart with the pending Continue,
and Enter to begin attempt two. It verifies the first-attempt Shotgun claim,
then the same run ID, synthetic body, entry health, armour, Tack, 29 bullets
and one remaining continue after retry.
`tools/test_m02_carry.sh` registers the check in the Godot CI job and requires
both a clean engine log and its own PASS marker. On Windows, Git Bash with the
pinned Godot 4.7.2-stable binary returned `M02 carry check: PASS`; the fixture
test passed. The first direct source run returned the same PASS marker. This
is source-client automation from a validated departure fixture; it does not
prove a fresh player can finish M01 or understand M02, and it does not convert
the packaged preview into transition evidence. Exact-head CI for
[`008dd17`](https://github.com/blisspixel/fragr/commit/008dd17be7c48b7f84b12dc1c902d143993b4e12)
passed all required checks on [draft #293](https://github.com/blisspixel/fragr/pull/293),
including the saved-carry Godot step, workspace tests and coverage, soak,
audit, Windows and macOS portability and desktop packages. Publishing was
skipped for this draft. The player gate still needs a fresh-player session.

For the first session, a moderator starts PowerShell at the repository root.
After extracting the verified v0.58.0 archive into
`.agents/player-gate-v058/unpacked/`, run:

```powershell
New-Item -ItemType Directory -Force '.agents/player-gate-v058/player-run-1' | Out-Null
$env:FRAGR_RUN_DIR = (Resolve-Path '.agents/player-gate-v058/player-run-1').Path
& '.agents/player-gate-v058/unpacked/fragr-v0.58.0-windows-x86_64/fragr.exe'
```

Before play, set **Radio** and **Voice** to zero in Settings > Audio, leave
**Effects** audible, and choose Single Player > Recall Notice. Do not use the
M02 development shortcut for this gate. The moderator may record the screen
with the player's consent; no recording is required to note timestamps and
their own words. Record time, place, player action or words, and the observed
outcome for each Shotgun claim, Crawler lesson, Latch encounter, optional ward,
retry and departure. The repeat session uses a separate `player-run-2` path
and a different fresh player.

The earlier [draft #292](https://github.com/blisspixel/fragr/pull/292) checks
are historical. The uncoached player sessions remain open. Keep this status
in flight until the transition, comprehension and repeat session are recorded.
