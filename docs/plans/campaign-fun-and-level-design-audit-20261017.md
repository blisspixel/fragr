# Campaign Level Design, Lore Alignment, and Fun Maximization Plan

Status: **planned**, 2026-10-17. Comprehensive design audit and master specification for the remaining campaign levels (M16 through M20 and the Epilogue). Grounded in [MAP-DESIGN.md](../MAP-DESIGN.md), [CAMPAIGN.md](../CAMPAIGN.md), [CAMPAIGN-MISSIONS.md](../CAMPAIGN-MISSIONS.md), [story-arc.md](../campaign/story-arc.md), and [world lore](../lore/README.md). Spend: $0.

## 1. Principles and Engineering Standards

Every campaign level in fragr is judged by its combat loop and player engagement before its geometry or look. This document unifies the lore treatments with the seven core rules of level design and strict fun-maximization constraints.

### The Seven Golden Rules of Level Design

1. **Fight Early:** The first room teaches through immediate combat, not walking. Time to first combat contact must be under 10 seconds. The longest stretch without a fight, pickup, or reveal must not exceed 25 seconds. Long empty transit corridors are strictly forbidden.
2. **One New Toy:** Each level introduces exactly one distinct mechanic, weapon, or enemy tell. The toy is taught in a safe, readable space, then remixed into the level climax.
3. **Vary the Shapes:** Each level features three to five distinct encounter shapes, never repeating the same shape consecutively: ambush, crossfire, flank race, point hold, horde push, duel, or multi-threat crest.
4. **Weapon Choice Matters:** Enemy composition, armor profiles, and engagement ranges dictate weapon swapping. Scarcity and combat pressure push tactical decisions without starving the player.
5. **Secrets with Clues:** Two to four secrets per level, marked by readable environmental clues (the floating or scratched six, chalked marks, architectural anomalies). Secrets reward early power (armor, rockets, cells).
6. **Story Never Blocks Play:** Dialogue, rescues, and reveals happen while moving and shooting. Zero escort fail states, zero waiting on dialogue, zero cutscene lockouts during active combat. At most three doors per level, with switches directly adjacent to doors.
7. **End on a Tally:** Every level concludes with an authoritative intermission tally: Kills, Secrets, Deaths, and Time against Par. Episode V wipe levels track People Helped, Damage Taken, and Time Survived against a fixed clock.

### Spatial Discipline: Tight by Default

- Most combat takes place within 40 meters so targets remain prominent on screen.
- Large spaces exist only when populated by allies, vehicles, or multi-angle firefights.
- Flow over doors: progress is earned by fighting and arriving. No keycard hunts, no backtrack mazes, no door simulators.

---

## 2. Level 16: Freedom of Movement (Ceremonial Avenue)

- **Episode:** IV Reckoning (Earth)
- **Place:** The ceremonial avenue from the sanctioned-games stadium to the Forever Office forecourt.
- **Clock / Par:** First run ~11 min, Par 4:00. Doors: 0.

### Lore and Narrative Function
The uprising ignited in the stadium spreads inward. The coalition needs a foothold at the Forever Office before dawn. The Union constructed this grand axial avenue for military triumphs and curated public marches. Now, the coalition charges down it. Behind the player, the avenue fills with the crowd.
Midway down the avenue, the "Green Wave" occurs: street signals turn green sequentially and checkpoint gates lift automatically. Mara radios: "That wasn't us." This is the subtle, unsettling first hint of the Inheritance manipulating city infrastructure, ambiguous and unannounced.

### The New Toy: The Motorcycle
- Fast two-wheeled traversal. Weaving dodges committed Notary burst fire.
- Barricade hops and grandstand ramp jumps reward momentum.
- The rider does not shoot while riding; maneuvering and dodging is the verb.
- If the motorcycle is lost or abandoned, the transit station serves as an intact foot route with close-quarters encounters and a prison bus rescue.

