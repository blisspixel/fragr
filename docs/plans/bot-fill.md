# Optional arena bot fill

Status: **in flight**. Contract accepted, 2026-10-05. Nick authorized optional automatic bot fill alongside fixed bots and no bots. The accepted active-round contract preserves existing lives, scores and committed devices, and visibly refuses unsafe replacement until the next round. Implementation and release acceptance remain pending.

## Goal and scope

Finish the existing desktop TDM and five-per-side Sabotage first-trial work with three explicit bot policies. Humans and externally controlled agents receive identical admission priority over replaceable server-owned rule bots. Retain current fixed-bot defaults and dedicated-server compatibility. No campaign changes, new modes, map work, paid operations, deployment or new gameplay authority.

## Configuration contract

| Policy | `bots` | `fill_target` | Meaning |
| --- | --- | --- | --- |
| `fixed` | 0 through the existing supported bot limit | 0 | Existing fixed rule-bot floor, unchanged. Desktop default remains four. |
| `none` | 0 | 0 | No rule bots spawned or refilled. |
| `auto` | 0 | 1 through 10 | Desired total occupied fighter slots, including humans, external agents and rule bots. Suggested initial selection: four. Ten enables a full five-per-side bot-filled room. |

Add `--bot-policy` and `--fill-target` to the existing CLI. An omitted policy is fixed and preserves the present `--bots` behavior. Reject contradictory combinations before binding; do not reinterpret a nonzero fixed bot count as an automatic target. Desktop Host always emits the complete explicit profile, including `--bots 0` for none/auto. The selected target is a desired population, not a new admission ceiling: TDM continues to accept external participants above that target under existing connection limits; strict five-per-side Sabotage retains ten seats and five per team.

Automatic fill is scoped to arena TDM and Sabotage in this item. Reject auto for authored missions, campaign/solo-run profiles and other match modes before binding. Existing fixed behavior in those other entry points remains unchanged. None retains their existing explicit zero-bot constraints.

The accepted first profiles are plain TDM and Sabotage. Reject automatic fill with any mutator before binding: limited-life elimination and a held golden weapon require additional retirement rules outside this scope. Preserve every existing fixed and no-bot mutator combination.

Client settings become exactly seven fields: current `mode`, `map_id`, `bots`, `lan`, `port`, plus `bot_policy` and `fill_target`. Native arena readiness becomes exactly eleven fields: current version/kind/url/listen/map_id/mode/five_vs_five/bots/gameplay_version, plus those two fields. Validate enum, integer bounds, policy/count consistency and exact requested equality at both boundaries. Retain readiness version 1 with a deliberately paired package update; older native children fail the strict check visibly. Do not loosen unknown-field validation. No game WebSocket schema or gameplay revision is needed if match facts and join timing remain unchanged. This local child profile is configuration, not client gameplay authority.

Host offers Fixed bots, No bots, Automatic fill. Use one count control, labelled Bot count for fixed and Total fighters for auto, hidden for none. Default remains fixed four. Summaries distinguish the selected policy and desired count; they do not claim that an actual participant roster was observed. Preserve supported small-window fit and loading-first behavior.

## Authoritative roster accounting

Keep policy reconciliation inside `GameSession`, reusing `min_bots`, bot roster spawning, the existing ten-seat semaphore, team assignment and resume table. Fixed continues its present floor behavior. Auto must not let `spawn_bots` silently raise a fixed floor to the current spawned count; either separate the raw spawn helper from floor establishment or explicitly keep policy-specific floors apart.

Identify a replaceable rule bot exclusively by `GameSession.bots[*].player_id`, backed by `bot_seats` when strict five-seat rules apply. `Role::Agent`, body, display behavior and callsign are never bot ownership credentials. Other controllers in `GameState.bots`, authored enemies and campaign companions are outside this policy.

Count external fighter slots once per authoritative participant identity, including dead/eliminated late joiners and detached pawns with the existing 200-tick resume reservation. Spectators count zero. Pending validated admissions reserve population until commit/cancel so simultaneous requests cannot overfill. A detached reservation is occupied, not a vacancy. Resume restores the same pawn, equipment, team and permit without replacing a bot or increasing the desired population. Explicit Leave, nonresumable removal or expired grace frees the slot; refill at the next permitted reconciliation point. Admission failures release their own reservations exactly once.

