# The weapons

Player-facing names, as of 2026-09-22: Fists, Pistol, Rifle, Shotgun, Railgun.
The corner and the pickup read those words. Wire ids stay `fists`, `tack`,
`flechette`, `scatter`, and `rail`. Ammunition is Doom style (2026-09-24): one
count per type, no magazines and no reload. Pistol and Rifle share Bullets, the
Shotgun uses Shells and the Railgun uses Cells. A Sniper Rifle, Rocket
Launcher, Grenade, Proximity Mine, and Remote Mine are earned on later
missions. They are not in M01, not in the arcade arsenal, and not implemented.
The order and the rules are
[the readable arsenal](plans/readable-arsenal.md). Lobber and proximity tin in
the proposal table below are that rocket launcher and that proximity mine, not
extra weapons. The mechanics below still use the wire names.

The canonical arsenal direction, pickup economy and sound roles. Current M01
implements fists, found Tack and Flechette, owned selection and finite
ammunition counts. The same inventory supports Scatter and Rail, tested
through server fixtures but not placed in M01. Six arcade maps retain their
explicit full-arsenal policy with unlimited Flechette, Rail and Scatter.
The remaining arsenal, projectiles, carry limits, broken weapons and sidearm
trickle below are proposals. Implementation and evidence:
[`plans/m01-weapon-discovery.md`](plans/m01-weapon-discovery.md).

