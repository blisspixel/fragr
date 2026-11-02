# Privacy

**Status:** fun metrics are implemented and off by default ([#529](https://github.com/blisspixel/fragr/issues/529)). The project receives nothing from anyone, and the only records are on your own machine and in a server's console.

The Union keeps a file on everyone, forever, in triplicate. Local Exception keeps a tally
of how often the Rifle wins, only if the host asks it to, and shreds even that
after 67 days.

This is the whole policy. It applies to the game, the server, the agent adapter,
the example brain and any server the Local Exception project itself ever hosts.

## The game never phones home

- No accounts, no ads, no trackers, no analytics libraries, no crash reporter
  that uploads anything. The client and server send nothing to the project.
- Your service record, settings, saves and benchmark results stay on your
  machine. Delete the files and they are gone.
- Nobody sells, rents, trades or gives away player data. Not the project, not
  for money, not for favours, not ever. There is nothing to sell, and that is
  the point.

## The server console

A running server prints an operational log to its own console so its host can
run it: who joined by callsign, rounds and frags, and the address of a
connection it refused (for flood and abuse defence). Local Exception does not write that
log to disk or send it anywhere; a host who saves their console output owns it.
Join tickets and resume tokens are never logged, and `/status` never shows an
address, callsign, id or token. Fun metrics never read the console log.

## Fun metrics: a host's own tally, off by default

A host may turn on fun metrics to see how matches on their own server actually
play, so maps, weapons, bots and pacing can be tuned against real games instead
of bot games. They are off unless the host switches them on: `--fun-metrics` on
a dedicated server, or **Fun tally** under the desktop host's more
options. Campaign runs never record them; a mission keeps its own run file.

When they are on:

- **What is recorded is about matches, not people.** Map, mode, rules and bot
  tier; round and match length; frags a minute; lead changes; each weapon's
  share of shots and frags and its kill distances; time to kill; time from
  respawn to first contact; spawn deaths; pad pickups; Sabotage and Conquest
  outcomes; server tick health. Counts and timings per match, never a timeline
  of one player: every list of times or distances is stored sorted, so it is a
  spread and not an order of events.
- **What is never recorded:** IP addresses, callsigns, player or agent ids,
  join tickets or resume tokens, chat, voice, hardware fingerprints, location,
  the time of day, or anything that links a number to a person. Agents are
  counted like any other fighter.
- **Everyone is told.** A server recording fun metrics says so in the join
  welcome (`fun_metrics: true`, shown in the match feed before the first fight)
  and in its `/status` answer, which the multiplayer page reads out before you
  join.
- **It stays on the host's disk.** One file per match, named only by the day,
  in `fun-metrics/` under the host's run directory (`LOCALEXCEPTION_RUN_DIR`, or the
  platform's user data folder). A match still running when the host stops
  the server (Ctrl+C or SIGTERM on a dedicated server, the game ending a
  desktop host) is filed too, marked `finished: false`; a server killed
  outright loses it. Nothing is sent anywhere. A host may choose to
  share their own files with the project, for example by attaching them to an
  issue; that is the host's decision, made by hand.
- **It self-destructs.** Files older than 67 days are shredded automatically
  when the server starts and once a day while it runs. Sixty-seven days is
  long enough to compare a few nights and short enough that nobody builds an
  archive. The Union would keep it forever. We do not.

### Exactly what a file holds

Each match file holds these fields and nothing else. The server refuses to
read a file with any other field, and a test fails the build if the record
type gains a field that is not on this list or a field name that reads like
something about a person. A per-gun table (`*`) is keyed only by gun.

<!-- fun-metrics-fields -->
- The match: `schema`, `map_id`, `mode`, `mutators`, `friendly_fire`,
  `bot_tier`, `finished`, `match_ticks`, `fighters_peak`, `bots_peak`.
- Pace and fights: `tally.rounds`, `tally.live_ticks`, `tally.frags`,
  `tally.spawns`, `tally.spawn_deaths`, `tally.hits`, `tally.self_deaths`,
  `tally.lead_changes`, `tally.shots.*`, `tally.frag_weapons.*`,
  `tally.zone_hits.head`, `tally.zone_hits.torso`, `tally.zone_hits.legs`,
  `tally.zone_hits.plate`, `tally.zone_hits.weak`, `tally.kill_zones.head`,
  `tally.kill_zones.torso`, `tally.kill_zones.legs`, `tally.kill_zones.plate`,
  `tally.kill_zones.weak`, `tally.kill_distance_cm.*`,
  `tally.time_to_kill_ticks`,
  `tally.respawn_to_contact_ticks`, `tally.respawn_to_hit_ticks`.
- Pads: `tally.pickups`, `tally.power_returns`, `tally.power_claims`,
  `tally.power_wait_ticks`, `tally.appointments`, `tally.contested_frags`,
  `tally.plate_claims`, `tally.rocket_claims`, `tally.drop_claims`.
- Objectives: `tally.captures`, `tally.sabotage.rounds`,
  `tally.sabotage.attack_wins`, `tally.sabotage.defence_wins`,
  `tally.sabotage.level_rounds`, `tally.sabotage.by_elimination`,
  `tally.sabotage.by_detonation`, `tally.sabotage.by_defuse`,
  `tally.sabotage.by_time`, `tally.sabotage.plants`,
  `tally.sabotage.matches_decided`, `tally.conquest.matches_decided`,
  `tally.conquest.union_wins`, `tally.conquest.coalition_wins`,
  `tally.conquest.site_flips`, `tally.conquest.union_sites_at_end`,
  `tally.conquest.coalition_sites_at_end`, `tally.conquest.union_tickets_left`,
  `tally.conquest.coalition_tickets_left`.
- Server health: `tick_health.ticks`, `tick_health.p50_us`,
  `tick_health.p99_us`, `tick_health.max_us`, `tick_health.over_budget`.
<!-- /fun-metrics-fields -->

Times are in ticks (twentieths of a second), distances in centimetres, tick
health in microseconds. `fighters_peak` and `bots_peak` are head counts, the
most fighters and the most rule bots at once.

To read a host's files as the same tables the bot survey and the
[1.0 bar](ROADMAP.md#the-10-bar) use, run `localexception-server --fun-summary` from a
release package (it reads the host's own folder; name another folder after
the flag), or `cargo run -p localexception-playtest --release -- --fun-summary <folder>`
from a checkout. Both print from the same code, read only and send nothing
([hosting guide](HOSTING.md#fun-metrics)).

## If the project hosts a server

Any server the Local Exception project runs follows the same rules, with fun metrics
announced in the welcome and shredded on the same 67-day clock. The aggregated
numbers may be published to explain a balance change; they contain nothing
about any person by construction.

## Changing this policy

A change to this file is a change to the game: it goes through a reviewed pull
request, and the code that enforces it (what the recorder can store, the
retention clock, the join notice) changes in the same pull request with tests.
