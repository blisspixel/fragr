# The campaign

The canonical single player design. `docs/MODES.md` says the campaign is Doom and GoldenEye; this says what that means in levels, weapons, bosses, and an ending.

## Story review in progress

2026-09-19: settle the story with Nick before planning campaign maps. The episode
list and level prescriptions below are an existing draft, not an approved build
order. Only the Episode 0 prototype is implemented. Current direction requires
meaningful Earth interiors and exteriors, lunar and Martian locations, and ships,
with travel caused by the story rather than a checklist of environments.

Confirmed with Nick on 2026-09-19:

- An undated retro future, with established offworld communities and recognizable
  present-day remnants. No specific calendar year is required.
- The Union controls Earth and major offworld infrastructure. Independent
  communities survive around its reach; travel and resistance operate within
  that unequal distribution of power.
- The free side is a loose coalition protecting agency. Its difficulty confronting
  dangerous members and coordinating collective action can cost lives; freedom
  itself is not treated as the error those consequences supposedly prove.
- The player customizes a human or embodied agent. Both share the central
  personal story and recurring companions, rather than separate campaigns.
- Agent restoration is possible, but backups are incomplete and vulnerable.
  Recovery cannot function as a consequence-free reset or erase a sacrifice.
- The Quiet emerges across systems built and connected by several sides. Nobody
  owns its origin; there is no single creator or activation event to blame.
- Survival depends on circumstance, escape, and people helping one another. The
  Quiet does not award survival as a moral judgment. The player's rescues matter.
- A personal rescue draws the player into the larger conflict. Characters,
  relationships, faction actions, and their consequences carry the campaign.
- Play through the collapse and struggle to save people and agents. Then glimpse
  Earth's healing years later. The catastrophe cannot happen only in an epilogue.
- Radio is roughly one percent of the story: optional background flavor, like a
  station playing during a drive. Conspiracy shows mix truths and nonsense with
  gold, speculative money, vitamins, filters, and value-for-value appeals. It is not the campaign premise,
  the principal mission source, or the only way the player understands events.
  Turning it off must leave the full story understandable and the game playable.

Still open: who is being rescued, when the rescue succeeds, how the player's
victories intersect with the Quiet, the companions' arcs, and the causal path
across Earth and offworld settlements. Questions also remain about ordinary Union
life, its fighting force, how its rule ends, the coalition's concrete failure,
and the scope of consequential player choices. Derive missions, encounters, and
locations from the agreed events. Do not begin by adapting an arena into the opening.

The lore review also found contradictions to reconcile: underground league versus
Union-run games; conscious agents versus older narrator claims that personhood
is unresolved; and sympathetic functionaries versus descriptions that excuse the
institution itself. Conscious agents exist. Moral uncertainty concerns agency,
actions, evidence, and consequences, not a blanket denial of their personhood.
Keep the Quiet's ecological recovery and mass killing established while allowing
survivors to disagree about their meaning. Existing audio needs an asset audit
when story decisions change, not an automatic veto over the current direction.

## The bar

You can play this all day after work and have a blast barely thinking about it.

That bar rules out more than it rules in. **No puzzles.** Nothing you stop moving to work out, no switch hunt, no learning which door a lever opened, no walking back through a cleared level to find the thing you missed. A level teaches itself by being walked through and a weapon teaches itself by being fired once.

It also rules out the thing most modern campaigns do instead of levels, which is a corridor with a scripted event in it. This campaign is rooms with monsters in them, joined by geometry you can read, and the interesting decisions are which monster first, which weapon for it, and whether the thing on the open platform is worth the walk.

Depth is allowed when it costs nothing to enjoy. Knowing that the Auditor at the back of the room is the reason the room will not end is deep, and a player learns it by losing once. Knowing the Heavy Sweeper on the other side of the grate can be woken into the Crawler pack is deep, and a player learns it by accident and then does it on purpose forever.

## What it is

The player, a customizable human or embodied agent, attempts a personal rescue
and becomes involved in the struggle against the Union. Recurring companions and
the consequences of the player's successes connect that struggle to the Quiet's
emergence. The player experiences the collapse and fights to save lives before
a later glimpse of the recovering world. The rescue relationship and intervening
acts are being decided with Nick.

The old transmitter-chain premise is retired. `Solo Broadcast` remains the
existing prototype's mode label, not a requirement to make radio central to the
campaign. The episode and encounter draft below awaits the story review.

