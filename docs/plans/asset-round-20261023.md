# Expiring-credit asset round, 2026-10-23

**Status:** planned, 2026-10-23. Tool changes T1 to T5 are implemented in the same change that adds this plan; paid batches open only through the ledger below.
Free account checks and receipts are in the ignored `.agents/asset-round-20261023/` directory:
`elevenlabs-quota.txt`, `meshy-check.json`, `meshy-balance.json`, `hf-api-check.json`, `hf-price-probes.json`, `audio-audit.md`, `visual-audit-notes.txt`, `l19-l20-asset-needs.md`.

> **Correction, 2026-10-23 (Nick):** radio is a small GTA-style feature, not the plot. E-16 (radio news), E-17 (radio refresh, 200k), E-18's radio extension and H-10 (station badges) are **cancelled**. E-1 and E-2 Host barks use plain arena calls in fragr's voice (e.g. DOUBLE FRAG, RAMPAGE), never "frequency" puns. The ElevenLabs budget moves to E-15 score, E-12 to E-14 combat, enemy and world sound and ambience, E-8 movement, character voice (E-11 onward) and campaign narration.

## Goal

Turn Nick's funded, expiring allowances into assets that will actually ship visibly, before each allowance resets:

- **Meshy:** 1,855 usable credits expire 2026-11-03 20:34 UTC.
- **ElevenLabs:** about 1.158M credits reset 2026-11-06 14:51 UTC.
- **Higgsfield:** $52.25, user-reported, prepaid, no stated expiry.

Order of work:

