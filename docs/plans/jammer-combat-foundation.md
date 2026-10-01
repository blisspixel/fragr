# Jammer combat foundation

**Status:** shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. Local work under
`campaign-and-feel-buildout.md`.

## Goal

Make the next campaign enemy playable on a dedicated development range. The
Jammer opens its antenna during a readable tell, launches one slow interference
pulse along committed aim, and exposes a recovery opening. This supplies the
combat capability Scheduled Service needs without claiming its mission exists.

## Design and ownership

Reuse authored encounter activation, campaign identity, shared combat rays and
the existing traveling-shot launcher. The Jammer has 90 health, no carried gun
and no locomotion. Its wire weapon is Fists, but it never performs a fists attack.
Its Windup is 24 ticks and Recovery is 40 ticks on every difficulty. Existing
difficulty tables and campaign rules revision remain unchanged.

Its pulse travels at 2.5 metres per second, does 12 damage, and expires after
240 ticks (12 seconds or 30 metres at 20 Hz). Aim locks at the start of the tell.
A visible target must remain in sight until launch. A hit cancels the tell and
uses the existing six-tick Hit phase. One pulse per emitter bounds overlap;
another attack waits until the preceding pulse finishes. Solids stop it, players
can sidestep it, and friendly campaign bodies cannot take damage.

Keep the existing traveling-shot fixture defaults intact. Add an internal pulse
profile rather than another collision model. Keep a dead emitter's body until
its in-flight pulse resolves, preserving the existing combat ownership path.
Campaign party reset and explicit retry clear every traveling shot.

Server ownership: `protocol/actors.rs`, `encounters/enemy.rs`,
`sim/traveling_shot.rs`, minimal attack dispatch in `sim.rs`, reset and cleanup in
`encounters.rs`, dedicated tests and `server/maps/test/jammer-range.json`.
Integration owns actor capability admission, client validation, original offline
rig and atlas, projectile presentation and shared protocol documentation.

## Protocol and architecture impact

`EnemyKind` gains `jammer`. Existing phases and projectile position shape stay
unchanged. Maps containing this kind require the corresponding client capability
before admission; existing missions retain their existing requirement. There is
no new Action field, combat tick, transport, dependency or scripting runtime.

## Non-goals

No full M03, mast destruction, rail-car liberation, radio interference mechanic,
train departure, new weapon, splash, homing or revised campaign difficulty.
No human acceptance or finished-art claim. No publishing or paid generation.

## Verification and success criteria

Seeded tick tests must prove telegraph delay, delayed impact, dodge, locked aim,
solid occlusion, hit and sight interruption, dead-emitter persistence beyond
corpse cleanup, campaign hostility, one-pulse limits and party-reset cleanup.
Load and route-check a playable range with cover and a clear flank. Run focused
server tests and integration checks; record exact commands and results here.
The coordinated build runs workspace checks and rendered inspection.

## Spend

Planned and actual external spend: $0. All code, fixtures and character source
use local development tooling and original offline art.

## Work record

- Source inspection confirmed the traveling-shot foundation has no live caller.
- Campaign reset does not currently clear shots, and corpse cleanup can remove
  an emitter before a long-lived shot reaches its target. Both belong to this
  increment's behavioral tests.
- Implemented the authoritative Jammer, playable two-encounter range, campaign
  reset cleanup and retained dead-emitter ownership. No existing enemy timing
  changed. The range validates all landmarks, supplies and enemy routes through
  the existing authored loader.
- `cargo test -p fragr-server --locked tests::jammer -- --nocapture` passed:
  16 dedicated tests plus one matching legacy Jammer-dish test. This includes
  live socket admission for human, agent and spectator roles: capability 22
  receives `unsupported_gameplay` before game messages, capability 23 receives
  authoritative geometry before snapshots. M02 still admitted capability 22
  at that check. Current Discovery maps require capability 26; the retained
  admission regression rejects historical 22, 23 and 25 before game messages
  and checks geometry ordering for current readers in every role.
- Initial focused assertions were corrected to use the actual first controller
  tick after encounter placement and the existing Rail's 80 damage. The
  implementation and existing weapon damage were preserved.
- Focused Clippy caught a redundant `clone` on a Copy wire point in a test; it
  was removed. `cargo clippy -p fragr-server --all-targets --locked -- -D warnings`
  then passed. Coordinated workspace and rendered verification remain open.
- `cargo test -p fragr-server --locked tests::traveling_shot` passed all 13
  existing projectile regression tests, preserving the original four-second
  fixture, floor and wall collision, shield behavior, departed shooter behavior,
  round cleanup and omitted-empty wire contract.

- Coordinated workspace tests and Clippy passed, including 642 server library
  tests with three existing ignored tests. The pinned full Godot checker passed
  the Jammer boundary, animation, source/atlas freshness and projectile harnesses.
- The input-driven range tour passed all eight states, clearing the solo Jammer
  and both mixed-fight enemies without equipment grants or teleports. Inspected
  poses and a twelve-frame strip show fixed feet, unfolding, the bright moving
  pulse and collapse. This is development-range evidence, not M03 acceptance.
  Final integration results and retained screenshot paths belong to the parent
  [buildout plan](campaign-and-feel-buildout.md).

## Local range

```sh
cargo run -p fragr-server --locked -- --bind 127.0.0.1:6767 --bots 0 --map-file server/maps/test/jammer-range.json
```

Watch or join through the existing client. Find the Rifle and Shotgun beside the
entry, then cross the first trigger at the front of the train cars. Their outer
routes provide clear flanks. The second encounter pairs a Jammer and Sweeper.
This is a development combat range, not a Scheduled Service campaign mission.
