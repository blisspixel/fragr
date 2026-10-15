# Launch Authority presentation integration

Status: **implemented**, 2026-10-15. Local evidence below; the linked integration
plan owns composed checks and shipping. Follows the existing campaign rung and the
[M14 integration](m14-launch-authority-integration-20261015.md), using retained
assets and local geometry at $0. No generation, cash charge or quota consumption.

Free authenticated checks on 2026-10-15 retained in
`.agents/launch-authority-20261015/` report 1,870 Meshy credits available,
the existing 15-credit hold, no local pending reservation and 1,855 usable
(reported reset 2026-11-03 20:34:13 UTC).
ElevenLabs reports active Pro, 24,979 of 1,185,132 included credits used and
1,160,153 remaining (reset 2026-11-06 14:51:20 UTC), with zero current overage.
Its extension fields report `can_extend=false`, `allowed_extend=true` and a
250,000 maximum extension; no extension or overage was enabled by this work. No
unattributed account decrease is assigned to this work. The native Higgsfield
API check verifies the credential and its default payload price estimate only;
its dollar balance remains unverified because the checker has no documented
balance endpoint configured. These checks submitted no generation and consumed
no credits or cash.
Any later production still requires the exact native operation preflight,
retained holds and existing caps. This presentation batch remains $0.

## Scope

Build `m14_launch.gd` at the existing mission-presenter seam:
`configure_map(info)`, `apply_state(state)` and `clear_map()`. The native mission
owner supplies the five registered Walker solids and the fallen-world flag.
Build the wreck from those accepted fallen bounds after the server has drained
committed shells and removed live Walker registration. No local collapse timer,
damage result, party outcome or speculative wreck collision is introduced.

Reuse the current Walker's angular steel, restrained issued red, cooling ribs,
joint castings and artillery sockets. Improve its live relocation mechanisms
with rigid piston travel inside the registered columns. Grounded feet remain
grounded; genuine lifted-foot gait requires compatible native geometry first.

Use existing launch gantry, lander and registered service surfaces to make the
depot-to-pad route legible. Place practical coalition cargo and service detail
within those hosts, preserving walking, driving, firing and interaction space.
Pad lamps change only with accepted mission progress. Fitted world signs use
localization keys and remain depth-tested. No new cast identity, mandatory
driving, magical technology or assumed machine personhood.

## Acceptance

Verify invalid and stale facts cannot change presentation; intact/fallen map
changes remove old nodes and resources; fitted wreck parts stay inside the five
native solids; relocation mechanisms stay inside their native leg columns.
Inspect ordinary player-height intact, relocation, recovery and fallen views
against Mars exterior light, including silhouettes and warnings. Compare both
supported renderer paths in coordination with the composed mission capture.
Controlled fixtures stay distinct from ordinary mission completion and hardware
performance evidence. No final gait or final mission acceptance is implied.

## Overlook report

The accepted brief's Mara line is implemented as a localized, nonblocking
combat-feed notice on an observed transition to `approach_secured`: "Mara
(radio): Site two is ours. Site four is ours." Two small, slowly rising and
fading flare shapes appear sequentially beyond the map's playable bounds.
They add no collision, light pulses, voice, camera shake or network facts.
The existing three-second notice remains available with audio muted.

The presenter retains its run/attempt identity across same-contract MapInfo
refreshes, refuses stale/invalid progress, suppresses catch-up on late first
hydration, and permits the beat again on a fresh retry. Clear/fallen worlds
retire the effect. Focused `test_m14_presentation.gd` passes these transitions,
sequential timing, outside-bound geometry and cleanup, with evidence in
`.agents/m14-overlook-tests.log`. The normal route clears the approach before
entering Walker activation, but a player already inside that region can activate
the Walker at the same transition. This presentation does not delay authoritative
combat, so exact report-before-stomp ordering is not guaranteed. The authored
berm-top staging and final audiovisual acceptance remain separate gates.

## Implementation and controlled review, 2026-10-15

Implemented the three presenter methods in `client/scripts/m14_launch.gd`.
Fallen hull sockets, cold optics, cooling ribs and folded joints fit the five
registered bounds, including translated fall positions. Pad and gantry lamps,
service signs and nine restrained cargo modules bind only to exact retained
host faces. The live Walker uses rigid rods, fixed sleeves and small crank
rotation driven by accepted relocation distance. Its feet remain grounded.
The Vulkan inspection also exposed coplanar cabinet and cooling-rib faces;
separating those surfaces inside the existing torso bounds removed the conflict.

