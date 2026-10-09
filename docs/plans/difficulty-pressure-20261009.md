# Difficulty pressure

Status: **in flight**, 2026-10-09. Spend: $0. This pass makes the existing
Assisted, Standard, and Severe tiers smarter and tighter on campaign supply.
It is not final balance and not a fresh-player acceptance.

## Goal

Harder is smarter enemies and less ammunition. The three tiers already exist.
This pass does not add a fourth tier, rename them, or build a second
difficulty system. Standard tell numbers and Standard grant amounts stay exact.

The campaign contract already said Assisted has more recovery and Severe has
tighter supply margins. The first implementation kept authored ammunition.
This pass implements that margin and a bounded pursuit. The historical tell
table stays in [difficulty and rewards](difficulty-and-rewards.md).

## Visual pursuit memory

One function, `pursuit_memory`, is used only when a sighting refreshes
`search_until` from the last visible feet. Last known feet are that last
seen position. They are never the participant's live position behind cover.
No enemy gains line of sight through solids.

| Tier | Visual pursuit memory |
|---|---|
| Assisted | 40 ticks |
| Standard | 100 ticks (unchanged) |
| Severe | 160 ticks |

Alarm dispatch stays `tick + 600` on every tier and every kind. The walk
home stays 400 ticks. A new controller still starts at `tick + 600` until a
sighting refreshes it.

Crawler and Jammer use this table too. Their tests do not assume 100 ticks
of visual memory. The Crawler leap test sets `search_until` to 0. The Jammer
difficulty test checks tell timing `(24, 40)` and rules revision 4. A Jammer
does not walk a search trail after it loses sight. No kind is special-cased.

A session without a mission keeps Standard pursuit through the existing
`campaign_rules()` fallback, the same fallback attack timing already uses.
That fallback is not used for supply grants.

## Recovery between bursts

Clerk, Sweeper, and Heavy Sweeper only, and only between bursts. Windup and
firing stay planted on every tier.

| Tier | Between bursts |
|---|---|
| Assisted | Hold still. No sidestep and no step in. The Heavy does not start its sideways shuffle. |
| Standard | The current sidestep. Step in when the fight is farther than `PRESSURE_RANGE` (8 m). The Heavy shuffle stays sideways. |
| Severe | The current sidestep. Step in when the fight is farther than `PRESSURE_RANGE * 2 / 3`. The Heavy shuffle stays sideways and does not gain a step-in. |

## Supply grants

`CampaignDifficulty::supply_grant` is the pure rule. Tests call it without a
match. The claim site in `tick_pickups` applies it only when the session has
a mission difficulty (`campaign_difficulty()`). Arcade, benchmarks,
weapon-only mutators, and any state without a mission keep authored amounts.
`campaign_rules()` is not the supply key: it would invent Standard when
`mission` is absent.

The grant below is the amount before the existing capacity cap. The cap stays
in `grant_ammo` and the health and armor clamps (bullets 200, shells 50,
cells 100, rockets 20, health 100, armor 100). Snapshot pad amounts stay
authored. Pickup events already carry the gained amount.

| Case | Grant |
|---|---|
| Secret pickup | Authored amount on every tier. Exploration still pays. |
| Standard | Authored amount. |
| Non-positive authored amount | Unchanged. |
| Assisted ammunition, weapon-discovery rounds, health, and armor | `ceil(authored * 3 / 2)`, as `(authored * 3 + 1) / 2` for a positive integer. |
| Severe ammunition, weapon-discovery rounds, health, and armor | `max(1, authored * 2 / 3)` when authored is positive. |
| Grenades, proximity mines, and remote mines | Authored count. Mission explosive lessons do not shrink. |

The claim site does not pass grenades or mines through the scaler. The pure
function still has an explosive case so a test can show those counts stay
authored.

A first cut of half ammunition dried out two existing Severe proofs before
they could finish: the M01 public route stalled two fights short, and the
M02 side-ward walker stopped in front of a close enemy it could no longer
shoot. Two thirds is still less than the authored count, and those proofs
have to keep departing on ordinary stock.

Weapon discovery uses `weapon.pickup_rounds()` inside the campaign grant
(`grant_weapon_rounds`). The same ammunition rule scales that grant. The
minimum is 1 when the unscaled grant is positive. A zero grant stays 0.
`grant_weapon` remains the authored path for spawn, tests, and arcade
discovery.

## What stayed identical

Health, damage, burst length, locked aim during windup and firing, and hit
stun are identical on every tier. Engage range, headshot choice, and the
attack patterns of Notary, Auditor, Turret, marksman, Enforcer, Assessor,
Redactor, Crawler, and Jammer stay as they were, except the shared pursuit
memory number above.

`attack_timing` and `channel_ticks` are unchanged. Severe Clerk windup stays
10 ticks (half a second at 20 Hz). No tell was shortened. There is no health
sponge, no sight through solids, no perfect tracking through the tell, no
hidden knowledge, and no unreadable tell.

Map JSON is unchanged. Canonical and development map bytes stay exact.

## Rules revision and saves

`CAMPAIGN_RULES_REVISION` stays 4. Tells and the rules wire shape are
unchanged. The constant's comment now says the revision tracks tell timing
and the wire shape, and that supply amounts and visual pursuit memory are
not a new revision. Historical revision sentences (magazines, Notary,
Assessor and Arc) stay.

`RUN_FILE_VERSION` stays 16. Saved runs already store the difficulty enum.
Saved inventory stores amounts already claimed. Only a future claim scales.
No save migration and no client script change. No save or client test in
this pass required a revision bump. If one does later, stop and record it
here instead of migrating saves.

## Refused

- No `CAMPAIGN_RULES_REVISION` bump and no `RUN_FILE_VERSION` bump.
- No map JSON edits.
- No grenade, proximity mine, or remote mine scaling.
- No tell changes and no shorter Severe Clerk windup.
- No fourth tier and no second difficulty system.
- No fresh-player balance claim. This is not final difficulty acceptance.

## Verification

From this worktree, on 2026-10-09, after the Severe grant moved from one half
to two thirds:

- `cargo fmt -p fragr-server` completed with exit 0.
- `cargo test -p fragr-server --locked --lib difficulty -- --test-threads=1`
  passed 11 tests. The pure grant, a campaign claim on all three tiers
  (ordinary ammo and health grow or shrink, a secret does not, Standard is
  exact, an Assisted health grant still clips at 100 HP), an arcade claim
  that stays authored, pursuit memory 40/100/160 from the last seen feet,
  Assisted recovery holding still, and Standard recovery still sidestepping
  are in that run. Existing tell tests in that filter still pass.
- `cargo test -p fragr-server --locked --lib severe_side_ward_route_survives_with_ordinary_supplies`
  passed. The same test failed when Severe ammunition was half: the walker
  stopped in front of a close enemy it could no longer shoot.
- `cargo test -p fragr-server --locked --lib m01_all_tiers_both_ordinary_routes_depart_with_periodic_resolved_misses`
  passed. The same test failed on Severe at half ammunition, two fights
  short of the public route.
- `cargo test -p fragr-server --locked -- --test-threads=2` was run against
  the half-ammunition cut and failed only those two route proofs (1383
  passed). It was not repeated after the two-thirds change. The later code
  change only raises Severe grants. Assisted, Standard, secrets, explosives,
  and arcade amounts were unchanged.
- `cargo clippy -p fragr-server --locked --all-targets -- -D warnings`
  completed with exit 0 after the two-thirds edit.

Checkers were not weakened to pass. No assertion was deleted. This is not
fresh-player balance acceptance.
