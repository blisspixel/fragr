# Optional five versus five Sabotage admission

**Status:** implemented, 2026-10-04. Focused local checks pass; combined
integration, complete CI and shipping remain open. Plan preceded implementation.
**Spend:** $0. No rendering or external calls required.

## Goal and scope

An explicit host option, `--sabotage-five-v-five`, bounds Sabotage to ten
fighter seats and five per side. Humans, decision agents and rule bots obey
the same capacity. Spectators remain welcome. Generic matches retain their
existing limits and behavior. This is admission, not a readiness quorum:
fewer than ten participants may play while seats fill.

No buy shop, elimination mode, packet revision, new gameplay
capability, account service or skill-based admission is introduced.

Nick's subsequent 2026-10-04 decision adds a basic Pistol start to this optional
profile only. Admission, first round and fresh post-death rounds grant the
canonical owned Tack/Pistol and fifty finite Bullets. Stronger weapons remain
map pickups. Survivors keep their exact carried weapons and ammunition;
Muster grants no repeated sidearm ammunition. A parked resume retains exact
inventory. Generic Sabotage and campaign starts remain unchanged.
Weapon-only mutators are rejected for this profile before binding, since they
would contradict its finite Pistol start. Generic weapon-only games remain
available. Friendly fire and Golden Rail remain compatible host options.

The late-action regression exposed an existing eliminated-body bug: an omitted
body could still accept move/fire input. Fix the canonical action and active
tick boundaries for all eliminated participants, including passive pickups,
without changing lives, damage or committed-device lifetimes. Keep the original
failed ordinary-action and socket record receipts.

## Contract

- Overflow receives an existing-shaped Error with `match_full` before Welcome.
  No fighter identity, player body, statistics entry or resume token is granted.
- Vacant-seat joins use existing side balancing, counting all seated bodies,
  including eliminated and disconnected parked participants. No side exceeds
  five. Side choice never depends on human versus agent control or callsign.
- During Muster a new seated participant may play. During a live round or its
  result card, existing Sabotage admission keeps the newcomer eliminated with
  zero lives until the next Muster. Replacing a leaver grants no mid-round life.
- A resumable drop retains its seat, side, body and current life for the
  existing 200-tick grace. A valid resume reuses that seat without minting a new
  life or evicting a fighter. Explicit leave or grace expiry frees the seat.
- Existing rule bots occupy seats. Capacity does not evict them to prefer a
  human or external agent. A host chooses how many bots to start; refill stops
  when all seats are occupied. More than ten initial bots is a startup error.
  The unchanged CLI default is four bots, leaving six external fighter seats;
  `--bots 0` leaves all ten available. `--bots 10` intentionally leaves none.
  Session's internal `min_bots` floor is seeded by the initial bot roster and
  does not create additional capacity. It has no new CLI or reload path here.
- Spectators use normal connection safeguards, not fighter seats. Tickets and
  bans still run before any fighter permit; strong aim is not grounds for refusal.

## Owning seams

Use one explicit flag in the internal Sabotage config and validate it before
binding a server. Reuse the current network party-seat Semaphore and its
resume-owned permit; share that same pool with Session rule bots. Preserve
Welcome, MapInfo-first delivery and existing resume ordering. Add an
authoritative simulation capacity backstop so direct sim admissions cannot
create an eleventh fighter. Existing side counting includes dead and parked
bodies; do not redefine contestant eligibility.

## Verification

Meaningful socket tests exercise a mixed ten-person roster, concurrent overflow
before Welcome, spectators at capacity, leave/replacement, parked resume and
late-round waiting. Session tests exercise rule-bot permits and refill bounds.
Direct simulation tests prove five per side with dead/parked bodies, side
replacement and unchanged generic Sabotage with more than ten participants.
Invalid host mode/bot combinations must fail before binding. Run focused
tests, formatting and warning-denied lint using a private two-job build cache.

Also verify the first private Equipment before ordinary action, actual finite
Pistol fire and exact spent-ammo resume, real stronger-weapon pad claims,
survivor carry and fresh post-death inventory. Elimination tests cover both
late Sabotage seats and generic FFA/TDM TwoLives, including queued jump/swap
input and passive pickups. Preserve existing committed-device tests.

Integration, complete CI, public host documentation and player-facing room
profile discovery remain separate parent-owned gates. The server sends no
new profile field in this cut; a host must advertise the optional room rule.

Local receipts and scope are recorded in
[the profile evidence](../evidence/sabotage-five-seats-20261004.md).