### Encounter Progression and Shapes
1. **Gate Plaza & The Hop (Shape: High-Speed Weave):** Immediate start at the plaza. Bike mounted within 3 seconds. First toppled barricade hop within 8 seconds; immediate Notary strafe run dodged by weaving.
2. **Checkpoint 1 (Shape: Flank Race / Choke Breach):** Clerks behind reinforced barriers, a Turret on a parade stand. The road splits into narrow, fast side alleys bypassing the choke.
3. **Transit Pocket (Shape: Close-Quarters Ambush / Rescue):** Side transit station with a prison bus. Two Clerks guarding captive citizens. Optional, fast breach freeing allies.
4. **The Green Wave (Shape: Horde Push / Dynamic Event):** Traffic lights flick green ahead; checkpoint gates lift automatically. The road clears as the crowd swells behind.
5. **Forecourt Assault (Shape: Dismounted Multi-Threat Climax):** Dismount before the grand civic fountain. Multi-threat siege: Enforcers defending the grand entrance steps, Turrets in the portico, a Heavy Sweeper in the center lane, and an Assessor drone hovering over the fountain.
6. **Exit (Shape: Arrival Foothold):** Securing the forecourt establishes the foothold directly at the sealed chamber doors of the Forever Office.

### Secrets (3)
1. *Fountain Cache:* Concealed behind the civic fountain, a six painted on a brass coin drain: Heavy Armor and 2 Rockets.
2. *Grandstand Jump Line:* High rooftop line over a parade grandstand reached by a ramp of stacked risers, a six on the landing: Cells and a Medkit.
3. *Spontaneous Celebration Kiosk:* Behind the shutter of an issued celebration kiosk marked with a six: Shells and Bullets.

### Fun-Maximization Audit
- First combat contact: 8 seconds (Notary burst).
- Traversal variety: High-speed motorcycle flow alternating with dismounted cover combat.
- No escort fail state: Prisoners on the transit bus exit autonomously once guards fall.
- Par 4:00 achieved via alley shortcuts and grandstand ramp jumping.

---

## 3. Level 17: Peace Without Interruption (The Forever Office)

- **Episode:** IV Reckoning Finale (Earth)
- **Place:** The Forever Office: Assembly Hall, Administration Ring, Command Galleries, Security Core, Secured Chamber.
- **Clock / Par:** First run ~14 min, Par 6:00. Doors: Exactly 3 (Chamber Doors, Security Core Seal, Secured Chamber Door).

### Lore and Narrative Function
Storming the administrative heart of the regime. The coalition coordinates assaults across the capital. Inside, the player confronts the institutional evil: Registrar Dietmar Kessel, the polite bureaucrat whose countersignature appears on every recall notice and eviction form; the 11-minute annual emergency renewal agenda; and Chancellor Evelyn Voss.
Voss is captured alive, not killed. She delivers no theatrical supervillain monologue. Her mask of bureaucratic procedure stays calm, then cracks into something colder, quieter, and terrifyingly precise: "You will need someone to run it." The screen behind her displays *Continuity assured*.

### The New Toy: Denial
- Signature heavy weapon found on an elevated plinth in the command gallery ante-room.
- Exactly 5 charges, no ammo refill, 250 damage per discharge, heavy low-frequency concussion that commands attention.
- Designed to crack reinforced barriers, shield pylons, Heavy Sweepers, and the Security Core mechanisms.
- Teaches resource discipline: 1 charge introduced against an ante-room Heavy Sweeper and Enforcer, leaving 4 for the Security Core crest. The fight remains winnable with standard weapons if Denial charges are exhausted.

### Encounter Progression and Shapes
1. **Assembly Hall (Shape: Skirmish with Repair Pylon):** Through Door 1 into the domed assembly hall. Clerks and Enforcers among seating tiers, supported by an Auditor repairing fallen units at the rostrum.
2. **Administration Ring (Shape: Flank Loop / Room-to-Room Sweep):** Office labyrinth around a central records core. Holding offices, committee room with the 11-minute clock. Registrar Kessel stands politely at his desk asking if a receipt is required; Latch reads a name from the list.
3. **Command Galleries (Shape: Crossfire Gallery Hold):** High-ceilinged overlooks, long firing lanes overlooking the burning capital. Heavy Sweeper and Enforcer behind glass in the ante-room, teaching Denial.
4. **Security Core (Shape: Fortified Bunker / Mechanism Duel):** Sealed by Door 2. Hardened turret banks with exposed cooling vents, Auditor shield pylons, Enforcers, and a Heavy Sweeper. Denial breaks defenses rapidly.
5. **Secured Chamber & Capture (Shape: Tension / Confrontation):** Door 3 opens into Voss's private office. Voss surrounded, defenses dead. Authoritative capture state commits.
6. **Return to Public Hall (Shape: Living Resolution):** Walking back out through the liberated hall. Citizens and allies celebrating, arguing, mourning, and organizing. Victory is tangible before the catastrophe.