For TDM, reconcile immediately on the tick-owned path, aiming for `max(fill_target - external_occupied, 0)` rule bots. Human/agent admission is never refused merely because the desired auto target is already reached. For Sabotage, ordinary fresh admission still uses `add_player_with_body` and `admit_sabotage_joiner`: a Muster joiner can play now, a Live/Planted joiner waits with zero lives for the next Muster. No bot body, life, ammunition or objective is transferred to the newcomer. New auto bots also use ordinary late-join timing; missing active lives are not resurrected by fill.

## Active-round safety contract

Removing an alive bot followed by an ordinary inactive late joiner can manufacture elimination if that bot was its team's final standing fighter. Therefore reconciliation and admission may only retire a bot during Live/Planted if the unchanged outcome rules would not change merely from that administrative retirement. Keep at least one standing contestant on each previously standing side. Prefer already inactive/eliminated bots, then safe living bots; use stable deterministic choice. Defer unsafe surplus retirement until the normal round boundary.

When all ten strict seats are occupied and no owned bot is safely replaceable, keep the room unchanged and return an observable join refusal advising the participant to join/watch until the next round. Do not invent an inactive eleventh seat or delay an unbounded socket request. At the next Muster, validated humans and external agents can replace any rule bot equally. This is the recommended bounded contract; seamless immediate admission in the last-standing case requires an additional replacement representation and is outside this change unless separately approved and planned.

Do not retire a bot owning a committed grenade or an active mine. Keeping just its explosive objects after removing the owner is insufficient: grenade damage requires that authoritative owner, and a mine goes dark without its owner. Excluding these owners from administrative replacement preserves committed effects without introducing new damage attribution or ownership transfer. Reconcile when the device resolves or through the existing normal removal semantics. During Live/Planted also exclude a carried unplanted charge or active plant/defuse hold from administrative yield. Preserve the planted charge, its clock and resolved score. An otherwise eligible bot's unplanted carried charge during Muster drops through `drop_charge_from` at the actual feet, with existing drop/hold-interruption events. Do not award a frag, death, kill, round or inventory transfer for administrative bot retirement. Remove the matching Session/GameState controller, cached navigator, bot permit and presentation bookkeeping exactly once. Preserve ordinary explicit participant Leave semantics.

## Race-safe strict-seat admission

The current net path acquires the ten-seat permit before `GameCommand::Connected`, so merely evicting bots after Connected cannot admit an auto-filled room. Route only optional auto admission through a bounded request/reply on the existing `GameCommand` queue. Do not add a second gameplay channel or mutate simulation state from socket tasks.

1. Complete current address/global admission, WebSocket/hello bounds, ticket, geometry/gameplay and role validation before requesting a fighter reservation. Attempt valid resume first. Spectators keep the present no-fighter-seat path.
2. Session serializes the request. If there is a free slot, reserve it; otherwise reserve one trusted, currently eligible owned bot slot. Use a unique request identity, at most one reservation per bot, and transfer the actual held permit on commit rather than dropping/reacquiring it between competing requests.
3. Preparation does not remove or stop the bot and does not create a pawn. Complete the bounded hello/Welcome path, then commit through the same Session command queue, rechecking cancellation and active-round retirement eligibility. MapInfo delivery retains its existing before-broadcast ordering. A now-unsafe candidate refuses cleanly; never weaken eligibility to honor a stale reservation.
4. Hold reservations in an explicit owned guard. Failed Welcome/send, closed response receiver, timeout, failed commit, socket cancellation and server shutdown cancel and release/return only that reservation. The tick owner checks response closure/cancellation before destructive mutation. Expire abandoned prepared reservations within the same finite admission deadline. Returning a cancelled reservation restores the original bot permit/controller without generating gameplay outcomes. Commit ownership passes once to the ordinary client/parked resume seat lifetime.
5. Reconciliation includes prepared reservations, so fixed per-tick refill cannot immediately steal a yielded seat. Concurrent human and external-agent admissions use the same ordered path. If all ten slots are external or parked, preserve existing `match_full` behavior. Do not remove a real participant because its callsign or role resembles a bot.

