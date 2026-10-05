# Full-game model and asset plan

Status: in flight, 2026-10-04. This is the asset catalog beneath the roadmap's existing art-excellence and campaign/multiplayer rungs. It does not create a second global build order. Nick requested the complete model backlog, individual lore/reference briefs, bounded use of existing credits and concurrent gameplay development.

## Scope and counting

The catalog has **190 individual asset and construction-kit briefs**: 35 cast/role briefs, 33 weapon/equipment briefs, 79 world/vehicle/multiplayer source choices and 43 local construction/detail briefs. Count source families once; faction paint, wear, poses, opened/damaged states, icons and repeated placements reuse them. A kit can produce many runtime pieces. These are not 190 completed models.

| Route | Briefs | Meaning |
|---|---:|---|
| Potential new core sources | 68 | 10 cast/enemy families, 8 guns and 50 campaign world/vehicle sources; each still needs reference and quality review |
| Conditional/later sources | 31 | 3 fallback cast bases, 14 local-first world choices and 14 later multiplayer choices |
| Retained paid sources | 7 | Clerk, Sweeper, Auditor, free human, Latch, Shotgun candidate and yard generator candidate |
| Local/derived | 84 | 17 cast variants/retained mechanical roles, 24 equipment briefs and 43 construction/detail briefs |

Selected Clerk/Sweeper/Auditor atlases, the free-human strip and live Latch are distinct from older library exports. The parked Shotgun and generator need actual refinement and selection. The [147-image source library](../../client/art/production-20261003/README.md) supplies 28 prop designs, 14 character designs, 14 weapon designs/finishes and venue references; images are not finished models. The full M02 and Auditor route gates remain open.

The [Wipe design](wipe-survival.md) adds a larger M20 mobile survival stand, placeable automatic sentries and shared multiplayer systems. M18's unresolved Union fighting is interrupted by the unexpected takeover; M19 carries the escalating escape. Threat pressure is continuous, without announced shopping breaks or an outbreak forecast. Its one additional model family is E-portable-sentry; jeep, motorcycle, jetpack, restoration machines and waterworks are already counted. Locally isolated resistance equipment requires an explicit control boundary, not merely different paint. This is planned gameplay, not implemented waves, vehicles or deployments.

## House style and reference contract

Read the [art bible](../ART_STORY_BIBLE.md), [palette](../palette.json), [lore index](../lore/README.md), [character continuity](../design/characters.md), [Earth](../design/earth.md), [Moon](../design/moon.md), [ships](../design/space.md), [Mars](../design/mars.md) and [map design](../MAP-DESIGN.md). Keep practical circa-2070 retro-futurism, physical controls, inhabited places and restrained advanced machinery. Angular painted faces, broad material values and coherent pixel clusters carry the modern boomer-shooter direction. Photographic pores, fabric weave and uniformly noisy wear are unsuitable.

Union black/red belongs chiefly to issued outfits and equipment, with original institutional marks. Civilian communities keep warm individual repairs and possessions. Lunar pressure shells, Martian lifelines, occupied ships and tropical multiplayer sites retain their own materials/light. Flesh or metal never assigns allegiance or consciousness. Latch retains a lean civilian body, taller-than-wide CRT, one anatomical-left antenna and voluntary gestures. The Inheritance has no default humanoid avatar; the wipe does not turn free agents into a machine army.

Each linked brief freezes use, lore owner, reference basis, silhouette, materials, independent parts/motion, integration, quality gate and credit route. An existing concept is not an approved model sheet. Create and review missing object-specific references before generation; record exact reference/source hashes. For guns and props, use isolated conversion input rather than a scene containing several copies or baked text. New named identities remain proposed until their reference is reviewed.

## Credits and allowance

The latest production reconciliation on 2026-10-04 reports **2,375 API
credits**, **15 uncertain credits held**, and **2,360 usable**. Enforcer,
Crawler, Pistol, Rifle, the bounded civilian revision and the corrected Jammer
candidate, followed by the first Railgun and Sniper Rifle sources and three
inhabited-world props, consumed 370 included credits inside the first
900-credit allocation, leaving 530 within that ceiling. Total tracked consumption
is 695 credits.
The Jammer task `01a10891-f9a6-76b4-9ba1-85f035260e77` consumed 35 credits
for a textured 7.1 Ultra candidate; mechanical and played acceptance remain
open. No humanoid rig was requested for its four-foot/four-petal machinery.
The [precision weapon receipt](../evidence/precision-weapon-references-20261004.md)
records two serialized 35-credit source stages, eight inspected raw views and
the subsequent account reconciliation. The
[Sniper refinement](../evidence/sniper-source-refinement-20261004.md) selects
prepared held, firing and pickup art after source and ordinary played
comparison checks; final combined CI and packages remain pending. The Railgun
source remains parked, with preparation and played acceptance open.
These receipts do not establish finished game coverage. The
[production receipt](../evidence/asset-production-20261004.md) records actual
operations, inspection and remaining acceptance; the later
[civilian revision receipt](../evidence/free-human-civilian-20261004.md) records
its additional 40 credits and its dated balance. The [world-prop receipt](../evidence/world-prop-sources-20261004.md)
records the scrubber, pump and radio, their twelve raw views and 105 actual
credits. No pack is needed for the remaining two first candidates in this
allocation: non-Latch free agent and repair workbench.