1. Meshy work goes first because it expires first. Its Higgsfield reference sheets are its critical path.
2. Then the gaps players see today:
   - the Repeater has no art and fires silently
   - reloads have no feedback (#440)
   - the Rocket has no pickup profile
   - the Assessor, Walker and motorcycle are built from primitive boxes
   - story scenes have no stills or narration
3. Then wave 2 (#431, #442), wave 3 (L19 #429) and wave 4 (L20 #430).

Quality comes before count. Every candidate stays offline until it passes its acceptance gate.

This round follows these authorizations in AGENTS.md:

- 2026-10-13: the Meshy and Higgsfield allowances
- 2026-10-17: the $52.25 Higgsfield figure and use of funded credits
- 2026-10-18: the $5 per-run ceiling is replaced by the funded balances, and native tool ceilings must be updated before larger batches

## Non-goals

- **No new money.** No cash purchases, top-ups, renewals or overages. Do not touch the ElevenLabs `allowed_to_extend` setting (maximum 250,000). Higgsfield refusing for lack of balance is a hard stop, not a prompt to top up.
- **No game mechanics.** This round does not build mechanics or new `EnemyKind`s. That includes the Paver, Surveyor and Collector, jetpack fuel and movement, sentries, footstep surface tagging, and host-bark routing. Waves 2 to 4 own those. This round produces candidates and their acceptance receipts only.
- **No committing unreviewed audio.** Nick resolved the rights gate on 2026-10-23: new ElevenLabs SFX and music ship by committing them with provenance (see the rights gate). Nothing is committed until it passes its audio gate. Speech is already cleared under the 2026-09-30 paid-account basis.
- **No change to the brain inference $5 ceiling** or to the cloud approval rules.
- **No automatic retries** of uncertain submissions. No paid CI calls. No runtime API calls.
- **No volume for its own sake.** Credits left after the batches below are not spent on content nobody will audition or integrate.

## Verified usable balances and budget

| Service | Live reading 2026-10-23 | Holds | Usable | Planned ceilings (sum) | Contingency inside sum | Unallocated |
|---|---|---|---|---|---|---|
| Meshy | 1,870 monthly, 0 permanent (`meshy-check`) | 15 historical external hold (`art/raw/meshy-account-hold.json`); 0 local pending | **1,855 credits** (~$37.10 at the tool's 0.02/credit) | 1,840 | 150 retry pool (R-M) | 15 |
| Higgsfield | **No balance endpoint.** $52.25 is Nick's 10-17 report. All 8 ledgers are `downloaded`, with no unreconciled holds. | none known locally | **$52.25, unverified** | $51.40 | $1.00 (R-H), plus low-priority batches that absorb any shortfall | $0.85 |
| ElevenLabs | Pro, 26,318 / 1,185,132 used (`audiogen quota`) | none local (no `.audiogen-pending` receipts); 1,333 credits of drift since 10-17 were Nick's own account use (2026-10-23), noted, not held | **1,158,814 credits** | ~501,000 | 30,000 (R-E) | ~658,000 (see note) |

**Higgsfield prices, live `/estimate` today** (about 18% above the 2026-09-19 figures; [`higgsfield-pipeline.md`](higgsfield-pipeline.md) now records both):

| Setting | Price per image |
|---|---|
| marketing-studio low 2k | $0.023 |
| marketing-studio medium 2k | $0.118 |
| marketing-studio high 2k | $0.439 |
| medium with reference images (estimated) | ~$0.16 |
| high edit from a reference (estimated) | ~$0.41 |

Price every spec with `fragr-spritegen price` before running it.

**Meshy prices** (tool constants dated 2026-10-03; rechecked against the [primary pricing page](https://docs.meshy.ai/en/api/pricing) on 2026-10-23 and unchanged):

| Operation | Credits |
|---|---|
| `meshy-7.1` standard geometry | 30 |
| `meshy-7.1` 2k/4k geometry | 35 |
| `meshy-t2` Smart Topology | 15 |
| Rig | 5 |

**ElevenLabs prices:**

| Operation | Credits |
|---|---|
| SFX | 40 per second, rounded up (so a 0.6 s cue costs 40) |
| Music | 900 per minute |
| `eleven_v3` speech | 1 per character |

**Rules that stop credits being counted twice:**

- Opening a batch commits its ceiling against a running ledger kept at `.agents/asset-round-20261023/ledger.md`.
- At any moment: sum of open batch ceilings + retained holds ≤ last live usable reading.
- When a batch closes, reconcile its actual spend against a fresh live check, after which unused ceiling returns to the pool.
- Contingency pools are drawn by opening an explicit retry batch, never by raising a running batch's cap.
- Meshy, ElevenLabs and Higgsfield batches run one at a time per service, through the single account ledger.

**Unspent ElevenLabs note.** About 658k credits have no batch. Nobody can audition 1.1M credits of output into shippable assets before 11-06. The listening load from the batches below is already about 200 music takes and about 900 SFX and speech takes. If listening shows a high keep rate on E-17 (radio) or E-15 (score) by 2026-11-03, open an E-18 radio/score extension sized to the remaining balance minus a 50k margin. Otherwise let the remainder reset. That outcome is deliberate, not an oversight.

## Deadlines and schedule

| Date (UTC) | Work |
|---|---|
| 10-23 to 10-24 | Tool changes T1 to T5 (one small PR). Free price and quota probes. Nick's rights decision (made 10-23: commit with provenance). Open H-1a. Open E-1, E-3, E-4. |
| 10-24 to 10-25 | **Nick reviews H-1a reference sheets.** Open H-1b, H-2, H-3. |
| 10-25 to 10-27 | Meshy M-1, M-2, M-3a, M-3b from approved sheets. Nick reviews H-1b. Open H-1c, H-4, H-5a. Open E-2 (after casting), E-5 to E-8. |
| 10-27 to 10-30 | Meshy M-4, M-5, M-6. Open E-9 to E-14 and H-6 to H-9. |
| 10-30 to 11-01 | Meshy M-7 bank, sized to the real remainder after reconciliation. Open E-15 to E-17. |
| **11-02 23:59** | **Meshy submit cutoff.** Open retry batch R-M on rejected candidates. Final `meshy-check` reconcile before the 11-03 20:34 reset. |
| **11-05 23:59** | **ElevenLabs submit cutoff.** Optional E-18 decision. Final `quota` before the 11-06 14:51 reset. |
| After | Higgsfield does not expire. H-5b, H-10 and H-11 can follow game demand. |

## Tool changes needed first

**Status:** T1 to T5 implemented on 2026-10-23 in the PR that adds this plan (branch `assets/tool-ceilings`). Results:

- T1: `HARD_CAP_USD` is 40.0; `check_budget` still refuses a live run without an explicit `--max-spend-usd`.
- T2: `meshy-gen --max-credits` accepts 1 to 1,900 (`MAX_CREDITS`); 1,900 credits at `USD_PER_CREDIT` is $38, inside T1. The 250-credit stage valuation (`MAX_STAGE_CREDITS`) and 32-stage limit (`MAX_STAGES`) are unchanged.
- T3: prices unchanged at the primary source (7.1 with 2K/4K textures 30, Ultra geometry +5, t2 15, rigging 5). `PRICING_DATE` stays 2026-10-03 because it is part of each reservation identity.
- T4: a live `batch` reads the free subscription endpoint, refuses unless `--max-credits` ≤ remaining − 25,000 (`BATCH_QUOTA_MARGIN`), and prints the quota after, including after a failed job. Tests use fake transports only.
- T5: done, except the #440 note, which is an issue comment outside this change.

Original task list:

- **T1. `tools/spritegen/src/lib.rs:79`**
  - Change `HARD_CAP_USD = 5.0`, the superseded ceiling, to a funded-balance ceiling, for example `40.0`. Every run must still pass an explicit `--max-usd`, enforced in `check_budget` (line 384).
  - Update the pinning test at line 948.
  - Needed by H-1a ($5.50), H-3 ($8.50), H-5a ($6.30) and any Meshy run above 250 credits.
- **T2. `tools/spritegen/src/meshy.rs:485`**
  - Allow `max_credits` from 1 up to the live usable balance (1,900 maximum) instead of 1 to 250, and keep it consistent with T1 through `USD_PER_CREDIT`.
  - Keep the 250-credit per-stage `pending_credits` check (line 208) and the 32-stage limit (lines 465 and 492).
  - Every Meshy batch below is sized to 250 credits or less. If T2 slips, only M-7 has to be split (M-7a, M-7b, M-7c).
- **T3. Meshy price recheck.** Check the primary source for 7.1 standard and 2k, t2 and rigging prices. Update `PRICING_DATE` and the constants if they have changed. Do not add text-to-3D, refine, retexture or remesh this round.
- **T4. `tools/audiogen` batch preflight (recommended).**
  - Make `batch` call the free subscription endpoint first.
  - Refuse when `--max-credits` exceeds remaining minus a 25,000 margin.
  - Print the quota afterwards.
  - Until this exists, run `quota` manually before and after every batch.
- **T5. Documentation.**
  - Update the stale marketing-studio prices in [`docs/plans/higgsfield-pipeline.md`](higgsfield-pipeline.md).
  - Add a note to #440 that Nick's 10-17/10-18 authorization now funds reload assets.
  - Add [`docs/plans/meshy-assets/e-stretcher.md`](meshy-assets/e-stretcher.md) and [`e-supply-crate.md`](meshy-assets/e-supply-crate.md); both briefs are missing and needed by M-4 and M-5.
- **Optional.** Higgsfield concurrent submission (the account allows about 4). This saves time only, and is worth doing if H-5 becomes a bottleneck.

## Rights gate (decided 2026-10-23)

**Decision:** Nick chose option 1. New ElevenLabs SFX and music ship by committing them to the repository with provenance, on the same basis as the [October 2 sound pass](sound-pass-20261002.md) and [`client/assets/audio/README.md`](../../client/assets/audio/README.md). Each committed file keeps its `audiogen-manifest.json` entry (prompt, model, format, duration, generation time) and its batch spec. The decision is recorded in [`m02-ward-soundscape.md`](m02-ward-soundscape.md), [`audio-round-20261013.md`](audio-round-20261013.md), [`radio-refresh.md`](radio-refresh.md) and the [plans index standing facts](README.md#standing-facts).

The options that were considered:

1. Accept the terms and commit, as the 10-02 sound pass did. **Chosen.**
2. Ship the assets only in packaged builds from a private asset pack, kept out of git.
3. Use the generations as references for original sounds baked offline in Godot.

The decision removes the distribution block, not the quality bar: every cue still passes the audio gate below before it is committed. Speech batches were never blocked. All audio is generated into `.agents/asset-round-20261023/audio/<batch>/` first so that it can be auditioned before the reset.

## Standing rules for every batch

- **Before:**
  - Run a free preflight (`price`, `meshy-check --requested`, or `batch --dry-run`).
  - Set an explicit ceiling equal to the preflight total, plus that batch's stated retry share.
  - Write a durable reservation receipt.
- **After:**
  - Run a live balance or quota check.
  - Reconcile the batch in `ledger.md`.
- **Never print credentials.**
- **No tilted or rotated text.** Nick dislikes tilted or rotated UI text. Generated badges, signs, cards and HUD frames keep lettering level, and essential text is overlaid, not baked in.
- **Outputs stay under ignored paths** until accepted:
  - Meshy: `art/raw/meshy-pilot-20261003/`
  - Higgsfield: `art/raw/<batch>/`
  - audio: `.agents/asset-round-20261023/audio/`
- **Generated sources are not finished assets.** Selection requires inspecting the actual geometry or image in Godot, or a listening measurement, followed by a played or gameplay-distance check.
- **Nick reviews (taste gate):**
  - all enemy and named-character reference sheets
  - host and character voice casting
  - story stills
  - the music
  - crowd poses
  - the Orrin and Sorrel identity sheets
  - the rights gate (decided 2026-10-23: commit with provenance)

---

## Higgsfield batches ($51.40 of $52.25)

These all use `tools/spritegen gen` with a JSON spec in `tools/spritegen/specs/`. Specs stay untracked until their PR lands, and follow existing templates:

- `m13-ladle-reference-20261013.json` for reference sheets
- `rocket-idle-20261015.json` for viewmodels
- `missing-pickups-20261016.json` for pickups
- `m13-foundry-surfaces-20261013.json` for surfaces

`enhance_prompt` is always false. Every reference sheet uses a flat magenta (`ff00ff`) background, contains no text, serials or faces, and gets the reduce `--key ff00ff` step.

### H-1a: Meshy reference sheets, critical path (ceiling $5.50, priority 1, needs T1)

Approach for each subject:

1. Three low 2k explorations, about $0.07.
2. Two medium front/three-quarter sheets, about $0.32, using the selected exploration as `image_urls`.
3. One high keeper ($0.44) for the three new enemies only.

Silhouette and primary read follow the brief's "must read at gameplay distance" line.

| id | Brief / reference | Prompt approach | Cost | Consumer |
|---|---|---|---|---|
| ref-paver | [`meshy-assets/c-paver.md`](meshy-assets/c-paver.md), ENEMIES.md:229, [`l19-planned-works.md`](../campaign/l19-planned-works.md) | Broad, low, matte-bone restoration machine. Ink joints, muted cyan indicators, substantial work head with a projector for the strip. Front and side. | ~$0.83 | M-1, #429 |
| ref-surveyor | [`c-surveyor.md`](meshy-assets/c-surveyor.md), ENEMIES.md:230, [`l20-local-exception.md`](../campaign/l20-local-exception.md) | Elevated off-white observer on a visible support. Oversized lens assembly drawn shut and open. | ~$0.83 | M-1, #430 |
| ref-collector | [`c-collector.md`](meshy-assets/c-collector.md), ENEMIES.md:228, `server/src/mission/m18.rs` | Narrow continuous off-white body with a working tool. Commit pose. | ~$0.83 | M-1, #429, #430, M18 |
| ref-jetpack | [`e-jetpack.md`](meshy-assets/e-jetpack.md), [`docs/plans/vehicles.md`](vehicles.md) | Personally adapted industrial flight pack. Clear twin nozzles, fuel hardware, coalition repairs. Back and three-quarter views. | ~$0.39 | M-2, #429 |
| ref-sentry | [`e-portable-sentry.md`](meshy-assets/e-portable-sentry.md), [`wipe-finale-and-mode.md:629`](../design/wipe-finale-and-mode.md) | Foldable civilian tripod sentry. Visible ammo box and slew joints. | ~$0.39 | M-2, #430 |
| ref-assessor-hull | [`c-assessor.md`](meshy-assets/c-assessor.md), `assessor_rig.gd` (2.6 x 1.2 m) | Armoured four-fan drone hull only, with empty fan wells (fans stay local). | ~$0.39 | M-3a |
| ref-motorcycle | [`e-motorcycle.md`](meshy-assets/e-motorcycle.md), [`vehicle-assets-20261006.md`](vehicle-assets-20261006.md) | Side and three-quarter views. Wheels clearly separable for pivots. | ~$0.39 | M-3a |
| ref-walker-hull / -leg / -artillery | [`c-continuance-walker.md`](meshy-assets/c-continuance-walker.md), `sim/walker.rs` | Three isolated part sheets, each matched to the server solid proportions. | ~$1.17 | M-3b |

**Gate:**

- isolated on magenta, with no text
- matches the brief's silhouette and palette rules
- original, with no franchise likeness
- **Nick approves** each enemy sheet before its Meshy stage; the rest are approved by the engineer against the brief

### H-1b: L19 and L20 prop reference sheets (ceiling $4.20, priority 2)

Approach: start from the `client/art/production-20261003/prop_*.png` image where one exists (meal stove, luggage scanner, bicycle and others). Then make three low explorations and one medium sheet with reference, about $0.23 per subject, plus a 30% revision share.

| ids | Briefs | Consumer |
|---|---|---|
| ref-rooftop-tank, ref-turnstile, ref-tram-motor, ref-civilian-tram, ref-duffel, ref-hard-luggage, ref-meal-stove, ref-stretcher | [`e-rooftop-tank.md`](meshy-assets/e-rooftop-tank.md), [`e-turnstile.md`](meshy-assets/e-turnstile.md), [`e-tram-motor.md`](meshy-assets/e-tram-motor.md), [`e-civilian-tram.md`](meshy-assets/e-civilian-tram.md), [`e-duffel.md`](meshy-assets/e-duffel.md), [`e-hard-luggage.md`](meshy-assets/e-hard-luggage.md), [`e-meal-stove.md`](meshy-assets/e-meal-stove.md), [`e-stretcher.md`](meshy-assets/e-stretcher.md) (T5) | M-4, #429 |
| ref-pier-crane-cab, ref-edda-lamp, ref-sluice-actuator, ref-valve-manifold, ref-filter-skid, ref-supply-crate | [`e-pier-crane.md`](meshy-assets/e-pier-crane.md), [`e-edda-lamp.md`](meshy-assets/e-edda-lamp.md), [`e-sluice-actuator.md`](meshy-assets/e-sluice-actuator.md), [`e-valve-manifold.md`](meshy-assets/e-valve-manifold.md), [`e-filter-skid.md`](meshy-assets/e-filter-skid.md), [`e-supply-crate.md`](meshy-assets/e-supply-crate.md) (T5) | M-5, #430 |

**Gate:** same as H-1a. The rooftop tank must match the M05 landmark (`m05_water_tank` decoration). Edda's lamp gets **Nick's review** because it is a named story beat.

### H-1c: vegetation and bank prop reference sheets (ceiling $4.00, priority 4)

Approach: about $0.18 per subject (two low explorations and one medium). Use the production-20261003 prop image as the reference where one exists.

- **Vegetation:** e-deciduous-tree, e-scrub, e-reeds.
- **Bank list:** the 19 M-7 subjects listed under M-7.

**Gate:** engineer review against the brief. A subject whose sheet is not approved drops out of M-7.

### H-2: Repeater viewmodel and pickup (ceiling $4.50, priority 1)

| Field | Detail |
|---|---|
| id | H-repeater-viewmodel |
| Brief | [`docs/plans/meshy-assets/w-repeater.md`](meshy-assets/w-repeater.md), [`docs/lore/guns.md`](../lore/guns.md), ART_STORY_BIBLE weapon consistency (2026-10-08) |
| Style references | `client/assets/weapons/viewmodels/rifle_idle.png`, `shotgun_idle.png` |
| Prompt approach | High 2k edits on one approved idle. Make idle first, then fire, cycle/spin and two reload frames as edits from that idle, so the gun stays identical. Same glove family. Reduce to 241x180 `--no-trim` on the palette canvas. Add one medium 1:1 side-profile pickup. |
| Cost | 5 x $0.41 x 2 attempts + 2 x $0.16 ≈ $4.42 |
| Consumer | wave1 #440 and wave2 #431 |
| Integration seam | `weapon_art.gd` IDLE, FIRE, CYCLE, PROFILE and reload. Flip the unsupported-Repeater assertion in `test_viewmodel.gd:177`. Holdfast pad (`maps/holdfast.rs:188`). |
| Gate | Side by side with `rifle_idle.png` at 1x and in-game scale. Palette-locked. No drift between frames. `test_viewmodel` passes. Pickup reads at `PICKUP_TEXEL_METRES`. |

### H-3: reload frames (ceiling $8.50, priority 1)

| Field | Detail |
|---|---|
| id | H-reload-frames |
| Guns | Tack, Flechette, Scatter, Rail, Sniper, Rocket (Arc already has `arc_reload.png`; the Repeater is in H-2) |
| References | Each gun's approved idle: `pistol-sprite-20261005/pistol_idle.png`, `viewmodels/rifle_idle.png`, `shotgun_idle.png`, `railgun_idle.png`, `sniper-sprite-20261005/sniper_idle.png`, `rocket_idle.png` |
| Prompt approach | High 2k edits of each idle. Two frames per gun: magazine or cell out, then seat (Scatter: shell feed; Rocket: tube slide). Use `arc_reload.png` as the precedent. |
| Cost | First pass 12 x $0.41 = $4.92. Retries only for rejected frames, up to $3.58. |
| Consumer | wave1 #440 |
| Integration seam | Generalise `weapon_art.gd` `reload_frame()` and `ReloadMotion` beyond the Arc, keyed on the accepted `ready_at`, with a reduced-motion path |
| Gate | Same identity as the idle (no redesign). Readable at 1x for 0.7 to 1.4 s. Playtest check with the #440 reporter's scenario. |

### H-4: pickup profile set (ceiling $1.60, priority 2)

| Field | Detail |
|---|---|
| ids | pickup-rocket (missing), pickup-golden-rail, pickup-tack and pickup-sniper (redraw the model-derived ones for consistency), pickup-jetpack (icon) |
| References | `specs/missing-pickups-20261016.json`; `client/assets/weapons/pickups/rifle.png`, `shotgun.png`; `client/assets/pickups/*.png` for the jetpack |
| Prompt approach | Medium 1:1 with style references and a matching side profile |
| Cost | 5 x $0.16 x 2 = $1.60 |
| Consumer | wave2 #431 (guns become map pickups); M13 Rocket pad |
| Integration seam | `weapon_art.gd` PROFILE, `weapon_pickup.gd` |
| Gate | The full pickup set reads as one family in a lineup screenshot. Each gun is identifiable at pad distance in an MP map. |

### H-5a: story stills for existing scenes (ceiling $6.30, priority 2, needs T1)

| Field | Detail |
|---|---|
| ids | still-l01_l02-key, still-opening-address, still-opening-recall (all three are referenced but missing); 21 imageless manifests (l03_l04 to l14_l15 transitions, m03 to m18 arrivals) |
| References | `client/assets/story/stills/opening/manifest.json` workflow; `client/art/characters/references/latch-stylized-v2.png` as a canonical `image_urls` reference; `docs/campaign/l*.md`; [`docs/plans/campaign-scenes.md`](campaign-scenes.md) |
| Prompt approach | Two low 16:9 composition explorations, then a medium final with references, 1.5 attempts on average. No baked-in text. Reduce to 637x360 to match `opening/annex.png`. |
| Cost | 24 x $0.26 ≈ $6.24 |
| Consumer | campaign levels 1 to 18 (playable now) |
| Integration seam | The scene JSON `image` key and the stills manifest, through `story_scene.gd` and `scene_player.gd` |
| Gate | **Nick's taste review** (series consistency and character likeness). Caption-safe area clear. Also fix the `l07_l08.json` `STORY_L05_L06_RECORDS` caption data error in the same PR. |

### H-5b: Episode V stills (ceiling $2.70, priority 3)

| Field | Detail |
|---|---|
| ids | Scene 18 "One Rhythm" and the hands extra; 19 "Even"; 20 "Water Around a Stone" and "Latch at the end of the pier"; 21 "Still Here" and the anomaly; 22 "The Last Page" and the worlds/ledger extra; optional L19 page-in |
| References | [`campaign-scenes.md:259-268`](campaign-scenes.md), [`characters.md`](../design/characters.md) "Stills first"; Latch, Tern and Edda references |
| Approach and cost | Same as H-5a: 10 x $0.27 |
| Consumer | #429 and #430 transitions and endings |
| Gate | **Nick reviews** these as the climax images. They must not depict Latch's departure as a cutscene, since that happens in play. |

### H-6: L19 and L20 surfaces (ceiling $3.00, priority 3)

| Field | Detail |
|---|---|
| ids | Three sets. Concourse: tile floor, enamel wall, platform trim, gallery rail. Waterworks: stained concrete, painted service steel, grating, wet edge. Pier and refuge: timber deck, wet concrete, bollard steel, community-painted gate. Plus the Inheritance work-strip marking. |
| References | `m13-foundry-surfaces-20261013.json`; `production-20261003` manifest; [`docs/design/earth.md`](../design/earth.md) M18-20 row; `client/assets/environment/low_water` |
| Prompt approach | Tileable albedo, low and medium, three options each |
| Cost | About 16 maps x 3 options, mixed low and medium ≈ $3 |
| Consumer | #429, #430 |
| Integration seam | `environment_textures.gd` 24-step ramps |
| Gate | Tiling seam test in Godot. Palette ramp holds. Reads as a distinct place from Low Water. |

### H-7: jetpack HUD and VFX (ceiling $1.50, priority 3)

| Field | Detail |
|---|---|
| ids | jetpack-flame-flipbook (4 to 6 frames), jetpack-gauge-frame |
| Approach | Magenta key, medium, frames edited from frame 1 |
| Consumer | #429 ("three seconds of fuel, a visible flame, a gauge") |
| Integration seam | Jetpack presenter and HUD |
| Gate | Flame reads against both the night and the concourse. The gauge matches the stamped-card HUD language (#416). |

### H-8: crowd billboards (ceiling $3.50, priority 3)

| Field | Detail |
|---|---|
| ids | About 16 static civilian poses, mixing humans and agents: sitting on crates, carrying, waiting, waterworks crew, the stretcher pair |
| References | [`meshy-assets/c-civilian-ensembles.md`](meshy-assets/c-civilian-ensembles.md), [`wipe-finale-and-mode.md:600-606`](../design/wipe-finale-and-mode.md), [`characters.md`](../design/characters.md) civilian direction |
| Approach | Medium with a style reference; reduce to billboard sprites |
| Consumer | #429 concourse, #430 pier (400 people) |
| Integration seam | Billboard group presenter (wave 4 builds it) |
| Gate | **Nick's taste review.** Variety without any recognisable real person. Groups read as a crowd at gameplay distance. |

### H-9: decals and signage (ceiling $2.50, priority 4)

| Field | Detail |
|---|---|
| ids | Changed-use Low Water decals (possessions, carried-away marks, chalk sixes), concourse wayfinding frames with blank fields, waterworks valve and hazard plates, refuge community marks, the Green 67 vote poster (number overlaid as keyed text), the harbour-screen bezel |
| References | [`meshy-assets/l-signs.md`](meshy-assets/l-signs.md); L19 "Secrets" and "Landmarks"; L20 "Turn" |
| Integration seam | Decoration ids in `map_decoration.gd` |
| Gate | No essential text baked in |

### H-10: radio station badges (ceiling $1.00, priority 5)

| Field | Detail |
|---|---|
| id | radio-badges |
| References | `client/assets/audio/radio/stations.json` (colours and taglines), `client/assets/ui/on_air.png` |
| Consumer | #442 now-playing panel (`pause_menu.gd`, `hud.gd`) |
| Gate | Legible at badge size. Replaces the "LI" and "LR" text badges. |

### H-11: Orrin and Sorrel identity sheets (ceiling $1.60, priority 5, conditional)

| Field | Detail |
|---|---|
| Briefs | [`meshy-assets/c-orrin.md`](meshy-assets/c-orrin.md), [`c-sorrel.md`](meshy-assets/c-sorrel.md), [`lore/cast.md`](../lore/cast.md), [`l11-right-of-search.md`](../campaign/l11-right-of-search.md) |
| Gate | **Nick approves the named identities.** A Meshy stage (about 80 credits) is opened only if this lands before 11-02 and there is R-M headroom. Otherwise it waits for next month's credits. |

### R-H: Higgsfield retry contingency ($1.00)

Opened only as an explicit retry batch. Because the balance is unverified, H-11, H-10 and H-9 absorb any shortfall in that order.

---

## Meshy batches (1,840 of 1,855 usable)

All use `fragr-spritegen meshy-gen` against the single ledger `art/raw/meshy-pilot-20261003/ledger.jsonl`. Common rules:

- Stage IDs follow `<subject>-20261023-v<n>`.
- Image-to-3D only, and only from a reference sheet approved in H-1.
- Textured output.
- Each batch is sized to 250 credits or less, so it runs even without T2.

**Gate for every Meshy candidate:**

1. Import the GLB into Godot, check face count and look for holes.
2. Check scale against the server solids or rig volume.
3. Check the silhouette at gameplay distance in the target map lighting.
4. Do the host match (`ship_furnishings.gd` pattern, `tools/prepare_world_prop_sources.gd` and `verify_world_prop_sources.gd`).
5. Do played acceptance.

Candidates stay offline under `.gdignore` until that is done.

### M-1: Inheritance enemies (ceiling 215, priority 1)

| id | Brief / reference | Approach | Cost | Consumer | Integration seam |
|---|---|---|---|---|---|
| M-paver | [`c-paver.md`](meshy-assets/c-paver.md) + ref-paver | 7.1, 2k geometry, 2 candidates, no rig | 70 | #429 L19, #430 L20 | New EnemyKind (wave 3). Static hull with a locally authored work-head pivot and strip origin. AssessorRig-style live rig through `enemy_view.gd`, or a directional atlas bake (`client/art/characters/*_bake.gd`). The strip is a local shader. |
| M-surveyor | [`c-surveyor.md`](meshy-assets/c-surveyor.md) + ref-surveyor | 7.1 2k, 2 candidates | 70 | #430 | Hull GLB with a local lens iris and mark-disc origin; the mark disc is a local shader |
| M-collector | [`c-collector.md`](meshy-assets/c-collector.md) + ref-collector | 7.1 2k, 2 candidates, plus a 5-credit rig only if the inspected candidate is a clean biped | 75 | #429, #430, M18 back-fill | Atlas bake if biped (`*_source.gd` adapter, 8 directions at 160 px), otherwise a live rig |

**Gate:** as above. Also check the tell is readable (work head, lens, tool), that the design stays muted (bone, ink, muted cyan), and that it does not read as a Union unit. **Nick's taste pick** between candidates.

### M-2: equipment (ceiling 140, priority 1 to 2)

| id | Brief / reference | Approach | Cost | Consumer | Integration seam |
|---|---|---|---|---|---|
| M-jetpack | [`e-jetpack.md`](meshy-assets/e-jetpack.md) + ref-jetpack | One `meshy-t2` Smart Topology attempt (15) if the hard-surface parts separate cleanly in the sheet, then one 7.1 2k candidate (35). The 70 ceiling covers two 7.1 attempts. | 50 to 70 | #429 lesson, #430 crane secret | Back-socket attachment, nozzle flame origin (H-7), rack and pickup prop |
| M-sentry | [`e-portable-sentry.md`](meshy-assets/e-portable-sentry.md) + ref-sentry | 7.1 2k, 2 candidates; packed, broken and allied variants come from the same source | 70 | #430, Wipe mode | Sentry presenter (gameplay is unbuilt) |

### M-3a: primitive rigs visible now, part 1 (ceiling 140, priority 2)

| id | Brief / reference | Approach | Cost | Consumer | Integration seam |
|---|---|---|---|---|---|
| M-assessor-hull | [`c-assessor.md`](meshy-assets/c-assessor.md) + ref-assessor-hull | 7.1 2k, 2 candidates, hull only | 70 | Campaign M12 (playable) | Replace the Hull and plates in `assessor_rig.gd`. Fans, optics, launcher and the hit material stay local. |
| M-motorcycle | [`e-motorcycle.md`](meshy-assets/e-motorcycle.md) + ref-motorcycle | 7.1 2k, 2 candidates (the 10-06 raw was lost) | 70 | Campaign M16 | `jeep_view.gd` MODELS: a `.tscn` with wheel pivots like `jeep.json`, replacing `_build_motorcycle` |

### M-3b: Continuance Walker parts (ceiling 105, priority 2)

| id | Brief / reference | Approach | Cost | Consumer | Integration seam |
|---|---|---|---|---|---|
| M-walker-hull, M-walker-leg, M-walker-artillery | [`c-continuance-walker.md`](meshy-assets/c-continuance-walker.md) + the three ref sheets | 7.1 2k, 1 candidate each. The leg is mirrored and reused. Retries come from R-M. | 105 | Campaign M14 boss | `walker_view.gd` existing joints. Must match the five body solids in `sim/walker.rs`. |

### M-4: L19 props (ceiling 245, priority 2)

All use 7.1 standard, one candidate each.

| id | Brief | Cost | Consumer and seam |
|---|---|---|---|
| M-rooftop-tank | [`e-rooftop-tank.md`](meshy-assets/e-rooftop-tank.md) | 30 | #429 Latch landmark matched to M05; epilogue. Host match on the roof solids. |
| M-turnstile | [`e-turnstile.md`](meshy-assets/e-turnstile.md) | 30 | #429 concourse Collector gates; blocking solid |
| M-tram-motor | [`e-tram-motor.md`](meshy-assets/e-tram-motor.md) | 30 | #429 |
| M-civilian-tram | [`e-civilian-tram.md`](meshy-assets/e-civilian-tram.md) | 35 (2k) | #429, epilogue; reuse in M05, M16, M18; `m05_tram.gd` |
| M-duffel | [`e-duffel.md`](meshy-assets/e-duffel.md) | 30 | #429 abandoned possessions |
| M-hard-luggage | [`e-hard-luggage.md`](meshy-assets/e-hard-luggage.md) | 30 | #429 |
| M-meal-stove | [`e-meal-stove.md`](meshy-assets/e-meal-stove.md) | 30 | #429 meal table (matches `m04_meal_six`) |
| M-stretcher | [`e-stretcher.md`](meshy-assets/e-stretcher.md) (T5) | 30 | #429 clinic post |

### M-5: L20 props (ceiling 185, priority 2)

| id | Brief | Cost | Consumer and seam |
|---|---|---|---|
| M-pier-crane-cab | [`e-pier-crane.md`](meshy-assets/e-pier-crane.md) | 35 (2k) | #430 jetpack-reached cab; blocking solids |
| M-edda-lamp | [`e-edda-lamp.md`](meshy-assets/e-edda-lamp.md) | 30 | #430 lit-lamp story beat; light origin. **Nick review.** |
| M-sluice-actuator | [`e-sluice-actuator.md`](meshy-assets/e-sluice-actuator.md) | 30 | #430 Surveyor sluice lesson |
| M-valve-manifold | [`e-valve-manifold.md`](meshy-assets/e-valve-manifold.md) | 30 | #430 valve house |
| M-filter-skid | [`e-filter-skid.md`](meshy-assets/e-filter-skid.md) | 30 | #430 waterworks |
| M-supply-crate | [`e-supply-crate.md`](meshy-assets/e-supply-crate.md) (T5) | 30 | #430 pier and yard |

### M-6: Earth vegetation (ceiling 90, priority 4)

| Field | Detail |
|---|---|
| ids | M-deciduous-tree, M-scrub, M-reeds ([`e-deciduous-tree.md`](meshy-assets/e-deciduous-tree.md), [`e-scrub.md`](meshy-assets/e-scrub.md), [`e-reeds.md`](meshy-assets/e-reeds.md)); 7.1 standard, 30 each |
| Consumer | L19 and L20 Earth exteriors and epilogue boundaries |
| Gate | Geometry noise and face count acceptable at distance. Otherwise fall back to billboards baked from the GLB, which still uses the source. |

### M-7: current-campaign bank (ceiling = real remainder, planned 570, priority 5)

This batch is opened last, after M-1 to M-6 and every open retry have been reconciled. Its size is: live usable minus R-M still needed. One candidate per subject at 30 credits, in this order. The list is cut where the credits end.

| Order | Subjects | Level |
|---|---|---|
| 1 to 4 | e-casting-furnace, e-ingot-trolley, e-industrial-press, e-lathe | M13 foundry, next to the accepted ladle |
| 5 | e-growth-rack | M12 |
| 6 to 8 | e-ship-bunk, e-galley, e-pilot-console | M10 |
| 9 to 12 | e-luggage-scanner, e-registration-console, e-impound-tug, e-lunar-loader | M06; production-20261003 refs exist for the scanner and loader |
| 13 to 15 | e-locomotive, e-recall-car, e-gantry-hoist | M03 |
| 16 | e-broadcast-console | M15 |
| 17 to 18 | e-restraint-frame, e-correction-machine | M02 |
| 19 | e-custody-housing | M08 |
| Spill-over if credits remain | e-transformer, e-recycler, e-robot-parts | |

**Rules for the bank:**

- **Visible-integration rule:** before submitting a subject, name its target map and presenter (decoration id or `ship_furnishings` slot). A subject with no named slot is dropped.
- **Run size:** 250 credits per run unless T2 has landed (M-7a, M-7b, M-7c).
- **Gate:** as for every Meshy candidate. Integration happens later, per level, each subject under its own host-match and played gate.

### R-M: Meshy retry pool (150, from 11-01)

- Used for the second attempt on any rejected M-1 to M-5 candidate, in that priority order.
- Opened as an explicit retry batch.
- Whatever is unused by 11-02 12:00 UTC is released to M-7.

---

## ElevenLabs batches (~501k of 1,158,814)

All use `fragr-audiogen batch --dry-run`, then `--max-credits` equal to the dry-run total, with `quota` before and after.

- Gunshots and impacts use `pcm_48000`. Loops use `--loop`.
- Output goes to `.agents/asset-round-20261023/audio/<batch>/`.

**Audio gate for every cue:**

1. Measure for clipping, DC offset and leading or trailing silence. The 10-13 lesson: raw files peak at full scale, so normalise to the loudness ladder in [`sound-pass-20261002.md`](sound-pass-20261002.md) (about -12 K50, at or below -1 dBTP).
2. Listen.
3. Hear it in-engine against combat.
4. Commit with provenance (the 2026-10-23 rights decision): keep the `audiogen-manifest.json` entry and batch spec.

### Speech (not rights-blocked)

| Batch / id | What | Voice / brief | Ceiling | Priority | Consumer and seam | Gate |
|---|---|---|---|---|---|---|
| E-1 host-casting | 10 representative barks (FIRST BLOOD, TRIPLE FRAG, QUAD FRAG, RAMPAGE, FLAG CAPTURED, CHARGE PLANTED, SUDDEN DEATH, LAST ONE STANDING, MATCH POINT, FIGHT) x 4 voices x 2 takes, `eleven_v3` with tags such as `[shouting]` and `[deadpan]` | Bill `pqHf…` (radio Host continuity), Daniel `onwK…`, Brian `nPcz…`, Callum `N2lV…`; [`docs/lore/voice.md`](../lore/voice.md) (capitals, short, never explains) | 2,500 | 1 | #431 Pillar 1 | **Nick picks the voice.** Premade voices retire at the end of 2026, so lock the choice now. |
| E-2 host-barks | About 70 name-free lines x 4 takes in the chosen voice. The voiced (big) Host reaction kinds, 3 variants each: first blood, triple frag, quad frag, frag storm, rampage, riot, untouchable, streak ended, last standing, comeback, flag captured, charge planted, match point, sudden death; then Conquest under-25, 3-2-1-FIGHT, one minute, won/lost, MVP, warmup, mutator intros. Captions only, never voiced: double frag, lead change, flag taken, golden rail. | `HOST_REACTION_*` in `match.en.po`, server `HOST:` strings, [`multiplayer-excellence-20261017.md`](multiplayer-excellence-20261017.md) Pillars 1 and 7; captions keep `{player}`/`{team}` and the audio is the name-free cut; frozen strings respected | 10,000 | 1 | #431; `client/assets/audio/host/<kind>_<variant>.mp3` (`host_voice.gd`, wire kind ids); Announcer bus; radio ducks through `HostVoice.spoke` | Listening; 2 kept variants per line; no stacking at match pace |
| E-9 narration-backlog | Seven missing files (opening x5, l01_l02 ledger and shift) plus unvoiced m03, m07 to m18 arrivals and l07_l08 to l14_l15. About 8k characters x 3 takes. | River `SAz9…`; [`campaign-transition-audio.md`](campaign-transition-audio.md) (exact caption text, `{locale}` paths) | 24,000 | 2 | `client/assets/story/voice/en/`; scene JSON narration; `test_campaign_audio` | Matches the existing River takes in tone and level |
| E-10 narration-ep5 | Scenes 18 to 22 and the L19 page-in, about 4k characters x 3 takes | River; [`campaign-scenes.md`](campaign-scenes.md), `specs/campaign-transitions-20260930.json` | 12,000 | 3 | #429, #430 | **Nick listens** (emotional peak). The harbour message stays text first. |
| E-11 character-casting | Latch, Tern and Clerk auditions: 6 voices x about 12 lines x 2 takes ("Nobody's filing anymore.", "Held them. We're even.", "It's very polite. I hate it.", the Clerk form line, and others) | [`characters.md`](../design/characters.md) (Latch relaxed, dry and self-directed; not a battle-unit voice; no real-person imitation) | 6,000 | 3 | Optional voice for #429 and #430 | **Nick approves the casting.** Audition only; nothing is integrated. |
| E-16 radio-news-wave2 | `specs/radio-news-scripts-wave2.json`: 14 clips, 5,643 characters x 2 | Check the lore review status in voice.md first | 12,000 | 4 | Radio news station via `radio.gd` manifest; #442 | Lore check; listening |

### Weapon, UI and mode SFX (commit with provenance after the audio gate)

| Batch / id | What | Ceiling | Priority | Consumer and seam | Notes |
|---|---|---|---|---|---|
| E-3 reload | 16 cues: start and done for Tack (0.8 s), Rocket (0.8), Flechette (1.1), Repeater (1.1), Arc (1.1), Scatter (0.7), Rail (1.4), Sniper (1.4). Start is mag out or breach open; done is seat and charge. Scatter shell feed, Rail and Sniper cell seat with capacitor whine, Arc cell clunk, Rocket tube slide. 6 takes each. | 4,000 | 1 | #440; `client/assets/audio/reload/<gun>_{start,done}.wav`; cued on accepted reload start and complete, cancelled on swap or death through the `fire_feedback` cancellation seam | Dry and quieter than gunshots, but must read through combat |
| E-4 repeater-rocket | Repeater fire, spin-up, spin-down and hit; Rocket launch and blast re-takes; Sniper and Rocket hit. 7 cues x 6 takes, `pcm_48000`, explicit headroom request. | 3,500 | 1 | `player_pawn.gd:204` `fire_streams`; `hit_%s.wav`; flip `test_combat_audio.gd:181` | The 10-13 rejection reasons (clipping, DC offset) are the gate |
| E-5 ui | 11 cues x 6: focus tick, confirm, back, toggle on and off, slider step, denied, panel open and close, match found, station-change static, tune-in | 3,000 | 2 | wave1 menus (#435, #436): `boot_menu.gd`, `pause_menu.gd`, `local_host.gd`, `settings_panel.gd`; shared helper in `menu_theme.gd`; UI volume; #442 | Seal-cut stamped-card language (#416): paper stamp, relay click. Must not be fatiguing. |
| E-6 pickups | 9 per-weapon pickup stingers (Tack, Flechette, Repeater, Scatter, Rail, Sniper, Arc, Rocket, Shiv), pad respawn shimmer, Golden Rail spawn sting. 11 x 6. | 3,000 | 2 | #431; `game_manager.gd` pickup handler (respawn needs a wire fact) | [`weapon-pickups.md`](weapon-pickups.md), [`weapon-economy.md`](weapon-economy.md) |
| E-7 modes | CTF taken, dropped, returned and captured; Sabotage `beep`, `hum` loop, `arm`, `planted`, `defused`, `detonation`; Conquest siren and heartbeat loop; sudden death sting; win, loss and draw stingers. 15 x 6 (loops 10 s). | 9,000 | 2 | Sabotage drops into `client/assets/audio/sabotage/<name>.wav` with no code change (`sabotage_audio.gd:8`); `conquest_hud.gd`; `hud.set_ctf_state` | Pillars 6 and 7 |
| E-8 movement | Single-step footsteps on concrete, metal, grate and water (4 variants each), jump, light and heavy landing, rocket-jump whoosh. About 22 x 4. | 4,000 | 3 | #431, #432; `player_body.gd` (surface lookup is wave 2 work) | Single-step requests only; sequence requests returned 1 or 2 steps |

### Episode V SFX and ambience (commit with provenance after the audio gate)

| Batch / id | What | Ceiling | Priority | Consumer and seam |
|---|---|---|---|---|
| E-12 inheritance | Paver: prep rise, strip hum loop, work grind, cancel, destroyed. Surveyor: lens open, mark lock, convergence ping, exposed, shutdown. Collector: approach, commit, work, exposed, disable. 15 cues x 6. | 11,000 | 1 | #429, #430, M18 Collector; per-enemy folders, `<kind>/tell.wav` (`player_pawn.gd:104`). Tells must be timed to the windup and captioned ([`wipe-finale-and-mode.md:272`](../design/wipe-finale-and-mode.md)). |
| E-13 jetpack-sentry-world | Jetpack ignite, 4 s thrust loop, fuel-low, sputter, landing. Sentry deploy, traverse, fire, dry. Sluice gate, pump thud loop, crane winch, refuge gate, harbour display chime, reprieve (machines stopping), strip close. About 18 x 5. | 12,000 | 2 | #429, #430; `m20_mission_state.gd` cues |
| E-14 ambience | 30 s seamless loops x 3 takes: evacuation concourse, Low Water dark night with distant machines, waterworks pump hall, sluice and catwalk water, pier crowd of 400 with water lapping, post-reprieve hush, strip-hum field. Low Water also reuses `low_water_runoff.wav`. | 30,000 | 2 | `client/assets/story/ambience`; #429, #430 |

### Music (commit with provenance after Nick's taste review)

| Batch / id | What | Ceiling | Priority | Consumer and seam | Gate |
|---|---|---|---|---|---|
| E-15 score | Instrumental, 2 to 3 minutes, 3 takes each, about 15 cues: main menu theme loop; one story bed each for episodes I to V (scene `music` field, `test_story_scene.gd:20`); Episode V cues (L19 dark night, roof loop, trench climax, L20 hold in three escalating layers, last six minutes, reprieve, Still Here theme); epilogue and credits; wipe-failure cue; workshop motif | 125,000 | 3 | `boot_menu.gd` stream player; scene JSON `music`; #442 playback; #430 epilogue | **Nick's taste review.** Rights gate. Loop points checked. |
| E-17 radio refresh | About 6 new tracks per station in `stations.json`, 3 minutes each, 1.5 takes on average, following the existing station briefs and the `specs/workshop-music-20261013.json` pattern | 200,000 | 5 | `radio.gd` manifest discovery; #442 now-playing | Rights gate ([`radio-refresh.md:89-96`](radio-refresh.md)); listening; station identity holds |
| R-E | Retry contingency | 30,000 | | Explicit retry batch only | |
| E-18 (optional) | Extension of E-17 or E-15, decided 11-03 from keep rates | ≤ live remaining − 50,000 | | | Opened only if the keep rate justifies it |

---

## What needs Nick

1. ~~**Rights basis** for ElevenLabs SFX and music~~: decided 2026-10-23, commit with provenance.
2. **Enemy reference sheets:** Paver, Surveyor and Collector (H-1a). These block M-1, so the turnaround is about 24 h.
3. **Host announcer voice** from E-1.
4. **Taste picks:**
   - story stills (H-5a, H-5b)
   - crowd poses (H-8)
   - Edda's lamp
   - enemy model candidates
   - music (E-15, E-17)
5. **Latch, Tern and Clerk casting** (E-11). **Orrin and Sorrel identity** (H-11).
6. ~~**The ElevenLabs drift**~~: resolved 2026-10-23. The 1,333 credits used from 10-17 to 10-23 with no local manifest were Nick's own use. Noted, not held.

## Free wins to do alongside ($0)

- Place the already-prepared air scrubber, water pump and community radio from `client/art/world-props/candidates/` through the `ship_furnishings.gd` pattern.
- Reuse for L19 and L20:
  - the Low Water kit (`m04_*`, `m05_*` presenters and decorations, `low_water_*` and `water_*` surfaces, the `arena_water` shader)
  - yard surfaces
  - the cast models
  - the Union atlases for absorbed bots
  - the Assessor's local rig
  - epilogue voice-over 01 to 10
