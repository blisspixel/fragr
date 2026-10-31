# Build round, 2026-10-27

Goal: carry the roadmap's remaining Episode V rung and the open #431, #432 and #434 scope forward in waves. Each wave lands as one reviewed PR from an integration branch and returns to one green `main`. Lanes push temporary `waveNN/<lane>` branches, never open their own PRs, and are deleted when absorbed.

Non-goals: new modes, new services, transport rewrites, cloud apply, save migrations. Spend stays inside the asset-credit authorization in `AGENTS.md`.

## Nick's decisions (2026-10-27)

- Larak Lot Rocket supply (#432): weapons drop on death. A fragged fighter's held gun becomes a short-lived pickup. A second launcher pad was not chosen.
- Host announcer (#431): Callum records the voiced Host calls now, before the ElevenLabs reset on 2026-11-06. A later recast re-records the same slots.
- Meshy credits (reset 2026-11-03): final Inheritance Paver and Surveyor models for Levels 19 and 20, replacing the placeholders.
- Waves of three or four lanes.
- Episode V evidence: agent-led acceptance and independent agent review are the default; no human reviewer is required to proceed. Platform, device and human gaps are recorded, not simulated.

## Wave 11 (shipped, #490)

| Lane | Scope | Owner doc |
|---|---|---|
| `m19-market` | Finish the #487 market diagnosis (the overlapping-strip case) without buffs; then, if the boundary is trustworthy, extend the earned M19 survey to the next authored objective toward the water tanks | [L19 brief](../campaign/l19-planned-works.md), [harness guide](../../tools/playtest/README.md) |
| `carry-bridge` | Join #483's earned M01 departure and disk-save retry to a bounded M02 window under the constrained policy | [harness guide](../../tools/playtest/README.md) |
| `inheritance-models` | Lore-gated Meshy Paver and Surveyor, integrated and inspected in Levels 19 and 20 | [asset practices](asset-practices/README.md) |
| `mp-rules` | Weapons drop on death with a measured Rocket share, Duel queue and winner-stays, host presets and mutator stacking, the Conquest ticket bleed | [multiplayer excellence](multiplayer-excellence-20261017.md), [bot and enemy AI](bot-and-enemy-ai-excellence-20261017.md) |

## Wave 12 (shipped, #495)

Host voice (Callum), the hit confirm and the Scatter pass; Rocket use, CTF pads and side calls for rule bots; campaign guard sighting, squad roles and barks; the #434 stage 1 baseline with stage 3 measured and deferred. The main hotfix #496 rests dropped guns where a body can stand (roster stall on map 6). Follow-ups: #489, #491, #492, #493, #494, #497.

## Wave 13 (shipped in its wave PR)

Four lanes, each finishing inside the wave:

| Lane | Scope | Owning docs |
|---|---|---|
| `m01-trace` | Trace and fix the deliberate Standard/Severe regression and M14 seed 1015 (#493); diagnose the seed 44 strand (#497) | [m01](../campaign/m01-recall-notice.md), [harness guide](../../tools/playtest/README.md) |
| `net-close` | Close slow readers on a measured bound (#492), then #434 stage 4 (acknowledged deltas, compact encoding) as far as it measures | [BENCHMARK.md](../BENCHMARK.md), [UDP and hosting plan](dedicated-server-udp-and-hosting.md) |
| `harness-trust` | The map 4 Sector 9 roster pocket (#491), the portability timing flakes (#494), a per-attempt retry seed (#489) | [harness guide](../../tools/playtest/README.md) |
| `l02-dress` | Persons Unknown (Level 2) raised to the golden-slice bar in rendered passes | [m02](../campaign/m02-persons-unknown.md), [art bible](../ART_STORY_BIBLE.md) |

The coordinator lands #498 (CLAUDE.md imports AGENTS.md). Independent review added a guaranteed turn for an out-of-view guard and a 30 s load grace before the read-behind close. Lane evidence is in `.agents/lane-evidence-20261028/`.

## Wave 14 (shipped in its wave PR)

| Lane | Result |
|---|---|
| `l03-dress` | Scheduled Service dressed as a working rail yard; fallen mast and route tour fixed |
| `l04-dress` | Notice to Vacate dressed as a late-afternoon Low Water town; vote sign timing and the shutter wipe fixed |
| `l06-dress` | Port of Entry dressed; cargo moved off Union black and red |
| `lag-comp` | #434 stage 5: bounded hitscan rewind, 200 ms, gameplay 62 |
| `polish` | Perimeter Talk station name, Level 2's dark rooms, Level 2 sign audit (one sign) |

Independent review kept seated riders with their vehicle and corrected the cover and rewind wording. The campaign briefs are renamed by level number.

## Wave 15 (shipped in its wave PR)

| Lane | Result |
|---|---|
| `l05-dress` | No Forwarding Address dressed in Level 4's district vocabulary; the Heavy Sweeper reads black and red in daylight |
| `l07-dress` | Declared Goods dressed as a lived town; the off-white blocks and the Union-livery props are gone |
| `radio-voice` | "Frequency" removed from spoken audio and song titles (3,912 credits, ledger W15-RV) |
| `net-finish` | Roster positions in deltas, per-reader deltas, a text-level encoder (gameplay 63), rewind counters on `/status`, #502 root cause |

## Wave 16 (shipped in its wave PR)

| Lane | Result |
|---|---|
| `l08-dress` | Custodian of Record dressed as a green-enamel archive; the noise screen visible again; eight signs |
| `l09-dress` | Passenger Manifest dressed; Tern's ship reads in its cradle; the Enforcer reads black and red |
| `l10-dress` | Common Carrier's three decks distinct; the off-white walls and floor stripes gone |
| `combat-checks` | Turret and Heavy tells stay red, absorbed swell stays cyan; Level 6 and Level 19 captured |
| `net-motion` | Wire-only quantized motion (6 to 12% less per client), a loopback link shaper, rewind under jitter |

## Wave 17 (implemented)

Level 10's Repeater from finite acquisition through visible, audible play;
Levels 11, 12 and 13 dressed with lore and design continuity, route clarity
and enemy contrast reviewed in the renderer. The Assessor now reads black/red
and mine instructions show active bindings. Stale briefs and the roadmap are
reconciled. Native and rendered authoring evidence remains distinct from human
acceptance; spin cycle cues and Level 13's primitive geometry remain open.

Character production depends on live credits and unresolved choices. Level 9's
ship geometry and two-machine networking evidence remain bounded follow-ups.
The [roadmap](../ROADMAP.md#next-steps) owns the current sequence and Nick's
separate review round.

## Wave 18 (implemented)

Nick's calls on 2026-10-30: Level 17 instead of Compliance Yard ("do what makes
sense and is fun"); a Blood setting, On by default; an optional ambient
campaign score, with A and B takes he picks while playtesting rather than any
automatic choice; wait for the Meshy refresh on 2026-11-03 (usable balance was
zero under a retained hold); keep every multiplayer map and build each out
before any cut.

| Lane | Result |
|---|---|
| `m09-layout` | Arrival aisle under the office piers, outer gantry and hull-side lane, bow crossing |
| `m13-foundry` | Maintenance loop, closed roof, machine collision, amber process light; the server fire-press latch |
| `l17-gallery` | Raised command galleries, two stairs, the service stair, Union palette and dressing |
| `characters` | Splice, Tern, Renn and Level 8's held people in their own colours, offline recolours |
| `presentation` | Blood setting, wall-aware death camera, Screen Flashes reaching the HUD |
| `score` | 21 ambient beds and 6 story cues, A and B each, 109,308 ElevenLabs credits of a 140,000 ceiling |

The coordinator fixed the tour's Rail route (#506) and ran a read-only story
audit (2 blockers, 12 confusing, 27 minor; 6 designed feelings delivered, 7
partial, 2 on paper only), which feeds wave 19's story lane. The
[roadmap](../ROADMAP.md#next-steps) owns what remains.

## Wave 19 (implemented)

Nick's calls on 2026-10-30: build every multiplayer map out and bug-hunt it
before any cut, with hosts switching maps in or out of rotation; make the
campaign's designed feelings land in play.

| Lane | Result |
|---|---|
| `between-match` (#509) | Podium nemesis and rivals, a three-map vote, per-map rotation switches |
| `team-seat` (#510) | Teammate seat after death, clutch stamp, Sabotage resupply ladder |
| `map-hunt` (#511) | Every map in every mode surveyed; a walked route to every pad |
| `yard-water` (#512) | Compliance Yard and Low Water rebuilt, lit and dressed; Low Water spawn table |
| `story` (#513) | The Level 18 turn in play; people introduced before they matter; pages and timeline |

The coordinator kept one survey implementation where two lanes built the same
lead-change counter, reconciled both lanes' wire bump to one gameplay 64, and
fixed the radio playing through the Level 18 turn. Follow-up: #520.

## Verification

Each wave PR carries the AGENTS.md verification list run on the final tree, inspected captures for anything a player sees, and exact-head and exact-main CI. Headless checks, inspected visuals, measurements, fresh-player acceptance and installed releases stay distinct.
