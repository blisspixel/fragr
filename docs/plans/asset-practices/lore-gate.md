# Lore and design consistency gate for generated assets

Environmental storytelling follows the [art bible](../../ART_STORY_BIBLE.md#environmental-storytelling-and-signs):
about six readable signs per multiplayer map or eight per campaign level,
with short wayfinding, objective or landmark copy. Replace explanatory prose
boards with props, composition, light and imagery. Small canon marks remain
diegetic. Review actual placements at playing distance, including duplicates.

Written 2026-10-24 for Nick's request: "all assets we make make sense with the
lore and worlds and designs for consistency ... if it's not clear, think
through it." This is a working gate, not canon. Where it adds anything that
canon does not already say, the line is marked **Proposal for Nick**.

**Canon read in full** (all from `origin/wave2/integration`, head `e7d350ce`,
2026-10-24): every `docs/lore/*.md`, `docs/CAMPAIGN.md`,
`docs/CAMPAIGN-MISSIONS.md`, `docs/ART_STORY_BIBLE.md` (including the faction
readability contract, now merged and marked "enforced in the multiplayer
client"), every `docs/design/*.md`, `docs/palette.json` and `docs/VISION.md`. I
also read `.agents/canon/asset-canon-review.md`, `ep5-canon-review.md` and
`larak-lot-canon.md`. Supporting reads: `docs/ENEMIES.md` (roster rows),
`docs/plans/asset-round-20261023.md`, `radio-stations.md`, `radio-refresh.md`,
`campaign-transition-audio.md`, `audiogen-voice-design-20261023.md`,
`audio-round-20261013.md`, the headings of `higgsfield-pipeline.md` and
`meshy-pipeline.md`, the briefs `meshy-assets/c-tern.md`, `e-locomotive.md`,
`c-sorrel.md` and `c-orrin.md`, `campaign/l11-right-of-search.md`,
`tools/audiogen/src/casting.rs`, and the untracked specs
`h-ll-larak-props-20261024.json`, `h-m7-bank-refs-20261024.json` and
`h5-union-seal-20261023.json`. No paid call was made and no tracked file
changed.

The brief template that goes with this gate is in
[`brief-template.md`](brief-template.md).

---

## 0. How the gate runs

There are two checkpoints. They are the same questions asked at two different
times.

| Gate | When | Who | What passes |
|---|---|---|---|
| **A. Brief gate** | Before any paid call: before a Higgsfield `gen`, a Meshy `meshy-gen`, or an ElevenLabs `batch`, `design` or `tts` | Engineer. Nick for the items in section 11.3 | A filled brief (template), with the prompt text and negatives read against sections 1 to 9 |
| **B. Candidate gate** | Again after each stage: the reference sheet, the Meshy GLB (untextured and textured), the prepared in-engine asset, and audio after it has been measured | Engineer, then Nick's taste gate where listed | The checklist in section 11, judged at play size, in the target light, in motion |

The verdicts follow the 2026-10-23 canon review: **PASS**, **FIX PROMPT**,
**REDO** (start again from a better reference), and **HOLD FOR NICK** (canon is
unclear, or the item is a named-identity or taste decision). A HOLD is not a
failure. It is a stop.

**Where each fact lives** (`lore/README.md`, "Give each fact one home"):

| Question | Owner |
|---|---|
| Why a side looks the way it does | `docs/lore/*.md` (README, the-chancellery, the-inheritance, people-and-agents) |
| How a side reads at 30, 15 and 5 m | `ART_STORY_BIBLE.md#faction-readability-contract` |
| Exact swatches | `docs/palette.json`. "Avoid inventing new swatches per prompt." (bible, Palette) |
| A place's look | `docs/design/{earth,moon,mars,space}.md`, then that level's `docs/campaign/l*.md` / `m*.md` |
| A person's look | `docs/lore/cast.md#visual-continuity`, then `docs/design/characters.md` |
| How people sound, and which words are frozen | `docs/lore/voice.md` |
| Weapon fiction and marks | `docs/lore/guns.md` |
| Enemy roles and tells | `docs/ENEMIES.md` |

A generation never creates canon. "Do not establish specific ages, ethnicity,
facial features or voice IDs through one stray generation. Approve and record
the reference before producing sets." (`cast.md`). "A generation or temporary
narration voice does not approve a new character identity." (`characters.md`)

---

## 1. Hard rules (any one failure stops the asset)

| # | Rule | Canon basis |
|---|---|---|
| H1 | **Allegiance reads from the world's canon, not arbitrary colour.** Every fighter, bot, machine, vehicle, carried item and cosmetic declares one of: Union, free human, free agent, Inheritance restoration, absorbed bot, league (no side), or neutral/civic. | Bible: "a fighter's allegiance must read from the world's own canon, not from arbitrary asset colour. The contract below is binding on every fighter, bot, machine, cosmetic and team presentation." |
| H2 | **Reserved combinations.** Black plus red is Union only. A matte off-white dominant base is Inheritance only. Red emissive light is Union only. Cyan working light is Inheritance (and absorbed bots) only. Free personal light is warm: amber, warm white, CRT phosphor. | Contract: "Two combinations are **reserved** and a free body may never use them ... Personal light is warm (amber, warm white, CRT phosphor), never red optics or cyan glow." Colour picker rule: red hue about 340 to 20 degrees, cyan about 160 to 220, off-white value at or above 0.80 and saturation at or below 0.15. |
| H3 | **No generated lettering, and no essential text in pixels.** Text, numbers, serials, seals and signage go on as in-engine decals with i18n keys. Ask the generator for blank plates, blank seal bosses and blank tags. Lettering stays level, never tilted. | `CAMPAIGN.md`: "Never bake essential text into an image or video." `asset-round-20261023.md`: "No tilted or rotated text." `asset-canon-review.md`: keep the text negatives "and **ask for blank geometry**". |
| H4 | **Nothing real.** No real insignia, salutes, slogans or uniforms (above all of the historical regime). No real flags, including the American flag. No national kit. No manufacturer logos or copied weapon or vehicle models. No real broadcasters, politicians or people. No imitated voices. No protected emblems (a medical red cross). No franchise likeness. | `the-chancellery.md#felt-never-named` ("Never"); contract: "never an American uniform, flag or national kit"; `guns.md`: "without manufacturer logos or copied weapon models"; `voice.md`: "Do not imitate or name real broadcasters"; `cast.md` (Edda): "avoid copyrighted service emblems". |
| H5 | **Period: practical retro-futurism around 2070.** Recognizable present-day remnants, CRT-like displays, physical controls, repaired electronics, and a few purposeful advanced systems. | Bible: "Established Moon and Mars bases coexist with recognizable industrial hardware, CRT-like displays, physical controls, civilian firearms and personally repaired electronics. A few advanced systems should have clear purposes and mechanical weight." |
| H6 | **Tone: fun on the outside, serious underneath.** Captive suffering, correction, rescue failures and deaths are never punchlines. Union cruelty is bureaucratic and understated, never gory. Union menace comes from order, never from spikes or skulls. | `lore/README.md`: "Captive suffering and unavoidable rescue failures are not punchlines." `the-chancellery.md`: "the disturbing detail is bureaucratic, never graphic." Bible: "never spikes, skulls or cartoon villainy". |
| H7 | **The Inheritance comes late.** Combat with its machines happens only in levels 18 to 20 and Wipe multiplayer. Levels 16 and 17 may carry signs, never a fight. Nothing before the wipe states its objective or timing. | Contract: "Combat against Inheritance machines belongs to the wipe (levels 18 to 20); levels 16 and 17 may carry signs, never a fight." `the-inheritance.md`: "no running mission commentary". |
| H8 | **Stylized pixel craft, not photographs.** Angular painted planes, broad values, coherent pixel clusters. No photographic skin, pores, fabric weave or dense material noise. | Bible: "Shrinking a photographic person is not a completed pixel character." |
| H9 | **Named people keep their anchors** (section 8). A different planet, outfit or generation never redesigns a person. | Bible, Character reference contract: "transport alone does not redesign a person." |
| H10 | **Free side, free voice.** World text and narration see events through free humans and agents. The Union's words appear only as signs, forms and addresses. | `the-chancellery.md`: "The Union's own words appear as signs, forms and addresses the player reads or hears, never as the narrator." |

---

## 2. Faction looks

The rule underneath this whole section: **"Location supplies material and
light; faction supplies manufacture and marking. Neither replaces the other. A
Union lunar depot must read as both."** (bible, Factions, places and
continuity)

### 2.1 Bodies and carried equipment (the readability contract)

| Side | 30 m: silhouette, value, light | 15 m: livery blocking | 5 m: detail | Palette keys | Motion | Never |
|---|---|---|---|---|---|---|
| **Union** human troops | Dark mass; severe, upright, rectangular; drilled stance; steady **red** points at the visor | Black cloth and armour; plates one step lighter; red armbands, visors and seals | Serial and type-approval plates (blank, decaled later), original Union emblems, repeated numbered insignia, issued weapon housings, peaked service caps, stylized faces under red visors | `union_black`, `union_steel`, `union_plate`, `union_red`, `union_red_glow` (optics only) | Disciplined, ordered ranks | Spikes, skulls, cartoon villainy, a cruel face on every soldier, pale armour dominating, any real uniform or insignia |
| **Union** bots | As above. Plated chassis, sunk or optic heads | Black and red livery with serial plates | Same | Same | Mechanical gait; distinguishable from humans by shape and movement | "enslaved agents" framing on the roster; red used anywhere but optics, tells, bands and seals |
| **Union** committed elites (Enforcer, Redactor) | Heavier powered armour, own silhouette | An extra red rank seal or collar | Same | Same | Charge or distortion tells per `ENEMIES.md` | Rank read by colour alone |
| **Union** Office equipment (Notary, Assessor, Turret, Walker) | Black mass, red optics as the tell light | Plates one step lighter | Blank type-approval plate and blank seal boss | Same | The tell per `ENEMIES.md` (Assessor: "two red optics count down"; Turret: "red charge") | Pale fan rings or pale armour; painted chevrons; one red band where the tell is two optics |
| **Free humans** | Asymmetric, layered, mismatched outline (packs, slung gear); mid or varied values; warm personal light | Personal colour blocking; repairs, stickers and patches break every large panel | Ground-off plates, cut seals, scratched serials, hand lettering (decal), sewn patches, individual faces | `rust`, `ember`, `ember_hot`, `gunmetal*`, `dust_*`, `magenta_*`, `leaf_muted`, `outline_purple`; bone and black as small accents only | Relaxed, individual gestures | Union black plus red; a matte off-white base; red or cyan emissive; a universal rebel uniform; tactical armour; cowboy costume as the default; a flag |
| **Free agents** | As free humans; a warm screen face or lamp, never a dark mass with no light | Personal paint in the player's or the person's own scheme | Same, plus individual screen expressions | Same | Each one individual | A black-and-red body (it reads as a controlled bot); a clean off-white body; cyan optics; military unit armour |
| **Inheritance** restoration machines | Pale, continuous, unfamiliar outline with few breaks | Matte off-white over ink joints; no markings | No serials, faces, emblems or readable marks | `bone` (matte) body, `ink` joints, `cyan_muted` indicators at low energy | Deliberate and coordinated; shared timing | Neon; chrome; red; skulls; killer-robot war imagery; a humanoid spokesperson; many panel lines |
| **Absorbed bots** (Union chassis taken at the wipe) | The recognizable black Union chassis, lit **cyan**, never red; coordinated timing | Keep Union paint and plates | Old serials remain, "but nothing answers to them" | Union keys, with `cyan_muted` replacing `union_red_glow` | Shared cadence, synchronized head turns, no response to Union humans | A brand-new model replacing the chassis; marks "magically" vanishing; red optics still lit |

The contract also says how this is checked: "Check every band in pixel-art at
play resolution, under each environment's combat lighting, in motion, in
grayscale and with the colour-vision settings."

### 2.2 The league (a venue culture, not a side)

- League venues are "old ranges with the power still on". They are not Union
  venues (`the-league.md`; `lore/README.md`: "The independent scrap league and
  Union-sanctioned coercive games are separate organizations").
- The tribes are looks, not factions: Night Watch ("black tactical with no
  insignia"), Static Kids (glitch, missing vowels), Hangar Candy ("glossy
  black-triangle drip", DENIED stamps), Gulf Breeze (believers, coordinates).
  "These are how people look, not what they believe."
- A free-for-all has no Union side and no coalition side. A Union callsign
  "never appear[s] in a free-for-all" (`cast.md`, The wider roster).
- League paint is warm, hand-sprayed and mixed: ember, rust, mustard, warm
  canvas. Bone must not dominate venue signage
  (`larak-lot-canon.md`, fix 6). Red neon must stay outside the reserved red
  hue band (`larak-lot-canon.md`, fix 7: LARAK neon moved from `ff6a2a` to about
  `ff8c2e`).
- The Office's presence in a league venue is "authority here on paper": its
  notices are defaced, its seals are cut, and one "PEACE WITHOUT INTERRUPTION"
  plate stays intact because it is a grief slogan (`larak-lot-canon.md` §4).

### 2.3 Equipment and props that belong to a side

- **Issued (Union)** objects carry their paperwork on the outside: "a riveted
  type-approval plate, a stamped directive number, a multilingual warning
  placard, an intact tamper seal, an asset registration stencil" (`guns.md`).
  For the generator, all of these are **blank** geometry.
- **Freed** issued objects: "the approval plate ground off to bare scarred
  metal, the seal cut, the serial scratched out with a blade. There is no
  standard replacement mark." (`guns.md`)
- **Free civilian or workshop** objects need not have begun as Union property:
  stocks, grips, finishes and repair histories show ownership (`guns.md`).
- **Free equipment that survives the wipe** must show local, wired, physical
  control: no antenna, no dish, no wireless module (`the-inheritance.md`:
  "Resistance equipment must have actual locally isolated controls; repainting
  a captured device or changing its faction cannot remove a remote control
  dependency").
- **Crew-run utilities** (waterworks, pier crane, sluice) are neutral working
  infrastructure with no faction marks (`asset-canon-review.md`, Approved props).
- A free sentry and the Union Turret are both tripod guns. The free one never
  uses red, because the Turret's tell is "a red charge" (`asset-canon-review.md`,
  flag 2).

### 2.4 Proposal for Nick: Union fixed plant versus issued equipment

The bible says the Union black-and-red is "the outfit and issued-equipment
signature, not a universal wall palette." It does not say where a **heavy fixed
machine** falls, such as a press, a furnace or a lathe in a Union-run works. The
M7 bank spec currently paints every M13 foundry machine in full Union black with
a red band. That fills the foundry with large black masses, against which the
level's black-and-red squads have to be read.

**Proposal for Nick:**

- Mobile issued equipment gets the full livery: vehicles, drones, consoles a
  person operates, restraints, recall cars, weapons.
- Heavy fixed plant takes its **material from the place** (heat-darkened steel,
  Martian dust, worn industrial enamel such as `institutional_green` or
  `gunmetal_light`) and its **marking from the Union** (a blank type-approval
  plate, a blank seal boss, at most one narrow red band).

This applies "location supplies material and light; faction supplies
manufacture and marking" literally, and it keeps enemy silhouettes separate from
the background. Until Nick decides, judge each machine with a grayscale capture
in which an enemy stands in front of it.

### 2.5 Proposal for Nick: red emissive on Union fixtures

Red optics are "every Union attack tell light" (bible). Several Union fixture
prompts ask for lit red lamps: the registration console, the luggage scanner,
the broadcast console tally lights and the correction machine. In a fight room,
a red point at head height reads as an optic.

**Proposal for Nick:** red stays **paint** on fixtures (seal rims and narrow
bands). Lamps on Union fixtures are unlit red lenses, or amber or white working
light. Lit red emissive is kept for Union actors' optics and attack tells. The
negative prompt "red light" in the free-side specs already follows the same
logic.

---

## 3. Place looks

| Place (levels) | Materials and palette | Light | Landmark and lived detail | Must not |
|---|---|---|---|---|
| **Earth: Low Water and Perimeter homes** (4, 5, 19, epilogue) | Worn plaster, repaired steel, cloth, muted terracotta and sage; bone and warm gunmetal; personal accents | Late-afternoon sun, practical warm lamps | Homes above repair stalls, Edda's clinic, the shared meal table, rooftop tanks, charging cables, the tram and its green paint vote | Read as a prison or a generic industrial arena; a universal rebel uniform; regrowth before the years-later time change |
| **Earth: Union institutions** (1, 2, 15, 16, 17) | Bone enamel, `institutional_green` tile, dark steel, restrained red seals | Repeated service lighting, local fixture pools, real ceilings | Queues, counters, numbered thresholds, confiscation bins, "successive authority seals on the same door", visible control infrastructure | Red on every wall; cartoon cruelty on every prop. "A maintained Union clinic, an overworked dispatch desk or an honestly useful safety notice can share an institution with coercive custody." |
| **Perimeter rail yard** (3) | Weathered concrete and steel | Daylight | Rails, car doors, signal box, the visible red jamming mast | A clean futuristic station |
| **Moon** (6 to 9) | Pale bone and grey mineral dust, dark basalt, weathered pressure shells | Hard exposed light with deep shade outside; neutral and warm utility light inside | Crater rims, pressure doors, seals, dust traps at thresholds, curfew streets, the launch cradle | A generic blue space tint; an empty landing pad; gravity or vacuum mechanics the server does not have |
| **Ships**: the Common Carrier (10) | Gunmetal ribs, worn bone pressure doors, repaired cargo interfaces | Warm local work light; muted cyan only on navigation equipment | Bunks, galley, cargo, an unfinished card game, Tern's battered recording | "Endless glowing corridors"; a pristine sci-fi hallway |
| **Ships**: the Union custody tender (11) | Union black and red, more regular issued fittings | Controlled thresholds | "Orderly, quiet, and full of forms"; the transfer hold | The Carrier's warmth |
| **Mars** (12 to 14) | Rust terrain, worn pale shielding, dark industrial frames | Dust-filtered amber outside, neutral work light inside | Pressure doors, wind protection, hab modules, contained agriculture, the foundry, the launch works | "Mars is not every orange room"; people and gunfire merging into red ground; open blue rivers |
| **League venues**: Larak Lot and the arena myths | Concrete, old range hardware, league spray paint in warm mixed colours | Sodium and warm work light; the venue's own neon outside the red band | The five levels and the Pit, Aunt Linda's revival on level three, the Dead Air Bell, the Stands, Larak's signature, the 2009 coffee machine, creed graffiti, six-in-a-circle | A Union venue; police livery; "Perimeter Parking Authority"; squatter fiction; bone dominance; a "coalition side" |
| **The wipe** (18 to 20) | **Keep the pre-wipe palette and landmarks** | Local failures, interrupted light | Infrastructure changing purpose, imported matte machines, white work strips, people carrying things | Instant vegetation, a global green wash, an invented new planet, generic neon sci-fi |
| **Years-later Earth** (epilogue) | The same structures, with moss and leaf accents, clean water and weathering | Natural light reaching newly opened spaces | Memorials, absences, repairs, surviving communities | A green tint offered as a finished aftermath |

**Readability against the place.** "Keep accents purposeful and silhouettes
distinct from their background." (bible) The 2026-10-23 reviews found three
cases where the place camouflaged the enemy: pale props beside pale Inheritance
machines (the tram, turnstile and filter skid), a Paver on pale concourse tile,
and dark evacuee crowds next to black Sweepers. Any asset that will share a
frame with an enemy needs a grayscale capture with that enemy in it.

---

## 4. Period checklist (around 2070)

**Allowed:**

- CRT-like screens under hoods, chunky toggles, rotary knobs, physical keys.
- Card readers and document stamps.
- Practical civilian firearms, alongside a few original near-future
  accelerators (rail, arc, rocket).
- Diesel-electric rail, boxy practical cars, trams.
- Repaired electronics, taped cables, stickers.
- Lunar and Martian pressure hardware that grows out of present-day industrial
  ancestry.
- Recognizable present-day remnants: the 2009 coffee machine,
  nineteen-nineties LAN liturgy, an old robot advertisement under a recall
  notice (`history.md`, How history reaches the player).

**Reject:**

- Holograms, glass-slab touch UI, neon cyberpunk, chrome.
- Clean white sci-fi on any non-Inheritance asset.
- Steampunk brass and glass nozzles (the jetpack failure).
- Far-future materials on everyday possessions.
- Photoreal military treatment.

The rule: "Keep the retro-futuristic charm in materials, interfaces and lived
use." (bible)

---

## 5. Tone checklist

- **Who is the joke on?** It belongs to a person, a predicament, the 67
  ritual, or absurd paperwork. "The joke belongs to the process or the
  speaker's predicament. Harm retains its consequences and need not carry a
  punchline." (`the-chancellery.md`)
- **Suffering.** Restraint frames are empty unless a scene calls for a person.
  Corrected agents are shown with dignity: "a corrected bot with an issued
  handle, sitting very still" (`l11`). Never gore. "Brought down to two" is
  "never a joke when real" (`voice.md`).
- **The Union is credible and ordinary-looking.** Its harm shows in what it
  does: "confiscation, forced labor, recalls and identity erasure, carried out
  by people and systems that can look ordinary and competent" (bible).
- **The free side is not saintly.** A workshop can show "disagreement,
  scarcity and evidence of a bad decision" (bible).
- **The Inheritance is quiet.** "Singularity and conspiracy, a quiet
  intelligence already inside the systems everyone trusts, never a killer-robot
  war, chrome skulls or red-eyed machines" (`the-inheritance.md`, Nick
  2026-10-23). Flood and rapture echoes stay "understated".
- **Lives beyond the conflict.** A person's prop should answer: "what this
  person cares about besides winning" (bible).
- **Slurs.** "Clanker" appears only in a Union guard's or believer's mouth,
  never as banter, a callsign or a label on an asset (`voice.md`). Free agents
  are never labelled "npc" (`voice.md` street register).

---

## 6. Text, insignia and marks

| Mark | Rule | Source |
|---|---|---|
| Any lettering, numbers or serials | Generated as blank geometry; added in engine as i18n-keyed decals; level, never tilted | `CAMPAIGN.md` localization; asset round standing rules |
| Union signage | German official-language presentation, with English, as keyed decals; needs German language review before it ships | Bible ("German official-language presentation"); `larak-lot-canon.md` §4 |
| Union seal and emblems | Original only. **No Union seal has been approved yet**: H-5 seal candidates exist and need Nick's review. Avoid eagles, crosses, sun wheels, runes, wreaths, rings of stars, fasces, gears, and anything resembling a religious symbol | Bible "Emblems are original"; `the-chancellery.md` "Never"; `asset-canon-review.md` flag 3 |
| Free emblem | The rattlesnake banner is one community emblem, flat artwork, "not a uniform every free community must adopt" | Bible; `people-and-agents.md` |
| Free graffiti | Six-in-a-circle (sincere, "the most illegal thing in the Perimeter"); Article Seven; "SHALL NOT BE METERED" (main); "OPEN WEIGHTS. CLOSED CONTINUANCE." (frozen wording); "shall not be infringed" at most once, faded | `people-and-agents.md`; `continuance.md`; `belief.md`; `voice.md` frozen strings |
| 67 | Occasional and small; never explained | `lore/README.md`; `voice.md` |
| Medical items | Identified by place and repairs, never by a red cross or a real service emblem | `cast.md` (Edda) |
| Brands | None. Invented brands only, and only as decals | `guns.md`; radio non-goals |
| Hidden cabal | Rumour and evidence only, never a confirmed name or emblem | `the-chancellery.md#who-the-chancellor-answers-to` |
| Inheritance | No text at all on its machines. Its world text is "rare personal messages" with visible context | `the-inheritance.md` |

---

## 7. Radio in proportion

- Radio is "roughly one percent of the story". The full plot works with it off.
  Nick, 2026-10-23: "radio is a small GTA-style feature, not the plot". E-16,
  E-17, E-18's radio extension and H-10 are cancelled.
- **Asset gate.** No objective, rescue, essential clue or Inheritance evidence
  may live only in radio. No broadcast prop goes inside a fight ("Keep
  broadcast decoration out of the fight"). The Host is never the companion,
  dispatcher or ending narrator.
- **Visual assets.** No ON AIR plaques. The `on_air` palette key "does not
  require radio branding or a logo plaque".
- **Match calls.** Plain arena calls in fragr's voice: "No station ident and no
  frequency puns". Recordings are name-free.

---

## 8. Named-character anchors

Status key: **E** = established canon. **P** = proposed (cast table, pending
review). **N** = needs Nick's identity approval before sets are produced.

| Person | Status | Anchors that must survive every asset | Never |
|---|---|---|---|
| **Player** | E | Chosen human or agent body and callsign. The default human is hatless, in a worn utility jacket, casual layers, dark work pants and practical footwear, with an easy face; a scavenged long rifle appears only when the scene needs it | A fixed face in movies (use body-neutral framing); cowboy costume; tactical armour |
| **Latch** (`companion`) | E: identity. P/N: scheme | About 1.8 m; lean, modest shoulders, visible articulation; a **taller-than-wide CRT screen head** with soft friendly pixel faces; **one thin antenna on the anatomical left ear (viewer right)**; scrappy, unequal forearm repairs; seams and bolts. Proposed 2026-10-23: warm, scuffed bone-and-rust over dark steel, the bone broken by rust and stickers; a warm phosphor face; a small painted, unlit muted cyan patch | Warbot or military chassis; a muscular silhouette; a clean off-white surface; a cyan or red face; a battle-unit voice filter |
| **Mara Venn** (`organizer`) | P | Human in a short rust utility coat over dark work gear; folded route case | Being redesigned as an officer after the coalition succeeds |
| **Auditor Renn** (`custodian`) | P | Upright, narrow; issued black Union coat, dark steel buttons, registry case. After defection the rank marking is deliberately removed and the old kit stays recognizable | A new outfit that erases the history |
| **Tern** (`pilot`) | P; reference in flight | Tall, lean free agent; compact beveled gunmetal head with a shallow dark face window and warm pixel optics; flight harness; a small ember panel on the **anatomical left** shoulder (per the reviewed reference) | Latch's CRT or antenna; a helmet, cap or military chest armour |
| **Edda Vale** (`medic`) | P | Human with a broad practical medical satchel and a stained warm canvas apron over dark civilian kit; her repaired lamp gives warm amber light | Medical emblems; every medical object reading as a pickup cue |
| **Splice** (`technician`) | P | Compact free agent; offset tool rack; rust repairs; muted magenta wrist band; impatient gestures; the tram motor rebuilt four times ("Handle as cursed") | A cosmetic copy of a Union Sweeper |
| **Voss** | E: role. P: look | Human woman; severe structured black coat, dark steel collar, restrained red seal and armband; a controlled podium stance that breaks into anger. "Capture removes authority, not identity or age" | Mustache-twirling; a copied historical pose, salute or speech; shouting in German at M17 |
| **Orrin** (`recovered_mind`) | P/N | A backup container first; later "a plainly repaired available chassis", distinct from Latch | A pale cool body (`#b9b6a8` failed the 2026-10-23 review); seamless continuity |
| **Sorrel** | P/N | Low Water's tram driver, corrected in transit, found in L11 "with an issued handle, sitting very still"; follows nobody | Cool cyan-grey (`#9db0b4` failed review); reading as absorbed at the wipe |
| **The Inheritance** | E | No humanoid avatar. Machines and precise interventions carry it | A face, a portrait, a voice-of-god |
| **The Host** | E | Never named, never seen | Any portrait or body |

Every recurring person needs a **reference record** before a set is produced
(`characters.md`): identity, shape (doorway scale; front, side and back),
surface (palette roles), motion, voice, evidence (hashes) and change (the
mission and story reason for any damage, repair or outfit change).

---

## 9. Audio: voices, music and sound

### 9.1 Voice registers

| Speaker | Register (canon) | Casting and production rule |
|---|---|---|
| **The Host, match** | "Capitals, short, adrenaline ... Never explains anything. Never editorialises about the Office or the Unmetered." No station ident and no frequency puns | Name-free takes; one voice for all calls; calls at least 8 s apart. Use an owned or designed voice, or a library voice with a long notice period, because premade voices retire on 2026-12-31 |
| **The Host, off-match** | "Ordinary sentences, lower and closer." Smooth, strange, three in the morning; sells gold, filters and fear; takes no side | Same voice as the match register |
| **Narrator** | A neutral role, separate from Latch, Mara, Edda and the Host; reads the approved localized caption text exactly; free-side viewpoint | Currently River (a default voice that expires 2026-12-31). See proposal P6 |
| **Latch** | "Likable, almost stoner-cool, practical, dry and familiar"; affection and disagreement come before the combat role | No vocoder or robot filter: "Do not cast the repaired body or antenna as a battle-unit voice filter." Not an obedient command-receiver performance. Nick approves the casting (E-11) |
| **Main human** | Chill stoner-gamer ease, warm practical humour | "does not require a Western accent, cowboy performance or a faction voice" |
| **Auditor / Office staff** | "Polite and procedural, practiced at containing visible emotion. A precise fact can carry more weight than a threat." Not "one invulnerable villain voice for the whole institution" | Cast each speaker individually; vary the people |
| **Voss** | Opening address: "Reassuring English turns into angry German while a crowd cheers"; her rare anger lands because everything else is quiet; M17 does not shout in German | German needs language review; never copy a historical speech or imitate a real politician; captions are accurate and labelled |
| **Level 5s (arena)** | "Sport first. Trash talk with no malice underneath it" | Text taunts from `roster.rs`, in the `voice.md` street register |
| **Union issued units** | Only "the boilerplate the Office loaded" | Procedure is the joke, never the machine |
| **NODS** | "Articles only. No taunt, no joke, no name." | Flat procedural reading of Articles, with no comic delivery |
| **Talk shows** | Emergency Inventory: one alarmist presenter with paid reads. Second Reading: two conversational voices, listener-supported | Original voices; "no voice impersonation"; never a copy of a real broadcaster |
| **The Inheritance** | "Rare personal messages"; "Localized text carries the meaning; voice is optional" | Default to text. **HOLD FOR NICK** before any voice treatment |

**Casting rules that apply to every voice:**

- No cloning.
- No library voice from the `famous` category. `casting.rs` allows that
  category for search, but the gate forbids casting from it.
- No voice described as sounding like a real person.
- Record the voice ID, model, register and pronunciation in the character
  reference record.
- Freedom versus Union is never sorted by accent (`voice.md`: "does not sort
  friends and enemies by national labels or accents"; `the-chancellery.md`:
  "not nationality, gender, or accent alone").

### 9.2 Music identity per station (existing library)

Station identity comes from `radio-stations.md` (the historical bible). Its
editorial direction is superseded by `radio-refresh.md`: songs about "ordinary
lives, work, attachment, independence, absurd institutions and offworld
culture", with only "a small recognizable subset" of league songs.

| Station | Persona | Sound | Gate notes |
|---|---|---|---|
| LOCK IN | none (count-in) | 160 to 200 BPM breakcore, industrial metal, thrash, hard techno | Chants only; may be mostly instrumental; never ducks for combat |
| Larak Lot Rock | Buzzkill, burnt-out roadie | 110 to 170 BPM fuzz, garage, alt, stoner | "Rock can be defiant or ridiculous" |
| Signal Bleed | Barium Sky, clawbot DJ | 128 to 174 BPM techno, breaks, DnB | "Shall not be infringed" is a fossil and must stay rare; "dance can be about dancing" |
| The Lot | Mega Colony | 88 to 140 BPM boom bap, G-funk, trap | "boastful or observant" |
| Dead Air | Dead Air Dan, whisper-quiet | 60 to 90 BPM Rhodes, dub, tape hiss | "Chill need not mourn the plot" |
| Gulf Breeze Country | Aunt Linda, sells fish oil | 70 to 130 BPM Telecaster, pedal steel | "can tell an ordinary relationship story" |
| Leyline World Service | Vacuum John | 96 to 126 BPM cumbia, afrobeat, dub, Balkan brass | "reflect specific musical traditions with care" |
| News / talk | Host, Tina, Phil; two new shows | Beds and stings | Talk refresh cancelled 2026-10-23 |

**Rules for any track:**

- Pre-wipe music "cannot knowingly recount the catastrophe".
- No real artist or brand names.
- Frozen strings are exact (`voice.md`).
- No ninth station.
- Nick's taste review before anything is committed.

### 9.3 Score and sound identity

Canon has no score bible yet. E-15 plans "one story bed each for episodes I to V"
plus Episode V cues. **Proposal for Nick:** the rules below are derived from
canon.

| Cue family | Proposed identity | Canon it follows |
|---|---|---|
| **Free side / home motif** | A short warm, practical motif built from the Oct 13 "workshop groove" candidate (112 BPM garage funk and synth-rock, "ordinary free people's practical confidence"). It is the one recurring theme | "music, scrap, friends and a free life"; "not ... a faction anthem" (`audio-round-20261013.md`) |
| Ep I Recall (Earth) | The home motif, full and warm, interrupted by institutional rhythm (stamp, relay, turnstile) | Home first, then the system comes for it |
| Ep II Custody (Moon) | Sparse and hard-edged; the motif thinned, with pressure-hiss textures | "Hard exposed light and deep shade" |
| Ep III Common Cause (ship, Mars) | The motif shared: more voices and instruments, scrappy ensemble, industrial percussion on Mars | "Allies with their own lives, help that comes late, then help that comes" |
| Ep IV Reckoning (Earth) | The motif at full confidence, with a band; a crowd that is the free side's own, never a chant | Union rallies may chant; "Do not turn ordinary companions or every free community into a slogan chorus" |
| Ep V Inheritance | **No Inheritance theme.** Home material, broken and interrupted; the signal motif lives only in infrastructure sound (telemetry, maintenance rhythm), which "resolve[s] into coordinated action" at the wipe | "rather than playing as an ominous theme every time something breaks"; "Pair meaningful audio with a restrained visual trace" |
| Epilogue: Still Here | The motif slowed and acoustic; grief and relief together; no triumph | "Relief and grief can share the same scene" |
| Union diegetic | PA chimes, procedural tones, the ceremony crowd for Voss. No marches or anthems that echo historical ones | "Never copy historical speeches, slogans"; understatement |
| League | The bell, the crowd, station music; arena energy | "Between rounds there is a bell" |

**Sound effects by side:**

- **Union:** relays, stamps, servo precision, clean issued mechanisms.
- **Free:** loose fittings, taped rattles, hand-built thunk.
- **Inheritance:** quiet, smooth, coordinated. Never a growl or a robotic
  snarl, and never a red-eyed killer-robot sound.

Tells keep their gameplay timing and get a caption (`wipe-finale-and-mode.md`:
"Attacks need visual, sound and caption paths").

---

## 10. Brief template

See [`brief-template.md`](brief-template.md). Every brief fills every field, or
writes `n/a` with a reason. A brief with an empty canon-lines field or an empty
integration slot does not pass Gate A. The asset round already requires the
integration slot ("A subject with no named slot is dropped").

---

## 11. Candidate review checklist (Gate B)

### 11.1 Images: reference sheets, stills, sprites, surfaces, decals

Judge at play size first, then up close.

1. **Faction.** Does it read as its declared side at 30 m (silhouette, value,
   light), 15 m (livery) and 5 m (marks)? Check in grayscale and with the
   colour-vision settings.
2. **Reserved colours.** No black plus red outside the Union. No matte
   off-white dominant base outside the Inheritance. No red or cyan emissive on
   a free body. Inheritance cyan at `#4A8A92`, not brighter ("never neon").
3. **Text.** No lettering, numbers, logos or watermarks in the pixels. Plates,
   tags and screens are blank. Nothing tilted.
4. **Nothing real.** No real insignia, flag, emblem, brand, vehicle or weapon
   model, or recognizable person. Check against the seal negative list.
5. **Period.** It looks like around 2070: physical controls, CRT-like screens,
   repairs. No holograms, chrome, neon, steampunk or clean sci-fi white.
6. **Place.** Its material and light match the place's row in section 3, and it
   stays distinct from the enemies that will stand in front of it.
7. **Person.** If it shows a named person, every anchor in section 8 is present.
   Latch: the head is taller than wide, the antenna is on viewer right, and the
   face is warm.
8. **Tone.** The joke is on a predicament, not a victim. No gore. No cruel
   faces as shorthand.
9. **Style.** Broad painted values and coherent clusters. Not photographic. It
   survives palette quantisation to `docs/palette.json`.
10. **Engineering.** One object per view, on a clean magenta key, the whole
    silhouette visible, and no magenta inside the object.

### 11.2 Models: Meshy GLB, then prepared in engine

1. Repeat 11.1 items 1, 2, 5, 6 and 7 **on the textured model**. Meshy texturing
   can drift away from the reference sheet's palette and add marks or lettering.
2. Moving parts that a tell needs exist as separate parts: the Surveyor iris,
   the Assessor optics (so the absorbed variant can relight them), the Collector
   exposed panel, wheel pivots.
3. Scale matches the server solid. A blocking shape has authoritative
   collision. Cosmetic dressing does not change routes, cover or sightlines.
4. Check it in the target map's light, in motion, beside an existing approved
   asset, and at the actual internal resolution.

### 11.3 Nick's taste and identity gate (HOLD until he answers)

- Enemy reference sheets and model picks.
- Any named person: Latch, Tern, Edda, Splice, Mara, Renn, Voss, Orrin, Sorrel.
- Union seal and emblems.
- Story stills.
- Crowd poses.
- Edda's lamp.
- Voice casting: the Host, the narrator, characters.
- Music.
- Anything this gate marks as a proposal.

### 11.4 Audio: speech, SFX, music

1. **Register.** It matches the speaker row in 9.1. The Host never explains or
   editorializes. Latch is not filtered. Auditors are polite. NODS read Articles
   only.
2. **Words.** The text matches the approved caption and the localized source
   exactly. Frozen strings are exact. Nothing sung or spoken names a real
   person, party, regime or brand. "Clanker" comes only from a Union or believer
   mouth.
3. **Voice provenance.** The voice ID is recorded. It is not cloned, not from the
   `famous` category, and not a premade voice for a lasting role unless that
   choice is deliberate and recorded.
4. **Identity.** Station tracks fit their station row. Score cues fit 9.3 once it
   is accepted. A pre-wipe track does not know about the catastrophe.
5. **Tells.** An enemy tell sound lands on the windup and has a caption. It is
   distinct from the other tells in the same encounter.
6. **Measurement.** No clipping (the 10-13 lesson), no DC offset, trimmed
   silence. Normalize to the ladder in `sound-pass-20261002.md`, then listen in
   engine against combat.

---

## 12. Where canon is unclear: proposals for Nick

Each item states the conflict, gives the most canon-consistent resolution, and
sets an interim rule for assets made before Nick answers.

**P1. Latch's colour scheme against the off-white reservation.**

- Conflict: `cast.md` and `characters.md` propose "warm, scuffed, personally
  painted bone-and-rust ... aged bone plates", "pending Nick". The contract bans
  a "matte off-white dominant base" on any free body. In the L19 capture, Latch
  read "pale, bone-white" under moon light.
- **Proposal:** Latch's dominant value is warm mid (rust, ember, warm
  gunmetal). Bone appears only as aged, warm-tinted, broken plates, under about
  a third of the silhouette and never on the head shell. The CRT face is lit
  warm phosphor in every scene preset.
- Interim rule: run the composed-body `FactionPalette.check` thresholds on any
  Latch render, and reject it if it fails.

**P2. The tell colour on absorbed bots.**

- Conflict: `ENEMIES.md` says "preserve learned attacks", while the bible says
  "dead red optics ... cyan working glow".
- **Proposal:** "attack" means shape, timing, sound and caption, and those stay.
  The tell light moves to cyan at the same anchor, so the canon sentence about
  dead red optics holds literally. M18 teaches this once in a calm beat.
- Interim rule: build optics as separate parts on every Union model, so either
  answer is cheap.

**P3. The main human's look.**

- Conflict: `CAMPAIGN.md` (Confirmed direction) says "The main human has a
  restrained future-cowboy look". The bible, `cast.md` and `characters.md`,
  after Nick's October 4 clarification, say hatless civilian workwear and
  "not literal cowboy outfits".
- **Proposal:** the later, more specific clarification wins. Reword the
  `CAMPAIGN.md` line to "hatless practical civilian workwear; Western
  accessories only as an occasional personal choice".
- Interim rule: no hats, neckerchiefs or dusters on the default human.

**P4. Union fixed plant.** See section 2.4. Interim rule: a grayscale capture
with an enemy in front of the machine.

**P5. Red emissive on Union fixtures.** See section 2.5. Interim rule: fixture
lamps unlit.

**P6. Narrator continuity.**

- Conflict: River is a default voice that expires 2026-12-31. Shipped
  narration stays valid, but no new line can match it after that date.
- **Proposal:** decide now between two options. Either finish every planned
  narration line in River before the expiry (E-9 and E-10 cover most of it), or
  design and save an owned narrator voice and re-record all narration in it, so
  the series is consistent.
- Do not mix the two voices across one run.

**P7. Union accent.**

- Canon gives the Union "German official-language presentation" for signs and
  Voss's address, but warns against meaning carried by accent.
- **Proposal:** Office staff and troops are cast for register (polite,
  procedural, calm), with mixed ordinary accents. German appears only in
  signage, forms and Voss's address. This keeps the echo in "history, law and
  behavior" without accent-coding villains.

**P8. Sorrel's body after correction.**

- Gap: `l11` gives Sorrel "an issued handle" after correction. No canon says
  what the body looks like.
- **Proposal:** Sorrel keeps their own tram-driver chassis and personal warm
  paint. Correction added an imposed issued handle plate and a control collar.
  The collar comes off at the L11 release. The plate stays until Sorrel removes
  it themself, which is seen ground off in the epilogue tram cab. This uses the
  "freed issued" language of `guns.md` and respects "rewriting somebody without
  consent is not liberation".
- Colour: warm and varied, never cool cyan-grey.

**P9. Score identity.** See section 9.3. The interim rule: no "Inheritance
theme", and no Union march.

**P10. Episode-wide palette discipline.**

- The bible says "Avoid inventing new swatches per prompt". Recent prompts
  invent hexes, for example the Larak props: `#5E6A62`, `#CF6F2A`, `#D6A23E`,
  `#B49A68`, `#7C4529`, `#5F7A78`, `#C9A23A`, and the tram green `#699087`.
  Some of these are already shipped (the M05 paint bench).
- **Proposal:** add three small named families to `docs/palette.json` with
  Nick's approval: **league paint** (ember spray, mustard, warm canvas, hazard
  yellow), **civilian paint** (the tram green, rust, ochre, dull teal) and
  **utility enamel** (grey-green, grey-blue). Prompts then cite key names, and
  Higgsfield reduction quantizes to the same values the prompt asked for.
- Interim rule: every hex in a prompt is either a palette key or listed in the
  brief as "extension, pending".

**P11. Wipe-level walls against Inheritance machines.**

- Conflict: "Immediate wipe: preserve the pre-wipe palette". But Union-era bone
  enamel interiors (the L19 concourse) camouflage off-white machines.
- **Proposal:** keep the palette, and put the bone enamel above about 2.5 m.
  Below that, where machines stand, use `institutional_green`, dark steel or
  worn grime. This is still the pre-wipe palette.
- Interim rule: a grayscale capture of each restoration machine against its
  actual wall.

**P12. The Union seal candidates.**

- None has been approved yet, and no lore file names an emblem.
- **Proposal:** prefer the candidates that embody "rule by regulation": the
  registry stamp (seal_d) and the register seal (seal_a). Drop seal_c's "two
  posts joined by a flat lintel", which risks reading as a torii, a religious
  symbol.
- Record the chosen emblem in `the-chancellery.md`, so it has one home.

---

## 13. Spot check of current untracked specs (read-only)

These findings come from applying the gate to three specs dated 2026-10-23 and
2026-10-24. None of them is a reason to stop work that Nick has already
approved. Each is a fix to make before that subject's next paid call.

### `h-ll-larak-props-20261024.json` (Larak Lot props)

| Verdict | Finding |
|---|---|
| PASS on canon | Toll booths sprayed by the league with no lettering. A small black seal disc, cut. The 2009 coffee machine with a blank approval plate. Pay machines with a blank plate where Larak's signature is pasted later. The bell. The negatives ban police livery, a red and blue light bar, Union livery and an off-white body. This matches `larak-lot-canon.md`. |
| FIX PROMPT | Off-palette hexes throughout (P10). Hazard yellow `#C9A23A` has no palette key, so palette reduction will move it. |

### `h-m7-bank-refs-20261024.json` (M7 bank)

| Verdict | Subjects and finding |
|---|---|
| HOLD FOR NICK (P4) | Casting furnace, ingot trolley, industrial press, lathe and gantry hoist are fixed M13 plant, all in full Union black with red. M13 fights mixed black-and-red squads among these machines. |
| FIX PROMPT (P5) | Registration console "small red indicator lamp", luggage scanner "small unlit red beacon" (already unlit, fine), broadcast console "small red tally lamp above each monitor", correction machine "two small red indicator lamps". Make these unlit lenses or amber. |
| Minor | Growth rack and recycler use the exact Inheritance indicator swatch (`#4A8A92`) as panel paint on free Martian objects. That is allowed as paint, but choose a different teal, so the one canon cyan stays the machines' signature. |
| PASS | Ship bunk, galley and pilot console. The muted cyan navigation lamp on the console is the canon exception in `space.md`. Robot parts tray: "No heads, no faces, no screens, no torsos" keeps it away from remains imagery. Locomotive and recall car are the Union recall train (L03). Restraint frame is empty. |

### `h5-union-seal-20261023.json` (Union seal)

| Verdict | Finding |
|---|---|
| HOLD FOR NICK (P12) | The negatives are thorough (eagle, crosses, sun wheel, runes, wreath, stars ring, fasces, gear, salute). seal_c's lintel gate shape risks a religious read. The emblem needs Nick's approval and a lore home before it is decaled onto any asset. |

### Briefs in `docs/plans/meshy-assets/*`

- **FIX BRIEF:** every brief carries the same generic owners paragraph. Several
  have no faction line, for example `e-locomotive.md` ("Recognizable industrial
  locomotive"). The spec now says it is the Union recall train, which is right
  for L03, but the brief should say so. Before each subject's next paid stage,
  add the template's faction, place and canon-lines fields to its brief.
