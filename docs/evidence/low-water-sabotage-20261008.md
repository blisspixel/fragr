# Low Water Sabotage evidence

Status: implemented locally, 2026-10-08. Spend: $0. Map 8 is an original
five-per-side Sabotage town with Clinic Steps and Tram Stop. It has its own
built-in collision/layout, host selection, registered materials, markers and
site wording. Sector 9 retains its existing layout and timing assertions.

The [machine-readable receipt](low-water-sabotage-20261008.json) binds focused
sources, the tested socket executable, capture manifest and selected originals.
Diagnostics, commands and failed controls remain in
`.agents/low-water-sabotage-20261008/`.

## Mechanical evidence

The final focused runs pass 44 existing Sabotage cases, five new Low Water
cases, actual owned-child admission, desktop profile validation, the socket
admission test and the full socket match. Focused clippy passes with warnings
denied. The map tests prove 69 ordinary walking routes through both sites,
all stairs/bridges, supply claims and both retakes. Defenders take 6.0-8.4 s to
either site, attackers 13.35-15.8 s, and cross-site retakes 9.3 s. These
measurements describe these fixtures, not human balance.

Both sites pass ordinary finite human planting and defusing, including cancelled
work. Actual Tack fire kills a carrier; the charge drops, refuses defender
pickup, remains unavailable through nine ticks beside a waiting attacker, then
permits contact recovery on tick ten. Two normal finite rule-bot matches finish
with combat, plants, defuses, carrier drops and side swaps. Final seed 71
finishes eight rounds in 9,445 ticks with 51 frags; seed 72 finishes ten rounds
in 10,911 ticks with 65 frags. UUID ties are not frozen, so these are completed
measurements rather than bit-identical replay claims.

Ten ordinary WebSocket participants (five Human, five Agent) finish a normal
short match in 5,108 ticks. They start with Tack and 50 finite rounds; Humans
have 12 loaded. Four actual plants are defused, the sides swap, and the former
defenders plant the fifth charge and let it detonate. The actual winner is
coalition, 5-0, with five plants, four defuses, one detonation and zero deaths.
The driver sends ordinary movement, aim and held Use through the shared
controller/navigation. It does not fire or alter poses, HP, clocks or outcomes.
Separate native bot and carrier tests provide actual combat evidence.

## Inspected renderer evidence

All eight original 1280x720 states were inspected at original size from the
same socket match. Godot 4.7.2-stable used OpenGL compatibility on the local
AMD Radeon 780M. Exit is zero and the retained renderer log has no ERROR or
WARNING. The client stayed a spectator, including the first-person view that
followed the actual defuser.

- [Town and three crossings](../screenshots/low-water-sabotage-20261008/overview.png)
  shows the original clinic/market/depot geometry and ten-player HUD.
- [Clinic Steps](../screenshots/low-water-sabotage-20261008/clinic_steps.png)
  shows the proper site name, civic control prop and supported plant disk.
- [Tram trench](../screenshots/low-water-sabotage-20261008/trench.png)
  shows dry floor, stair access and standing clearance beneath a bridge.
- [Actual defuse](../screenshots/low-water-sabotage-20261008/defusing.png)
  shows held-use progress on the planted charge.

The other originals show Tram Stop, the walking carrier, the planted charge
and the actual defused round card. The carrier's small satchel is not clearly
readable from its retained front angle. The native proxy buildings and existing
material kit are playable presentation, not final-art acceptance.

## Remaining gates

Human enjoyment, two-machine side-swapped LAN play, other-platform execution,
packages and voluntary rematches remain separate gates. This receipt does not
establish those outcomes. Failed initial warmup and class-import attempts remain
retained and are excluded from the clean-pass results.
