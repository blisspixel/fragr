# Fight feel: pressure, heads, radio, scope

Status: **in flight** (2026-10-06). Local only. Not merged. The running night process does not have it.

## Goal

Campaign Clerks, Sweepers and Heavy Sweepers stop planting between bursts. A traced pellet in the head band deals double damage. Radio and scope are obvious on a keyboard, and scope still works as a held mouse button.

## Non-goals

- No new pathfinder, no idle pacing for a guard that was never alarmed, and no change to Turret, Ranged Sweeper, Notary, Crawler, Jammer, Enforcer or Auditor attack rules.
- Windup and firing stay planted, so a committed shot can still be dodged.
- No difficulty-timing change, so `CAMPAIGN_RULES_REVISION` stays put.
- Reloads are a separate capability. This slice does not put magazines back.
- No tour republish, no commit, no night-binary restart.

## Rules

- During Recovery, while a live target is in sight, a Clerk, Sweeper or Heavy Sweeper strafes. Farther than 8 m, it also steps forward. Seated clerks stay seated. Hit stun stays planted. The Heavy's existing post-recovery shuffle remains.
- The client plays the walk cycle when that recovery actually moves. A still recovery keeps the settle pose.
- Head band, standing fighters: impact from 1.45 m above the feet through the top of the volume. That is above the 1.22 m chest and includes an eye-level ray at 1.6 m. Crawler and Notary: the top quarter only, so centre mass is a body shot.
- The bonus is 2x per pellet, saturating, inside the victim damage sum. Fists and the Shiv stay flat. Armour, the Auditor plate and Licence to Kill still apply after the sum.
- Radio defaults: C station, N skip track, M play/pause. The d-pad is not radio. Scope stays right mouse and Z, hold, Sniper Rifle only. The loading card and the console say so.

## Verification

- Enemy unit test: close strafe, far close-in, seated and stun and windup stay planted, turret recovery stays planted, an unalarmed guard stays put.
- Head geometry test, plus a sniper body shot at the chest, a level sniper shot at the face, and a fist at face height.
- `solo_controller_finishes_actual_m01_with_combat_and_open_gate_retries` was re-run after magazines. It still departs. Deaths stay 2: the injected lift death, plus one in the sidestep fight. Attempt 3, one continue left. The in-process controller is unarmed, so reload did not add a death.
- `walking_guards_sidestep_between_bursts_and_stay_planted_on_the_tell` and `a_level_shot_at_the_face_doubles_and_a_chest_shot_does_not` passed again after the recovery action was written as one literal.
- Godot `test_equipment.gd` and `test_enemy_animation.gd` passed with the recovery walk frames. The atlas layout did not change.

## Spend

None.
