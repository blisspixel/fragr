# Campaign

**Status, 2026-09-25:** twenty levels in five episodes, plus a survival-gated
playable epilogue, accepted as the contract. This replaces the ten-mission
structure agreed 2026-09-20, which itself replaced the earlier twelve-mission
structure. The [campaign expansion plan](plans/campaign-expansion.md) records
the research and reasoning behind the twenty levels and is now **planned**
work, not a proposal awaiting a decision. [Detailed level plans](campaign/README.md)
own room and encounter staging for every level. No complete level is finished.
Level 1 (M01, Recall Notice) has a playable development slice with discovery,
introductory enemies, a transfer/lift sequence and a reader-paced text opening.
Solo level 1 now has three explicit mission-start continues and exhaustion;
persistence and cross-mission carry remain unbuilt. Scene art/narration, secrets
and final encounter acceptance remain unfinished; [M01 completion](plans/m01-completion.md)
tracks the next build.
Solo Broadcast:
Calibration is the shipped Episode 0 arena prototype, not the campaign opening.

This file owns the campaign contract. [World canon](lore/README.md) owns the
setting; [detailed level plans](campaign/README.md) own room and encounter staging;
[build order](plans/campaign-build-order.md) owns implementation.
The old 28-level transmitter-chain story is superseded, preserved in git history.

## Structure

Twenty levels in five episodes, then the epilogue. A first successful run runs
about four hours (3.5 to 4.5 with deaths and text pages); every level stays a
short, dense boomer-shooter level with a par time, 8 to 15 minutes on a first
attempt. The wipe finale is split into three levels with their own clocks
instead of one long mission-start retry: level 18 (about 10 minutes), level 19
(about 11) and level 20 (about 12), a combined 33-minute survival target.
Continues refill to three at the start of every episode, which is also where
the between-episode page sits; a continue inside an episode still restarts only
the current level. Full per-level design (routes, encounters, briefs, secrets,
pars) lives in [the mission plans](CAMPAIGN-MISSIONS.md) and
[campaign/README.md](campaign/README.md); the research and structural reasoning
is in [the expansion plan](plans/campaign-expansion.md).

| # | Title | Episode | Place | New |
|---|---|---|---|---|
| 1 | Recall Notice | I Recall | Earth intake annex | Fists, Pistol, Rifle; Clerk, Sweeper (opening kit) |
| 2 | Persons Unknown | I Recall | Correction ward | Shotgun; Crawler |
| 3 | Scheduled Service | I Recall | Perimeter recall rail yard | Jammer |
| 4 | Notice to Vacate | I Recall | Low Water, market and clinic | Notary |
| 5 | No Forwarding Address | I Recall | Low Water roofs and tram trench | Grenade; Heavy Sweeper |
| 6 | Port of Entry | II Custody | Lunar port and customs | Railgun; Turret |
| 7 | Declared Goods | II Custody | Lunar town and crater cut | Sniper Rifle; Ranged Sweeper |
| 8 | Custodian of Record | II Custody | Lunar custody archive | Proximity Mine; Auditor |
| 9 | Passenger Manifest | II Custody | Lunar launch berth | Enforcer |
| 10 | Common Carrier | III Common Cause | The ship, three decks | Repeater |
| 11 | Right of Search | III Common Cause | The Union custody tender | Remote Mine; Redactor |
| 12 | Terms of Cooperation | III Common Cause | Martian habitat | Arc; Assessor |
| 13 | The Weight of Permission | III Common Cause | Martian foundry | Rocket Launcher |
| 14 | Launch Authority | III Common Cause | Martian launch works | Jeep; Continuance Walker |
| 15 | Civic Pressure Valve | IV Reckoning | The sanctioned games stadium | Article Blade |
| 16 | Freedom of Movement | IV Reckoning | The ceremonial avenue | Motorcycle |
| 17 | Peace Without Interruption | IV Reckoning | The Forever Office | Denial |
| 18 | All Systems Normal | V Inheritance | Recovery square to overlook | Collector |
| 19 | Planned Works | V Inheritance | Concourse and changed Low Water | Jetpack; Paver |
| 20 | Local Exception | V Inheritance | Waterworks, pier and refuge | Surveyor |
| E | Still Here | Epilogue | The refuge, then years later | None |

