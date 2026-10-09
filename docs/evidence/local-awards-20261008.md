# Local awards and appearance, October 8

Status: implemented locally. This is the bounded increment for
[#197](https://github.com/blisspixel/fragr/issues/197), owned by the
[difficulty and rewards plan](../plans/difficulty-and-rewards.md).
Integration, full-campaign rewards and final tier acceptance remain separate.

Two stable award identities consume validated human records from an owned local
durable mission: completing Recall Notice, and discovering an authored secret.
The existing service-record writer now stores version 3, with bounded award
proofs independent of its 256-entry history and three appearance selections.
Version 1/2 history loads without invented historical awards. Unknown formats,
invalid proofs and unavailable choices fail closed. A failed replacement retains
the prior committed generation; failed appearance saves roll back the selection.
Pending award notices wait for a successful save and issue once.

The callsign page opens localized criteria, locked previews and title, emblem
and gun-finish selectors. Standard and oxide are immediately available. The
secret unlocks margin teal; M01 completion unlocks ON FILE and the transfer stamp.
The enclosing callsign draft survives visiting this page; appearance Cancel
discards its own preview. Finishes use the existing firearm textures and frame
timing. The benchmark explicitly restores standard. Combat, wire and run-file
formats remain unchanged, with no dependency or paid asset request.

## Actual earning and persistence

An isolated owned Standard M01 process completed the sixteen-state route in
`client/qa/earned_rewards_live.gd`, using ordinary participant actions. The secret
proof arrived at tick 246 while the run was active; completion arrived at tick
2,973. The authoritative record reports 2,911 elapsed ticks, twenty kills, one
secret, no deaths, no HP lost and fifty armor lost. The profile then saved and
reloaded the selected title, emblem and finish.

All sixteen original stills were inspected. The departure image is story page
one of three, not the result statistics. Counts come from the retained record,
not visual inference. That capture precedes later persistence-error, notice and
profile-navigation refinements and the shared QA retirement drain. The final
presenter checks below cover the listed final source. The
[machine receipt](../screenshots/earned-rewards-20261008.json) binds the native,
private record, manifest, logs and final source hashes without publishing the
private profile.

Fifteen retained live enemy phase originals were also inspected. Clerk lesson
windup/hit and file-stacks Sweeper windup/hit clearly show their respective
characters and feedback. Images named `dead` capture the lethal transition
while the sprite remains upright; they do not prove a settled corpse pose.
The named Sweeper recovery still mainly shows a Clerk beside cover, so that
phase remains a manifest observation rather than clear visual pose evidence.

## Final presentation and failure checks

The same earned profile was loaded into current presenters on OpenGL
Compatibility and Vulkan Forward Mobile, Godot 4.7.2-stable on Windows with an
AMD Radeon 780M. Each run passed with exit zero and clean logs. Actual images are
1280x720 for earned/locked menus and 960x360 for eleven idle, fire and Shotgun
cycle comparisons. OpenGL originals and selected Vulkan comparisons were
independently inspected. Labels, selectors, preview and Save/Cancel fit; the
locked finish previews with Save disabled.

Rendered pixel controls prove dark neutral metal changes while warm, bright,
colored-light, transparent and lower-grip controls stay exact. Every alpha texel
remains exact, and output luminance differs by less than 0.005. The original
gloves, warm muzzle flashes and cyan Rail energy remain readable. Static sheets
do not establish complete first-person motion or final art acceptance.

Focused checks cover actual eligibility, all tiers, source/role refusals,
duplicate/retry/reconnect ingress, history eviction, migrations, corrupt-newest
recovery, future-format refusal, unavailable choices, write failure/retry,
deferred notices, navigation and benchmark isolation. The composed client run
caught an older benchmark fixture with no HUD. It now supplies the real HUD and
asserts the standard-finish reset alongside console closure; the focused check
passes. The original failed combined log is retained.

An initial review inherited fullscreen preferences and the project's larger
logical canvas. Final QA isolates windowed preferences, asserts image dimensions
and matches the comparison canvas to its output. Initial files are retained
privately, not selected as final evidence.

The [M01 finite-supply receipt](m01-finite-supply-validation-20261008.md) covers
both routes, three tiers, human magazines and finite agent ammunition with
periodic resolved misses, plus actual enemy deaths and continue exhaustion.
These automated routes do not settle fresh-player comprehension, pacing, fun or
final tier balance. Campaign-completion and gold rewards require the actual
finished campaign. No new cash or included asset credits were consumed.