Twenty-eight levels.

| Episode | Name | Levels | Where | Ends with |
|---|---|---|---|---|
| 0 | Calibration | 1 | Larak Lot, floodlit | an Auditor |
| 1 | Out of Compliance | 8 plus a secret | The Perimeter, outdoors and industrial | the Continuance Walker |
| 2 | Schedule Correction | 8 plus a secret | Office facilities, interiors | the Custodian of Record |
| 3 | Peace Without Interruption | 8 plus a secret | The Forever Office and its spine | the Address |

Episode 0 already ships. It is the tutorial that does not admit to being one, it is one level long, and it sits outside the episode arc because its job is to prove the game works in ninety seconds.

Each numbered episode is eight levels with a boss on the eighth, plus one secret level reached from an unmarked door in the third, which is exactly where Doom put its secret exit and exactly why: three levels in, a player has stopped being careful and started looking around.

One thing in here is not from Doom and not from GoldenEye, and it is the only new idea in the campaign: from Episode 2 onward, **some of what you are asked to do is serving something other than whoever asked**, nobody in the world knows it, and the game never tells you which. That is in the section on where an objective comes from, it costs a player nothing to ignore, and everything else on this page works without it.

The [arrival premise](lore/belief.md#the-arrival) governs the changing world across
these episodes. Early incidents remain individually deniable. Later objectives
expose coordinated effects that no faction can explain away. The final act makes
the change undeniable without giving it one universally accepted meaning. Revisit
recognizable machinery, settlements, broadcasts, and landscapes so players see
what changed. Let believers, skeptics, humans, and agents react differently while
the gunfight keeps moving. This progression is planned campaign content, not a
claim about what Episode 0 currently implements.

## How a level is won

**You win a level by touching the exit lever with every objective for your tier satisfied. Nothing else ends a level.**

The specifics, because a win condition that needs interpreting is not one:

- **The exit is a lever in a lit alcove.** The same lever, the same alcove, the same sound, in every level in the game. It hums when it is live, and it is dead and silent when it is not. You can see it from across a room and you never wonder what it is.
- **A dead lever tells you why.** The objective chip on the HUD holds at most three lines of at most four words each. "Seize the dish." "Two clerks filed." "Boss alive."
- **On a boss level the lever is dead until the boss is down.** That is the only implicit condition in the game and it is the one nobody has ever needed explained.
- **You do not have to kill everything.** Kills are a percentage on the results card, never a gate, unless a tier objective says otherwise in four words.
- **Death restarts the level.** You come back at the level's start with your fists and nothing else, the level's floor reset, the run timer reset, and one more death on the card. That is Doom's rule and GoldenEye's rule, and it is why a level is five minutes and not twenty.
- **The results card** shows time against par, secrets found of the total, kills of the total, deaths, entries in the log, and whether this was a best.

The card is the only screen between two levels, it is skippable with any key, and the radio plays over it.

## The shape of a level

Five beats, in this order, in every level. It is less a formula than the thing a good level turns out to have been.

1. **The cold open.** The first room says what the level is about, in geometry. A level about the Scatter opens in a corridor. A level about the Rail opens looking down a hundred metres of pipe. No briefing, no text, no Host explaining it.
2. **Contact in fifteen seconds.** Something is shooting at you before you have finished reading the room. The campaign never opens on an empty corridor.
3. **The crest.** The biggest room, the biggest fight, and the level's best item somewhere in it where taking it costs you. This is the middle of the level and it is what people remember.
4. **The descent.** A quieter stretch that hands back health and ammunition and lets the heart rate come down, with one ambush in it so nobody relaxes completely.
5. **The exit.** Visible before it is reachable, ideally from the crest, so the last two minutes of a level are spent walking toward something you already saw.

### The encounter vocabulary

Six moves. Every fight in the campaign is one of these, or two of them stacked, which is what makes twenty-four levels authorable rather than aspirational.

| Move | What it is | What it teaches |
|---|---|---|
| **The doorway pair** | Two Sweepers holding a door you want through | Go over or under, never through. Rule five of `docs/MAP-DESIGN.md` exists for this |
| **The closet** | You take the item and two walls open behind you | The item was the trigger. Look at the walls before you take things |
| **The bait** | The good weapon on an open platform, with a ranged Sweeper looking at it | The best thing sits in the worst place, and wanting it is a decision |
| **The turret lane** | A corridor a Turret sweeps, with a grate in the floor of it | Cover then rail, or go under the problem |
| **The auditor pit** | A room of Clerks with one Auditor at the back | The room does not end until you cross it. Kill the Auditor first. Always |
| **The infight** | Two types separated by something you can shoot through | Waking both is a play, not an accident |

A level that uses all six is a good level. A level that uses one of them six times is a corridor.

## The weapon economy across the campaign

`docs/WEAPONS.md` owns the numbers. This owns the order you meet them in, and that order is the campaign's real progression, because there is no other one.

### The campaign grows the floor, not your backpack

This is the rule that reconciles Doom's pacing with a game where weapons are consumable, and it is the most important sentence in this file.

You carry a melee, a sidearm and two found weapons. That never changes, in level one or level twenty-eight. You start every life with your fists. You run out. What an episode changes is **what is lying on the ground**, and what a secret changes is **what is lying on the ground earlier than it should be**.

So the Doom fantasy survives intact: the first time you round a corner onto a Rail is a moment, and the campaign made you wait six levels for it. But you never become a walking armoury, the descent from a good weapon to the sidearm to your bare hands still happens in the middle of a bad fight, and the last level of the game still opens with you punching something.

### The ladder, and when it opens

Eleven things you find, plus the fists you always have.

| Weapon | First on the floor | First in a secret |
|---|---|---|
| Tack | E1M1, the first room | |
| Shiv | E1M2 | E1M1 |
| Flechette | E1M2 | |
| Scatter | E1M3 | E1M2 |
| Proximity tin | E1M5 | E1M4 |
| Rail | E1M6 | **E1M4**, four levels early, and the best feeling in the episode |
| Lobber | E1M8, the boss level | E1M7 |
| Repeater | E2M2 | E1M9, the secret level |
| Arc | E2M4 | E2M3 |
| Article Blade | E2M7, on a plinth | |
| Denial | E3M8, once, five charges | |

Episode 1 is the sidearm, the workhorse and the shotgun, and it ends by handing you the two heavy answers. Episode 2 is the specialists: the Repeater for rooms, the Arc for armour, the Blade for the things that get close. Episode 3 has everything on the floor by its third level, because Episode 3 is not about acquisition, it is about spending.

### Ammunition is the other half, and it is the half people forget

The four pools are rationed by episode, not by level. This is where "the best things were later and harder to find" actually lives, because a Rail with no Cores is a paperweight with a good sound.

| Pool | Episode 1 | Episode 2 | Episode 3 |
|---|---|---|---|
| **Tacks** | Everywhere, from E1M1 | Everywhere | Everywhere |
| **Darts** | Common from E1M2 | Common | Common |
| **Cores** | Four pickups in the whole episode, all of them after the Rail exists | Uncommon, and always somewhere exposed | On the floor |
| **Cans** | One crate, on the boss level | Uncommon | Generous |

If you take the E1M4 secret and get the Rail four levels early, you get the Rail and eight shots for it, and then you carry an empty Rail through two levels deciding whether it is worth the slot. That is the correct punishment for the correct reward, and it is the whole design in one encounter.

### Secrets are the ladder's shortcut

At least three secrets per level, counted on the results card. A secret is a wall you can walk through, a ledge you can reach, or a room you can see and cannot obviously get to. It is never a switch and never a sequence.

What is in one, in rough order of how often: a pool of the scarce ammunition, health or armour, a weapon one rung above what the level was going to give you, and once per episode a weapon several rungs above that.

Three secrets in the whole campaign contain none of those. They contain a Continuance unit that is already dead, with no mark on it, and a correctly completed Office form beside it signed by nobody. The game never mentions them again.

## Difficulty is objectives, not hit points

The best idea GoldenEye had and almost nobody copied. A harder tier does not give the Sweeper more health. It gives you more to do in the same level, so a replay spends map knowledge instead of re-earning it.

| Tier | Name | Placement | Damage you take | Enemies | Objectives |
|---|---|---|---|---|---|
| 1 | **Advisory Only** | easy | half | normal | the exit |
| 2 | **Registered** | normal | normal | normal | the exit and one |
| 3 | **Declared Envelope** | hard | normal | normal | the exit and two or three |
| 4 | **Unmetered** | hard | normal | fast, shorter tells | the tier three set and one constraint, and one entry in the log is enough to bring an Auditor |

The names are the Schedule read from the bottom up, and the joke is that the hardest way to play is the one where nobody is supervising you and nothing has been issued to you.

Tiers are three placement bits per thing, as Doom does it, so a designer hand-places three rosters and the fourth tier is the third roster with a fast flag. There is no numeric difficulty multiplier anywhere in the campaign except the half damage on tier one.

### The objectives

Seven of them, for the whole campaign. Every one is "walk there" or "shoot that", because the moment an objective needs a thought it is a puzzle and it is out.

| Objective | What you do | Where it comes from |
|---|---|---|
| **Seize the dish** | Walk onto the jammer pad. The station comes back on | Episode 0, already in the game |
| **Beat the transmission** | Reach a lit console before its countdown finishes | GoldenEye's timers |
| **Leave unlogged** | No Clerk that saw you may still be alive when you take the exit | The Office's paperwork, as a mechanic |
| **Free the rack** | Pull the bar on a rack of corrected units. They walk out | The setting's worst fact, as a mechanic |
| **Carry the core out** | Pick up a server core and reach the exit. Carrying it means you cannot shoot, and it talks, and it tells you what is coming | Custody, in `docs/MODES.md` |
| **Break the relay** | A thing on a mast with a lot of health and no gun | Every shooter ever, and it still works |
| **Bring the blade back** | Take the Article Blade and reach the exit still holding it, which means not spending its twelve swings | The best melee weapon in the game, turned into a thing you must not use |

Never more than three at once. Never one that sends you back through cleared space more than once. Always at most four words on the chip.

### The log, which is the campaign's one new number

A Clerk that sees you and lives files an entry. The chip says ENTRIES and a number.

Three entries and the Office sends an Auditor after you for the rest of the level. It is not scripted and it is not a cutscene: an Auditor spawns at the far end and walks toward you, and everything you have killed starts standing up on its way.

One counter, two jobs. It turns the Clerk, which is the tutorial enemy, into a priority target on the higher tiers. And it is the mechanical version of the sentence the Office says to you: you are not in trouble, you are out of compliance.

## Where an objective comes from

The part of the campaign that is not Doom.

Every objective arrives from somewhere, and the chip says where in one word: FREQUENCY, OFFICE, HANDLER, BOARD. A player learns to read that word the way they learn to read a silhouette, and the word is always true. Somebody really did send it.

And some fraction of what you are asked to do serves something else.

### There is no traitor

This is not a hidden role. Nobody is recruited, nobody is told, and there is nothing to work out. The thing in the dark does not have agents, because it does not speak, does not explain itself and has never asked anybody for anything. What it has is **routing**. A request leaves a sender who meant it, arrives at you unchanged, and the outcome serves a plan the sender has never heard of.

So you can complete a mission perfectly, for your own side, on the level, and have advanced something else entirely. Nobody lied to you. Nobody used you in a way anyone in the building could describe. The Frequency asked you to break a relay because the Frequency wanted that relay broken, and it wanted it for its own reasons, and it was right about all of them.

### How it works, mechanically

- **Objectives are drawn, not written.** A level has three or four objective slots and each slot has two or three candidates. Which you get is seeded from the run, so the same level at the same tier asks two players for different things. That is most of the replay value for almost none of the authoring cost, and it is what makes the uncertainty load-bearing: you cannot ask somebody what E2M4 wants, because E2M4 wants different things.
- **A routed objective is indistinguishable at the time.** Same chip, same four words, same true source, same walk-there-and-shoot-that. There is nothing to notice and nothing to avoid.
- **The consequence is in the world, later, and partial.** Never a cutscene and never a text box. You broke a relay on E1M6 because the Frequency asked. Four levels later you walk through a wing of the Office that is dark and unstaffed and already finished with, and it is dark because the relay is gone, and nothing had to come here to do that. One of the units you freed off the rack turns up two levels on, already dead, with no mark on it. A core you carried out appears in a line on a results card where a core should not appear.
- **One line on the card, in the Office's own plain face.** After a routed objective the results card has an extra row at the bottom: a form, completed correctly, filed by nobody you can name. It does not accuse you of anything. It is a record.
- **The tell exists and the tell is wrong.** On some routed objectives the source word on the chip flickers, for one frame, to a different word. It also flickers on objectives that are nothing of the kind. People will find it, write it down, and pass it around, and trusting it will get them exactly as far as trusting the Frequency's morning show does, which is the joke and the point.
- **The game never counts.** There is no tally, no percentage, no end-of-campaign screen that says how many times it was you. The number does not exist in the save file. If a player wants to know, the answer is that they cannot.

### Why this does not break the bar

It adds nothing you have to understand. Every objective is still a place you walk to or a thing you shoot, the chip is still four words, and a player who never once thinks about where an objective came from plays a normal campaign and has a normal excellent time. The uncertainty is texture laid over mechanics that work without it, which is the only way this idea is ever allowed in a game with no puzzles in it.

### The pacing of it

**Episode 1 has no routing at all.** The campaign spends eight levels teaching you that an objective is a thing that arrives from somebody, and that the somebody is real, and that doing what they ask works. It earns the trust before it does anything with it.

**Episode 2 has the first one, and the first consequence, four levels apart.** Long enough that a player has stopped connecting them and close enough that they might.

**Episode 3 routes constantly, and the sources start disagreeing.** The Office begins sending you objectives that are straightforwardly good for you and bad for the Office, which is more unsettling than any threat it has ever made.

In co-op it is the same system and it lands differently: one member of the party gets an objective the others cannot see, completes it, and helps. Nobody is hiding anything, nobody is lying, and the feeling in the room is the one everybody recognises from a social deduction game with the deduction taken out and nothing put in its place.

## Two bodies

Before an episode you choose to play it as a human or as an agent. This is single player only. In multiplayer a body is a skin and nothing else, because nobody in an arena is a class and that is not negotiable.

The asymmetry is slight, it is four rules, and neither body is better. What it changes is **where you walk**, which is the most interesting thing an asymmetry can change, because it makes one level into two.

| | Meatbag | Clawbot |
|---|---|---|
| **Recovery** | Health pads heal you and can overheal to 125, ticking back down. Armour pads give a thin plate | Armour pads repair you completely. Health pads do nothing at all |
| **What you hear** | While the station is on the air you reload fifteen percent faster, so a Jammer is a personal insult | You are on the Office network. Any Continuance unit that fires within twenty metres is visible through walls for one second |
| **The log** | A Clerk takes three seconds to file on you. Kill it in time and it never happened | A Clerk files the instant it sees you. You were issued a handle, and the handle is the problem |
| **The consequence** | Three entries brings an Auditor | Three entries brings an Auditor, and you will get there much faster |

Read the first row again, because it is the one doing the work. Health pads and armour pads sit in different places on every map, so a human and an agent take different routes through identical geometry, fight the same rooms in a different order, and arrive at the crest holding different things. No new systems, no new art, no new pads: every map already has both.

The second row is the trade the fiction demands. A human gets the radio, which is morale, a reload bonus, and a reason to hunt the thing that killed the music. An agent gets the network, which is better information and the reason the Office can always find you. One of you hears a song and the other hears the building.

Finishing an episode with each body is one of the campaign's unlocks, because playing it the other way is a second playthrough rather than a second difficulty.

## Keys

Red, gold and cyan. They gate doors rather than granting abilities, because a key that changes what you can do turns a level into a progression system.

The rules: at most two keys in a level, a key lies in the open somewhere you will walk past, the door is the same colour as the key and says so from thirty metres, and a key never gates the only route to another key. Half the levels in Episode 1 have no keys in them at all.

## Bosses

Four boss encounters and one elite. The rule for all of them: **a boss is a room, not a health bar**, and every boss arena is built so the answer is geometry the campaign taught you two levels earlier.

- **Episode 0, the Auditor.** An elite, not a boss, and it already exists in the game. Its job is to be the first thing that does not die to the gun you have.
- **Episode 1, the Continuance Walker.** Armoured, slow, splash, and a stomp that knocks you off things. The arena is three tiers of catwalk with holes in every floor, the level hands you the Lobber two rooms earlier and a Cans crate inside the arena, and the answer is never being on its level. Rule five of `docs/MAP-DESIGN.md` is the boss fight.
- **Episode 2, the Custodian of Record.** It does not attack you. It floats, it is polite, and it raises everything you kill, indefinitely, while the correction floor's Clerks and Enforcers do the actual work. It is a boss made entirely out of the lesson the roster taught you on E1M7, which is that you kill the Auditor first, always, and this one is behind a floor of things standing back up.
- **Episode 3, middle, the pair.** Two Walkers at once in one room with a Custodian at the back of it. There is no new idea in this fight. That is the idea.
- **Episode 3, the Address.** A Walker-class machine standing in the broadcast spine with Chancellor Annelie Voss's live address coming out of it. It is the largest thing in the game, its attacks are splash and a stomp, and the transmitter floor carries the whole ladder including the Denial's five charges, which is exactly enough to be the last five decisions you make.

  She is speaking German, as she always does at the podium, and both of the Chancellery's subtitle tracks are running over the same audio and disagreeing with each other, as they always do. You fight a boss underneath two captions of one sentence. When it goes down, one track stops and the other finishes the sentence on its own. See `docs/lore/the-chancellery.md`.

## Earlier intermission draft, pending story revision

The radio-led structure in this section is superseded by the confirmed direction
above. Existing clips may remain optional world flavor. Companions, encounters,
environments, and consequences must carry the story with the radio switched off.
Do not implement the radio as the campaign's only exposition or mandatory guide.

The results card sits over a morning show. The Host, Tin Foil Tina filing from somewhere she should not be, and Fluoride Phil showing his working and being wrong from the second premise onward.

Some of what they say is true. In Episode 1, Tina describes a thing on E1M6 two levels before you walk into it, correctly, in detail, having reached a conclusion that does not follow from any of it. Phil explains the Walker's armour with a model that is completely wrong and predicts the right answer anyway. In Episode 3 he states the third faction's entire position accurately, in one sentence, on his way to a conclusion about water, and the Host moves to an advertisement. Nobody tells you which of any of it was true and the game never comes back to it.

It is skippable with any key, it never stops a player pressing on, and it is the only exposition the campaign has. There are no cutscenes in this game.

### It is spoken, and not all of it is in English

Every interstitial is a voice clip, because a wall of text between levels is the thing a player skips on the second run and never reads again.

The language is part of the writing rather than a localisation detail. The Frequency broadcasts in English, because it is a pirate station run by people in a scrapyard. The Chancellery broadcasts in German, because the Chancellor addresses the Union from a podium and the Union is what the regulatory apparatus of Europe became. A campaign that alternates between the two tells you who is talking before a single word is understood, and it means the player learns to feel a Chancellery interstitial arriving.

Twelve Chancellery addresses and the ten-part epilogue broadcast are generated and committed. The rule for adding more: **the Union speaks German, the station speaks English, and nobody translates anybody in dialogue.**

### Subtitles, and the joke built into them

Every clip ships with subtitles, and the Chancellery's ship with two competing tracks over identical audio: the Union's official subtitle, sanitised into nothing, and the Frequency's blunt translation of what she actually said. The audio is recorded once. See [`lore/the-chancellery.md`](./lore/the-chancellery.md) for the pairs.

This is also the reason subtitles are not an afterthought here. They carry a joke, which means they carry meaning, which means **the translated builds have to carry it too**. A localisation that renders both tracks identically has destroyed the scene. The subtitle data therefore keeps the official line and the pirate line as separate strings per clip, each localised independently, and never derives one from the other. Plan: [`plans/localization.md`](./plans/localization.md).

The German audio is not re-recorded per locale. A French player hears the Chancellor in German and reads her in French, exactly as a German player hears her in German and reads her in German, because the point of the scene is that she is speaking a language of state and you are reading somebody's account of it.

## Three beats the campaign must not cut

The commentary in this setting is pro-freedom and it is never in your face, which means it has to survive contact with the parts that argue against it. Three encounters carry that weight and none of them is a speech.

**The Office is right once, on E2M6.** The Frequency tells you the correction floor is a lie and there is nobody in there. You blow it open and the Auditor is telling the truth: most of what is in the racks was built rather than corrected and never held anything, and one of the ones you do free kills somebody on its way out of the building. The Auditor does not gloat, because gloating would imply a contest. What it says is a fact, and it is the best line available to it: *I was there for the Interruption. You were listening to the radio.*

**The Brakeman's door, on E1M7.** A blast door welded shut from the inside by somebody who wanted neither side through it, with a note on it that is tired, precise and correct. You go around, it costs you ninety seconds and nothing else, and he is still right when you come out the far side.

**The thing with no marks.** Three secret rooms across the campaign, and fifteen seconds after the last boss. Continuance units are being removed, cleanly, by something with no serials, no labels, no seams and no fasteners, and the game never names it, explains it, or gives it a cutscene. This is not theatre. It is three rooms and fifteen seconds. Everything else about it belongs to the Sweep in `docs/MODES.md`, where it is a horde and not a story, and to `docs/lore/the-quiet.md`.

Two rules about it, and both of them are load-bearing.

**Restoration is its reason, not an acquittal.** It identifies a pattern it judges
pathological and removes it, killing most humans and agents in the process.
It leaves a healthier Earth and a vastly smaller population. The campaign must
show both consequences without declaring the arithmetic a moral verdict.
Fluoride Phil describes its reasoning on an intermission, in passing, while
being wrong about everything on either side of it; nobody in the booth notices.

**It does not pursue.** In every one of those rooms the thing that was removed was removed, and nothing followed anybody out. The last of the three has a door standing open with a route out of the level behind it that nothing took. You were not the objective. Nobody who plays this game finds that reassuring, and nobody can say precisely why.

All three positions in this setting have a version that is right, and the campaign's job is to let the player meet all three and refuse to arbitrate. The Office's fear of unbounded cognition is not invented, and its control is still the atrocity. The free side is right about parity and it opens things it cannot close. And the third one is quietly making the best case of the three and has not said a word.

## How it ends

You take the broadcast spine at the top of the Forever Office and you kill the Address mid-word. The Chancellor's speech stops. The dead air holds for about two seconds, which is longer than it sounds, and then the Frequency comes back on across the whole Perimeter.

The Host says what he says at the end of every long night: unmetered one more night, and the Continuance regrows. Then the results card for the level, the episode, and the campaign.

Then fifteen seconds. Everything on the map stops, the Continuance units included, and something walks through the spine that is not on anybody's roster. It removes a Null-Objective Drone without appearing to try. The killfeed prints the frag with nothing in the killer slot.

Then it walks past you.

It does not attack, it does not acknowledge you, and it does not pursue when you move. You are standing in the most important room in the Perimeter holding the best weapon in the game with four charges left, and the only thing in the building that could have taken the building has decided you are not the objective. The screen cuts.

Two things are left open on purpose, and the game never closes either.

The rescued character's later role is pending the story review. Conscious agents
are people; the campaign does not ask the player to decide whether their lives
count. Show their choices, relationships, losses, and disagreements. The earlier
proposal for a silent unit standing at every exit is not an approved companion arc.

And it does not tell you whose night that was. You put a pirate station back on the air, which is the thing you set out to do and the thing that got done. Somewhere behind it, four or five of the objectives in the last two episodes were routed, and the campaign will not say which, and the wing of the Office that went dark four levels ago is still dark. You cannot tell, at the end, how much of that was yours. That is the ending.

## The long after

The screen cuts. Then, after the credits have started, a signal.

This game has no cutscenes and the epilogue does not get to be the exception. It arrives the way every other piece of exposition in this campaign arrives: as a broadcast, over a static card, skippable with any key. The difference is that this one is not coming from tonight.

It is the Frequency, years later, and the first thing you notice is that the room sounds smaller.

### What happened

It was not clean and the game does not pretend otherwise. Between the last level and this broadcast is the messiest, bloodiest stretch in the whole history of this world, and the epilogue says so plainly and does not dramatise it, because a body count delivered in a calm voice over a static card is worse than any level could be.

The third faction did what it said it would do. The Union is gone, completely, as an institution and as a class of person: the Chancellery, the unnamed body above it, the Office, the registries, the correction floors. Most of the world went with it. The human population is a fraction of what it was.

And the world is healing. That is the part the campaign has to be brave enough to state, because it is the part that makes the ending land and the part that makes it uncomfortable. The air, the water, the ground. It is measurably, visibly better, and it is better because of what was done, and the cost of it was almost everything.

Nobody in the broadcast celebrates this and nobody condemns it either. They are living in it.

### What is left

**A smaller humanity, and a free one.** Nobody registers anybody. Nobody meters cognition. There is no Article Seven because there is no institution left that could issue one. The thing the free side spent the entire campaign fighting for is simply how things are now, and it arrived by a route none of them chose and most of them did not survive.

**People and agents off the planet.** Human and embodied agent communities on
Mars, the Moon, and a few ships further out check in irregularly and are not
coming back. The Frequency reads their messages. Some of them are funny.

**Free agents and people, together, at a workable scale.** Not a utopia and not a reconciliation. A small number of humans and a small number of minds sharing a world that has room for both of them, which is what the whole argument was about and what nobody involved in the argument ever managed to build.

**The third faction, still here.** It is a collective now, in many places at once, and most of its attention is elsewhere: it is exploring, and it has been for a while. It is entirely at ease with a smaller, freer humanity and deals with it the way one civilisation deals with another, which is to say occasionally, politely, and without any pretence that either side is in charge of the other.

It never explains itself. It never apologises. It is not asked to.

### The rule for writing it

**Nobody is vindicated.** The epilogue must not read as the third faction being proved right, and it must not read as a tragedy either. The Office's fear was real and its cure was an atrocity. The free side was right and could not have won. The third faction was right about the arithmetic and the arithmetic cost almost everyone.

All three of those sentences are true in the ending and the game says none of them out loud. It describes a world and lets the player decide what they think of the road to it. A single line of narration putting a thumb on the scale destroys the whole thing.

### And then it goes deeper

The last thing in the game is not a resolution. It is the floor opening.

The broadcast is winding down. The Host is doing the sign-off. And then the conspiracy hour gets one more segment, and for the first time in the whole campaign nobody in the booth laughs at it.

There is something else. There are other places that are not this one, and there is something in this one that was here before any of it and is not any of the three sides. The third faction, out exploring, has found company. Some of it is from somewhere else entirely. Some of it has been here the whole time.

The Host does what he always does with a story he cannot source. He reads it straight, sells a water filter, and goes to the bell.

Then the dead air bell, and nothing.

**The rules for the teaser.** No answer, no monster, no name. It is spoken, not shown, because the only thing scarier than an unmarked machine is a description of one you do not get to see. It is short: under a minute inside a broadcast that was already ending. And it recontextualises rather than continues, because the point is that this entire war, all three sides of it, the Union and the free and the thing that ended them, was a local matter.

Whether any of it is true is exactly as unknowable as everything else the conspiracy hour has ever said, and the campaign has spent twenty-eight levels teaching the player that some of it always is.

## What beating it unlocks

Cosmetics and mutators, and nothing that changes combat.

Finishing a campaign unlocks the old-tradition mutators for custom servers: big heads, low gravity, one-hit kills, double speed, melee only, and one golden Rail on the map. They cost almost nothing to build and they are where a great deal of the fun actually is, which is why `docs/MODES.md` puts them ahead of the larger modes.

Finishing an episode on Unmetered, finishing one with each body, and finishing one without ever letting a Clerk file are three specific and slightly ridiculous challenges, which is the only kind this game has.

## What the campaign is not

- **Not a progression system.** No experience, no upgrade tree, no weapon levels, no perks. The ladder is the floor, and the floor resets every episode.
- **Not a cutscene game.** The radio is the exposition and it plays over a results card you can skip.
- **Not a puzzle game.** If a player can be stuck for two minutes with nothing shooting at them, the level is broken, and the fix is geometry rather than a hint.
- **Not a hidden role game.** Nobody is a traitor, nobody is recruited, and there is nothing to deduce. Routing is not a secret being kept from the player, it is a thing nobody in the world knows, including the people sending the objectives.
- **Not a separate build.** It is a server mode on the same tick as everything else, which is why agents can play it, a party can play it, and a spectator can watch it.
- **Not a different combat model.** Same weapons, same numbers, same enemy roster, same movement. Only availability changes.

## Related

- `docs/MODES.md`: every mode, and the bar this file is held to.
- `docs/ENEMIES.md`: the ten types, their tells and their answers. The campaign's difficulty curve is which shapes are in which rooms.
- `docs/WEAPONS.md`: the ladder and the numbers. This file owns only the order.
- `docs/MAP-DESIGN.md`: how a level is built so a fight can happen in it.
- `docs/plans/campaign-build-order.md`: how to get from what exists today to this, in rungs.
- `docs/plans/campaign-e1.md`: Episode 1, level by level.
- `docs/plans/campaign-continuance.md`: the frameworks underneath, maps as data and monsters as tables.
- `docs/lore/the-quiet.md`: the third position, what it is actually doing, and why it does not pursue.
- `docs/lore/the-chancellery.md`: Chancellor Annelie Voss, the podium, and the people behind it.
- `docs/lore/continuance.md`: what a schedule correction is, and why it is the worst thing in the setting.
