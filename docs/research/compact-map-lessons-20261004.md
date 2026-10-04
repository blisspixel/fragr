# Compact map lessons for fragr

Checked 2026-10-04. Research only, $0 spend, source base `f79b86f0` plus the
in-flight Kitchen and revised garage leaves. This is input to the existing
[full build order](../ROADMAP.md#full-build-order-updated-2026-10-04), not a new
implementation queue. No map layout, asset or weapon behavior is copied.

The useful comparison is decision density: how often a player can identify a
threat, choose an approach or retreat, and return to a place worth contesting.
These six comparisons are a curated fit for fragr, not an authoritative ranking
of the most fun maps. Popularity, designer recollection, technical metrics and
fresh-player enjoyment are different evidence.

## Primary evidence and its limits

| Source | What was verified | Limits |
| --- | --- | --- |
| [Martin Hollis, 2004 development talk, preserved transcript](https://www.mi6-hq.com/sections/articles/gaming_ge64_making_of) | Interesting architecture preceded objectives; multiple routes and apparently ordinary rooms supported freedom. Visible enemy decisions supported tactics. | First-person retrospective, not map timings or a controlled fun study. The original host is no longer the inspected page. |
| [1997 Edge interview with Hollis, Doak and Hilton, preserved transcript](https://www.raregamer.co.uk/games/the-golden-touch-edge-interviews-the-goldeneye-007-team/) | The team repeatedly played four-player multiplayer; detail and observed character behavior mattered. | Interview transcription; it does not establish that one map or floor area is universally best. |
| [Duncan Botwood interview](https://www.therwp.com/article/duncan-botwood-interviewed) | Architecture training informed his work; he identifies the Gasplant and Temple among backgrounds he built. | Retrospective authorship/process account, not a measured route graph. |
| [John Romero's official map-source release page](https://rome.ro/resources), [actual ZIP](https://rome.ro/s/1996-quake-map-sources.zip) | Original `DM3.MAP` and `DM6.MAP`, item coordinates and spawn entities were inspected directly. Release README identifies v1.06 sources and the included GPL. | Historical source revision, not every tournament variant. No original maps/textures enter fragr. |
| [Classic_DM first-person Deck16 account](https://www.reddit.com/r/unrealtournament/comments/1jyr899/i_am_an_unreal_tournament_addict_ive_been_playing/) | The commenter describes varying sightlines and later weapon/pathfinding revisions. | Self-reported creator account; identity was not independently authenticated in this bounded research. Its map-quality explanation is opinion. |

The downloaded Quake source ZIP SHA256 is
`c2f0660617264e0918edc4a7c34dc66692ef396f2308c6cf9b6d12cfe595db7c`.
Original files and their legal notices are retained only in private diagnostics.
GoldenEye reference room motifs below are design interpretations; original
geometry dimensions and item-by-item positions were not independently measured.
Do not turn those interpretations into historical designer intent.

## Six comparisons and the transferable question

| Comparison | Why it belongs here | Application, explicitly design judgment |
| --- | --- | --- |
| GoldenEye Facility | Practical institutional architecture makes a believable place readable. Botwood's Gasplant account and Hollis's architecture process support the contextual comparison. | Kitchen should retain recognizable service work and two different escape destinations. Repeated appliances can establish place; repeated anonymous corridors cannot establish orientation. |
| GoldenEye Complex and Temple | Compare a layered chase-space motif with a simpler arena motif, rather than treating all small maps as identical room counts. Botwood directly identifies Temple as his work. | Garage floors need local fights and recognizable stair returns, not an atrium copied from another reference. Every vertical route should change exposure or reward. |
| GoldenEye Archives | A records-room motif is a useful contrast to a central arena: short corners and meaningful ordinary rooms. Hollis's account supports nonlinear architecture and visible decisions, not a particular Archives balance claim. | Kitchen's archive lane should offer a flank and a return, while its filing banks need a distinct silhouette. Campaign civilian rooms can express life without adding compulsory interaction. |
| Quake DM6, The Dark Zone | Inspected source has two rocket-launcher entities at different locations, seven deathmatch spawns and items on several elevations. | More than one access to combat capability can prevent a single prize holder from deciding every fight. Height must connect valuable places, not only add floor area. |
| Quake DM3, The Abandoned Base | Inspected source separates a rocket launcher, lightning weapon and super-damage item; its six deathmatch spawns and resources occupy different elevations. | Distribute contested reasons to move. Do not bundle all useful guns, armor and escape health in one dominant room. Its existence does not prescribe DM3's dimensions for four people. |
| Unreal/UT Deck16 | The first-person account attributes fun to varied long, tight and wider sightlines and describes adapting weapons and bot paths. | Combine a memorable visible destination with alternate approaches at different ranges. Tune navigation and gun reach together. Do not import its void, lifts, hazards or room shape as prerequisites. |

## Direct audit of current fragr work

**Area Kitchen:** `server/src/maps/area_kitchen.rs`, `area_kitchen.gd` and the
fifteen-state route provide three break rooms, Cubes, two office stairs, a
40 m archive line and a dock loop. Preserve these. The next gameplay review
should compare the two exits from each kitchen: they should let a fleeing
fighter choose another contested place, rather than enter the same enemy
sightline twice. Make Ring/Cubes/Archive/Dock distinguishable through broad
architecture and work identity; tiny fridge lamps alone are weak orientation
at a fast corner. Keep civilian beige/sage finishes and actual cover.

Eight-pad proof passes 96 navigation routes, 60 actual player arrivals and
fifteen rendered states/47 arrivals. A four-fighter seed-42 socket run gives
23 frags in 61.9 s, first frag 6.2 s, one later spawn death and no opening
deaths. This establishes contact, not human fun. The earlier six-fighter run
was seven-pad source and cannot certify the final eight-pad map. Full-size
office frames have blank white faces behind glass: **art gate fails**. Two
later material diagnostics did not reproduce them, so cause remains unresolved.
The upward-view timing hitch and repeated floor grid remain visible concerns.

**Larak Lot:** current revised `larak_lot.rs` and its plan propose three solid
parking floors, 3.2 m spacing, actual perimeter right-angle ramp circuits and
enclosed stair shortcuts. Respect the rejected-atria decision. A roughly
128 m perimeter lap takes about 25.6 s at 5 m/s before fighting: useful as
vehicle architecture, potentially costly as four-player circulation. Give each
floor one legible destination and a short route to both stairs. Contrast ground
street/workshop access, middle parking and top dispatch/storage through use,
not only numbered paint. Place contested rewards across different floor routes
and put recovery on reachable retreats. Do not accept a connected ramp graph
as proof that players choose to use it. The earlier split-deck capture and
failed ramp arrival are rejected historical evidence, not proof of this rewrite.

**M04 Notice to Vacate:** keep the clinic, workshop, communal tank and lived-in
court as a readable sequence. Tank visibility already survives the residential
frontage. Extend identity around east/north frontage before adding generic
clutter. The finite-health court correction matters: an entry that accidentally
claims the pack converts a tactical retreat into wasted supply. Roof returns
must reconnect to the mission without shortcuts around original guards or
departure. Preserve the demonstrated 28 guards, patient/photo facts and real
departure; closed homes must remain honestly closed.

**M06 Port of Entry:** preserve the 58.25 m Rail lesson and actual freight
cover. From a new player's customs position, the long line, nearer cover and
alternate route need to be identifiable together. Shipment, sorter and gantry
identity should explain the route. Do not fill its firing lesson with arbitrary
props or let attractive equipment imply interaction that does not exist.

**M07 Declared Goods:** tower, dark dwelling fronts, market/vault, sniper rack
and crater cut supply different meanings, not merely different distances.
Preserve the 25-guard ordinary route and finite equipment. The proven earlier
capture failures from out-of-range Rifle targeting and insufficient ammunition
show why reachable routes alone are inadequate. Present the useful firearm and
its firing position before the long shot; every return needs a recognized
landmark. Civilian pressure-shell/repair surfaces stay distinct from issued
black/red barriers and outfits. Preserve personhood and optional civilian
outcomes; campaign rescue space is not a multiplayer loot arena.

## Measurable review gates

Use the existing [multiplayer rule sheet](../plans/multiplayer-maps.md#rule-sheet),
without reducing its assertions: small-map first frag under 8 s, six-fighter
rate at least 12/min, two distance bands each at least 20 percent, at most one
opening spawn death per round and no stall over 10 s. Repeat final source with
duel, four and six fighters over varied seeds; keep per-player deaths and
empty travel, not only aggregate frags. Kitchen still needs final-source duel
and six-player evidence; the revised garage needs its own complete matrix.

For the next human review, proposed observations are: identify current zone
and a return route after one lap; obtain a first frag within the first minute;
find two tactically different approaches to the main reward; demonstrate a
covered escape and an ordinary stair return. Record whether choices were
actually used and where orientation failed. These are proposed human review
questions, not claims that those tests have passed or universal thresholds.

Campaign review instead records first combat, the longest empty stretch,
weapon/range comprehension, visible enemy tells, optional rescue choice and
fresh departure on the unchanged authoritative rules. Different skill and
inventory states must still work. No deadline, damage, encounter count or
mandatory mission assertion is weakened for a reference-inspired layout.

Visual acceptance requires ordinary moving-camera inspections with ready
surfaces, readable characters and truthful enclosure/cover. Stable nodes,
better models and passing bots do not establish excellent rendered art or fun.
