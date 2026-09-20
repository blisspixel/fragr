# Difficulty and earned customization

Status: in flight, 2026-09-20. Task #197. The first increment implements explicit
new-run difficulty selection and shared, versioned enemy timing rules to M01.
Persistent achievements and earned cosmetics remain planned. Local work, no paid
services. The campaign now targets a compact solo run with limited continues;
spending one restores the current mission's entry state. Three per run is the
initial balance proposal. The local M01 lifecycle is now implemented in
[campaign-continues.md](campaign-continues.md); disk saves remain unbuilt.

This increment implements the independent new-run selection boundary. Changing
a running mission, supply variants, campaign-run persistence
and rewards follow the retry contract and broader balance evidence. Standard must
retain the released timing. This first pass is not final difficulty balance.

## First increment

- One typed server profile, fixed for a server lifetime, reported in every mission
  state with rules revision 1. Human, agent and spectator readers see the same
  rules. Reject explicit difficulty on arcade hosts and benchmarks.
- Assisted / Standard / Severe Clerk windup: 20 / 12 / 10 ticks; recovery:
  30 / 20 / 16 ticks. Sweeper windup: 22 / 14 / 12 ticks; recovery:
  38 / 26 / 20 ticks. At 20 Hz even Severe keeps a half-second minimum tell.
  Preserve health, damage, locked aim, burst length, ammo, movement and hit stun.
- Local menu chooses a tier before creating a child. The readiness record echoes
  that choice; mismatched or invalid replies fail closed. Remote hosts select
  `--difficulty` with `--map-file`. No new dependencies or paid calls.
- Gameplay capability 6 adds required mission rules. Older mission readers are
  rejected before admission; arcade compatibility stays intact. Shared Rust
  readers and the strict Godot boundary reject unknown or changing rules.
- Prove phase durations, dodge/interrupt behavior, default equivalence, reset
  retention, invalid CLI/bootstrap/wire cases and all three tiers in real play.
  Inspect the retro menu and shared mission display. Record evidence below.