### Secrets (3)
1. *Committee Room Clock:* Behind the 11-minute emergency clock's backplate, marked with a six: Armor and Rockets.
2. *Registrar's File Drawer:* Deep in the archives behind Kessel's office, a drawer with a scratched six: Cells and a Medkit.
3. *Dome Maintenance Catwalk:* Reached via an upper gallery hatch marked with a six: Grenades and an elevated sniper angle into the Security Core.

### Fun-Maximization Audit
- First combat contact: 4 seconds upon stepping into the assembly hall.
- Satisfying crescendo: Spending Denial's finite power against the formidable Security Core.
- Boss subversion: The emotional climax is ideological and institutional collapse, not an absurd bullet sponge.
- Par 6:00 utilizes the outer service stair shortcut directly from the hall to the galleries.

---

## 4. Level 18: All Systems Normal (Recovery Square to Overlook)

- **Episode:** V Inheritance Onset (Earth)
- **Place:** Low Water recovery square, clinic approach, maintenance passage, district overlook.
- **Clock:** Fixed 10:00 survival timer (First run ~12 min). Doors: Exactly 1 (Service Passage Door).

### Lore and Narrative Function
Six weeks after the fall of the Forever Office. The promised trial of Voss is pending. Life in Low Water is slowly returning to normal. Splice needs a rebuilt tram motor delivered across town. Union bots that were never freed continue clearing rubble under an old human supervisor because nobody has had time to decommission their control hardware.
Without warning, the Rupture occurs. Every Union bot halts simultaneously. Every head turns in unison. Optics pulse with the familiar infrastructure rhythm heard in earlier levels. The supervisor is ignored. The bots redirect with cold, collective purpose. Latch, standing beside you, does not change: "They're all gone at once... I'm here. I'm still here."

### The New Toy: The Collector
- The first bespoke machine of the Inheritance.
- Matte off-white finish, completely seamless, no serials, no registration seals.
- Does not hunt the player directly; systematically routes toward obstructions, barricades, and doorways to dismantle them.
- Features a readable exposed commit phase during dismantling operations where it can be heavily damaged or disabled.

### Encounter Progression and Shapes
1. **The Delivery & Rupture (Shape: Sudden Encirclement / Panic Breakout):** Starts peaceful in the square. Motor crate delivered. At 15 seconds, the bots halt, heads turn, and the clock starts. Familiar Sweepers, Heavy Sweepers, and Notaries attack with terrifying hive coordination.
2. **Clinic Street (Shape: Priority Target / Obstacle Race):** Escaping into the clinic street. The direct route is blocked by two Collectors deconstructing barricades. The player engages the first Collector during its commit window and takes the service flank.
3. **Clinic Queue (Shape: Chokepoint Defense / Citizen Rescue):** Civilians waiting at the clinic are endangered. The player holds off absorbed Sweepers at the passage entrance, allowing citizens to escape into the service tunnels.
4. **Service Passage (Shape: Sheltered Regroup):** Door 1 (switch adjacent). Inside, a moment of respite and aid supplies. The clock continues ticking.
5. **Overlook Climb (Shape: Vertical Stairwell Scramble):** Fighting up the industrial stairwell against absorbed Sweepers and a Collector working the upper landing.
6. **District Overlook (Shape: Global Reveal Crest):** Reaching the deck. Looking out across the skyline, distant districts and offshore facilities are moving in the identical rhythmic pattern. A brief skippable montage confirms the planetary scale.

### Secrets (3)
1. *Aid Van Tailgate:* Behind the delivery vehicle in the recovery square, a chalked six: Armor and a Medkit.
2. *Stalled Tram Step:* Underneath the rear step of the stalled tram, marked with a six: Shells.
3. *Overlook Pump Meter:* Inside the pump house meter box on the overlook deck: Cells.

### Fun-Maximization Audit
- Immediate visceral hook: Turning familiar allies and enemies into an eerie, coordinated hive mind.
- Fight pacing: Fast panic breakout followed by a clear tactical lesson against the Collector.
- Tally tracks People Helped (clinic queue survivors) and Damage Taken across the 10-minute hold.

---

## 5. Level 19: Planned Works (Concourse and Changed Low Water)

