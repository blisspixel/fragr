# M02 Crawler descent, scripted visual proof

These five unedited 1280x720 frames were captured by the pinned Godot 4.7.2
client on an AMD Radeon 780M through a live local Standard-difficulty M02
session. The QA driver sent ordinary human inputs; the Rust server resolved
movement, enemy phases, shots and HP. This is directed authoring evidence,
not a fresh-player difficulty or fun review.

| Frame | Exact capture source | What it shows |
| --- | --- | --- |
| [Cue before clear view](cue-before-clear-view.png) | `.agents/qa/m02-crawler-final-proof/06_crawler_scrabble.png` | Live localized scrabble caption at the switchback, with only part of the low chassis visible past the pillar. |
| [Solo crouch tell](solo-crouch-tell.png) | `.agents/qa/m02-crawler-final-proof/crawler_solo_crawler_windup.png` | Low crouched body and red tell, captured after the server windup began and the camera faced it. |
| [Solo locked leap](solo-locked-leap.png) | `.agents/qa/m02-crawler-final-proof/crawler_solo_crawler_leaping.png` | Side-profile leap on the grounded landing. The scripted first encounter kept authoritative HP at 100 through recovery and defeat. |
| [Pack, first person](pack-first-person.png) | `.agents/qa/m02-crawler-spectator-final/crawler_pack_crawler_windup.png` | A low Crawler in front of the taller Sweeper during the later pack fight. |
| [Pack, detached observer](pack-detached-observer.png) | `.agents/qa/m02-crawler-spectator-angle/08_crawler_pack_spectator_world.png` | An authored free camera above the raised landing showing three low Crawlers at separate depths and a Sweeper. This was not a separate spectator-role client. |

The 14-state M02 route reached departure and asserted the lone Crawler's
windup, leap, recovery, missed contact, and later four-enemy pack. Its
detached camera state required all three named Crawlers and the Sweeper to
be alive at capture. Timing changes which bodies overlap in a single still;
the motion strips and live manifest remain under `.agents/qa/` for local
review. Caption routing and audio loading were tested, but no human listening
or muted-sound readability trial has been recorded. A player unfamiliar with
the route still needs to test the warning, dodge and Shotgun response.
