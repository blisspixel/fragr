# Combat notification polish

Status: implemented and locally verified; integration pending, 2026-09-20. Spend: $0.

Deathmatch previously put frags, pickup announcements, chat, streaks and pressure
events in animated labels near the reticle. Routine events overwrote one another
and delayed hides could dismiss newer messages. Nick requested a quieter view.

Route routine combat information through one bounded, expiring corner feed.
Use plain text, a small fixed row count and no bounce or full-screen flash.
Pickup notices belong only to the local or spectated participant, matched by
server player ID. Other players' frags and streaks must not shake a human camera.
Keep the reticle area clear during active play. Round starts can have a brief
banner, and round results retain their authored summary. Campaign objectives,
damage feedback and server outcomes remain unchanged.

Own presentation in `hud.gd` and the existing HUD scene; identity filtering stays
in GameManager's event routing. No wire change, preference framework or new package.
Test burst expiry, bounded rows, no central routine messages, and player-ID
filtering. Re-run client checks and inspect live deathmatch, spectator and
campaign captures. Refresh the release gallery before integration.

## Implemented and verified

`combat_feed.gd` owns three plain-text entries, each expiring independently after
three seconds. There are no delayed hide callbacks or bounce animations. GameManager
filters pickup notices by participant ID and no longer shakes the camera for every
frag or streak. Round start lasts one second; the warmup screen clears immediately.
Round results keep their summary with one owned expiry timer. Episode 0's distinct
authored objective presentation remains separate.

All 30 Godot harnesses pass, including burst limits, independent expiry, duplicate
callsign filtering, spectator identity, unchanged aim during other players' events
and result-banner ownership. The 23-state published tour, full fourteen-state M01
route and an actual completed round on Directive 17 Substation pass with clean
logs. Inspected first-person, spectator, shot-sequence and result views confirm
routine notices occupy the upper-right corner and leave the reticle clear.

Receipts: `.agents/stats-hud-godot-final.log` and
`.agents/qa/stats-hud-{arena,m01,round}-20260920/`. The current gallery is in
`docs/screenshots/`. Current arena geometry and character art still need their
planned production passes; these checks do not establish a finished game.
