# Optional 5v5 Sabotage seats and finite Pistol

2026-10-04. Implemented and tested locally, not yet integrated or shipped.
Initial source checkpoint: `fb9e419df92ef9fa2d5955ccfecda54619dc833e`, rebased onto
main `f409ff3726e1b5e3f251cb3a11281ab4502695d1`. Spend: $0.

## Proven scope

`--mode sabotage --map 4 --sabotage-five-v-five` opts into ten shared fighter
seats. The default four rule bots leave six external seats; `--bots 0` leaves
ten, and `--bots 10` intentionally fills the roster. There is no automatic bot
eviction or ten-player readiness requirement. Humans, agents and rule bots
obey the same seats and side balancing. Spectators do not consume fighter seats.

Six direct/session tests prove five per side with dead and parked bodies,
vacant-side replacement, actual halftime swaps, live-round zero-life waiting,
next-Muster one-life restoration and bounded rule-bot refill using the same
permit pool. Generic twelve-bot Sabotage remains available; its weapon-only
mutator still provides its existing unlimited weapon.

Six actual socket tests use the canonical server runner on ephemeral loopback:
two rule bots plus eight mixed humans/agents, concurrent overflow refused with
`match_full` before Welcome, spectators and MapInfo-first delivery, bad resumes
without seat consumption, explicit leave, vacancy replacement, parked resume,
actual 200-tick grace expiry and unchanged generic eleven-client admission.
Invalid mode, excessive initial bots and weapon-only overrides fail before
readiness; CLI failures report clear errors.

The first private Equipment is inspected before ordinary Action. Fresh seats
own Fists and selected Tack/Pistol with exactly fifty finite Bullets and zero
Shells/Cells. One real resolved Pistol shot leaves forty-nine Bullets; actual
parked reconnect preserves those counts, weapons, selection and other private
inventory facts. Friendly fire and Golden Rail do not replace this start.
An actual Rail map-pad claim, ammo consumption and resolved fighter death
prove survivor weapon/ammo carry and fresh post-death Pistol reset through real
round transitions, without repeated survivor ammunition grants.

The late-seat test exposed an existing eliminated-body correctness defect:
an omitted body could still move and fire. Ingress and active-tick guards now
clear queued work and suppress eliminated movement, jumping, swapping and new
attacks. Passive pickups also reject eliminated bodies. Tests cover healthy
waiting Sabotage seats on a real weapon pad and resolved generic FFA/TDM
TwoLives elimination on a health pad. Exactly the existing life allocation
returns at the next round. Committed grenade/mine lifetimes are unchanged.

The reviewed admission refinement recognizes the actual `match_full` packet
through the existing localized client hard-stop path. Headless client tests
prove the failed loading card presents the useful message and Return, suppresses
automatic fighter resume, and allows a deliberate spectator reconnect/Hello
without reusing a fighter token. This combines with the native full-room
spectator socket proof; it is not a recorded human menu walkthrough.
An additional owner-boundary test proves a stale profile flag cannot grant the
Pistol in FFA or an authored campaign, or before a Sabotage instance exists.

## Local verification

The following commands used `--locked`, a private target directory and two
build jobs. Logs remain in ignored local diagnostics under `.agents/`.

| Gate | Result |
|---|---|
| `cargo test -p fragr-server --lib five_seats` | Seven tests pass, including the owner boundary |
| `cargo test -p fragr-server --test sabotage_five_seats` | Six tests pass, actual sockets |
| `cargo test -p fragr-server --lib sabotage` | 35 tests pass |
| `cargo test -p fragr-server --lib session` | 39 tests pass, includes profile tests |
| `cargo test -p fragr-server --lib tests::modes` | 37 tests pass, existing seeded CTF survey retained |
| `cargo test -p fragr-server --lib sim::grenade` | 13 tests pass, includes dead-owner committed device |
| `cargo test -p fragr-server --lib sim::mine` | Ten tests pass, existing owner/reset lifetimes |
| Server and playtest all-target Clippy with `-D warnings` | Pass |
| Workspace formatting check and `git diff --check` | Pass |
| Pinned headless client import | Pass, clean errors |
| `test_kick_reasons` | PASS, localized full-room packet and spectator reconnect |
| `test_loading_first` | PASS, matching error and visible Return |
| `test_resume` and `test_join_ticket` | Both PASS, clean errors |

## Retained failures and limits

Original late-seat movement and private attack-record failures are retained;
the authoritative defect was fixed rather than reducing their assertions.
Early test fixtures assumed an eliminated wire field, visible waiting bodies,
always-present empty shot arrays or zero rather than negative resolved HP.
Those fixtures were corrected to the actual protocol and damage facts.
One local relink failed because the private Windows test executable was still
running the mode survey. Serializing the subsequent checks passed without
source or threshold changes. The initial CLI failure message lacked its mode
name; the final error explicitly identifies five versus five Sabotage.

This is not a standalone elimination mode, a new room-discovery packet, a buy
shop, a required full roster or proof of human enjoyment. Complete workspace
CI, coverage, integration with other pending gameplay work and main selection
remain open. No renderer or GPU performance claim is made.