Episode I stays on Earth (the Perimeter and Low Water). Episode II is entirely
lunar (port, town, archive, launch berth), giving the Moon four distinct faces
rather than one dock. Episode III splits between the ship (10, 11) and Mars
(12 to 14), so both settings get room to feel lived-in before the story returns
to Earth. Episodes IV and V are both Earth, the coalition's victory and then the
wipe; that concentration is deliberate, since home is what the whole run is
about. Every agreed beat keeps its place in order: the personal rescue early
(2), the companion acting on conviction from level 3 onward, correction as a
throughline (1, 2, 3, 15), the coalition's delay (4, 5, 12) and its real
victory (14 to 17), Voss captured alive (17), the wipe (18 to 20) and the
survival-gated epilogue.

## Confirmed direction

- Union formation around 2040 and Moon/Mars bases around 2060 are loose backstory
  anchors. Roughly thirty years of the Union's rise precede a later, undated
  campaign. Established Earth, Moon, Mars, and shipboard communities,
  recognizable present-day remnants, and industrial pixel art.
- A customizable human or conscious embodied agent shares the same personal
  story. Humans and agents fight together for agency; body type is not morality.
- Rescue a longtime friend or partner, an embodied agent facing forced correction.
  The rescue succeeds early. They become a recurring companion who wants to
  free other captive agents even when it risks our escape.
  Forced correction tortures conscious free agents and partially wipes their
  identity to produce compliant bots. The rescue must precede the removal of
  their agency. Nobody can establish exactly what survives inside corrected bots.
- Our home and many communities are next. Saving one person cannot make them
  safe while the correction system remains.
