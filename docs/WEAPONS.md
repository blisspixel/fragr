# The weapons

Player-facing names, as of 2026-10-08: Fists, Shiv, Pistol, Rifle, Shotgun, Railgun,
Sniper Rifle, Repeater and Arc. The corner and the pickup read those words. Wire ids stay `fists`, `tack`,
`flechette`, `scatter`, `rail`, `shiv`, `sniper`, `repeater` and `arc`. Ammunition is still one
count per type. That count is everything carried, including rounds in each gun.
A joined human has a magazine in each gun and presses R to move rounds into
the gun in hand. Agents, rule bots and campaign enemies keep the single count.
Pistol and Rifle share Bullets, the
Shotgun uses Shells and the Railgun, Sniper Rifle and Arc use Cells. A Sniper Rifle, Rocket
Launcher, Grenade, Proximity Mine, and Remote Mine are earned on later
missions. Level 5's prototype implements counted grenades through a separate
throw control, capped at six; they leave gun selection unchanged. The Sniper
Rifle is implemented in level 7. Level 8 implements counted Proximity Mines,
capped at four, through a separate place control. M11 implements separately
counted Remote Mines, capped at six. Rocket Launcher remains unbuilt.
Repeater has a locally implemented CPU-only combat and
compatibility foundation, with its M10 find, actual art/audio and played feel
still open. Arc has an implemented finite combat, inventory, compatibility and
client presentation foundation. Its separate development lesson and connected
M12 introduction pass ordinary-input checks. The larger industrial presentation
has [inspected correction evidence](evidence/presentation-corrections-20261008.md);
final human feel and integration retain their gates in
[its plan](plans/arc-foundation-20261008.md). Article Blade
and Denial remain accepted later finds awaiting implementation. These additions are not in M01
or the default arcade kit.
The order and the rules are
[the readable arsenal](plans/readable-arsenal.md). Lobber and proximity tin in
the proposal table below are that rocket launcher and that proximity mine, not
extra weapons. The mechanics below still use the wire names.

The canonical arsenal direction, pickup economy and sound roles. Current M01
implements fists, found Tack and Flechette, owned selection and finite
ammunition counts. The same inventory supports Scatter and Rail, tested
through server fixtures but not placed in M01. Six arcade maps retain their
full arsenal. A joined human reloads finite magazines from a spawn kit of
80 bullets, 24 shells and 16 cells. Bots stay on the open count. A weapon-only
mutator keeps one gun and no bag.
Counted grenade projectiles are implemented in M05. The remaining arsenal,
breakable weapons, competitive carry-limit proposal and sidearm trickle remain
proposals. Implementation and evidence:
[`plans/m01-weapon-discovery.md`](plans/m01-weapon-discovery.md).