The implementation must choose the smallest transaction representation meeting these invariants. Do not claim failure compensation from permit RAII alone: releasing a permit does not undo a removed bot, committed objective or scored round.

## Source findings motivating the contract

Checked native `dff0b39ba232ad94c83713870706d05871873fb1`, client runtime unchanged from `ebaac375cc58b9fb378814d365a234405fa58fe3`.

- `server/src/session.rs`: `spawn_bots` assigns Role::Agent and raises `min_bots`; trusted owned controllers and `bot_seats` are the proper identity and capacity seams.
- `server/src/net.rs`: current permit acquisition precedes Welcome and Connected; Resume already uses a bounded Session oneshot. Admission validation precedes seat acquisition.
- `server/src/sim.rs` and `sim/grenade.rs`/`sim/mine.rs`: `remove_player` drops charge/flag and deletes owner explosives; grenade damage requires its original owner and mines go dark with an absent owner. An administrative replacement candidate must own no committed devices.
- `server/src/sim/sabotage.rs`: ordinary late joiners are inactive outside Muster; elimination considers remaining standing contestants. Planted charge resolves independently. The new empty-Muster fix must remain intact.
- `server/src/resume.rs`: grace holds the actual permit, claim transfers it and expiry frees it. Auto must not fill that reservation.
- `client/scripts/local_host.gd`: settings currently require five fields, readiness nine; additive policy fields require paired strict validators and fixtures.

## Verification and acceptance

Extend the existing Session/five-seat/socket/owned-child/Host harnesses, not a parallel imitation. Required cases:

- Omitted fixed policy retains old CLI and bot floor. Fixed zero and explicit none remain empty. Reject all contradictory counts, unknown policies and out-of-range targets before listener readiness. Auto desired targets four and ten are distinct from fixed counts.
- Auto TDM fills to target, replaces trusted bots for both human and external-agent arrival, allows external count above target, refills after Leave and grace expiry, and does not refill a parked slot. Equal callsign/Role::Agent never permits eviction of an external participant.
- Auto ten-seat Sabotage admits validated humans and agents by safely yielding only owned bot seats; strict five per team and ten total remain true. Test simultaneous requests, full external room, spectators, bad ticket/capability, failed Welcome, timeout, cancelled receiver, delayed commit and exact reservation cleanup/refill.
- Live joiners keep zero lives until ordinary Muster, new-round pistol and survivor carry stay unchanged. Unsafe last-standing eviction and owner-with-committed-device eviction are refused without changing phase, score or charge; safe retirement preserves existing planted charge/clock and dropped-carrier facts. Committed device owners remain until those effects resolve or ordinary removal applies. No administrative frags or duplicate outcomes.
- Existing empty-server/watcher delay regression retains round one, zero score and full Muster clock until an attached contestant arrives. No bot-fill workaround hides the retained failed two-desktop empty-round witness.
- Client typed boundary tests cover exactly seven settings/eleven readiness fields, mismatched policy/target, integer versus float/bool, unknown fields, invalid combinations, actual Start/Watch/Join/Leave/Resume/Stop and exact-owned child retirement for all three policies. Require numeric zero, clean error logs and each harness's own PASS.
- Inspect actual Host fit at the supported minimum window. After final native/client checks, rerun the unchanged eight-state canonical two-desktop Sabotage witness using the final exact native. Require distinct desktop PIDs/ordinary human identities, at least two shared authoritative nonzero result ticks, expected 0:1 detonation, numeric zero/clean logs/own PASS, owned process retirement and bounded Windows socket refusal. This proves two apps on one machine, not physical LAN, defuse or human fun.

Run the repository's required formatting, Clippy, workspace tests, unfiltered 90-percent coverage, release, license, semantic playtest and full client checker gates on the final combined source. Keep earlier ACK, private probe, coverage, decoder teardown and empty-room failures separately retained. Record actual pending/failed/passed receipts honestly, publish only curated credential-free evidence. Integrate to one CI-passing main and update the release only after its own package smoke gates pass. Then stop for the day as requested.

## Spend

All planning, local sockets, tests and desktop witnesses use existing local tools at zero new cost. No asset API, paid compute, subscription change, top-up or deployment is part of this item.
