# Frag feed, corner voice and objective calls

Status: **in flight**, #413 within [#418](https://github.com/blisspixel/fragr/issues/418).
Base: reviewed main `8ecbb99c77a74dbb28ff8090fc86f5b58d36a881`, PR #422,
with passing main CI [39150766048](https://github.com/blisspixel/fragr/actions/runs/39150766048).
v0.88.0 is published with three verified desktop archives and a passing downloaded
Linux installation and exact server build metadata check. The sole
sequence remains [Full build order](../ROADMAP.md#full-build-order).

## Goal and non-goals

Make frags readable for their full lifetime while preserving the game's frozen
voice. Present frags, corner speech and objective calls in separate regions.
Use the retained palette, fonts and weapon sprites at $0. No generated assets,
new dependencies, combat changes, save changes or invented headshot evidence.
World materials, fighter colors and nameplates remain outside this change.
HUD scaling, flash controls and signature effects follow in their own issues.

Include small verified workspace lockfile maintenance: Rustls 0.23.46 and non-yanked yoke-derive
0.8.4, subject to actual resolver and license checks. This updates existing
developer HTTP dependencies without changing TLS policy, game transport or
packaged desktop behavior. Record the advisory check separately from the UI
acceptance. No new dependency family or paid-provider call is planned.

## Accepted event facts

Add optional `killer_id`, `victim_id` and `weapon` to `GameEvent::Frag`, with
serde defaults and omission when absent. IDs are participant UUIDs; weapon is
the existing snake_case `WeaponType`. Preserve all current text fields and
their wording. Older events deserialize without these fields and remain usable
without fabricated identity or weapon information. Document the shared enum in
`docs/protocol.md` and the adapter README, including `get_events` compatibility.
No required gameplay capability changes for these additive optional facts.

Capture the resolved trace weapon before moving its trace into ShotResult.
Normal and friendly-fire deaths share the same metadata. Pass Rocket weapon
provenance separately into the shared damage commit: never manufacture a ray
trace, which would change shield, armor, self-hit or plate behavior. Committed
rockets retain their source even after an owner dies or switches weapons.
Untyped explosions omit weapon. Keep existing self-death and campaign early
returns and team-kill scoring unchanged.

GameManager prefers validated event IDs throughout the frag path, including
winner glow, local lives and death camera. Missing identity stays uncertain;
legacy unique-name lookup may support old servers, but ambiguous callsigns
must never select another fighter. Never convert arbitrary values into IDs.
Brain summaries prefer IDs and retain the participant record's count authority.
Bound any retained legacy identity index and fail closed on exhaustion. Forgetting
a known duplicate merely because a dead body left the next snapshot must not
make an old callsign certain again. Modern supplied IDs remain authoritative
without this fallback. A brain's own-name ambiguity can be retained as a small
per-identity fact; it does not need a full historical roster. Preserve its
separate event `frags` and record `kills` counters.

## Three presentation owners

**FragFeed** receives immutable accepted names, IDs, teams, weapon and viewer
relation. It owns five visible rows, each lasting 4.5 seconds from admission,
plus a 64-entry pending FIFO. Non-frag events cannot change either collection.
Preserve visible and pending rows across ordinary round transitions, including
result and warmup cards; retire them when the connection ends. When full,
reject the newest pending arrival and increment a diagnostic counter, without
evicting existing entries or adding a synthetic public notice or audit history.
Queue capacity is burst tolerance, never an unlimited throughput guarantee.
Fresh admission must not lose the preceding frame's delta. If a full-screen
story, campaign-results or warmup overlay covers the feed, pause visible time
and pending admission. An ordinary result card that leaves its reserved region
unobscured does not pause frags. Verify this with actual overlay ownership.
Include the pause/settings veil and a held standings board when they cover the
feed. DepartureReview is a centered 620-unit panel, so it always covers the
objective lane but need not cover the right-hand frag lane. Check console and
scope ownership explicitly. Derive coverage from actual visible owners and
regions, rather than pausing every tier for all control barriers.

A simple timing seam is to enqueue arrivals, advance only existing visible
rows in `_process`, then admit waiting rows at the end of that step without
subtracting its delta from them. This avoids frame-number flags and prevents
the pre-arrival interval consuming a new row's lifetime. Covered processing
does neither aging nor admission. Test arrival immediately after a long frame,
expiry plus refill in one step and uncovery with pending rows; permit at most
one rendered frame of timing tolerance. Keep this behavior independent of
text reflow and control reconstruction for accessibility settings.

Source follow-through: FragrConsole's opaque panel occupies the top 45 percent
of the view at CanvasLayer 128. PauseMenu's 0.75-alpha full-screen veil is layer
100; story and campaign results are layer 110. SniperScope is currently appended
after the original CombatFeed in the same HUD layer, with opaque side bars and
a square aperture. A newly appended tier must not accidentally bypass warmup's
cover, and the old frag lane must not silently expire underneath the scope.
Choose explicit tier draw order and coverage together. Prefer readable feed
rows over the scope's side bars if it preserves the aperture, while keeping
the warmup and higher-layer cover owners authoritative. Verify scoped and
unscoped transitions in the rendered fixture and covered-lifetime tests.
An actual 1280x720 Xvfb/GL Compatibility baseline on October 18 confirms both
occlusions. The logical view is 1920x1080, feed rect (1424,20,480,230), console
rect (0,0,1920,486). Scope is HUD child 28 and the feed child 5. Private stills
`feed-covers-baseline/baseline_{open,scope,console}.png` were inspected; this is
an isolated retained-HUD diagnostic, not played or new-tier acceptance.

Rows use plain labels, not parsed peer markup. Preserve full bounded names in
the immutable payload while visibly ellipsizing long display names. Existing
appropriate weapon sprites use nearest filtering; missing glyphs show the
literal wire weapon name. Missing weapon has a neutral separator. Never infer
it from a live pawn or adjacent shot. Own involvement gets bone backing with
ink text. A shared UI relation helper supplies ours, theirs and neutral marks
or plates beside readable names; avoid low-contrast red body text. Free-for-all
does not reuse pink or violet fighter tints. Relation is frozen at arrival;
parity with the live board means the same helper under the same viewer context.
Historical rows do not recolor after a spectator change or Sabotage side swap.
Keep actual local identity separate from viewing context: a followed fighter
may supply the side used for relation styling, but never becomes YOU or earns
the own-involvement plate. Retain a joined participant's last accepted side
through ordinary respawn omission, and clear it at role/map/session retirement.
Free camera without a side stays neutral, with accepted team marks still legible.

**CombatFeed** becomes the separate left-aligned voice lane. Keep its bounded
budget independent of frags. Taunts are bone, Host lines ember and personal
pickups muted. Audit every direct caller, retaining personal pickup/secret
filters, mission dispatch, rewards and venue copy. Start Host radio ducking when
the line is actually displayed, preserving snapshot/event deduplication.
Keep the existing warmup/result-card duck signals with those cards. Move the
reaction's current immediate duck to voice admission so it cannot fire twice.
A Host row replaced within the same burst before presentation must not duck
the radio. Track first presentation separately from text arrival; retire stale
voice ownership at map/session boundaries without changing frozen copy.

Primary API research: [CanvasItem.draw](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#signals)
is emitted when an item must redraw. A pinned 4.7.2 diagnostic, separately run
headless and on X11 GL Compatibility/llvmpipe, observed zero draw notifications
for a row removed before the frame, one for a surviving row, zero while a
parent was hidden and one after revealing and requesting redraw. Consider this
signal for first-presentation ownership, with an idempotent presented flag and
explicit redraw of unpresented entries when uncovered. These are API probes,
not a rendered game acceptance or hardware benchmark. Headless draw command
notifications alone do not establish visible pixels. Retain an actual mixed-tier
rendered fixture for the final Host/radio acceptance.

**ObjectiveCall** owns one backed Black Ops One call above the aim for about
1.5 seconds, with sequential admission and a 16-entry pending FIFO. Reject
newest arrivals when full and count rejections privately. Flag and Sabotage events use their
existing localized copy. Boss arrival joins this tier. Conquest compares
accepted ownership by stable site ID, silently priming on join/reset and
emitting only real changes in stable ConquestState.SITES order. Reuse site names and owner/neutral labels; progress
and contested updates are not ownership changes. Round/match cards keep
immediate priority. Pause objective display and its clock while covered by
warmup, results or story. Retain a final objective through its own Ended result
card; clear at the next round or map generation, not on entering Ended. Use
owned lifetimes so an older expiry cannot dismiss a newer call.

HudRegions remains the single geometry owner. At 720p, measure five populated
frag rows, three voice lines, radio, nearby vehicle controls and the ammunition
stack together. Start from compact 48-logical-unit frag rows and the existing
24-unit body type, not smaller text that conceals overflow. Keep campaign
dispatch clear of MissionHud. Later HUD-scale work must be able to reflow these
owners without mutating event state or lifetimes.

Read-only font measurements on pinned Godot 4.7.2 and MenuTheme.FONT at 24:

| Text | Logical width |
| --- | ---: |
| Dead Air Dan | 195 |
| Tin Foil Tina | 189 |
| Nightfall-2 | 177 |
| TOWN SOCKET 02 | 237 |
| rocket | 102 |
| article_blade | 210 |

Two common names plus a 48-unit glyph and 24-unit padding fit 456 units; long
names still need explicit ellipsis. Profiles range from 36x26 Pistol to
100x20 Sniper. Inspect
their actual small-size legibility rather than assuming every sprite is square.
The only current 48px glyph in that folder is Shiv; future-weapon placeholders
are not automatically selected assets for new event provenance.

The same font's measured height is 31 logical units (ascent 25, descent 6).
A 40-unit row with a 32-unit glyph height is a viable compact candidate without
shrinking body text; actual fallback-font row bounds still own layout. Five
such rows plus four 4-unit gaps occupy 216 units. A two-entry, two-line voice
budget plus a 12-unit lane gap can fit a crowded broadcast/vehicle column where
three voice entries cannot. Measure the actual radio/vehicle reservation and
bound the voice budget to the remaining region. Quiet voice may retire older
entries; protected frag rows must retain their full visible lifetimes.
Actual fallback-font minimum heights must replace the 40-unit candidate if
larger. Existing profile sprites also suggest a 72x32 bounding box for long
rifles, rather than forcing every glyph into a square. Compare 520- and
560-unit columns against common complete names and the remaining center lane
in rendered fixtures before choosing geometry. Reflow center Conquest and
objective calls within that same reservation, including broadcast chrome.

## Standings and measurement callers

Replace scoreboard name-keyed dictionaries with one accepted row array
containing optional real ID, name, validated team, score, behavior chip and
detailed counters. Preserve duplicate names and avoid invented IDs. Modern YOU
uses nonempty ID equality; a supplied unmatched ID never falls back to a name.
Explicit legacy name-only input may mark one unique matching callsign.
Spectating has no YOU marker. Use the same relation helper as frag rows.
Retain bounded scrolling, detailed columns, Unicode and deterministic score
ties. Clear identity/team facts at map and session boundaries. HudScoreSubject
remains independent: it retains the selected center score through a temporary
roster omission, while the standings show only the accepted roster.

The current board's Label is rebuilt as text every HUD frame. Prefer plain
per-row labels and shared relation marks inside its existing ScrollContainer,
with a pure detailed-row formatter. Rebuild controls only when accepted rows,
viewer context or style change; retain scrolling across refreshes. Keep all
64 Unicode rows reachable, replace old Label-cast tests with real row geometry
checks and preserve equipment-input isolation. Clear accepted board rows on
MapInfo/session retirement instead of carrying old name dictionaries until a
fresh snapshot. A held board pauses event clocks only where its actual visible
rect intersects the protected lane. See the private standings presentation
review for caller and acceptance details.

Playtest kill attribution uses explicit `Frag.weapon.name()` first. Remove
last-held-weapon inference. Shared ExplosionResult has no weapon provenance,
so its shots, hits and damage belong to a generic Explosion category, not
Grenade. Retained killing evidence matches IDs where available, with ambiguity
rejected for bounded legacy fallback. Consume pending evidence even when
explicit metadata wins. Count an attributed kill once without requiring a
position or time-to-kill measurement; append those measurements independently.
This bounded repair does not make every name-keyed report statistic ID-safe.

Remove held-weapon inference from trace-less ShotResult measurement too. Those
shots remain Unknown. Keep one Unknown kill for an unattributed Frag so the
aggregate shots-per-kill denominator remains honest. Preserve accumulated
historical statistics when decoding an Observation, but never promote its old
name-keyed transient correlations (which may contain inferred weapons) into
trusted evidence. Use a new default-empty UUID-keyed cache with optional
distance, clear it at snapshot boundaries, and enforce partial supplied IDs
as strictly as complete IDs. Reject ambiguous legacy names using accepted
identity evidence, not the already collapsed per-name report tracks. Optional
distance and timing samples must not attach to an ambiguous identity.

## Verification

- Native serialization tests cover legacy and new events, omitted optional
  fields, and adapter event round trips. Exercise actual normal/teamkill,
  Arc, Blade and Rocket kills, switched/dead owners and untyped blasts.
  Retain self-hit, shield, plate and score behavior checks.
- Client tests cover duplicate names, removed pawns, malformed optional IDs,
  immutable relation/weapon facts, mixed-tier bursts, full admission lifetimes,
  overflow, ordinary round transitions and connection retirement.
- Replay the original complete ten-bot round with original ordered events,
  including pickups, taunts, streaks and round boundaries. Preserve legacy
  missing metadata and retain source digest/provenance. Record a new ten-bot
  round after metadata integration. Check exact schedule and actual frames.
  For mixed-tier routing, explicitly follow the original Scout Ant ID from
  recorded pickup events: four personal pickups should reach the voice lane.
  This is a declared replay viewpoint, not the recorder's original viewpoint.
  A free-camera replay would suppress every personal pickup and would not
  exercise that independence. Never inject those IDs into legacy Frag payloads.
- The baseline has 62 frags, peak six arrivals within 4.5 seconds, one pending
  row and at most 1,499 ms continuous-time admission delay. Three rows remain
  at RoundEnd 92,158 ms; the last expires at 96,603 ms. Advance the replay past
  that point, asserting zero rejected arrivals. Add a separate round transition while a row is pending, since
  the recording cannot detect that reset bug itself.
- Standings tests cover equal names with different teams/counters, exactly one
  YOU, duplicate legacy names with none, rename with stable ID, absent selected
  center score and 64-row Unicode scrolling. Inspect feed/board relation parity.
- Playtest tests cover explicit Rocket overriding stale Rail evidence,
  posthumous kills without positions, untyped blasts while holding Rail and
  two same-name victims. Do not reward unproven weapon inference.
- Inspect actual Sabotage, CTF and Conquest calls and captures of every tier at
  720p, including long names, populated equipment/vehicle/radio combinations,
  covered cards and newly accepted facts while hidden. Refresh and inspect the
  full tour. Preserve match.en.po bytes and existing player-facing protocol
  string literals exactly; additive enum fields, comments and tests may change.
- Run appropriate locked native tests, full client checks, independent review,
  PR/main CI and all three desktop package/install checks before publication.

## Completion and limits

Record final commands, counts, screenshots, PR, main CI and release receipts
here. Ship only when the replay retains every admitted frag's full lifetime,
the three tiers do not displace each other, relation styling agrees with the
board and objective calls are sequential and clear of the crosshair.
Human readability, physical-controller acceptance, performance on real GPUs
and final campaign acceptance remain distinct evidence gates.

## Cover and generation follow-through

The October 18 independent source review also identifies LoadingCard's opaque
full-screen layer 90 and MissionHud's centered recovery panel. LoadingCard can
remain visible after `_awaiting_map` becomes false, including the controls hold
or a loading failure. Use actual visibility until dismissal for all tiers.
Recovery covers the objective lane and must own draw priority over the call.

Do not treat a campaign gate-world MapInfo resend as a new mission generation.
GameManager already compares numeric map IDs for its load generation; campaign
variants can carry different prepared geometry within the same mission. Retire
voice and objective state only at the actual venue/mission generation boundary,
next-round start or session retirement as appropriate. Separate geometry/rules
refresh from event ownership. Preserve accepted frag lifetimes through ordinary
rounds, and preserve the final objective on entering Ended.

Consider a small shared pure FIFO timing owner for FragFeed and ObjectiveCall,
with their distinct visible/pending limits and lifetimes. Advance existing rows,
expire, then admit waiting rows; coverage advances neither collection. Rendering
and immutable payloads remain in each presentation owner. CombatFeed retains
its different latest-voice policy and first-draw Host ownership, rather than
being forced through the protected-frag queue. This is a candidate implementation
seam, not a requirement for a generalized notification framework.

The legacy identity index may retain at most 512 callsign entries per connection.
Keep a unique accepted ID or a permanent ambiguity marker for each entry.
On exhaustion, disable legacy fallback for the connection rather than evicting
facts and rediscovering false uniqueness. Present non-null optional IDs are
modern evidence: malformed or unmatched values do not become absent fields.
Actual UUID validation applies to those Frag fields, while accepted older actor
IDs remain compatible with their existing boundary. No extra roster history
is needed for current modern events.

First-draw callbacks must recheck current coverage, since a higher CanvasLayer
still permits underlying draw notifications. GameManager supplies an explicit
current-cover query; HUD combines its own regions without scene-tree scanning.
Keep the presented latch on the entry across control reconstruction. Loading,
role change, mission retry and disconnect must invalidate stale ownership.
Sabotage's result card already ducks and is accompanied by show_host_join;
assign that duplicate presentation's duck to the card, suppressing only that
voice row's duck token. Do not globally deduplicate equal strings.

## Native layout candidate probe

The private `probe_frag_layout.gd` rendered 520- and 560-unit columns at actual
1280x720 with the pinned engine, GL Compatibility and llvmpipe. Each row measured
40 logical units high with BODY 24 and a 32-unit glyph box. Equal-width expanding
name labels truncated TOWN SOCKET 02 and Dead Air Dan-2 despite unused space
beside their shorter partners. Measuring both natural name widths and donating
unused half-row space fixes that defect. Preserve a balanced ellipsis allocation
when the combined names exceed the available width.

The inspected 560-unit candidate fits TOWN SOCKET 02 plus Nightfall-2 with an
88x32 Sniper glyph box, and Scout Ant plus Dead Air Dan-2 with the literal rocket
fallback. The 520-unit candidate still shortens the former. Compare profiles at
72 and 88 units: 88 improves the retained thin rifle silhouette while preserving
those names at 560. Unicode and literal markup-like text stayed plain and
ellipsized. Candidate stills are frag-layout-72-probe.png and
frag-layout-probe.png. These isolated controls establish a starting geometry,
not integration with center objectives, actual frags or human readability.
Keep the final layout choice contingent on the composed tour.

For the starting 560-unit right lane, shrink the central fact reservation to
720 logical units at 1920 wide, leaving a real gap before the feed rather than
allowing the former 900-unit center to collide. Existing 24-unit Conquest names
still fit three 240-unit cells, subject to composed checks. A normal voice lane
starts below the 216-unit frag reservation and uses the space before the actual
radio stack. Campaign dispatch may retain its left-side context reservation;
mission stage cards on the right are explicit covers if they overlap protected
frags. Do not simply place new controls above every existing HUD child.

## Workspace HTTP dependency maintenance

The completed checker audit reports Rustls 0.23.45 against
[RUSTSEC-2026-0346](https://rustsec.org/advisories/RUSTSEC-2026-0346),
[0347](https://rustsec.org/advisories/RUSTSEC-2026-0347),
[0348](https://rustsec.org/advisories/RUSTSEC-2026-0348) and
[0349](https://rustsec.org/advisories/RUSTSEC-2026-0349). The upstream stable
[0.23.46 release](https://github.com/rustls/rustls/releases/tag/v%2F0.23.46)
patches all four. The CI advisory step is report-only, so green CI alone does
not establish an empty advisory report. Check it explicitly after this update.

Rustls is reached through reqwest in developer audiogen, brain and spritegen;
the all-target packaged server/adapter graphs contain neither Rustls nor yoke.
Keep TLS features, AWS-LC provider, certificate verification and session policy
unchanged. Brotli is absent and no custom session store or ECH setup was found.
Do not call advisory 0349 feature-disabled: AWS-LC still offers hybrid exchange
without prefer-post-quantum, though this build prefers classical exchange.

Official Cargo metadata checked October 18 identifies Rustls MSRV 1.71 and
Apache-2.0 OR ISC OR MIT, and non-yanked yoke-derive 0.8.4 MSRV 1.82 and
Unicode-3.0. These licenses are already allowed. Precise dry runs resolve only
the two patch updates. Review the actual lockfile diff and unchanged desktop
graph, run locked workspace and affected tools' offline HTTP/ledger tests,
then cargo-deny advisories/licenses/bans/sources. No paid provider calls.

## Implementation evidence in progress

- The native optional fields and separate Rocket provenance argument preserve
  existing combat semantics. Focused normal/teamkill, Arc, final Blade swing,
  posthumous switched-owner Rocket and untyped-blast assertions pass. The Blade
  assertion removes the retained range's campaign encounter roster to stage an
  actual arcade kill, preserving its plinth, finite use and fallback path.
- Independent native review found an ordering gap before the brain's own first
  accepted identity. Earlier unresolved roster history now disables legacy name
  fallback conservatively; direct IDs remain usable. Its regression passes.
- Queue/identity/presenter tests and the existing status-bar, combat-feed and
  standings harnesses pass. Wrapped standings settle with a bounded owned
  follow-up; controls rebuild only after accepted data/context changes, retaining
  scrolling. First-draw Host tests cover replacement, cover, reflow and retirement.
- The complete retained event extract is
  `client/qa/fixtures/busy-round-events-20261018.json`. Its source digest,
  native/client revisions and explicitly declared Scout Ant replay view are
  retained. The original 7,007,682-byte recording remains in private diagnostics.
  `test_event_replay.gd` passes all 62 frags at full admission lifetime, four
  personal pickups, peak one pending row, three visible rows at RoundEnd and
  post-result drain. A separate pending-row round/warmup transition also passes.
  Legacy Frag identity/weapon fields remain absent throughout the replay.
- The 92-test playtest library pass includes new contradictory-weapon,
  posthumous/no-geometry, duplicate-name/reversed-order, partial-ID, Unknown and
  historical-observation and bounded-cache cases. Existing
  serialized totals remain readable; historical transient guesses are ignored.
- Locked workspace clippy with warnings denied passes. The precise two-package
  lockfile update passes cargo-deny advisories, licenses, bans and sources.
  The all-target packaged server/adapter dependency graph is byte-identical.
- `match.en.po` remains SHA256
  `afa107dfb3891b71c21802919357c07c24e62b812e433213f9ef6e67e157c429`.
  `protocol.rs` outside the additive Frag block remains byte-identical.
- Private 720p composed GL Compatibility/llvmpipe captures show five frag rows,
  independent voice, center call, CTF/Conquest, radio and vehicle reservations.
  These are isolated populated HUD fixtures, not played or hardware evidence.

## Completed local acceptance, October 18

Independent native and client review found and verified repairs for modern-event
name ambiguity, historical position borrowing, lost timing history, wrapped
objective placement, Unicode row height, scoped voice ordering, spectator retry
ownership and a leaderboard layout callback resuming after HUD destruction.
Fresh UUID-owned snapshot receipts now own optional observer geometry. Losing
engagement history disables optional timing for the rest of that observation;
later hits cannot manufacture shorter samples. Historical aggregates stay readable.
The final review found no remaining consequential blocker.

`test_event_covers.gd` passes actual loading/controls/error, pause/settings,
console, story/results, mission recovery, departure and standings cover checks.
It verifies scoped voice, first-draw Host ownership, later identical arrivals,
single-duck Sabotage results, same-named local lives, spectator identity,
Conquest priming/change ordering and no-run/spectator retries. New wrapped-copy
and Unicode regressions use actual measured bounds. Immediate standings
open/update/free exits cleanly and retains ordinary scroll.

The fresh ten-bot recording lasts 103.238 seconds and has 78 frags, 14 pickups,
46 taunts, 32 streak events and five Host reactions. All 78 frags carry IDs and
resolved weapon metadata: 44 Flechette, 21 Rail and 13 Scatter. Its original SHA256
is `3f07b7890a7edb99dfba328eaf5e141682e90f50f573d8597e400d487f454b3d`.
The complete ordered extract, native base and exact tracked native-source patch
hash are retained in the modern fixture; the recording preceded the final
client/review-only edits. No source revision is invented for that working tree.

Both retained replays pass headless and rendered checks. The legacy rendered
run lasts 100.029 seconds, expires all 62 rows, reaches one pending and retains
three visible at result. The modern run lasts 113.251 seconds, expires all 78,
reaches two pending and retains four at result. Every admitted row receives its
full 4.5 seconds; non-frag traffic never evicts it and neither replay rejects a
pending arrival. Rendered replay is a flat-background HUD diagnostic. Actual
CTF, Sabotage and Conquest screenshots separately show live server-derived
calls. See the [capture receipts and captions](../screenshots/event-tiers-20261018/README.md).
The 33-state full tour passes and publishes fourteen inspected established stills.

Locked workspace tests pass: 2,166 tests across 55 suites, including affected
developer tools' offline provider and ledger cases. Workspace release build,
clippy with warnings denied and the explicit cargo-deny advisory/license/bans/
sources check pass. The first full client run found one stale audio-test HUD
double without the new reset method; its focused repair passes and a fresh full
run is pending. The checker correctly rejected its runtime errors despite an
otherwise completed suite. No production check was weakened.

| Local CPU correctness benchmark | Result |
|---|---|
| Arena Duel, seed 42, 16 bots, 1,200 ticks | Determinism and budget assertions pass |
| Session plus encoding tick p50 / p99 / max | 0.115 / 0.688 / 1.094 ms |
| Ticks exceeding the 50 ms budget | 0 |
| Context | Linux x86_64 release, concurrent unrelated work; no GPU or scale claim |

Remaining: clean final full client run, PR/main CI including coverage and all
desktop client checks, desktop packaging and publication. Work remains $0.
