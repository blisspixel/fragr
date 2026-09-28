# M01 to M02 integrated player gate

**Status:** in flight, 2026-09-28. Based on the stacked M02 draft head in
[#292](https://github.com/blisspixel/fragr/pull/292). Local preparation spend $0.

## Goal and reason

Prove that the current M01 and M02 drafts behave as one playable solo run and
learn where a first-time player actually stalls. The scripted route clears,
headless checks and rendered tours prove authoring and runtime contracts. They
do not establish that a player understands the Shotgun, Crawler lessons, Latch
rescue or exit without coaching. Pause new M02 content until that evidence
exists.

## Scope

1. Review the stacked M02 changes in order and build a local Windows preview
   from the exact draft head with Godot 4.7.2-stable and its matching export
   templates. Keep the preview under ignored `.agents/`, not a public release.
   Place the matching Rust server beside it and run the packaged install check.
2. Start a fresh local run at M01 and verify the M01-to-M02 transition, body,
   equipment, remaining continues and M02 retry behavior through the packaged
   client. Use the existing gameplay capability 22 boundary and one local save
   path. Record the preview's source commit and the exact commands and logs.
   Automate the saved departure fixture through a real source-client local
   child: M02 entry, ordinary movement into the guard encounter, death, child
   restart, pending Continue, Enter and restored attempt-two state.
3. Have one new player use that preview uncoached. Mute spoken radio and voice
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
together before changing the preview.

## Verification and success

- Preview export and `--check-install` pass with no script/runtime errors.
- One fresh-run M01-to-M02 transition and one M02 retry preserve server-owned
  body, equipment and continue counts in the local run record.
- The observation log names the exact build, session conditions, timestamps,
  player explanations, stalls and deaths. A clear without comprehension keeps
  the gate open. A scripted clear does not substitute for the player session.
- Any observed fix passes focused tests, pinned Godot checks and the affected
  first-person route; full CI runs at its PR head. Do not weaken the 90 percent
  workspace coverage floor.

## Spend and release gate

This local preview costs $0 and uses no asset API or GCP resource. The earlier
$20 allowance remains available only for priced, approved build operations
within the repository's total $50 cap. The preview is a local test artifact,
not a release, public deployment or approval to merge the draft stack.

## Current record

The local Windows preview was built from `bad8236118c9e70705b84b335928cdb97dc7199b`
with `cargo build -p fragr-server --release --locked` and the pinned Godot
4.7.2-stable Windows export. Its exact files and SHA-256 hashes are in the
ignored `.agents/playtest-preview/manifest.json`; the game and server sit
together in `.agents/playtest-preview/windows/`. Export exited 0 with no
script or parse errors in `.agents/playtest-preview/export.log`. From Git
Bash, `fragr.exe --headless -- --check-install` printed `PASS` with an empty
isolated run. The preview folder carries the project's license, generated
notices for 95 linked Windows crates, both font licenses and the pinned Godot
license and copyright record. The local
`.agents/playtest-preview/fragr-bad8236-windows-preview.zip` was checked for
both executables, a player start card and all six nonempty legal notice files;
its SHA-256 is in the ignored manifest. An exported `--script` attempt did
not return and was stopped; that command is not accepted as transition
evidence. The source Godot local
campaign harnesses and Rust route tests passed on the parent draft. A
packaged M01-to-M02 player transition is still open.

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

For the first session, a moderator starts PowerShell in the worktree and runs:

```powershell
$env:FRAGR_RUN_DIR = (Join-Path (Resolve-Path '.agents/playtest-preview').Path 'player-run-1')
& '.agents/playtest-preview/windows/fragr.exe'
```

Before play, set **Radio** and **Voice** to zero in Settings > Audio, leave
**Effects** audible, and choose Single Player > Recall Notice. Do not use the
M02 development shortcut for this gate. The moderator may record the screen
with the player's consent; no recording is required to note timestamps and
their own words. The repeat session uses a separate `player-run-2` path and
a different fresh player.

Exact-head CI for #292 passed at
[test and portability](https://github.com/blisspixel/fragr/actions/runs/36415145839)
and [cross-platform builds and packages](https://github.com/blisspixel/fragr/actions/runs/36415145858).
The uncoached player sessions remain open. Keep this status in flight until
the transition, comprehension and repeat session are recorded.
