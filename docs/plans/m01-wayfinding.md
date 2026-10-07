# Recall Notice wayfinding

Status: **implemented** (2026-10-06). Local client evidence. Not merged. The night process does not need a restart: the card, the bearing, and the console words are drawn by the client. A packaged build does not have them until a release.

## Goal

A player walking Recall Notice should know Latch's file is in transfer control, after dispatch, and still have a direction after the objective card leaves.

## Non-goals

- The eight-second objective card still leaves. A repeated mission packet must not bring it back.
- No waypoint path, breadcrumb, or door puzzle. The corner line is a straight bearing and can point through a wall.
- No change to use distance, the cone, or which panel the server accepts.
- Ordinary counters keep TRANSFER QUEUE. Shared records signs stay as they are.
- No tour republish, no commit, no night-binary restart, no roadmap edit.

## Why the floor felt like a loop

The card said the record was on the records mezzanine. That room is early. The console is in transfer control, which you enter from dispatch, after reception, the stacks or the bypass, sorting, and dispatch. Counters along the way share one terminal label, so they look like the objective. The card then hid, on purpose, and nothing replaced it.

## Rules

- The find-record card says the file is in transfer control, after dispatch.
- After that card leaves, and after the lift card leaves, a top-center line names the goal. It hides while the card is up, while a use prompt or an aim hint is up, and for a spectator.
- AHEAD, LEFT, or RIGHT comes from feet and yaw toward the record approach, then toward the departure approach even before the party is aboard. The word drops inside 3 m. Unknown facing shows the goal without a direction. Positive yaw is a left turn: yaw 0 faces +X and yaw pi/2 faces +Z.
- The mission record decoration, and only that terminal, reads LATCH'S FILE / READ THE RECORD.

## Verification

Godot 4.7.2.stable headless, after `--import`, exit 0, no script or parse errors:

- `test_mission.gd` PASS. The find-record card names transfer control and does not say mezzanine. The card still leaves after eight seconds, and a repeated packet does not reopen it. The lift bearing stays once that card is gone. A legal prompt replaces the bearing. Facing the record reads ahead; a positive turn reads left and a negative turn reads right. Inside three metres the direction word leaves. A spectator gets no bearing. Briefing and departure stay on their cards.
- `test_map_decoration.gd` PASS. Only the marked terminal uses Latch's file. Another terminal stays a transfer queue. A marked index does not retitle the lift control.

## Spend

None.