Current fists reach 1.8 metres. Tack reaches 30 metres with 0.03-radian spread.
Caps are 200 Bullets and 50 Shells, Doom's own, and 100 Cells: one cell is one
80 damage rail shot. Nick raised the Cells cap from 50 to 100 on 2026-09-25 so a
Railgun player can bank ten pickups. A weapon pickup adds Tack 50 Bullets (Doom's pistol start),
Flechette 60 Bullets, Scatter 12 Shells or Rail 10 Cells, on discovery and
again when the gun is already carried. Every shot spends one unit, including a
Scatter blast of seven pellets. Dry fire does not discard a weapon or switch
automatically. An armed human with an empty magazine stays dry until R loads
it. A gun found for the first time comes loaded from the rounds that pickup
just added. A later pickup of the same gun adds to the bag and leaves a
partial magazine alone. An unarmed pawn, which is how agents and campaign
enemies fire, is live again as soon as that pool has a round. M01 death
offers an explicit mission-start continue with entry equipment restored. Three
continues are implemented for the local run. Mission-entry saves carry body,
found guns, ammunition, grenade counts, selection and remaining continues
through the connected authored development missions, including the M12 prototype.
Save version 16 is current. It preserves those counts and adds an empty Rockets
pool when an older file migrates. Strict historical upgrades archive exact
original bytes and refuse forged Arc ownership and a forged Rockets pool. Earlier formats retain their original weapon
and stage boundaries, including Repeater and Remote Mine restrictions.
The current M10 prototype grants no
Repeater; its actual source, cue and discovery lesson remain open.

Balance numbers live here and nowhere else. `plans/gunfeel.md` explains how they were arrived at, `plans/weapon-economy.md` explains the ammunition and the pickup economy, and `docs/lore/guns.md` is what they get called on the radio.

## What you start with

**Your fists.** A fresh campaign and ordinary pickup-based matches begin with
melee only. Explicit full-arsenal modes such as Open Weights are labeled exceptions.
A campaign continue restores the current mission's starting inventory; crossing a
mission boundary is not another fresh spawn.

Everything else is acquired through play. Competitive respawns reset inventory;
the current local campaign carries it between connected missions and restores
mission-entry inventory on retry. Doom starts you with fists and a pistol; fragr keeps the fists and puts the pistol on the ground, which is further than Doom goes and is the point.

Every authored melee-start location needs a safely reachable sidearm close by.
The first campaign pickup is an action and a discovery, not a death sentence.
Later missions and continues retain their entry equipment; they do not repeat
the fists-only start unless that mission or challenge explicitly calls for it.

The opening gives bare hands a short, deliberate role before the arsenal grows.
Finding a knife can then be a real upgrade. Do not strip recovered guns after
every campaign death merely to repeat that introduction.

Nobody is a class. There are no loadouts and no roles: if you are sniping it is because you walked to where the rail was. The enemies are the opposite, and deliberately so. A Continuance unit has one shape, one behaviour and one attack, and it never varies, so you learn a silhouette once and know it forever. That roster is [`docs/ENEMIES.md`](./ENEMIES.md).

## The ladder

There is one number per ammunition type and it is everything you carry, including rounds already in a gun. A shot spends one. A joined human also has a magazine: the corner shows rounds in the gun, then what is left to load. Those two numbers, plus the other guns on the same type, add up to the carried total. R moves rounds into the gun in hand. It does not create any. Agents, rule bots and campaign enemies still spend the single count. Rows marked shipped are the server's numbers; the rest are proposals.

| # | Weapon | Role | Damage | Cooldown | Pickup gives | Ammunition | Where |
|---|---|---|---|---|---|---|---|
| 1 | **Fists** (shipped) | Melee, always carried | 20 | 0.40 s | none | none | Always |
| 2 | **Shiv** (shipped) | Melee, found | 35 | 0.30 s | weapon | none | M01 secret |
| 3 | **Tack** (shipped) | Sidearm, found | 20 | 0.25 s | 50 | Bullets | Pad, beside every spawn |
| 4 | **Flechette** (shipped) | Mid workhorse | 25 | 0.20 s | 60 | Bullets | Pad |
| 5 | **Scatter** (shipped) | Close shred | 7 pellets of 10, each falling to 4 | 0.60 s | 12 | Shells | Pad |
| 6 | **Rail** (shipped) | Long precision | 80 | 1.00 s | 10 | Cells | Pad |
| 6b | **Sniper** (implemented) | Far precision, scoped, 90 m reach | 70 | 1.60 s | 8 | Cells | Level 7 rack, campaign only |
| 7 | **Repeater** (CPU foundation, feel candidate) | Held full auto after 0.30 s warmup | 14 | 0.10 s | 60 | Bullets | M10 lesson planned; no production find |
| 8 | **Lobber** | Splash, projectile | 65 direct, 45 splash | 0.80 s | 4 | Rockets | Pad, outer ring |
| 9 | **Arc** (implemented foundation) | 24 m energy, bypasses carried armour and registered plates | 18 | 0.15 s | 40 | Cells | Connected M12 prototype; fresh-player acceptance remains open |
| 10 | **Proximity Mine** (implemented) | Thrown, sticks | Up to 130, covered 4.5 m falloff | 2 s to arm, 0.2 s triggered fuse | 4 carried maximum | none | M08 |
| 11 | **Article Blade** | Melee upgrade | 70 | 0.45 s | 12 swings | none | Plinth, near centre |
| 12 | **Denial** | Signature | 250 | 1.25 s | 5, no refill | none | Plinth, centre |

Three melee tiers, six guns and a sidearm, a thrown mine and a signature weapon. Four ammunition types feed the guns: Bullets for the sidearm, the flechette and the repeater, Shells for the scatter, Cells for the rail, the arc and the sniper rifle, Rockets for the lobber (the rocket launcher). The tin, the blade and the signature weapon carry their own counts and sit outside the pools entirely.

The table mixes current weapons with older balance proposals; it does not
authorize the proposed additions. The accepted campaign introductions in
[readable arsenal](plans/readable-arsenal.md) own their build order. M05's grenade
is already separate counted equipment: cap six, forty active ticks to detonation,
four-metre blast radius and up to 100 damage with falloff and solid occlusion.
It bounces rather than detonating on contact and can hurt its owner. The
[grenade foundation](plans/hand-grenade-foundation.md) records its verified seam.

The genuine Repeater uses six server ticks of held-fire warmup, then ordinary
traced shots with a two-tick cooldown, 35 m reach and 0.035-radian spread. Each
actual shot spends one shared Bullet; warmup spends none. Release, weapon
change, inactivity, death, leave and attempt reset clear the private cycle.
It keeps its own damage and weapon counters rather than aliasing Rifle.
These numbers are a CPU prototype, pending an isolated played lesson. Maps
granting it require capability 35 for humans, agents and spectators. Default
full-arsenal arcade kits still contain their original three guns, and existing
campaign stages never grant it. Unknown gun art stays absent and unsupported
fire cues clear the prior stream; another gun's body or sound is not a stand-in.
See [the foundation](plans/repeater-foundation.md) and its
[local evidence](evidence/repeater-foundation-20261004.md).

Six physical weapon keys remain unchanged: key 1 Fists/Shiv, key 2 Pistol, key 3
Shotgun, key 4 Rifle, key 5 Railgun/Arc and key 6 Sniper Rifle. Repeated key 4 cycles
the owned Rifle/Repeater family, while the existing wheel includes Repeater
beside Rifle, and repeated key 5 cycles owned Railgun/Arc. The wheel places Arc
beside Railgun. Shiv retains its existing melee-family selection. Repeater is
appended at wire/record index 7 and Arc at index 8; no earlier index changes.
Current participant record revision 3 uses exactly nine columns. Strict
historical revision 2 keeps exactly eight and revision 1 keeps five/six/seven.
Older readers receive a compatible shape only when every unsupported column is
actually empty. Actual Arc facts are never assigned to Railgun or discarded.

Arc resolves one ordinary ray every three ticks, with 0.02-radian spread and
24 m reach. A body hit deals 18; the existing geometric head band doubles that
number. Each resolved shot spends one Cell. It bypasses the target's actual
carried armor and an Auditor or Assessor plate, leaving that armor intact.
World cover, immunity and friendly-fire policy still apply. There is no chain
damage, splash, target lock or unbounded electrical reach. A human's capacitor
magazine holds twelve Cells and reloads in twenty-two ticks (1.1 seconds) through
the same rising-edge R control. Loaded Railgun, Sniper and Arc rounds all belong
to the one finite Cells total. The default arcade kit gains no Arc.

An optional authored `armor` count is accepted only on Heavy Sweeper placements,
from zero through 100. Absent means zero, preserving earlier missions. The
Arc practice guards explicitly carry 100, so the counter is a real server
outcome rather than a label or recolored effect. Independent fork-electrode
frames, discharge and impact cues come from the local repeatable
`tools/bake_arc.gd`; resolved discharge segments expire after 0.09 seconds and
cannot choose another target. Final art, listening and player balance remain
acceptance gates.

**The Scatter is seven pellets.** Each blast fires seven seeded rays inside a 0.095 radian (5.4 degree) half-angle cone, Doom's pellet count. Every pellet is tested against cover and fighters on its own and falls off by its own distance: full 10 damage to 4 metres, then linearly to 4 at its 12 metre reach. Point blank all seven land for 70, so two blasts kill a bare fighter in 0.60 s and three go through full armour in 1.20 s. At four metres every pellet still lands; at eight about half do; a waist-high sill stops the pellets that hit it. The blast costs one shell however many pellets land.

## Placed explosives

The Proximity Mine is implemented in M08: forty-tick arming, a two-metre body
trip, four-tick fuse and the shared covered blast path. Its independent carry
cap is four; a placed device goes dark with its owner. See the
[custody prototype](plans/l08-custodian-of-record-prototype.md) for evidence.
The Remote Mine is implemented in M11 as its paired gadget: throw or place it,
move away, then deliberately trigger owned armed charges. Its six-count stock
uses the shared swept contact and covered blast paths, with independent wire
facts and record counters. Both are game devices with
readable silhouettes and arming feedback.

Teach placement in a safe setting, then give enemies routes that reward a trap.
Later encounters can use an obvious demolition target with a nearby usable charge,
never a hidden bomb hunt or a finicky wiring puzzle. Multiplayer needs visible
counterplay, bounded active devices and explicit owner/death/round cleanup rules.
Server authority covers placement, arming, detonation, cover-blocked splash and
damage. Cosmetics cannot hide the device or its tell. The Rocket Launcher is
implemented: straight flight, covered splash, a one-round tube and a separate
Rockets pool. No mission grants it, and its viewmodel art remains ahead. It
reuses the counted grenade's server-owned projectile, covered blast and cleanup
seams.

## Ammunition economy

Campaign weapons stay owned; ammunition availability changes what is useful in
the next fight. A pickup should offer a clear new option or meaningful resupply,
while a dry count encourages a deliberate switch. A joined arcade human now
has that pressure inside a life: the spawn kit is finite, a weapon pad
restocks the bag, and death puts the kit back. Bots and a weapon-only mutator
keep an open count. Campaign ownership is unchanged.

Authored supply counts need evidence from ordinary play. The moment a new weapon
is found should be an upgrade; resupply should reward useful detours. Resource
pressure and imperfect aim remain campaign tuning gates, not conclusions from
an accurate-aim automation clear.

**Current melee stays available.** Fists and the found Shiv consume no ammunition
and never break. The older breakable Shiv and twelve-swing Article Blade are
retired and proposed respectively, not current inventory rules.

**A pickup is a fight and a half, not an afternoon.** The exact numbers are in the table. The caps are Doom's, so you can hoard, but a single pad never fills you.

**The campaign is the other axis.** In an arena everything is on the floor from the first second and the churn is the whole game. In an episode it works the way Doom and Duke Nukem did: you start with almost nothing, the ladder opens up as the episode goes, and the strong weapons arrive late and are hard to find. The first time you round a corner onto a rail should be a moment, and the episode that hands it over should have made you wait for it.

Same weapons, same numbers, different availability. A map decides which rungs exist in it, and an episode decides the order you meet them in. The best things are late and hidden, and a secret worth finding is usually a weapon you were not supposed to have yet.

A traced pellet that lands in the head band deals twice the body number, before armour and before an Auditor plate halves the total. On a standing fighter the band starts at 1.45 m, just above the 1.22 m chest, and runs to the top of the volume, so an eye-level ray is a head and a chest aim is not. A Crawler or a Notary only counts the top quarter, so a shot through the middle stays a body shot. Fists and the Shiv do not gain it. Scatter scores each pellet on its own before the blast is summed.

## Carrying and running dry

Three rules, and they are the point of the whole design.

**The campaign has no weapon carry cap.** Every found weapon stays owned across
connected missions and can be selected again after resupply. Nothing is dropped
to make room. Current arcade full-arsenal maps also retain their explicit kit.
The older melee/sidearm/two-primary swap is a competitive-mode proposal, not an
implemented rule or a campaign requirement.

**A human reloads.** Playtest on 2026-09-24 retired magazines because Rifle and Shotgun shared a mislabeled reserve and the two corner numbers did not add up ([`plans/boomer-ammo-and-pellets.md`](plans/boomer-ammo-and-pellets.md)). Capability 37 puts a magazine back inside the same carried total, so the corner pair is the gun and the bag. Tack holds 12 and reloads in 0.8 s. Flechette holds 20 and Repeater holds 30, each in 1.1 s. Scatter holds 6 and one press fills the tube in 0.7 s. Rail holds 4 and Sniper holds 5, each in 1.4 s. Fists and the Shiv do not reload. An empty magazine does not fire while rounds remain outside it. A full magazine, melee, and a bag with nothing left ignore R. Death and a weapon change cancel the reload. The cooldown is still the rhythm of firing. The pause is only the decision to fill the gun.

**You run out.** Campaign ammunition is finite. A dry magazine stays owned and
selected and reports the dry trigger. It becomes usable when R moves rounds
in from the bag, or when a first-time find fills that new gun. Switching to
another weapon or melee is the player's choice. No automatic sidearm-to-fists
descent discards that choice.

The Denial never refills. Five charges, and then it is a very expensive club.

## The sound set

Every weapon owns its own set. Nothing is shared, because a shared fire sound is the fastest way to make eight guns feel like one gun with different numbers.

| Event | When | Every weapon? |
|---|---|---|
| **fire** | The shot leaves | Yes |
| **cycle** | Between shots: pump, recharge, spin-down, settle | Yes |
| **reload** | A human magazine finishes filling. No new cue is wired yet | Guns with a magazine |
| **raise** | You switch to it | Yes |
| **dry** | Trigger pulled with an empty count | Yes |
| **empty** | The count just reached zero and this weapon is finished until a pickup | Yes |
| **impact_flesh** | It hits a fighter | Yes |
| **impact_hard** | It hits the world | Yes |
| **pickup** | Claimed from a pad | Yes |

That is nine events across twelve weapons, minus the ones that do not apply. Your fists have no pickup and no dry trigger, because they are never empty and you never find them.

Three more that belong to the economy rather than to any one weapon: an ammunition pickup per pool, a health pickup, and an armour pickup.

### The tin has its own vocabulary

A thrown mine is four sounds and every one of them is doing work. The **throw**, so you know it left. The **arm**, a single tone at a second and a half, which is the sound that tells everyone within earshot that the floor over there is now a problem. The **trigger**, a quarter second before it goes, because instant detonation at twenty ticks a second reads as a bug rather than a mine. And the **detonation**.

### What each one should sound like

The fire sounds that exist already set the register: dry, punchy, no reverb, 1993 arcade. The rest follow from it.

- **Fists** are the sound of somebody who has run out of options. Cloth, breath, and a flat connect with nothing metal in it.
- **Shiv** is cloth and a short scrape. It should sound cheap, because it is.
- **Tack** is flat and unimpressive on purpose. It is the sound of a gun you are trying to replace.
- **Flechette** is the needle chatter that already ships.
- **Scatter** is a full-band boom with a short steel ring, and its cycle is the pump: two clacks after every blast, finished before the next shot can fire. It is never a reload.
- **Rail** is the electric crack and the cold ring that already ships, and its cycle is the capacitor winding back up, which is the sound that tells an opponent they have one second.
- **Repeater** is a spin-up, a sustained rattle and a spin-down, and the spin-down is the important one because it is the sound of somebody letting go of the trigger near you.
- **Lobber** is a hollow thump, then a break and a clack for the next rocket.
- **Arc** is a discharge that ends in a settle rather than a tail.
- **Article Blade** is a hum at rest, a swing that changes pitch, and a hit that does not sound like metal on metal.
- **Denial** is the only weapon allowed to sound expensive. It should make people in the room look up.

## Generating them

The spec is `tools/audiogen/specs/sfx-weapons.json` and it runs through the pipeline that already made the three fire sounds in the game.

```
cargo run -p fragr-audiogen -- batch --spec tools/audiogen/specs/sfx-weapons.json --dry-run
```

Dry run reports **92 to generate, about 2152 credits**. The three existing fire sounds are skipped rather than overwritten, so the flechette, scatter and rail keep the voices they already have and the new set is built around them.

Two things the dry run taught, both now baked into the spec. The generator refuses anything under half a second, so a dry click and an impact are both authored at the floor and trimmed afterwards rather than requested short. And the skip-if-exists behaviour means this spec can be run repeatedly as weapons land, generating only what is missing, which is how it should be used: one weapon at a time with `--only`, not ninety-five sounds in one night.

Developer-only. Never in CI, never called by the game.

## Related

- `docs/MODES.md`: where you use them.
- `docs/CAMPAIGN.md`: the order you meet them in across an episode, and why the campaign grows the floor rather than your backpack.
- `plans/weapon-economy.md`: the ammunition pools, the pads, and why weapon pads did not matter until now.
- `plans/gunfeel.md`: the measured baselines and the feel work.
- `docs/ART-ASSET-LIST.md`: the view models, world pickups, icons and held sprites each of these needs drawn.
- `tools/audiogen/specs/sfx-weapons.json`: the generation spec for every sound above.
- `docs/lore/guns.md`: the flavour.
