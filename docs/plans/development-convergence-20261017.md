# Development convergence, October 17

Status: **in flight**. This round resumes six unpublished commits and the
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
assertions and coverage policy are unchanged. The changelog prepares v0.86.0;
its publication still follows reviewed PR CI, main CI and tagged packaging.