Focused `test_m14_presentation.gd` and `test_walker.gd` pass geometry, invalid
input, rigid motion and node-retirement checks. The controlled review at
`.agents/m14-art-20261015/{opengl3,vulkan}/` contains fifteen views per renderer,
including eight successive relocation samples, three wreck angles, the retained
launch approach, cargo and held/released control signs. Both use isolated X11
with software llvmpipe, not vendor GPU performance evidence. Review receipts
record source hashes. The released-light fixture explicitly sets a visual state;
it does not prove native mission progression. Native-golden presenter checks
now pass all eight actual fixtures, including committed-shell drain, fallen
map handoff, departure and retry. They reject facts from the other geometry,
reject the malformed native fixtures and bound every wreck mesh against the
actual fallen map. Complete ordinary-route evidence is recorded below.

Added the reader-paced `m14_arrival` and `l14_l15` scene manifests, catalog
entries and keyed copy. They establish the same-afternoon launch assault,
optional jeep or trenches, settlement supplies, Tern's repair invoice and the
canonical nine-day fleet journey to Earth. No M15 gameplay is implied. All five
pages were rendered and inspected at 960 by 720 in the existing scene player;
`test_story_scene.gd` passes manifest, caption and fallback validation. Evidence
is under `.agents/m14-art-20261015/story/`. These text pages need no generated
image, voice or video asset and consumed no service quota.

Connected route support now records accepted `m14` facts in `qa_tour.gd`,
compares the ordered objectives, staged support, first-cycle/fallen flags,
jeep identity and four challenge receipts, and recognizes completed M14 Use.
Unknown `expect_m14_*` names fail validation so a misspelled assertion cannot
silently pass. `test_qa_m14.gd` checks malformed types, ranges and objective
order through the tour's real boundary; it and the prior M13 route harness pass.
The install resource check now includes both M14 scene manifests. The
`client/qa/m14_launch_authority.json` routes an ordinary human through finite
supplies, the depot, road, berms, Walker/support battle and terminal Use. Its
separate `qa_m14.gd` probe prioritizes actual support bodies and retains an
artillery escape destination until accepted flying shells drain, including
after disable. It never grants resources, relocates a player or forces a
phase. Native ordinary route evidence guided the rendered iterations below.
The isolated Walker range helper is unchanged. Manifest validity alone is not
route acceptance.

## Ordinary route iteration

The retained `live-opengl1` through `live-opengl11` runs under
`.agents/m14-art-20261015/` separate controller and capture failures from game
balance. Early probes paused for a supply still inside an active encounter,
strafed off the freight stair, or used a ground-side search for the occluded
roof Turret. The corrected route clears the depot before collecting its
launcher, uses the authored stairs and takes the broad northern lander circuit.
The final central control approach uses a clear west-to-center segment, not
the narrow full-width gap between guard cover and gantry piers.

Actual shot receipts also exposed stale moving aim while the generic combat
probe captured expensive frames. The depot probe first followed the successful
native stationary-fire policy, then restored ordinary tell evasion after the
bounded capture interval was available. No damage, ammunition or enemy timing
changed.
The dedicated Walker probe keeps ordinary movement active through support
windups and continues until the final gantry guards are cleared, so a still
cannot interrupt the transition into their attack. The thirteenth capture
state separates repair supplies from the earlier active road encounter.

Run 10 completed the Walker and both support waves with 100 HP and ten actual
reload deadlines, received the native fallen-map handoff, and displayed the
registered low wreck. Its subsequent final-room capture pause killed the
participant, so it is partial fight/presentation evidence, not full mission
acceptance. The retained warning, recovery and fallen frames were inspected
against actual Mars terrain and gantry geometry. The later continuous-battle
runs below supply complete ordinary-route evidence on both renderer paths.

The generic combat probe now accepts a strictly typed optional capture interval
from 150 to 2,000 ms. Its existing 150 ms default and immediate phase captures
remain unchanged; M14 requests 1,000 ms to reduce interference with ordinary
aim updates. Success and failure receipts retain actual control-loop mean,
maximum and bounded individual intervals. Both the combat harness and the
manifest boundary tests pass, including malformed-option rejection. The
continuous M14 probe conserves finite Rifle ammunition for guards by firing at
Walker joints during accepted recovery, instead of exhausting the bag on plate
chip damage. These are probe policies, not changes to combat rules or supplies.

The complete ordinary OpenGL route passed in `live-opengl12`: all thirteen
states, six combat objectives and fresh terminal Use reached `party_departed`.
The participant finished with 100 HP, 12 armor, 34 Bullets, 36 Shells and three
Rockets. The continuous Walker/support/gantry segment retained fifteen actual
reload deadlines and twenty-four phase frames, with 100 HP throughout that
segment. No resources, positions, phases or outcomes were overridden. The
preserved native binary SHA-256 is
`f988abd4be6d1603120d4a7f7b7b48d7218dc131a53b3200df3b9e8dfdf4fef5`;
`source-hashes.txt` binds the route and presenter sources for this receipt.

