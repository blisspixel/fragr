# M01 opening and weapon input regression

Status: **implemented** (local evidence, 2026-09-23)

## Goal

Resolve the live M01 observations that an introduction card returned after it
left and key 1 did not switch the carried pistol to fists. Establish which
overlay returned, whether a live key event enters the action sent to the server,
and whether the authoritative selection changes.

## Scope and ownership

The five page story is `CampaignOpening`; GameManager owns its once per session
handoff. `MissionHud` owns the smaller phase card. `EquipmentState` maps owned
slots, GameManager gathers input, `NetClient` sends the discrete action, and the
server selects an owned weapon. Keep authority and the existing wire shape.
This task does not rewrite the story, change mission phases, or add weapons.

## Verification and acceptance

- Use real Godot key events to test key 1 from a validated M01 loadout with
  pistol selected, including the action that reaches `NetClient` and the
  authoritative response when practical.
- Test that later MapInfo for the same mission does not recreate the five page
  opening, while a changed mission phase may show the objective card for its
  documented eight seconds.
- Run focused Godot harnesses, the full headless checker, and an owned local
  server smoke if input behavior changes. Inspect any rendered evidence.
- Record proven cause, observed limits, commands, and next step here and in
  the roadmap. No paid calls or human acceptance sessions.

## Spend and safety

Local tests and owned server are free. Do not call paid services. No protocol
or combat authority changes are planned. Preserve the dirty root worktree.

## Initial evidence

The existing `test_equipment.gd` checks key 2 and wheel cycling but does not
press key 1 through a transmitted action. `test_mission.gd` covers phase card
expiry, not MapInfo after an opening completion. The live observation in the
roadmap does not identify which of the two cards returned.

## Findings and validation

The two presenters have different lifetimes. `CampaignOpening` is the five page
story and `_opening_finished` prevents a same-session MapInfo refresh from
creating it again. `MissionHud` displays the smaller objective card for eight
seconds after `find_transfer` or `reach_lift` begins. Repeated state in one
phase leaves an expired card hidden; a new phase introduces its own card. The
briefing and departed cards stay up while those phases hold. The earlier live
note has no capture or phase log identifying which card appeared, so its cause
cannot be assigned retroactively. The phase card is a plausible explanation,
not proof of that particular observation.

`test_local_campaign.gd` now starts an owned local server, dismisses the story,
replays MapInfo through the live manager, walks from an entry spawn to the
pistol, and sends a real Godot key 1 event. The private authoritative loadout
changes from `tack` to `fists`, followed by the public snapshot's `Fists`.
`test_equipment.gd` also confirms the key queues one `weapon_swap: fists` action
and does not repeat it. The first movement harness missed the pistol because
it stayed two metres to one side and walked into combat; the corrected harness
centres on the authored pickup before moving forward. This was a test route
error, not a weapon-selection failure.

Focused `test_equipment.gd`, `test_mission.gd`, and the owned-process
`test_local_campaign.gd` passed on Godot 4.7.2-stable, with a release server
built using `cargo build -p fragr-server --release --locked`. No runtime code or
wire contract changed. The original live key 1 failure was not reproduced by
these checks; a fresh in-game report would need the exact overlay and control
state to isolate a narrower condition. Automated coverage remains the current
acceptance evidence; human acceptance is deferred until near 1.0.

The full `tools/godot_check.sh` passed after import, script parsing and all
client harnesses. `tools/test_godot_check.sh` passed its injected exit,
diagnostic and missing-marker cases. `git diff --check` passed. No rendered
tour was needed because player-facing code and assets did not change. The
The regression tests and wording were reviewed before integration. A new
reproducible input or overlay trace would justify a separate runtime fix.