API research checked 2026-09-20: [clap ValueEnum](https://docs.rs/clap/latest/clap/trait.ValueEnum.html)
supports the existing derive-based parser; [Serde enums](https://serde.rs/enum-representations.html)
support fixed snake-case wire choices. Retain the installed stack and lockfile.

## Player outcome

Choose campaign pressure deliberately. Earn visible titles, emblems and cosmetic
variants through completing missions, exploration and skill. Rewards never
change damage, health, hitboxes, visibility, movement or the available arsenal.
Default customization stays available without grinding or an online account.

Three initial tiers, with working labels Assisted, Standard and Severe:

| Tier | Intended difference |
|---|---|
| Assisted | More recovery resources, longer readable tells and less overlapping pressure |
| Standard | The authored baseline with finite supplies and useful recovery |
| Severe | Deliberate role combinations, flank pressure and tighter supply margins |

Preserve enemy identities, movement, weapon feel, essential story and a valid
counter to every attack. Higher difficulty cannot depend on unexplained health
inflation, perfect hidden knowledge or unreadable tells. No silent adaptive
difficulty. Final quantities come from varied playtests, not this table.

The host selects one shared tier for the run, visible before joining. Solo can
change it at a retry boundary; record the change. Co-op does not silently change
rules per participant. Human and agent participants use the same tier. Extra
objectives may become explicit challenge variants later; essential rescue and
ending content cannot require the hardest setting.

The [campaign contract](../CAMPAIGN.md#runs-and-continues) replaces the earlier
default duo, revival and checkpoint plan. No tactical companion controls or
mandatory co-op across all missions. Balance solo pressure first; autonomous allies
must not consume required supplies or finish the player's introductory fights.
Any later co-op variant needs separate scope and evidence. Human and software
control use the same rules, with no hidden adaptation to an inferred skill score.

## Authority and persistence

Rust owns a typed difficulty profile and its application to encounters, supplies
and retries. Map data selects validated variants; no arbitrary expressions or
parallel combat path. Broadcast the tier and revision and include them in the
versioned save/content contract. Benchmark runs pin their complete rules and
seed independently of personal settings or unlocks.

Achievements consume authoritative events with stable mission, attempt, subject
and achievement IDs. Repeated snapshots, reconnects, mission restarts and replay
must not issue duplicate rewards. Separate participant achievements from shared
party outcomes and define eligibility before adding each achievement. Accessibility
options, subtitles, input device and body choice never invalidate ordinary awards.
Special difficulty or no-death challenges state their exact conditions up front.

First candidates: complete Recall Notice (title), discover an authored secret
(emblem), complete the campaign within its continue allowance (banner). Ship only
against actual implemented events. Names and art need the faction/palette review. Unlock data
must be bounded, versioned and saved atomically through the campaign/profile
persistence seam. Local records are editable local progress, not proof of a
globally verified competitive achievement. Accounts and platform integrations
are separate later work.

## Completion evidence

- [x] Typed profiles, validated selection and shared human/agent wire state.
- [ ] M01 solo balance evidence on all tiers, including misses, deaths, continues
  and scarce supplies. No softlock without secrets. Preserve existing mixed-client
  regressions without requiring full co-op authoring for every future mission.
- [ ] Idempotent awards and retry/reconnect/save corruption regressions.
- [ ] Retro selector and reward/customization screens inspected in motion;
  localization, keyboard/controller and settings cancellation verified.
- [ ] Cosmetic changes preserve silhouettes and combat; benchmark receipts
  identify fixed rules and cannot inherit profile preferences.
- [ ] Roadmap, save/protocol contracts and current rendered evidence updated.

## First-increment evidence

Local verification on 2026-09-20: strict workspace Clippy, 713 Rust tests (two
existing ignored stress cases), release build and license/bans/source checks pass.
Unfiltered workspace line coverage is 95.82%, against the unchanged 90% floor.
Logs: `.agents/difficulty-{clippy-final,workspace,coverage,build,deny}.log`.

Behavioral tests exercise real enemy fire on every tier: no shot before the tell,
ordinary movement evades committed aim, damage and burst lengths stay equal, and
recovery provides a real opening. Standard retains its earlier durations. Tests
also cover fixed rules through party reset, unsupported readers, corrupt rules,
same-mission geometry refresh, CLI restrictions and bootstrap mismatch. The MCP
observation contains the host's chosen profile. Two-participant automated parties
complete actual M01 on every tier; four participants also pass Standard.

Inspected solo tours use ordinary input with an accurate-aim controller, seed 1,
Godot 4.7.2, Windows and AMD Radeon 780M. Each completes all fourteen states,
confirms twenty named guard deaths, recovers the record and departs without a
failed walk or player death. Standard and Assisted use OpenGL compatibility;
Severe uses Vulkan 1.4.344 Forward+. Receipts and contact sheets are under
`.agents/qa/difficulty-{standard,assisted,severe}/`.

The inspected 22-state release gallery includes the new
[difficulty page](../screenshots/tour_difficulty_16x9.png), match views, settings,
shot and rail-impact sequences. Ten public stills are refreshed by the same tour.
The real local-launch harness selects Severe through the menu, verifies the
human and agent see the same profile, and starts Assisted on a later server.

All 27 headless client harnesses pass. The first local-launch assertion exposed
Godot JSON's floating numeric representation: a nested dictionary comparison to
an integer literal failed despite the correct Severe/revision 1 payload. The
fixture now checks both validated fields directly; validation still rejects
fractional, boolean and unknown revisions. No runtime check was relaxed. The
full corrected run is `.agents/difficulty-godot-final.log`.

Integration exposed a separate verifier fault on macOS: an early `grep -q` match
could close a pipe before `printf` finished, making `pipefail` invert a valid
match. The same pattern in the runtime-log checker could miss an error in a long
log. Local reproduction confirms the false negative; a large successful log also
reproduces a false failure in the actual verifier. The repair feeds captured logs
directly to the matcher, retains exit/error/PASS requirements, and adds large-output
success and error fixtures. [GNU grep's usage guidance](https://www.gnu.org/software/grep/manual/html_node/Usage.html)
documents this early-exit interaction (checked 2026-09-20). All ten verifier fault
scenarios and 27 local Godot harnesses pass. CI run 35536139881 at code head
`55405ac` passes all five jobs, including Linux Godot and Windows/macOS portability.
Subsequent final CI run 35537266801 passed all five jobs at `f9dee29`.
PR #198 merged as `b572396` and released in v0.30.0. The remaining achievement
and earned-cosmetic scope keeps #197 open.

These checks establish the implementation and reachable mission, not final human
balance. Missed shots, unfamiliar players, scarce supply margins and the new
limited-continue run need dedicated acceptance. Any future co-op variant requires
its own evidence. No achievement, persistence, reward, run-recovery or final-art
claim follows from this increment. Integration and remaining work stay on #197.
