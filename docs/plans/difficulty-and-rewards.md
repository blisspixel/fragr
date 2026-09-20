# Difficulty and earned customization

Status: planned, 2026-09-20. Requested during M01 completion. No difficulty
selector, persistent achievement ledger or earned cosmetic system exists yet.
Sequence: establish M01's normal balance and retry boundary, then implement this
first on M01 before multiplying campaign content. Local work, no paid services.

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

## Authority and persistence

Rust owns a typed difficulty profile and its application to encounters, supplies
and retries. Map data selects validated variants; no arbitrary expressions or
parallel combat path. Broadcast the tier and revision and include them in the
versioned save/content contract. Benchmark runs pin their complete rules and
seed independently of personal settings or unlocks.

Achievements consume authoritative events with stable mission, attempt, subject
and achievement IDs. Repeated snapshots, reconnects, checkpoint loads and replay
must not issue duplicate rewards. Separate participant achievements from shared
party outcomes and define eligibility before adding each achievement. Accessibility
options, subtitles, input device and body choice never invalidate ordinary awards.
Special difficulty or no-death challenges state their exact conditions up front.

First candidates: complete Recall Notice (title), discover an authored secret
(emblem), complete a mission with a co-op party (banner). Ship only against actual
implemented events. Names and art need the faction/palette review. Unlock data
must be bounded, versioned and saved atomically through the campaign/profile
persistence seam. Local records are editable local progress, not proof of a
globally verified competitive achievement. Accounts and platform integrations
are separate later work.

## Completion evidence

- [ ] Typed profiles, validated selection and shared human/agent wire state.
- [ ] M01 solo and one-to-four-player balance evidence on all tiers, including
  misses, deaths, drop-in/out and scarce supplies. No softlock without secrets.
- [ ] Idempotent awards and retry/reconnect/save corruption regressions.
- [ ] Retro selector and reward/customization screens inspected in motion;
  localization, keyboard/controller and settings cancellation verified.
- [ ] Cosmetic changes preserve silhouettes and combat; benchmark receipts
  identify fixed rules and cannot inherit profile preferences.
- [ ] Roadmap, save/protocol contracts and current rendered evidence updated.