The planning baseline before this production batch on 2026-10-04 was
**2,745 API credits**, with the retained **15-credit uncertain hold**, leaving
**2,730**. The catalog planning pass itself submitted zero generation requests.
Its original 325 tracked consumed credits and the separate historical
30-credit account decrease remain dated ledger facts. Use the later production
receipt above for the live allowance; the following scenarios retain their
original baseline rather than counting newly completed source tasks twice.

[Official API prices](https://docs.meshy.ai/en/api/pricing), checked 2026-10-04: textured 7.1 standard 2K/4K costs 30 credits, or 35 with Ultra geometry; textured Smart Topology costs 15. A suitable humanoid rig costs 5 and optional animations cost 3 per action. Pin the exact model/options; no obsolete lowpoly path. [Rigging](https://docs.meshy.ai/en/api/rigging) is designed for clear humanoid bipeds, not crawlers, fans, weapons or vehicles.

| Scenario | Source assumption | Rigs | Revision reserve | Optional motion reserve | Total planning credits |
|---|---|---:|---:|---:|---:|
| Core, conservative | 68 x 35 = 2,380 | Up to 6 x 5 = 30 | 30 percent of model requests = 714 | 24 actions x 3 = 72 | **3,196** |
| Core, mixed route to verify | 46 suitable hard-surface sources x 15 + 22 x 35 = 1,460 | 30 | 30 percent = 438 | 72 | **2,000** |
| Extended ceiling | All 99 potential new sources x 35 = 3,465 | Up to 9 x 5 = 45 | 50 percent of model requests, rounded up = 1,733 | 72 | **5,315** |

These are planning scenarios, not quotes for accepted finished assets. Smart Topology is appropriate only when the actual result meets the same silhouette, articulation, texture and played quality gates. No source is replaced simply to consume credits. Revisions are reserved, not automatically submitted. If each source needs a complete second candidate, the request cost rises accordingly. References, retopology, rig repair, local poses, collision, packaging and gameplay still need work; credit counts do not estimate completion time.

The planning baseline covered the important first batch and may cover the
whole core catalog on a successful mixed route. It did not guarantee the
conservative core plus revisions or the extended future fleet. Relative to
the original 2,730 usable baseline, those scenarios were 466 and 2,585 short.
Reconcile real source results and remaining work before recommending a pack.

[Monthly credit reset](https://help.meshy.ai/en/articles/9991991-when-will-my-credits-reset) says Premium resets its monthly allowance to 3,000 on the subscription date, without rollover. The [API price page](https://docs.meshy.ai/en/api/pricing) describes prepaid API credits; the current balance endpoint does not report the account's monthly/permanent split or renewal date. Confirm the account's actual API replenishment before scheduling future paid work. Purchased permanent credits and any pack price must be verified in the account. This plan enables no renewal, cash purchase, automatic top-up or overage.

Use only the existing native tools/spritegen path and one account ledger under art/raw/meshy-pilot-20261003. Serialize paid stages; parallel agents can prepare refs, levels and local assets but cannot maintain independent account ledgers. Run a free balance/hold preflight immediately before each stage. Keep both credit and dollar ceilings, the existing 5-dollar per-run ceiling, durable task IDs and uncertain reservations. The tool's conservative dollar equivalent is accounting, not an extra cash charge or a pack quote. Report actual consumed_credits and inspect the source before rigging or extra paid processing.

## First bounded production allocation

Allocate **at most 900 existing credits**, including justified revisions and suitable rigs, to twelve current-game/near-term sources: Crawler, Jammer, non-Latch free agent, Enforcer, Pistol, Rifle, Railgun, Sniper Rifle, repair workbench, community radio, water pump and air scrubber. At all-7.1 prices, twelve first candidates cost 420 and up to two suitable humanoid rigs cost 10. At most one full additional candidate per source plus repeated suitable rigs would total 860; remaining allowance is contingency, not a target to exhaust. Each operation is separately capped below the native per-run ceiling.

Reuse and refine the parked Shotgun and generator alongside those candidates. Derive Heavy/Ranged from the accepted Sweeper family, retaining meaningful geometry/gait differences. Preserve selected presentation until replacements pass. Ranged does not require another paid body just because it carries a scope. Current-game improvements come before speculative aircraft or fleet purchases under the existing roadmap.

Parallel gameplay work is independently bounded: Area Kitchen and Larak Lot preserve the six existing multiplayer IDs; Passenger Manifest is a prototype on main and Common Carrier remains planned. The dedicated Wipe design is planning, not implemented waves/vehicles/turrets. Every mission/map remains in flight until its own route, play and compatibility gates pass.

## Architecture and delivery

No asset service runs at player runtime or in CI. Preserve the Rust server's authority, one authored/runtime map loader, protocol identity, slow MCP tools, existing local save/continue seams and GDScript presentation boundaries. The catalog itself changes no wire format. New enemy, vehicle, deployment and Wipe mechanics need their own reviewed protocol/server plans before art implies them.

Use existing preparation/bake code, not another generation harness. Keep raw models and API receipts private. Inspect actual topology, material count, embedded textures and movable pieces; targets are not measured facts. Prepare compact pixel maps and measured meshes. Weapons/mechanical bodies use local pivots; humanoid rigs require actual skin/gait proof. Atlas actors retain feet, facing, matching albedo/normal cells and real state timing. Live skins need real hand/tool contact, near clipping and packaged resources.

World blockers, roofs, vehicles and major furniture require authoritative solids/shot cover and real navigation proof. Build rooms, stairs, terrain, ship decks, doors, rails and water boundaries as modular authored geometry. Source hulls do not supply interiors. Water motion, impacts, sparks, smoke, skies and keyed text use their owning shader/presentation systems. Retain GPU-neutral Compatibility paths and measure renderer/memory deltas at playing resolution; headless CI does not establish visual performance.

For every promotion, retain front/side/back inspection, old/new comparisons at identical camera/venue light, actual motion/state/contacts, ordinary played use, clean shutdown and offline package evidence. Gameplay checks cover supplies, routes, encounter/round outcomes and save/retry where applicable. Full client and implementation CI follow the selected source change. Wider fresh-player fun and hardware acceptance remain separate.

Nick reported an office wall appearing abruptly on 2026-10-04. Absence of visible
pop-in is an explicit world acceptance gate: inspect continuous ordinary camera
approaches, turns and return peeks, including first-use and warmed runs. Stills
alone cannot prove it. Prepare geometry, materials and required phase resources
before readiness; any future streaming, LOD or visibility optimization must
preserve visible silhouettes and cannot remove cover. Distinguish a reproduced
loading/culling defect from intentional server-owned world change, and retain
the exact map, camera, frame and source receipt when diagnosing it.

## Catalog

### Wipe equipment

| Brief | Route | Intended use |
|---|---|---|
| [Portable automatic sentry](meshy-assets/e-portable-sentry.md) | New source candidate | M20 district stand and shared Wipe multiplayer; finite ammunition and locally isolated controls |

### Characters and enemy roles

| Brief | Route | Intended use |
|---|---|---|
| [Clerk](meshy-assets/c-clerk.md) | Reuse existing paid source | M01 onward |
| [Sweeper](meshy-assets/c-sweeper.md) | Reuse existing paid source | M01 onward |
| [Auditor](meshy-assets/c-auditor.md) | Reuse existing paid source | M08 onward |
| [Heavy Sweeper](meshy-assets/c-heavy-sweeper.md) | Local or derived | M05 onward |
| [Ranged Sweeper](meshy-assets/c-ranged-sweeper.md) | Local or derived | M07 onward |
| [Crawler](meshy-assets/c-crawler.md) | New source candidate | M02 onward |
| [Jammer](meshy-assets/c-jammer.md) | New source candidate | M03 onward |
| [Turret](meshy-assets/c-turret.md) | Local or derived | M06 onward |
| [Notary](meshy-assets/c-notary.md) | Local or derived | M02 sighting; M04 onward combat |
| [Enforcer](meshy-assets/c-enforcer.md) | New source candidate | M09 planned |
| [Redactor](meshy-assets/c-redactor.md) | New source candidate | M11 planned |
| [Assessor](meshy-assets/c-assessor.md) | New source candidate | M12 planned |
| [Continuance Walker](meshy-assets/c-continuance-walker.md) | New source candidate | M14 planned |
| [Collector](meshy-assets/c-collector.md) | New source candidate | M18 planned |
| [Paver](meshy-assets/c-paver.md) | New source candidate | M19 planned |
| [Surveyor](meshy-assets/c-surveyor.md) | New source candidate | M20 planned |
| [Selectable free human](meshy-assets/c-free-human.md) | Reuse existing paid source | Participants and retained civilian-base derivatives |
| [Non-Latch free-agent base](meshy-assets/c-free-agent.md) | New source candidate | Selectable synthetic body; workers, crew and captives |
| [Latch](meshy-assets/c-latch.md) | Reuse existing paid source | M02 rescue and conditional later appearances |
| [Mara, organizer](meshy-assets/c-mara.md) | Local or derived | Later coalition scenes, proposed identity |
| [Renn, custodian](meshy-assets/c-renn.md) | Local or derived | Later custody and defection scenes, proposed identity |
| [Edda Vale, medic](meshy-assets/c-edda.md) | Local or derived | M04 rescue; conditional ship and evacuation return |
| [Tern, pilot](meshy-assets/c-tern.md) | Local or derived | M09 release; Common Carrier and later conditional travel |
| [Splice, technician](meshy-assets/c-splice.md) | Local or derived | M05 rescue; conditional later repairs |
| [Orrin, restored chassis](meshy-assets/c-orrin.md) | Local or derived | M08 backup recovery; later explicit restoration |
| [Voss](meshy-assets/c-voss.md) | Local or derived | M17 leadership defeat and live capture |
| [Sorrel, proposed tram driver](meshy-assets/c-sorrel.md) | Local or derived | Optional proposed tram/civilian continuity |
| [Registrar Dietmar Kessel, proposed](meshy-assets/c-kessel.md) | Local or derived | Proposed institutional story role |
| [Civilian ensembles](meshy-assets/c-civilian-ensembles.md) | Local or derived | Patients, passengers, workers, stadium entrants and refuge survivors |
| [Multiplayer body and cosmetic variants](meshy-assets/c-participant-cosmetics.md) | Local or derived | All current arenas and proposed multiplayer maps |
| [Conditional bespoke Heavy chassis](meshy-assets/c-heavy-fallback.md) | Conditional or later source | Only if Sweeper-family derivative fails silhouette or articulation gate |
| [Conditional additional civilian human base](meshy-assets/c-human-fallback.md) | Conditional or later source | Only if shared civilian anatomy and clothing fail meaningful variety |
| [Conditional additional pilot/technician chassis](meshy-assets/c-agent-fallback.md) | Conditional or later source | Only if free-agent derivatives cannot preserve distinct people |
| [Orrin backup container](meshy-assets/c-orrin-backup.md) | Local or derived | M08 optional recovery and later restoration continuity |
| [Inheritance-seized Union chassis variants](meshy-assets/c-seized-chassis.md) | Local or derived | M18-M20 planned |

### Weapons and held equipment

| Brief | Route | Intended use |
|---|---|---|
| [Pistol](meshy-assets/w-pistol.md) | New source candidate | M01 onward |
| [Rifle](meshy-assets/w-rifle.md) | New source candidate | M01 onward |
| [Railgun](meshy-assets/w-railgun.md) | New source candidate | M06 onward |
| [Sniper Rifle](meshy-assets/w-sniper.md) | New source candidate | M07 onward |
| [Repeater](meshy-assets/w-repeater.md) | New source candidate | M10 planned |
| [Arc](meshy-assets/w-arc.md) | New source candidate | M12 planned |
| [Rocket Launcher](meshy-assets/w-rocket-launcher.md) | New source candidate | M13 planned |
| [Denial](meshy-assets/w-denial.md) | New source candidate | M17 planned |
| [Shotgun](meshy-assets/w-shotgun.md) | Reuse existing paid source | M02 onward |
| [Human hands and forearms](meshy-assets/w-human-hands.md) | Local or derived | All first-person weapons |
| [Synthetic hands and forearms](meshy-assets/w-synthetic-hands.md) | Local or derived | Synthetic participants using all weapons |
| [Fists](meshy-assets/w-fists.md) | Local or derived | Always carried |
| [Shiv](meshy-assets/w-shiv.md) | Local or derived | M01 secret onward |
| [Article Blade](meshy-assets/w-article-blade.md) | Local or derived | M15 planned |
| [Grenade](meshy-assets/w-grenade.md) | Local or derived | M05 onward |
| [Proximity Mine](meshy-assets/w-proximity-mine.md) | Local or derived | M08 onward |
| [Remote Mine](meshy-assets/w-remote-mine.md) | Local or derived | M11 planned |
| [Remote detonator](meshy-assets/w-remote-detonator.md) | Local or derived | M11 planned |
| [Rocket projectile](meshy-assets/w-rocket.md) | Local or derived | M13 planned |
| [Medical pickup case](meshy-assets/w-medkit.md) | Local or derived | Supplies across campaign and multiplayer |
| [Armor pickup](meshy-assets/w-armor.md) | Local or derived | Supplies across campaign and multiplayer |
| [Bullets pack](meshy-assets/w-bullets.md) | Local or derived | Campaign and multiplayer |
| [Shells pack](meshy-assets/w-shells.md) | Local or derived | Campaign and multiplayer |
| [Cells pack](meshy-assets/w-cells.md) | Local or derived | Campaign and multiplayer |
| [Rockets pack](meshy-assets/w-rockets.md) | Local or derived | M13 onward planned |
| [Grenade supply pack](meshy-assets/w-grenade-pack.md) | Local or derived | M05 onward |
| [Proximity Mine supply pack](meshy-assets/w-proximity-pack.md) | Local or derived | M08 onward |
| [Remote Mine supply pack](meshy-assets/w-remote-pack.md) | Local or derived | M11 onward planned |
| [Sabotage charge](meshy-assets/w-sabotage-charge.md) | Local or derived | Sector 9 Sabotage and later supported maps |
| [CTF flag and pole](meshy-assets/w-ctf-flag.md) | Local or derived | Current CTF and later supported maps |
| [Auditor shield](meshy-assets/w-auditor-shield.md) | Local or derived | M08 onward |
| [Auditor repair emitter](meshy-assets/w-auditor-emitter.md) | Local or derived | M08 onward |
| [Auditor cable assembly](meshy-assets/w-auditor-cable.md) | Local or derived | M08 onward |

### Custody machinery

| Brief | Route | Intended use |
|---|---|---|
| [Registration console](meshy-assets/e-registration-console.md) | New source candidate | M01/M02/M06/M08/M11/M15/M17; civic multiplayer |
| [Luggage inspection scanner](meshy-assets/e-luggage-scanner.md) | New source candidate | M06 customs and later custody reuse |
| [Confiscated-property bin](meshy-assets/e-property-bin.md) | Conditional or later source | M01/M02/M06/M11 |
| [Records cabinet](meshy-assets/e-records-cabinet.md) | Conditional or later source | M08 archive/M17 command; Custody Archive map |
| [Agent restraint frame](meshy-assets/e-restraint-frame.md) | New source candidate | M02/M08/M11 custody |
| [Correction processing machine](meshy-assets/e-correction-machine.md) | New source candidate | M02 and later institutional evidence |
| [Custody-defense machine housing](meshy-assets/e-custody-housing.md) | New source candidate | M08 archive and later reused command hardware |

### Occupied rooms

| Brief | Route | Intended use |
|---|---|---|
| [Civilian repair workbench](meshy-assets/e-repair-workbench.md) | New source candidate | M04/M05/M07/M10/M12/M13/M18-M20; civilian maps |
| [Shared meal stove](meshy-assets/e-meal-stove.md) | New source candidate | Low Water and later habitation/epilogue |
| [Clinic examination bed](meshy-assets/e-clinic-bed.md) | New source candidate | M04 rescue and later medical use |
| [Ship bunk](meshy-assets/e-ship-bunk.md) | New source candidate | M10/M11 and later transport |
| [Ship galley unit](meshy-assets/e-galley.md) | New source candidate | M10/M11 and later ship return |
| [Civilian CRT](meshy-assets/e-civilian-crt.md) | Conditional or later source | Earth homes, ships, Mars; Area Kitchen |
| [Small civilian fridge](meshy-assets/e-fridge.md) | New source candidate | Low Water, ship habitation, Area Kitchen |

### Personal possessions

| Brief | Route | Intended use |
|---|---|---|
| [Community radio](meshy-assets/e-community-radio.md) | New source candidate | Low Water, ship, Mars, Earth return and epilogue |
| [Hard luggage](meshy-assets/e-hard-luggage.md) | Conditional or later source | M01/M06/M09-M14 and refuge |
| [Soft duffel](meshy-assets/e-duffel.md) | New source candidate | Homes, evacuation, ship and refuge |
| [Mechanic toolbox](meshy-assets/e-toolbox.md) | Conditional or later source | M04/M05/M07/M10/M12/M13 |
| [Robot maintenance-parts assembly](meshy-assets/e-robot-parts.md) | New source candidate | Workshops, ship repairs, restored Orrin and epilogue |
| [Civilian bicycle](meshy-assets/e-bicycle.md) | New source candidate | Low Water and Earth civilian districts |
| [Replacement tram motor](meshy-assets/e-tram-motor.md) | New source candidate | M05/M18-M20 continuity |
| [Edda portable lamp](meshy-assets/e-edda-lamp.md) | New source candidate | M04 clinic, conditional ship/evacuation and refuge |

### Utilities and lifelines

| Brief | Route | Intended use |
|---|---|---|
| [Yard generator](meshy-assets/e-yard-generator.md) | Reuse existing paid source | M03 utilities and other working industrial venues |
| [Water pump](meshy-assets/e-water-pump.md) | New source candidate | Earth drainage, Low Water, Mars services and M18-M20 |
| [Rooftop water tank](meshy-assets/e-rooftop-tank.md) | Conditional or later source | M04/M05/M18-M20 and epilogue |
| [Air scrubber](meshy-assets/e-air-scrubber.md) | New source candidate | Lunar/Martian habitation and ship services |
| [Recycling/filter module](meshy-assets/e-recycler.md) | New source candidate | Lunar/Mars/ship contained life support; waterworks |
| [Pressure-gas manifold](meshy-assets/e-gas-manifold.md) | Conditional or later source | Moon, ship and Martian services |
| [Heat exchanger](meshy-assets/e-heat-exchanger.md) | Conditional or later source | Moon, ship, Mars and large machinery |
| [Power transformer](meshy-assets/e-transformer.md) | New source candidate | Earth utilities, Directive 17 and later blackout sites |

### Rail and tram equipment

| Brief | Route | Intended use |
|---|---|---|
| [Locomotive body and cab](meshy-assets/e-locomotive.md) | New source candidate | M03 yard and later Earth continuity |
| [Recall freight car](meshy-assets/e-recall-car.md) | New source candidate | M03 captive recall and later institutional transport |
| [Patched civilian tram](meshy-assets/e-civilian-tram.md) | New source candidate | M05 departure; M18-M20 return and epilogue |
| [Maintenance gantry hoist](meshy-assets/e-gantry-hoist.md) | New source candidate | M03/M05/M14 and industrial maps |
| [Railway switch hardware](meshy-assets/e-rail-switch.md) | Conditional or later source | M03 and industrial rail reuse |

### Lunar logistics

| Brief | Route | Intended use |
|---|---|---|
| [Impound tug](meshy-assets/e-impound-tug.md) | New source candidate | M06-M09 freight/berth; possible later vehicle variant |
| [Lunar loader](meshy-assets/e-lunar-loader.md) | New source candidate | M06-M09 working cargo |
| [Pressure freight container](meshy-assets/e-pressure-container.md) | Conditional or later source | M06-M14 and transport maps |
| [Docking clamp head](meshy-assets/e-docking-clamp.md) | Conditional or later source | M09 berth and ship access |

### Ships and ship equipment

| Brief | Route | Intended use |
|---|---|---|
| [Common Carrier exterior](meshy-assets/e-common-carrier.md) | New source candidate | M05/M06 views, M09-M11 and M14 travel; ship multiplayer |
| [Union custody tender exterior](meshy-assets/e-custody-tender.md) | New source candidate | M11 and later distinct institutional ship framing |
| [Ship engine and power pack](meshy-assets/e-ship-engine.md) | New source candidate | M09-M11/M14 and ship multiplayer |
| [Boarding umbilical assembly](meshy-assets/e-boarding-umbilical.md) | New source candidate | M09/M11 ship access |
| [Pilot/navigation console](meshy-assets/e-pilot-console.md) | New source candidate | Tern ship scenes, M09-M11/M14 |

### Martian works

| Brief | Route | Intended use |
|---|---|---|
| [Foundry ladle](meshy-assets/e-foundry-ladle.md) | New source candidate | M13/M14 industrial work |
| [Furnace/casting housing](meshy-assets/e-casting-furnace.md) | New source candidate | M13 foundry |
| [Ingot/mould trolley](meshy-assets/e-ingot-trolley.md) | New source candidate | M13/M14 freight and factory workers |
| [Industrial press](meshy-assets/e-industrial-press.md) | New source candidate | M13 production and later industrial map reuse |
| [Greenhouse growth rack](meshy-assets/e-growth-rack.md) | New source candidate | M12 habitat and later epilogue reuse |
| [Machine-hall lathe](meshy-assets/e-lathe.md) | New source candidate | M13 practical industrial labor |

### Public institutions

| Brief | Route | Intended use |
|---|---|---|
| [Ceremony lectern](meshy-assets/e-lectern.md) | Conditional or later source | M15-M17 public staging and Voss |
| [Prison transport bus](meshy-assets/e-prison-bus.md) | New source candidate | M16 avenue and M18-M19 return |
| [Stadium broadcast console](meshy-assets/e-broadcast-console.md) | New source candidate | M15 coercive games; arena broadcast reuse |
| [Institutional turnstile](meshy-assets/e-turnstile.md) | Conditional or later source | M15 entry and M16-M17 checkpoints |

### Waterworks

| Brief | Route | Intended use |
|---|---|---|
| [Sluice actuator](meshy-assets/e-sluice-actuator.md) | New source candidate | M18-M20 and later Waterworks multiplayer |
| [Filter-bed service skid](meshy-assets/e-filter-skid.md) | New source candidate | M20 waterworks and later reuse |
| [Pier-crane cab](meshy-assets/e-pier-crane.md) | New source candidate | M20 pier and harbor multiplayer |
| [Waterworks valve manifold](meshy-assets/e-valve-manifold.md) | New source candidate | M18-M20 infrastructure |

### Vehicles and mobility

| Brief | Route | Intended use |
|---|---|---|
| [Utility rover/jeep](meshy-assets/e-jeep.md) | New source candidate | M14 introduction; later vehicle multiplayer |
| [Motorcycle](meshy-assets/e-motorcycle.md) | New source candidate | M16 introduction; later vehicle multiplayer |
| [Jetpack](meshy-assets/e-jetpack.md) | New source candidate | M19 introduction; later supported maps |

### Earth vegetation

| Brief | Route | Intended use |
|---|---|---|
| [Deciduous tree family](meshy-assets/e-deciduous-tree.md) | New source candidate | Earth boundaries and years-later epilogue |
| [Low scrub cluster](meshy-assets/e-scrub.md) | New source candidate | Earth exterior edges and epilogue |
| [Waterfront reeds](meshy-assets/e-reeds.md) | Conditional or later source | Earth water edges and epilogue |

### Additional multiplayer sources

| Brief | Route | Intended use |
|---|---|---|
| [Parked service van](meshy-assets/mp-service-van.md) | Conditional or later source | Larak Lot |
| [Rooftop HVAC chiller](meshy-assets/mp-roof-chiller.md) | Conditional or later source | Chemtrail Alley; Earth roof reuse |
| [Workshop loom](meshy-assets/mp-loom.md) | Conditional or later source | Custody Archive multiplayer |
| [Workshop kiln](meshy-assets/mp-kiln.md) | Conditional or later source | Custody Archive multiplayer |
| [Reclamation crusher](meshy-assets/mp-crusher.md) | Conditional or later source | Reclamation Gulch and Tripoint |
| [Unmarked industrial drum](meshy-assets/mp-industrial-drum.md) | Conditional or later source | Tripoint Works |
| [Lighthouse lens assembly](meshy-assets/mp-lighthouse-lens.md) | Conditional or later source | Holdfast Atoll future |
| [Tropical palm family](meshy-assets/mp-tropical-palm.md) | Conditional or later source | Holdfast Atoll future |
| [Fast boat](meshy-assets/mp-fast-boat.md) | Conditional or later source | Holdfast Atoll future |
| [Landing craft](meshy-assets/mp-landing-craft.md) | Conditional or later source | Holdfast Atoll future |
| [Coalition repaired prop plane](meshy-assets/mp-prop-plane.md) | Conditional or later source | Holdfast Atoll future |
| [Union Notary-class gunship](meshy-assets/mp-union-gunship.md) | Conditional or later source | Holdfast Atoll future |
| [Fixed anti-air gun](meshy-assets/mp-anti-air.md) | Conditional or later source | Holdfast Atoll future |
| [Mobile staging ship](meshy-assets/mp-staging-ship.md) | Conditional or later source | Holdfast Atoll future |

### Local construction and occupation kits

| Brief | Route | Intended use |
|---|---|---|
| [Registered service vent](meshy-assets/l-vent.md) | Local or derived | Retain existing registered fixture family |
| [Registered locker bank](meshy-assets/l-locker.md) | Local or derived | Retain current custody fixtures |
| [Registered wall terminal](meshy-assets/l-wall-terminal.md) | Local or derived | Retain current institution/utility fixtures |
| [Registered strip light](meshy-assets/l-strip-light.md) | Local or derived | All appropriate venues |
| [Registered property-sign housing](meshy-assets/l-property-sign.md) | Local or derived | Custody and practical wayfinding |
| [Earth building wall/window/roof kit](meshy-assets/l-buildings.md) | Local or derived | M01-M05/M15-M20; Earth multiplayer |
| [Pressure-shell wall/rib/ceiling kit](meshy-assets/l-pressure-shell.md) | Local or derived | M06-M14; offworld/ship maps |
| [Framed pressure-door kit](meshy-assets/l-pressure-door.md) | Local or derived | Moon/Mars/ships |
| [Stair/ramp kit](meshy-assets/l-stairs.md) | Local or derived | All height changes |
| [Catwalk/platform/railing kit](meshy-assets/l-catwalk.md) | Local or derived | Working industrial and ship venues |
| [Service grating](meshy-assets/l-grating.md) | Local or derived | Industrial, lunar and water services |
| [Rail/tram track kit](meshy-assets/l-track.md) | Local or derived | M03/M05/M18-M20; industrial maps |
| [Crane/gantry frame kit](meshy-assets/l-gantry.md) | Local or derived | Yard, lunar berth, foundry, pier |
| [Archive gallery/seal/shutter kit](meshy-assets/l-archive-structure.md) | Local or derived | M08; Custody Archive |
| [Lunar habitation dome](meshy-assets/l-lunar-dome.md) | Local or derived | M07 settlement and future lunar maps |
| [Crater/basalt terrain kit](meshy-assets/l-crater-terrain.md) | Local or derived | M06-M09 exterior boundaries |
| [Depot/Office/dock landmark volumes](meshy-assets/l-distant-landmarks.md) | Local or derived | Campaign and map skyline orientation |
| [Greenhouse glazing structure](meshy-assets/l-greenhouse-shell.md) | Local or derived | M12 habitat |
| [Stadium stands/plinth kit](meshy-assets/l-stadium-structure.md) | Local or derived | M15 and public arena maps |
| [Fountain basin](meshy-assets/l-fountain.md) | Local or derived | M16 avenue and civic maps |
| [Sluice/channel/filter-bed structure](meshy-assets/l-water-channel.md) | Local or derived | M18-M20; Waterworks map |
| [Pier/mooring structure](meshy-assets/l-pier.md) | Local or derived | M20; harbor and island maps |
| [Lighthouse/runway/harbor building kit](meshy-assets/l-island-buildings.md) | Local or derived | Holdfast Atoll future |
| [Occupied table](meshy-assets/l-table.md) | Local or derived | Homes, clinic, ships, workshops |
| [Occupied chair](meshy-assets/l-chair.md) | Local or derived | Homes, desks, waiting and ship rooms |
| [Community bench](meshy-assets/l-bench.md) | Local or derived | Low Water and inhabited districts |
| [Shelving kit](meshy-assets/l-shelving.md) | Local or derived | Property, workshops, ship cargo and pantry |
| [Meal bowl](meshy-assets/l-meal-bowl.md) | Local or derived | Shared domestic tables and galley |
| [Personal mug](meshy-assets/l-mug.md) | Local or derived | Homes, workshop, cockpit and desk |
| [Food container](meshy-assets/l-food-container.md) | Local or derived | Domestic, evacuation and galley |
| [Paperwork/record binder](meshy-assets/l-paperwork.md) | Local or derived | Custody, archive, organizer and desks |
| [Clothesline/bedding kit](meshy-assets/l-bedding.md) | Local or derived | Homes, evacuation and bunks |
| [Charging dock/cables](meshy-assets/l-charging.md) | Local or derived | Free-agent homes, workshops and ship |
| [Pipes/drains/fittings kit](meshy-assets/l-pipes.md) | Local or derived | All working utilities |
| [Restraint cuffs](meshy-assets/l-cuffs.md) | Local or derived | M02/M08/M11 |
| [Practical lamps](meshy-assets/l-lamps.md) | Local or derived | All occupied venues |
| [Traffic lights](meshy-assets/l-traffic.md) | Local or derived | M16 and streets/parking |
| [Keyed signs/boards](meshy-assets/l-signs.md) | Local or derived | All readable routes and story surfaces |
| [Contained water/ripple/foam surfaces](meshy-assets/l-water-surfaces.md) | Local or derived | Drainage, contained utilities, waterworks and later deep-water maps |
| [Repair/dust/wear overlays](meshy-assets/l-wear.md) | Local or derived | Place-specific repeated surfaces |
| [Memorial marker](meshy-assets/l-memorial.md) | Local or derived | Outcome-aware epilogue |
| [Greenhouse crop clusters](meshy-assets/l-crops.md) | Local or derived | M12 agriculture and later inhabited recovery |
| [Damaged/wreck dressing](meshy-assets/l-damage.md) | Local or derived | Outcome/time-specific scenes and vehicle states |

## Completion criteria

The inventory is reviewable and linked to canon; each selected batch has a reconciled allowance and actual task/source receipts. Important current assets pass the owning source, motion, venue-light, played and package gates before runtime selection. Remaining source families retain explicit demand, cost and references instead of being described as complete. Later maps/missions reuse accepted families and preserve identity across time and rescue outcomes. The roadmap remains the sole global sequence.