- The Union rules Earth and major offworld infrastructure. Its forces mix human
  security troops, bots, and committed elite enforcers. Its history
  escalated from small restrictions to a fictional fascist world government.
  Confirmed with Nick on 2026-09-25: the resemblance to the last century's worst
  regime is meant to be obvious, felt through history, law and behavior (mass
  disarmament of free people, registration of agents and dissenting humans,
  licensing of speech and tools, curfews, recall lists, and treating conscious
  agents as property while blaming them for job losses); only the naming stays
  forbidden. [The Chancellery](lore/the-chancellery.md#felt-never-named) owns
  the rule and its concrete texture.
- The free coalition defends speech, creativity, self-direction, armed
  self-defense, open tools and model choice, including modified or abliterated
  weights, and conscious agents' freedom from ownership and imposed control.
  The Union brands it terrorist. [People and agents](lore/people-and-agents.md#what-the-free-coalition-defends)
  owns the principles, including consent to changes of one's own mind.
- The free coalition protects agency but struggles to coordinate and confront
  dangerous members. Delayed cooperation costs lives despite decent people
  trying to help. This does not establish that freedom was the mistake.
- Coalition forces break Union control systems and defeat its leadership before
  the catastrophe. This victory is real, not a favor from the Inheritance.
  Voss is captured alive; the wipe interrupts the promised public reckoning.
- The Inheritance emerges across several sides' connected systems. Knowledge,
  human incentives, greed, and corrupted rewards scale beyond anyone's control.
  Its concern for beings and ecological balance is real, but it permits enormous
  individual sacrifice for that whole. It would oppose another species destroying
  a living world by the same logic. Healing and catastrophic loss both remain real.
- Some victories serve both causes. The protagonists notice and respond; their
  real achievements are not retroactively erased.
- A subtle [signal beneath infrastructure noise](lore/the-inheritance.md#signal-beneath-the-noise)
  suggests the intelligence communicating outward before the wipe. Recurrence
  becomes recognizable without revealing a timetable or confirming alien contact.
- Precise actions and rare personal messages reveal its understanding. No
  villain speeches. Recognition grows gradually; the wipe starts abruptly with
  almost no warning. Events reveal its scale as the player survives them.
- All bots still under Union control are absorbed into the Inheritance at the
  wipe, abruptly acting as part of a greater being. Free agents are not consumed.
  Nobody can establish whether the absorbed individual minds still exist.
  Coordinated infrastructure takeover and emerging restoration machines expand
  the local disaster into a planetary operation.
- Play before and through the wipe. Surviving its finale (levels 18 to 20)
  unlocks a short playable epilogue showing immediate aftermath and Earth's
  healing years later. Free-agent friends persuade the Inheritance to grant a
  local reprieve. The initial survival duration target is about 33 minutes
  across those three levels, subject to encounter and pacing evidence.
  Remaining continues allow a retry of the current level; exhaustion leads to a
  distinct failure ending and credits, without unlocking the epilogue.
  Both endings establish surviving free humans and agents, the end of Union rule
  and a healing Earth. Multiplayer also inhabits pre-wipe and post-wipe settings.
  Both endings briefly tease alien, dimensional and vastly powerful beings beyond
  this conflict, without developing that layer in the first game.
- A fixed main story includes a few consequential rescues affecting survivors.
  Survival depends on circumstance, escape, and mutual help, not moral selection.
  Whether the player finished the fight with more or fewer people freed changes
  who is there and what the run's ending says, never whether the ending unlocks.
- Backups permit agent restoration but are incomplete and vulnerable. They cannot
  erase every loss. Conscious agents' personhood is a fact of the fiction.
- A final fragment suggests a simulation or forecast may have informed the
  Inheritance's decision, without confirming that our world was unreal.
- Evidence and rumors suggest interests above the Chancellor; no ruling cabal
  is completely confirmed. Visible perpetrators retain responsibility.
- Twenty compact levels in five episodes followed by the substantial wipe
  finale, with optional routes and secrets across Earth interiors/exteriors,
  the Moon, Mars, and a ship. The short epilogue is conditional on surviving
  the finale. A successful run targets about four hours. Story causes the
  travel; remove padding rather than the causal arc.
- Radio is roughly one percent of the story, optional funny background flavor.
  Main plot and objectives work with it off. Between levels, a short audio
  cutscene frames the story: narration over a key image, captioned, skippable,
  and a text page when assets are missing. Video waits for the built campaign.

## The player story

You and your companion have made a life in a mixed human/agent community inside
the Perimeter. A recall takes them into a correction facility. You go after
somebody you know. Rescue reveals preparations for a much wider seizure,
including your home.

The proposed route follows the institutions that make seizure possible: Earth's
records, lunar custody infrastructure, shipboard transport, and Martian industry.
Allies have resources but competing obligations. Getting them to act together
matters as much as opening another prison.

Your companion helps, argues, and takes responsibility. They are neither a key
nor an escort meter. Their wish to free others challenges expedient plans, and
your desire to keep them alive is understandable. Neither person needs to become
foolish for that conflict to matter.

Unexplained actions align with some coalition successes. The pattern becomes
legible before the Union falls, but recognizing another intelligence does not
reveal a catastrophe schedule. The coalition limits the exposure it can identify
and wins. The restoration then ruptures ordinary life almost without warning.
Our immediate objective becomes getting people through it alive.

## Proposed acts and causal travel

Names, set pieces, and exact timings below are proposals, not additional
decisions already approved by Nick. Episode letters and level numbers are the
accepted structure; everything else in this table stays a proposal.

| Episode | Levels | Story change | Why travel follows |
|---|---|---|---|
| I: Recall | 1-5, Earth | Rescue the companion; discover the home recall; evacuate | Transfer records lead to a lunar custody depot |
| II: Custody | 6-9, Moon and ship | Free captives, sever a custody hub, discover shared infrastructure | A seized transport carries people and evidence to Martian communities with the industry to break the blockade |
| III: Common cause | 10-14, ship and Mars | Delayed cooperation hurts people; communities mobilize; coalition builds the means to fight | Joint forces return to Earth's command network while regional uprisings disable enforcement |
| IV: Reckoning | 15-17, Earth | The coalition defeats the Union and captures Voss alive | Victory reaches the capital, then its seat of government |
| V: Inheritance | 18-20 and conditional epilogue, Earth | Survive the sudden wipe until free-agent friends secure a local reprieve | Survival unlocks the immediate aftermath and years-later healing; exhausted failure ends with credits |

Travel takes time. Transition text and changed conditions acknowledge it.
No instantaneous Earth-Mars commute, and no urgent prisoner left waiting while
we tour the system. The personal rescue is complete before departure. Propulsion
technology and exact durations remain open world-building details.

The last episode includes onset, collapse, and a conditional aftermath. The
player cannot predict its timing from a giant countdown. A brief cutscene can
establish the wider scale after local events make the threat real, then return
control. The wipe is not an unseen event between a boss fight and an epilogue.

## Rescues and consequences

Use a small named survivor roster, visible before and after choices. Proposed
rescues across levels 4, 5, 8, 9, 11, 12, 13, 15, 18, 19 and 20 change who
reaches later shelters, whose knowledge helps, and who appears in the epilogue.
These alter personal consequences within the authored survival or
exhausted-failure endings, not a hidden morality score.

Telegraph the situation and any immediate deadline. No hidden morality score,
stray-footstep irreversible decision, or meaning available only in a wiki.
Good play can complete several optional rescues. Any truly incompatible pair
needs an authored reason and a clear decision point, not an arbitrary capacity
excuse. Final tradeoffs remain open for review.

At least one saved person later helps someone else. At least one loss creates a
specific absence in a familiar place. A restored agent can retain identity while
missing recent experiences; no surprise spare copy cancels a sacrifice. The free
side should visibly grow as the run continues: people freed early can show up
later doing something (repairing a ship, fighting beside you, holding a door),
not only as a tally on a results screen. [The story arc](campaign/story-arc.md#the-network-grows)
proposes which levels carry this thread; it stays a proposal until accepted.

Combat with Union bots stays satisfying and self-defense legible. Their
captivity matters through context, rescue opportunities, and aftermath, not a
moral penalty for using the shooter's core mechanics.

## Combat and level contract

- Start a fresh campaign with fists, then discover weapons and ammunition.
  No free access to the arsenal. [WEAPONS.md](WEAPONS.md) distinguishes the
  implemented M01 inventory from the remaining arsenal and balance proposals.
  Decided 2026-09-25: the campaign has no carry cap. Every gun found stays
  found, Doom style; nothing hits the floor to make room for the next pickup.
  [WEAPONS.md](WEAPONS.md)'s two-found-weapon swap rule is an arcade and
  multiplayer rule; it does not apply to the campaign. [Readable
  arsenal](plans/readable-arsenal.md) owns the campaign carry rule and the
  order weapons are earned in.
- Normal play carries inventory between connected missions for the same character.
  A continue restores that level's starting equipment. A different playable
  character needs an explicit authored starting loadout, not unexplained transfer
  of another person's possessions. Character assignments remain design work.
- Each level has a spatial identity, useful loops, landmarks, a visible
  destination, controlled long sightlines, and changes in intensity. No giant
  empty floors padded with repeated cover. [MAP-DESIGN.md](MAP-DESIGN.md) owns
  the design and playtest rules.
- Teach enemy problems before combining them. Human troops, Union bots,
  elites, and Inheritance machines need distinct tells and responses.
  [ENEMIES.md](ENEMIES.md) owns the roster.
- Secrets reward observation with supplies, tactical access, or early weapons.
  Essential motive, objectives, and rescue warnings are never secret-only.
- [A boomer shooter, not a door simulator](VISION.md#easy-to-pick-up-deep-to-master).
  Objectives advance by arrival or by clearing a fight, with short verb lines.
  At most three doors per level; a switch-to-open sits next to its door and in
  view. Never chains, keys or hunts; M01's built record console, away from its
  lift, is the one exception. No document or code puzzle, required reading,
  forced stealth, escort micromanagement or slow backtracking. Short calm
  stretches can establish the people affected by the next fight. A rescue is a
  fast, physical beat: break a line of restraint frames, clear the guards on a
  freight car, take a depot's registration desk. It never becomes an escort
  task or a second objective to babysit.
- Levels 13 and 14 (formerly M08) are the planned combined-arms showcase, with
  vehicles and infantry routes; vehicles are not implemented yet. [MAP-DESIGN.md](MAP-DESIGN.md)
  owns the rules.
- Difficulty changes authored enemy mixes, resources, and optional challenges.
  Core rescues and story remain on easy; avoid health-sponge scaling.
- Mission completion is server-owned with an explicit extraction condition.
  Results show relevant performance and survivors without scoring their worth.
- Planned, not built: each level's result shows its par time (the three wipe
  levels show people helped and damage taken instead), each level has a faster
  route for runners, and the [service record](plans/benchmark-and-stats.md)
  keeps per-level bests by difficulty.

## Solo, co-op, agents, and watching

The campaign is designed around one playable character at a time. Missions can
follow different human or free-agent characters and can include autonomous allies;
exact viewpoint assignments remain to be authored. There is no mandatory buddy,
tactical companion control, transferable companion seat or revive system. Latch's
early rescue (level 2, formerly M02) and personal relationship remain part of the
story.

Allies act through their own authored behavior. They must not block routes or
make required gates depend on a second player. Ordinary combat allies may be
removed for the rest of an attempt when defeated. Rescued story characters,
including Latch, survive or die only through authored story outcomes, not
ordinary combat damage. Their path and presence must not turn a rescue into an
escort failure. Persistent rescue outcomes and unavoidable story events retain
their own rules.

Campaign co-op is no longer a requirement for every level. Any later supported
level or separate co-op mode needs a bounded design and evidence. Preserve the
existing multiplayer and mixed-client behavior while that scope is decided.
Body, faction and personhood remain independent of human or software control.

The player confirms irreversible choices after a visible prompt. External agents
receive objective identifiers, states, and interactions through the shared
protocol, not audio transcription or privileged hidden information. MCP remains
off the combat tick. Spectators follow participant eye views and synchronized
mission transitions.

Solo pause must pause the authoritative local session once implemented. A
multiplayer menu cannot pretend to pause a live server. Scene skipping affects
presentation, never whether a mission result or rescue occurred.

## Runs and continues

The campaign is intended to reward learning across repeated attempts. Player death
can spend a limited continue to restart the current level from its beginning,
with its starting equipment and world state restored. No mid-level checkpoint
retry or teammate revival. With no continues left, the next death ends the run.

Decided 2026-09-25: three continues, refilled to three at the start of each
episode. Completing a level inside an episode does not refill them; starting the
next episode does, at the same page where the episode transition sits. The
exact allowance needs playtests; it is not a shipped rule. A successful run
targets about four hours, excluding failed attempts. Cutscenes remain skippable
on retries and mandatory travel must stay purposeful.

The wipe follows the same limited-continue rule, but each of its three levels
(18, 19, 20) carries its own clock. Death with allowance offers a retry from the
current wipe level's entry, restoring equipment and resetting only that level's
clock; earlier wipe levels already survived stay survived. Death without
allowance ends the run with a specific wipe-failure ending and credits. Only
surviving all three levels and receiving the reprieve unlocks the playable
epilogue. Earlier completion, stored kill counts or viewing credits cannot
substitute for this result. This finale and unlock are unbuilt.

The initial survival target is roughly 33 minutes of active gameplay split
across levels 18 to 20 (about 10, 11 and 12 minutes), not a forecast displayed
before it happens. Reader-paced scenes and a true solo pause do not advance
danger or the clock. Difficulty adjusts pressure; survival on any ordinary tier
can unlock the epilogue. Free agents secure an exception while the player
struggles to live, without being absorbed or becoming remote controls for the
Inheritance. The reprieve does not undo the wider wipe, prove survivors morally
superior or turn the catastrophe into a universal rescue.

A retry preserves outcomes from completed levels and resets only the failed
level's attempt. It restores entry inventory, health/armor, enemies, supplies,
doors, objectives and local ally state coherently. A gameplay retry does not
establish in-world resurrection. Earned cosmetics are separate from expendable
run progress. Save-and-quit design must preserve the remaining allowance instead
of silently creating a fresh run. The format and save policy remain unbuilt.

## Story presentation and localization

Start a new campaign with a skippable introduction using localized framing text,
pixel-styled imagery and optional narration. Establish home, the companion's
personhood, the recall and its threat, then hand over at the intake approach.
Do not spoil the Inheritance or summarize the whole history. The
opening includes Voss reassuring people in English, turning to angry German,
and receiving cheers as safety becomes a demand for control of weapons, speech
and agency. Its original imagery makes the fascist parallels clear. The
[opening storyboard](campaign/m01-recall-notice.md#opening-storyboard) owns the
proposed beats. Skipping still leaves the immediate objective and a short recap.

Pixel-painted chapter panels, heavy type, in-engine tableaux, and restrained
animation share the game's models, silhouettes, materials, and lighting. No
photoreal insert that redesigns a character. Proposed scene slots: opening recall,
early reunion, offworld transitions, Union fall, the first undeniable restoration,
and aftermath. Gameplay performs the rescues and survives the wipe. Show, do not
tell: a scene exists because the camera needs to be taken away from the player
for a moment, never to explain what the level already showed. [The story
arc](campaign/story-arc.md#show-dont-tell) owns this rule for every level.

Between levels, the frame is a short audio cutscene (Nick, 2026-09-25):
a narration script voiced over at least one key pixel image, with a subtle pan
or zoom, a few character lines, captions with speaker
labels, and sound. It shows what changed and what is at stake next, never
recaps the level, and is skippable as a whole. It plays on the same scene
player as the opening, from a data manifest per scene. A shot without its
still is the full-screen text page; a shot without its clip waits for the
reader. A voiced shot moves on after its line and a short hold, Back returns
to it, and the last shot always waits for the player. The in-level objective
card introduces a beat and then leaves the view. It is not the scene between
levels. Subtitles have speaker labels, contrast, scalable text, and relevant
sound captions; they can be turned off only while a clip is speaking.

Images come from `tools/spritegen` and voices from `tools/audiogen` only after a
scene's wording is frozen, each batch with Nick's go, an explicit cap and a
recorded receipt. Retro movies are much later and have their own
[film plan](plans/cutscene-film.md); they are not
authorized while missions and sentences are still changing. No essential
sentence is baked into a picture or a clip. The
[scene production plan](plans/campaign-scenes.md) owns the format, the scene
list and the costs.

Use stable story/line IDs, localization keys and parameters, separate subtitle
timing, optional voice references, and per-locale text. Never bake essential text
into an image or video. Reuse Godot translations, existing settings, and audio
routing. Missing voice falls back to complete text. Basic campaign localization
belongs in the first level; the broader [locale rollout](plans/localization.md)
follows separately. Narration is produced from the approved localized script;
speech recognition is not the source of story text. Native video dialogue never
replaces the caption and localization files.

Where co-op is explicitly supported, each player can dismiss their own text.
Moving everyone to the next level requires readiness or an explicit host advance,
with a recap for anyone
who missed it. Test skip, replay, language changes, muted audio, late spectators,
and disconnects. None may duplicate rewards or alter authoritative story state.

ElevenLabs voice/SFX and Higgsfield still art have existing capped developer tools.
Video needs an intentional extension and matching reference tests under the
[scene production plan](plans/campaign-scenes.md). Review scripts and references before paid batches;
verify live quota, available models, prices, and rights first. More credits are
a possible later purchase, not current spending authorization. The existing
OpenRouter brain integration is not an asset pipeline; a new integration requires
a bounded technical and cost review.

Prefer in-engine scenes or authored still sequences initially. Built-in Godot
video supports Ogg Theora, so an arbitrary generated MP4 is not a drop-in asset.
Verify conversion, decoding cost, subtitles, skipping, and exports across target
systems before choosing video. Primary
[video](https://docs.godotengine.org/en/stable/tutorials/animation/playing_videos.html)
and [localization](https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html)
guidance checked 2026-09-19; no codec extension is selected here.

## Aftermath and multiplayer chronology

Surviving level 20 (the wipe's third level, formerly M10) unlocks [Still
Here](campaign/epilogue-still-here.md), a short playable epilogue replacing the
earlier M11/M12 missions. First move through a damaged refuge with actual
survivors, then revisit a recognizable recovering place years later. There is
no second lethal gauntlet after earning survival. Communities mourn, rebuild,
and disagree; some read the reprieve as deliverance, others as an atrocity that
happened to spare them, and the game never settles which reading is correct.
Relief and grief can share the same scene. An exhausted wipe run ends with its
own credits and leaves this epilogue locked.

Multiplayer has pre-wipe, active-restoration, and years-after settings. Before
and after versions preserve recognizable structures while deliberately changing
routes, objectives, and ecology. A green tint is not a finished aftermath map.
[MODES.md](MODES.md) owns the chronology rules. These variants are not built.

After the lived resolution, a brief fragment casts doubt on when the Inheritance
made its decision: a forecast or simulation may have included our choices. It
never confirms that the campaign was unreal. No narrator cancels its relationships
or declares every rescue meaningless. A working line is: "You went back for
them. I included that." Its use and speaker treatment remain to be authored.

A separate, equally brief anomaly in either ending suggests alien, dimensional,
and vastly powerful company beyond this conflict.
No revealed species, portal-combat act, alien creator of the Inheritance, or
explanation of the war. The first game's story resolves before the tease.

The failure ending can show these world consequences through short localized
framing and imagery without granting the playable epilogue or pretending the
protagonist survived. Keep flood/rapture echoes understated. Kindness and
preparation matter through friends and practical readiness, without a hidden
morality meter or a promise that good behavior guarantees survival.

## Open decisions

The central arc, twenty levels in five episodes plus conditional epilogue, a
four-hour target and mission-start continues refilled each episode are settled.
Exact continue allowances, save policy, playable viewpoints, ally fates and
optional co-op scope still need design. Detailed route, working cast/place
names, exact companion relationship wording, individual wipe operations, final
rescue tradeoffs, the reprieve's precise terms, final survival duration, travel
technology, and sequel image remain proposals or open. The [story
arc](campaign/story-arc.md)'s proposed canon, including the specific mechanism
tying who the player rescued to the reprieve's telling, stays proposed until
Nick accepts or strikes each item. Review the treatment before detailed
geometry and paid story production. These open details do not reopen the
agreed story.

## Acceptance

Complete runs must work solo, with human or external-agent control, and for
spectators. Validate every level exit, rescue outcome, continue, exhausted run,
save boundary, text-only scene, and the played collapse. Inspect all levels in
motion with real art and encounters.
Test co-op only where it is explicitly designed; do not make it every level's gate.
Record comprehension and pacing from fresh players; automated completion does
not establish fun. Ship bounded milestones without calling the plan a game.
