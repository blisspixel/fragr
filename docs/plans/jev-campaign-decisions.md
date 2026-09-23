# Campaign-aware decision brain

Status: **implemented**. Local evidence below; integration review remains.

## Goal

Make the existing decision-brain agent useful and measurable in Recall Notice
before spending on a Jev trial. Its paid questions must describe the actual
mission stakes and carried equipment. The local controller must pursue the
server-owned objective when an occluded guard is not a current fight. A run
summary must report the authoritative mission outcome, not infer success from
frags or elapsed time.

## Scope and seams

Keep one action channel and the existing MissionClient, inventory controller,
navigation budget, provider budget gate, and spend ledger. Choose arena or
campaign questions from validated MapInfo and private loadout state. Include
the current phase, attempt, limited continues, and usable equipment in the
decision state. Use short atomic questions with the same typed answer contract.
Make only a visible, reachable hostile a combat priority in campaign control;
otherwise let MissionClient walk toward its current approach and use prompt.

Do not add a combat-tick provider call, a second mission door, model-specific
game rules, new wire fields, paid test calls, or a different runtime language.
Arena play and local-rule fallback must retain their current behavior.

## Verification

- Unit tests for arena and campaign question wording, carried-weapon choices,
  and decision state from validated mission/loadout messages.
- A deterministic controller test with a living but occluded guard must walk
  toward the record. A visible nearby guard must still receive combat priority.
- A live local-rule M01 matrix over fixed seeds and campaign difficulties must
  report the server's phase, run status, attempt, and remaining continues.
  Record survival, stalls, fallback decisions, and first-person observations.
- Preserve paid refusal, pending reservation, and cap tests with fake
  transports. Run full Rust/Godot checks and mixed arena playtests before PR.

Success is an interpretable free campaign clear or a diagnosed, reproducible
failure with no fabricated completion, plus no arena regression.

## Local evidence, 2026-09-22 to 2026-09-23

The brain now reads validated mission and loadout messages for its campaign
questions and receipt. Independent review found that the shared inventory
controller restored target aim after the campaign controller declined an
occluded guard. It also found that a distant visible guard could halt objective
travel. The action chain now uses one nearby, visible target rule before and
after equipment selection. A deterministic brain test covers hidden, nearby
visible, and distant visible guards with a loadout. A server test carries a
rejected target through inventory and mission steering, then confirms that
objective movement resumes. The watch verifier also rejects unknown mission
status, phase, and difficulty values, and the reported plan rejects weapons
absent from the offered choices. Local fallback plans are also constrained to
carried equipment before action and final reporting.

A later independent review found two decision-specific gaps. A remote
`fall_back_heal` reply could send a healthy fighter toward any health pad;
remote decisions now permit that detour only below 40 HP, within the existing
12-unit near-pad band, and along a directly walkable route. Local fallback
keeps its established recovery behavior. A test takes a
healthy model heal reply through actual M01 mission steering and confirms it
still walks toward the record. The model state now names the same nearest
engageable guard the controller can fight, rather than a hidden nearer guard;
a test covers hidden and exposed guards together.

The first four free-rule runs below preceded the target-filter correction.
They used the authored M01 file, a solo campaign run, and the same 20 Hz
server. No provider call or ledger charge occurred. The final row repeats
Standard seed 67 after the correction. Other seeds still need repeating.

| Difficulty | Seed | Limit | Latest server result | Observed course |
|---|---:|---:|---|---|
| Standard | 67 | 120 s | Complete, attempt 1, three continues | Departed around 104 s, no deaths, 40 HP at receipt. |
| Assisted | 19 | 150 s | Complete, attempt 1, three continues | Departed around 70 s, no deaths, 100 HP at receipt. |
| Severe | 42 | 150 s | Playing, attempt 4, no continues | Three deaths in sorting and stacks; still returning through the mission when the timer ended. This is not a clear or a terminal failure. |
| Standard | 1 | 150 s | Playing, attempt 3, one continue | First-person watch run; two server-recorded deaths, 33 kills, and no departure at the timer. The generated agent name affects its local decision stream. |
| Standard | 67 | 120 s | Complete, attempt 1, three continues | Corrected action path with fixed name CampaignProbe: 14 kills, no deaths; transfer and lift both progressed before the time limit. |
| Standard | 67 | 120 s | Complete, attempt 2, two continues | Remote-only health guard and aligned model target, fixed name CampaignProbe: 30 kills, one combat death, then departure. |

The Severe run exposed an observability defect: campaign deaths did not emit
arena frag events, so the original JSON `deaths` count stayed at zero. The
brain now takes total deaths and kills from the validated participant record.
A focused test checks three deaths without frag events. The later Standard
watch confirmed two deaths in the corrected live receipt. A later Severe run
should inspect whether sorting's pressure or the local route causes the
repeated losses.

The 150-second watch passed with eight first-person frames at ticks 76 to 148,
one participant ID, and a paired $0 receipt. Opening and pistol frames were
inspected: camera position and weapon progression looked coherent, while the
room and pickups still use provisional art. The watch now accepts fixed seed
and name inputs, and its verified receipt retains mission status, kills, and
deaths. A second 20-second seed-67 watch passed. Rechecking its receipt after
normalizing mission integers passed; replacing the status with a number was
rejected with exit code 1 before verification. The corrected seed-67 watch
again captured eight first-person frames and verified one participant ID,
authoritative completion and $0 spend. Frame 7 shows the pistol and objective
card in the intake blockout. A copied receipt with status `banana` was
rejected with exit code 1. That image still shows provisional wall and pickup
art, not a finished visual pass.

Focused brain tests and clippy passed. The full workspace test suite passed
before the target-filter correction, after two attempts to rebuild
`fragr-server.exe` collided with live M01 processes on Windows. Stopping those
exact processes removed the lock. The six-map mixed roster passed. Its spawn
deaths remain a separate open issue. The integrated branch then passed the
full workspace suite, Godot checks, release benchmark, release build, cargo
deny, and coverage at 94.63 percent. The local-rule plan was found to report
an unowned Railgun despite inventory correctly retaining the Pistol; the
reported plan is now constrained to carried equipment. After that correction,
workspace tests and clippy passed again, and coverage reached 94.61 percent.
A final 25-second seed-67 watch verified eight frames and $0 spend; its Pistol
holder no longer reported the unowned Railgun in `last_plan`. That short run
ended during `find_transfer` as expected from its timer. The longer corrected
run above supplies the completion evidence. CI and integration remain.
The two later decision corrections passed focused tests. An initial repeat
of Standard seed 67 after applying the health constraint to local rules spent
three continues and remained in `find_transfer` at 120 seconds. That is a
regression from the earlier clear. The constraint is now limited to remote
model choices while local recovery retains its prior range. A second corrected
seed-67 watch completed in attempt 2 with one death and $0 spend, showing that
the route progresses again but survival is sensitive to decision details.
Other seeds, full checks, and CI still need repeating before integration.

## Spend and later trial

Spend: $0 in this increment. No live provider calls in CI or local verification.
Only after the free matrix and watcher are credible: inspect the shared ledger,
reject unresolved reservations, check current Jev price and the key's lifetime
limit without automatic reset, then run a small OpenRouter trial with explicit
per-run and total caps below the user's $20 evaluation budget. No top-ups.