Current fists reach 1.8 metres. Tack reaches 30 metres with 0.03-radian spread.
Caps are 200 Bullets and 50 Shells, Doom's own, and 50 Cells: one cell is one
80 damage rail shot, so the cap follows Doom's rocket count rather than its
plasma count. A weapon pickup adds Tack 50 Bullets (Doom's pistol start),
Flechette 60 Bullets, Scatter 12 Shells or Rail 10 Cells, on discovery and
again when the gun is already carried. Every shot spends one unit, including a
Scatter blast of seven pellets. Dry fire does not discard a weapon or switch
automatically, and any pickup of that type makes it live again at once. M01 death
offers an explicit mission-start continue with entry equipment restored. Three
continues are implemented for the local run; cross-mission persistence remains unbuilt.

Balance numbers live here and nowhere else. `plans/gunfeel.md` explains how they were arrived at, `plans/weapon-economy.md` explains the ammunition and the pickup economy, and `docs/lore/guns.md` is what they get called on the radio.

## What you start with

**Your fists.** A fresh campaign and ordinary pickup-based matches begin with
melee only. Explicit full-arsenal modes such as Open Weights are labeled exceptions.
A campaign continue restores the current mission's starting inventory; crossing a
mission boundary is not another fresh spawn.

Everything else is acquired through play. Competitive respawns reset inventory;
the proposed normal campaign carries it between connected missions and restores
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

There is one number per ammunition type and it is everything you carry. A shot spends one. There is no magazine and nothing to reload, which is how Doom does it and why its fights never stop for housekeeping. Rows marked shipped are the server's numbers; the rest are proposals.

| # | Weapon | Role | Damage | Cooldown | Pickup gives | Ammunition | Where |
|---|---|---|---|---|---|---|---|
| 1 | **Fists** (shipped) | Melee, always carried | 20 | 0.40 s | none | none | Always |
| 2 | **Shiv** | Melee, found | 35 | 0.55 s | 25 hits | breaks | Pad, common |
| 3 | **Tack** (shipped) | Sidearm, found | 20 | 0.25 s | 50 | Bullets | Pad, beside every spawn |
| 4 | **Flechette** (shipped) | Mid workhorse | 25 | 0.20 s | 60 | Bullets | Pad |
| 5 | **Scatter** (shipped) | Close shred | 7 pellets of 10, each falling to 4 | 0.60 s | 12 | Shells | Pad |
| 6 | **Rail** (shipped) | Long precision | 80 | 1.00 s | 10 | Cells | Pad |
| 7 | **Repeater** | Heavy full auto | 14 | 0.10 s | 60 | Bullets | Pad |
| 8 | **Lobber** | Splash, projectile | 65 direct, 45 splash | 0.80 s | 4 | Rockets | Pad, outer ring |
| 9 | **Arc** | Energy, ignores armour | 18 | 0.15 s | 40 | Cells | Pad, outer ring |
| 10 | **Proximity tin** | Thrown, placed | 90 at centre | 1.5 s to arm | 3 carried | none | Pad |
| 11 | **Article Blade** | Melee upgrade | 70 | 0.45 s | 12 swings | none | Plinth, near centre |
| 12 | **Denial** | Signature | 250 | 1.25 s | 5, no refill | none | Plinth, centre |

Three melee tiers, six guns and a sidearm, a thrown mine and a signature weapon. Four ammunition types feed the guns: Bullets for the sidearm, the flechette and the repeater, Shells for the scatter, Cells for the rail, the arc and the sniper rifle, Rockets for the lobber (the rocket launcher). The tin, the blade and the signature weapon carry their own counts and sit outside the pools entirely.

**The Scatter is seven pellets.** Each blast fires seven seeded rays inside a 0.095 radian (5.4 degree) half-angle cone, Doom's pellet count. Every pellet is tested against cover and fighters on its own and falls off by its own distance: full 10 damage to 4 metres, then linearly to 4 at its 12 metre reach. Point blank all seven land for 70, so two blasts kill a bare fighter in 0.60 s and three go through full armour in 1.20 s. At four metres every pellet still lands; at eight about half do; a waist-high sill stops the pellets that hit it. The blast costs one shell however many pellets land.

## Placed explosives

The proximity tin remains planned. Add a remote-detonated charge as its proposed
paired gadget: throw or place it, move away, then trigger a deliberate ambush.
Use one shared placed-explosive implementation with explicit trigger behavior,
rather than separate damage systems. Final carry limits, damage, blast radius
and availability need prototype evidence; the table does not define remote-charge
balance. Both are game devices with readable silhouettes and arming feedback.

Teach placement in a safe setting, then give enemies routes that reward a trap.
Later encounters can use an obvious demolition target with a nearby usable charge,
never a hidden bomb hunt or a finicky wiring puzzle. Multiplayer needs visible
counterplay, bounded active devices and explicit owner/death/round cleanup rules.
Server authority covers placement, arming, detonation, cover-blocked splash and
damage. Cosmetics cannot hide the device or its tell. Projectiles and explosives
are unbuilt and follow the existing inventory and combat seams.

## Weapons are consumable

The closest thing to how this should feel is a kart racer's item box. You are getting something often. You are also losing it often. Holding a good weapon is a temporary state you enjoy and then lose, not an inventory you build.

So the pads are generous and the counts are thin. You will find a rail several times in a round and you will fire it maybe nine times each time you do. The moment you pick something up is an upgrade moment, the way it is in Halo when you trade up off a dead opponent, and the moment it runs dry is a real event that changes what you are doing.

**Melee lasts longer and still ends.** The shiv takes twenty-five hits before it breaks. The Article Blade has twelve swings and returns to its plinth. Melee outlasts a gun because you find it less often, and it still runs out, because nothing here is permanent except your fists.

**A pickup is a fight and a half, not an afternoon.** The exact numbers are in the table. The caps are Doom's, so you can hoard, but a single pad never fills you.

**The campaign is the other axis.** In an arena everything is on the floor from the first second and the churn is the whole game. In an episode it works the way Doom and Duke Nukem did: you start with almost nothing, the ladder opens up as the episode goes, and the strong weapons arrive late and are hard to find. The first time you round a corner onto a rail should be a moment, and the episode that hands it over should have made you wait for it.

Same weapons, same numbers, different availability. A map decides which rungs exist in it, and an episode decides the order you meet them in. The best things are late and hidden, and a secret worth finding is usually a weapon you were not supposed to have yet.

## You carry four things and you run out

Three rules, and they are the point of the whole design.

**You carry a melee, a sidearm, and two found weapons.** Not twelve. Picking up a third primary means choosing which one hits the floor, and you make that choice under fire with a number in your head about how much ammunition each one has left. A loadout you never have to edit is not a loadout, it is a menu you looked at once.

**Nothing reloads.** This used to say every weapon reloads. Playtest said the two numbers in the corner did not add up and the pause did not add a decision, so the magazine went (2026-09-24, [`plans/boomer-ammo-and-pellets.md`](plans/boomer-ammo-and-pellets.md)). The cooldown is the rhythm of firing and the count is the budget; the decision is which gun spends it.

**You run out.** Ammunition is found, it is finite, and a weapon whose count is empty is dead weight you are carrying instead of something better. Running dry drops you to the sidearm; running the sidearm dry drops you to your fists. That descent is a real thing that happens in a long fight, and it is supposed to be frightening rather than merely inconvenient.

The Denial never refills. Five charges, and then it is a very expensive club.

## The sound set

Every weapon owns its own set. Nothing is shared, because a shared fire sound is the fastest way to make eight guns feel like one gun with different numbers.

| Event | When | Every weapon? |
|---|---|---|
| **fire** | The shot leaves | Yes |
| **cycle** | Between shots: pump, recharge, spin-down, settle | Yes |
| **reload** | Retired with magazines on 2026-09-24; generated clips stay on disk unused | No |
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
- **Scatter** is the boom and the pump that already ships, with the pump promoted to its own cycle so you hear it when you are not firing.
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