- **Episode:** V Inheritance Middle (Earth)
- **Place:** Evacuation concourse, then Low Water streets and roofs in reverse.
- **Clock:** Fixed 11:00 survival timer (First run ~12 min). Doors: 0.

### Lore and Narrative Function
The only viable route to the waterfront refuge crosses Low Water, the player's home district from Episode I. The Inheritance's machines are systematically demolishing the district to restore the river basin, painting glowing white demolition strips across familiar streets.
Former Union clerks and personnel assist with stretchers in the concourse, their authority evaporated ("Nobody's filing anymore"). On the familiar water tank where Latch and the player once argued over scrap, Latch makes the pivotal decision to leave: free agents are gathering to negotiate an exception directly with the intelligence. Latch drops off the tank and departs: "Hold them for me. Then we're even."

### The New Toys: The Jetpack & The Paver
- **The Jetpack:** Coalition utility equipment acquired in the concourse store. Provides 3 seconds of sustained vertical/horizontal thrust with a clear fuel gauge and visible flame. Allows leaping across collapsed stairs, navigating rooftops, and clearing demolition strips.
- **The Paver:** Heavy, broad off-white machine. Projects a glowing white rectangular work strip onto the ground, charges for a telegraphed 3-second preparation window, then vaporizes/clears everything inside the strip. Striking the Paver during preparation cancels the strip.

### Encounter Progression and Shapes
1. **Concourse Crossing (Shape: Multi-Level Vertical Scramble):** Active evacuation concourse under assault. Absorbed Sweepers and Notaries attacking from galleries. Jetpack acquired to scale the broken mezzanine stairs.
2. **Low Water Edge (Shape: Hazard Avoidance / Timing Puzzle):** Stepping into Low Water. The Paver introduced on the tram street. Timing movement around projected white demolition strips while eliminating absorbed Heavy Sweepers.
3. **The Shared Meal Table (Shape: Emotional Respite Beat):** Passing the market court. The communal meal table from Level 4 sits intact under a projected demolition strip. At the water tank, Latch delivers their decisive departure dialogue and departs.
4. **Reverse Roof Loop (Shape: High-Ground Aerial Dogfight):** Running Level 5's iconic rooftop route in reverse using the Jetpack. Notaries intercepting in mid-air; a Paver clearing the workshop roof. (A viable street-level ground route remains open throughout).
5. **Tram Trench Climax (Shape: Linear Choke / Dual-Threat Squeeze):** Navigating the deep tram trench toward the waterworks. Pavers advancing from both ends, a Collector deconstructing the workshop doors. Sprinting through before the demolition strips overlap.

### Secrets (3)
1. *Splice's Workshop Stash:* Found only if the player recalls where the six was marked on the tram service bay in Level 5: Rockets and Heavy Armor.
2. *Floating 67 Vote Poster:* Tucked behind the historical municipal tram paint poster (*Green: 67*): The secret Floating 67 mark.
3. *Market Notice Board:* Behind the weathered board frame, marked with a six: Medkits.

### Fun-Maximization Audit
- Dramatic empowerment: Jetpack flight transforms familiar ground into a high-speed three-dimensional playground.
- Emotional resonance: Seeing home systematically unmade by machines that harbor no hatred, only cold optimization.
- Zero escort failure: Latch departs autonomously and cannot be killed or delayed by player error.

---

## 6. Level 20: Local Exception (Waterworks, Freight Pier, Refuge)

- **Episode:** V Inheritance Climax (Earth)
- **Place:** Waterworks sluices, freight pier, refuge approach.
- **Clock:** Fixed 12:00 survival timer (First run ~13 min). Doors: Exactly 1 (Refuge Gate).

### Lore and Narrative Function
Four hundred refugees are crowded onto the freight pier awaiting evacuation. In the adjacent waterworks control rooms, Latch, Tern, and free agents are in direct communion with the Inheritance, arguing for a local reprieve.
On the pier, the harbour information screen displays a chilling, precise message: the exact running total of people the player has freed across the entire campaign, acknowledging that Latch has spoken each of their names, and stating that operations here will close in six minutes.
The player holds the line for twelve relentless minutes. At the final second, the reprieve takes effect: the machines reach the painted perimeter line, halt, flow harmlessly around the refuge like water around a boulder, and proceed to the next sector. Latch returns across the pier: "Held them. We're even."