The full route contact sheet, all phase frames and selected full-size warning,
recovery, fallen and departure views were inspected. The published
[Walker warning](../screenshots/m14_walker_warning.png) is the accepted run's
`artillery_warning_3650.png`; the [fallen gantry](../screenshots/m14_fallen_gantry.png)
is `fallen_4048.png`, immediately after the native fallen-world handoff, while
the final gantry guards still require clearance. Both are actual play frames,
not reference illustrations. The chunky machine, visible joint signals,
registered low wreck and restrained Union markings fit the Mars yard. This
remains development art, not final character or environment art acceptance.

Measured generic combat-loop means in this run were 158.65 ms at the depot,
53.19 ms for road Notaries, 47.66 ms at the berms and 32.52 ms for the bend
Turret; maxima were 513, 103, 248 and 62 ms respectively. These are the probe's
actual loop intervals on software rendering, not hardware frame-rate claims.
Earlier capture-sample spacing does not establish an earlier control rate.

The first Vulkan route retained a bounded search failure at the depot: the
participant remained alive at 100 HP and 60 armor with four guards cleared,
but the east Clerk's remaining 10 HP was occluded from the roof endpoint.
The route now adds a seven-metre ground-side sweep before the roof stair,
outside the next encounter trigger. A second Vulkan attempt died while firing
stationary at the depot; its measured loop mean was 80.44 ms with a 231 ms
maximum. The depot probe now enables the existing ordinary tell-evasion policy
alongside the bounded capture interval. Assertions and deadlines are unchanged;
the strict route harness passes.

`live-vulkan3` completed the thirteen-state ordinary route and terminal departure
with 100 HP, 74 armor, 86 Bullets, 36 Shells and three Rockets. Its continuous
Walker/support/gantry segment retained fourteen reload deadlines and eighteen
phase frames, again with 100 HP throughout that segment. The full route sheet,
all phase views, full-size recovery vents and final terminal were inspected.
The terminal now reads `LAUNCH CONTROL / DEPARTURE CONSOLE`, consistent with
the overhead released-pad sign. Both complete routes used Godot 4.7.2 and Mesa
llvmpipe on owned Xvfb displays. This establishes two software-renderer paths,
not hardware or vendor performance support. Vulkan's measured combat-loop means
were 76.36, 58.36, 47.71 and 46.67 ms in the same encounter order; maxima were
715, 127, 230 and 85 ms. The full raw receipts remain available.

Vulkan's process exited zero after the completed route, but scene retirement
logged two `indexing did not unpair geometries from light` errors. No clean-log
claim is made for that run. The exact signature matches the documented
[Godot layer/light-pairing issue](https://github.com/godotengine/godot/issues/121989);
the local triggering path was then isolated with actual native intact/fallen
worlds and the actor-only ViewFill. Retiring that light reproduced both errors
before any world deletion. Omitting M14Launch retained the failure; omitting
ArenaCover removed it. Preparing cover geometry off-tree also removed it.

The narrow shared fix prepares ArenaCover's replacement subtree with final
world layers before live attachment. It retains the root, direct child names,
local transforms, registered solid indices, host metadata and same-map early
return; existing children retire only after successful preparation. No global
layer masks, engine pin, collision or gameplay changed. The real
`SceneTree.node_added` regression checks every new cover visual already has
its final world layer. Map geometry, decoration/locale, ship furnishing,
island water, movement goldens, M14 presentation and QA checks pass. The exact
Vulkan reproduction now exits cleanly in `retirement-fixed/client.log`, with
all failed baselines retained. Final native fallen/terminal presentation
fixtures under `cover-final-opengl3/` and `cover-final-vulkan/` separately check
the revised construction and released-pad copy. The completed ordinary route
remains a pre-fix gameplay receipt, not retrospectively a clean teardown run.

Mara's report and horizon flares were not visible in the ordinary route's
retained transition stills. Separate controlled reviews under
`.agents/m14-art-20261015/mara-opengl/` and `mara-vulkan/` passed with clean logs.
They use the actual native map and accepted approach state, an explicitly
derived predecessor, and the real CombatFeed with its normal three-second
lifetime. Five views at 0.2, 2, 4, 8.5 and 10 seconds verify the readable two-line
report, sequential rise and eventual removal. From the tested west approach
at `[-16,1.7,-9]`, the right flare reads as a small warm point and trail; retained
launch architecture occludes the left flare. These are presentation fixtures,
not a second ordinary mission proof. Final authored-overlook staging and
two-flare sightline acceptance remain open.
