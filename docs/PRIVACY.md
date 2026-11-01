# Privacy

**Status:** fun metrics are planned ([#529](https://github.com/blisspixel/fragr/issues/529)). Today the project receives nothing from anyone, and the only records are on your own machine and in a server's console.

The Union keeps a file on everyone, forever, in triplicate. fragr keeps a tally
of how often the Rifle wins, only if the host asks it to, and shreds even that
after 67 days.

This is the whole policy. It applies to the game, the server, the agent adapter,
the example brain and any server the fragr project itself ever hosts.

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
connection it refused (for flood and abuse defence). fragr does not write that
log to disk or send it anywhere; a host who saves their console output owns it.
Join tickets and resume tokens are never logged, and `/status` never shows an
address, callsign, id or token. Fun metrics never read the console log.

## Fun metrics: a host's own tally, off by default

A host may turn on fun metrics to see how matches on their own server actually
play, so maps, weapons, bots and pacing can be tuned against real games instead
of bot games. They are off unless the host switches them on.

When they are on:

- **What is recorded is about matches, not people.** Map, mode, rules and bot
  tier; round and match length; frags a minute; lead changes; each weapon's
  share of shots and frags and its kill distances; time to kill; time from
  respawn to first contact; spawn deaths; pad pickups; Sabotage and Conquest
  outcomes; server tick health. Counts and timings per match, never a timeline
  of one player.
- **What is never recorded:** IP addresses, callsigns, player or agent ids,
  join tickets or resume tokens, chat, voice, hardware fingerprints, location,
  or anything that links a number to a person. Agents are counted like any
  other fighter.
- **Everyone is told.** A server recording fun metrics says so in the join
  welcome and in its `/status` answer, before anyone fights.
- **It stays on the host's disk.** Nothing is sent anywhere. A host may choose
  to share their own files with the project, for example by attaching them to
  an issue; that is the host's decision, made by hand.
- **It self-destructs.** Files older than 67 days are shredded automatically
  when the server starts and once a day while it runs. Sixty-seven days is
  long enough to compare a few nights and short enough that nobody builds an
  archive. The Union would keep it forever. We do not.

## If the project hosts a server

Any server the fragr project runs follows the same rules, with fun metrics
announced in the welcome and shredded on the same 67-day clock. The aggregated
numbers may be published to explain a balance change; they contain nothing
about any person by construction.

## Changing this policy

A change to this file is a change to the game: it goes through a reviewed pull
request, and the code that enforces it (what the recorder can store, the
retention clock, the join notice) changes in the same pull request with tests.
