# M02 side-ward evacuation evidence

These three first-person frames come from the 27-state Standard tour in
`client/qa/m02-evacuation.json`, captured on Windows with Godot 4.7.2-stable,
OpenGL compatibility, and an AMD Radeon 780M. The tour uses the bundled M02 map
and an actual local server. Its manifest and logs are retained under the
ignored `.agents/qa/m02-evacuation-final-marker/` directory for local review.

| Frame | Observed state |
|---|---|
| [Ward departure](ward-moving.png) | One of two freed captives passes the player's view while the server reports movement toward the dock. The second is farther along the route. |
| [Floor wait](floor-wait.png) | Both captives wait behind the west wall while the dock encounter remains active. |
| [Dock arrival](dock-arrival.png) | Both captives have reached the loading exit; the server reports evacuation complete. |

The tour asserts server phases and positions, then departs through the ordinary
mission door. It is scripted authoring evidence. It does not establish
fresh-player route readability or a finished M02 art pass.
