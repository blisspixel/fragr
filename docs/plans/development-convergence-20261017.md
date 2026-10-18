# Development convergence, October 17

Status: **shipped**, [PR #419](https://github.com/blisspixel/fragr/pull/419)
and [v0.86.0](https://github.com/blisspixel/fragr/releases/tag/v0.86.0).
This round preserved six unpublished commits and the
existing M16-M18 working tree. The user's requested outcome is one green main
branch and an updated desktop release, with priority issues addressed through
the existing roadmap sequence. All work uses local tools and retained assets,
with $0 external asset or cloud spend.

Nick reports $52.25 available in Higgsfield and authorizes funded asset work,
plus remaining Meshy and ElevenLabs plan credits if useful. These are reported
allowances, not live readings. Verify each account, exact operation price,
retained uncertain holds and available quota before any paid stage. Preserve
native production tools, durable reservations and the $5 per-run dollar ceiling.
No additional cash purchase, renewal, top-up or overage is authorized.

Final integration: main `9081b54945086821f05293cebd3efe74b1aa0dba` passed
[all CI jobs](https://github.com/blisspixel/fragr/actions/runs/39101263743),
including 2,142 native tests and 92.74% unfiltered workspace line coverage.
The [tag workflow](https://github.com/blisspixel/fragr/actions/runs/39104147151)
built and smoke-tested Linux, Windows and universal macOS packages. All three
downloaded archives passed SHA-256 and ZIP integrity verification, and the
downloaded Linux package passed its exported installation check. The release
was published October 18 UTC. The repository returned to one remote main branch;
issues #407-#410 closed. The next bounded implementation is #411. Mission-level
human, difficulty and final-art acceptance remains in the owning plans.

## Scope and order

First establish the inherited native and client baseline, repair regressions,
and review the connected mission, save and protocol changes. Reconcile local
documentation with GitHub: v0.84.0 is the latest published release at entry,
v0.85.0 is a draft, and the local v0.86.0 shipment claims are premature.
The canonical Full build order remains the sole campaign sequence. M19 and
M20 must follow their accepted briefs, not the conflicting added recommendation
list that describes a different finale.

Address admission and match-description failures (#407, #408), then readable
muted narration (#410) and complete gamepad controls (#409). Review #411-#418
against the existing interface plans, retaining their visual and human acceptance
gates. Do not equate structural mission tests with finished campaign acceptance.

## Ownership and verification

Retain Rust outcome authority, existing mission controllers, strict archived save
migration, Godot boundary validation and the adapter's single connection state.
Document changed wire and MCP fields in docs/protocol.md and the adapter README.
No dependencies or toolchain changes are planned.

Run focused regression checks during repair, then the repository's native,
coverage, benchmark, playtest and complete Godot gates. Publish and inspect the
visual tour before a release tag. Use the normal PR, passing CI, squash merge,
main CI and desktop packaging workflow. Keep hardware play and fresh-player
acceptance distinct from automated verification.

## Entry evidence and remaining work

- GitHub main: b72034f, last CI successful; no open pull requests.
- Local main: 984ca50, six commits ahead, with extensive uncommitted campaign
  and multiplayer changes preserved on fix/development-convergence-20261017.
- Twelve open issues, #407 through #418.
- Initial working diff and command logs: .agents/convergence-20261017/.
- Initial workspace tests found a grenade test incorrectly expecting the new
  Rocket self-jump discount, plus a contended local readiness timeout. Initial
  Godot checks found four stale menu/host harness expectations. None were waived.
- Adapter regression suite: 115 passing tests, including real rejected Hello
  and explicit join. Event drain retains admission errors; Welcome clears them.
- M16-M18 native carried-arsenal routes depart at ticks 784, 1629 and 2183, with
  42, 70 and 17 HP. They use finite equipment, actual movement and shared combat.
  This is agent authoring evidence, not human magazine or fresh-player acceptance.
  A bare-handed M16 practice probe died in the forecourt; its balance remains open.
- Twelve prepared worlds and the actual native route states cross the Godot
  boundary. Repairs include fitted lowered controls, clear approach points,
  M17's executive world transition, ordered facts and valid prompt admission.
- Real owned menu launches now pass for M15-M18, including reader-paced arrival,
  readiness, accepted snapshots and local process retirement. The shared mission
  identity replaced the launcher's M14 ceiling; CLI parsing derives from the
  mission enum, and pending-run menus admit every implemented mission.
- M15's controlled native lifecycle passes through both clients, including JSON
  numeric entrant placards and map-before-facts gate transitions. These fixtures
  use controlled placements and encounter clears, not a played route. A separate
  regression covers a cleared blade wave waiting for a partner to leave the pen
  and closing gate before progression can continue.
- Historical v19-v21 promotion, interrupted write, exact archive and retry tests
  pass. Only M18's Episode V edge refills continues.
- Real owned campaign and multiplayer Godot harnesses pass pad-trigger magazine
  depletion, pad reload and authoritative held/released crouch. Muted scene
  tests pass with Voice/Master mute and both caption preferences.
- Rendered pad checks also pass on Xvfb with llvmpipe, four software rendering
  threads, Performance quality and medium pixels. Inspected captures:
  [campaign](../screenshots/pad_campaign_20261017.png) and
  [multiplayer](../screenshots/pad_multiplayer_20261017.png). Both show the
  refilled magazine and unobstructed reticle while crouched. This is synthetic
  pad-event integration evidence, not physical-controller or hardware-FPS proof.
- Independent review identified missing late-mission admission floors and an
  occupied M18 rubble transition. Shared capability derivation and whole-step
  refusal pass socket and solo/party regressions. The final focused review also
  confirmed the M15 party guard, launch/resume coverage, arrival handoff, HUD
  controls and live contract checks, with no remaining concrete blocker found.
- The eight required combat/objective playtest modes pass, as does the mixed
  two-to-sixteen-client roster across all seven maps. The 120-second soak passes
  at 20.00 Hz with four agents, four bots and two spectators, zero queue overflows
  and no degraded samples. These are local CPU/network measurements.
- The 32-state publication tour passes on llvmpipe and publishes fourteen
  current stills. The contact sheet and full controls page were inspected for
  readable menus, unblocked aim, body silhouettes and weapon feedback. Rendered
  M04 story sequences pass actual zero-volume settings, mid-clip mute and
  restored narration with captions on/off; complete fallback text and controls
  remain visible without changing the stored caption choice. The owning
  [audio plan](campaign-transition-audio.md#muted-narration-october-17) has captures.
- Local composed gates pass: 2,141 native tests (five existing ignored), 92.75%
  unfiltered workspace line coverage, 578 Godot checks including 185 harnesses,
  strict workspace Clippy, formatting, release build and the seeded sixteen-bot
  benchmark. The license/bans/source check and all verifier failure scenarios
  pass. Logs remain under the entry evidence directory. GitHub's PR package
  jobs also pass Linux, Windows and macOS builds and smoke checks. Main CI and
  release publication remain separate gates, tracked on PR #419 and the release.

## Consolidation review

[PR #419](https://github.com/blisspixel/fragr/pull/419) contains the inherited
work and the convergence repairs. The new entry captures pass and were inspected:
[M16 motorcycle](../screenshots/m16_motorcycle_20261017.png),
[M17 office](../screenshots/m17_entry_20261017.png) and
[M18 transit](../screenshots/m18_entry_20261017.png). They establish presentation
and accepted entry facts only. Geometry-only overview states explicitly allow
an empty roster after the sole participant leaves and encounters reset. The
unarmed M16/M17 practice entries take immediate damage; practice balance and
complete human routes remain open. These are development missions.

The composed native pass reached 1,487 passing server unit tests before the
build-metadata fixture inherited the surrounding checkout's Cargo/Git identity
from a repository-local TMPDIR. The fixture now explicitly owns its workspace
and bounds Git discovery; both original cache/worktree/archive tests pass.
Independent review confirmed the isolation. The client pass found one outdated
M02 transport double after readiness began reporting actual send success. The
double now models success and failure, and tests that a failed send is never
reported as accepted. The final full native, coverage and client reruns pass;
assertions and coverage policy are unchanged. Reviewed PR CI, main CI and tagged
desktop packaging passed, and v0.86.0 is published with verified archives and
the exported Linux installation smoke.

The final compatibility review found that three corrected M15 approach heights
changed its content identity. The registered exact predecessor from commit
984ca50 now uses the existing strict geometry migration, beginning with save
version 19. Versions 19 through 22 preserve inventory and M12-M15 outcomes,
archive original bytes through interrupted replacement, and promote completed
M15 into M16 without a refill. Completed and closed history retains the world
actually played. Unknown hashes and unsupported shapes still fail. Independent
review found no blocker; the extended native gates verify this final repair.

## Asset account readiness, October 17 Pacific / October 18 UTC

Free native checks report 1,870 Meshy monthly credits and no permanent credits,
with reset at November 3, 20:34:13 UTC. Retain the historical 15-credit uncertain
hold, leaving at most 1,855 usable before new batch reservations. The canonical
ledger has no pending local tasks. Its recovered October 13 ladle receipt
accounts for the completed 30-credit production since the prior 1,900 balance;
the separate older 30-credit discrepancy remains unresolved.

ElevenLabs reports an active Pro plan with 24,985 used out of 1,185,132 included
credits, leaving 1,160,147 at this reading. Its reset is November 6, 14:51:20 UTC.
Extension is not enabled and current overage is $0. No billing setting changed.

The Higgsfield credential check accepted a free Soul v2 standard estimate of
$0.004 for its default probe. That is not a production quote or a live balance
reading. No documented balance endpoint is configured in the native checker;
$52.25 remains Nick's reported funded allowance. Verify the account and exact
operation before production. No generation, uploads or credit consumption were
needed in this round.

Nick's October 18 instruction replaces the historical $5 per-run asset limit
with the remaining funded or included service credits. Live allowances, exact
prices, durable reservations and retained holds bound each batch. Native asset
limits need adjustment before larger batches; no new purchases, renewals,
top-ups or overages are authorized. Brain inference retains its separate cap.