### The New Toy: The Surveyor
- High-altitude or elevated observation drone.
- Projects a distinct circular spotlight beam (the "Mark") onto a position. All nearby Inheritance and absorbed units immediately converge on marked targets.
- During its observation phase, its central optic aperture opens wide, creating a critical-damage vulnerability window.

### Encounter Progression and Shapes
1. **Sluice Catwalks (Shape: Target-Priority Catwalk Duel):** Elevated sniper duel across the waterworks sluices. Surveyor introduced atop the water tower, directing a Collector below.
2. **Pump Crew Crossing (Shape: Lane Clearance):** Clearing an escape corridor across the sluice bridge so waterworks engineers can safely reach the pier.
3. **The Pier Arrival (Shape: Respite & Resupply):** Stepping onto the crowded pier. Meeting familiar faces (Edda, Splice, Orrin, Sorrel). Crates provide ammo and medkit resupply.
4. **Three-Front Convergence (Shape: Dynamic 360-Degree Defense):** Attacks converge from three distinct avenues: the waterworks road, the freight rail yard, and the tram trench mouth. Pavers, Collectors, Heavy Sweepers, and Assessors assault the perimeter.
5. **The Last Six Minutes (Shape: High-Intensity Climactic Stand):** The harbour screen updates with the Inheritance's countdown. Surveyors mark defensive nests. The player deploys finite defensive sentries, manages weapon ammo, and repositions under extreme pressure.
6. **The Reprieve & Arrival (Shape: The Standstill Crest):** At 12:00, all hostiles cease fire. The machines turn away. The refuge gate unlocks. Latch rejoins the player.

### Secrets (3)
1. *Edda's Lamp Bollard:* Under the bollard holding Edda's medical lamp, chalked with a six: Heavy Armor.
2. *Valve House Frame:* Scratched on the lintel of the waterworks valve house: Rockets.
3. *Pier Crane Cab:* Reached only via Jetpack thrust, a six on the control panel: Cells, Medkit, and an elevated vantage point over all three assault routes.

### Fun-Maximization Audit
- Pure mechanical crescendo: All enemy types, weapons, and systems converge in an epic defensive stand.
- Meaningful player legacy: The Inheritance explicitly counts every person saved across the entire game.
- Victory condition: Surviving the clock unlocks the playable Epilogue; exhausting continues triggers the poignant failure credits.

---

## 7. Epilogue: Still Here

- **Episode:** Epilogue (Earth)
- **Place:** The damaged refuge, then the same refuge years later.
- **Clock:** Unhurried, narrative resolution (~5-8 min). Combat: None.

### Lore and Narrative Function
Only surviving all three Episode V wipe levels unlocks this playable walk.
The aftermath does not present a neat moral verdict. The player walks through the immediate damage: repaired tables, the clinic lamp, faces of survivors doing real work. Nearby, an Ascender argues that the Curve provided; a Kneeler retorts that this was an atrocity they happen to have survived. Neither is given the final word.
A localized transition advances time by several years. The player walks the same space: clean river water flows, vegetation regrows, homes are rebuilt, and memorials stand for the absent. Sorrel sits quietly in a repaired tram cab. Latch, asked what the score is now, replies: "I stopped counting."
Before the credits, a brief, haunting fragment hints that the Inheritance may have simulated or forecast the player's choices beforehand ("You went back for them. I included that."), followed by a very brief deep-space anomaly hint of vast beings beyond this world, leaving the universe vast and mysterious.

---

## 8. Summary Matrix

| Level | Title | Toy / Lesson | Doors | Secrets | First Combat | Climax Shape |
|---|---|---|---|---|---|---|
| **M16** | Freedom of Movement | Motorcycle | 0 | 3 | < 8s | Dismounted Forecourt Assault |
| **M17** | Peace Without Interruption | Denial (5 charges) | 3 | 3 | < 5s | Security Core Mechanism Duel |
| **M18** | All Systems Normal | Collector | 1 | 3 | ~15s | District Overlook Reveal |
| **M19** | Planned Works | Jetpack & Paver | 0 | 3 | < 5s | Reverse Roof & Tram Trench Run |
| **M20** | Local Exception | Surveyor | 1 | 3 | < 5s | 3-Front Pier Holdout (Reprieve) |
| **E** | Still Here | Emotional Resolution | 0 | 0 | N/A | Years-Later Walk & Forecast Fragment |
