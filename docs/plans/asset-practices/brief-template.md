# Asset brief template (Gate A)

Fill every field before any paid call. Write `n/a` and a reason where a field
does not apply. An empty **canon lines** field or an empty **integration slot**
fails Gate A. The rules behind each field are in [`lore-gate.md`](lore-gate.md).

This template extends the per-object fields that
`docs/design/wipe-finale-and-mode.md` (Art families) and
`docs/design/characters.md` (Reference fields) already require. It does not
replace them.

## Visual asset brief

```text
id:                 <stable id, e.g. E-locomotive / ref-paver / still-l03-l04>
tool and stage:     <spritegen gen (low|medium|high, refs) | meshy-gen 7.1/t2, 2k/4k, rig y/n>
status:             <canon | proposal | historical>; reviewer of record

FACTION:            Union (troops | bots | elite | Office equipment) | free human | free agent |
                    Inheritance restoration | absorbed bot | league (no side) | neutral/civic
  owner, if any:    <person or community, e.g. "Splice", "Low Water", "waterworks crew">
  issued state:     issued | freed (plates ground off, seals cut) | civilian/workshop | n/a
PLACE:              <world + location: Earth Low Water | Earth Union institution | Perimeter rail |
                    Moon port/town/archive/berth | Common Carrier | custody tender | Mars habitat/foundry/
                    launch | Larak Lot / league venue | wipe (18-20) | years-later>
LEVEL / MODE:       <L## and room/beat, or MP map + mode; pre-wipe | wipe | after>
PERIOD CHECK:       <what makes it ~2070 practical: controls, displays, repairs, remnants>

CANON LINES:        <at least 2 quotes with file#section; one for faction, one for place or person>
                    - "..." (docs/lore/....md#...)
                    - "..." (docs/campaign/l##-....md)
PROPOSALS USED:     <any lore-gate P# or brief-level proposal this relies on; else none>

PALETTE:            keys from docs/palette.json, by role:
  dominant (60%+):  <key(s)>
  secondary:        <key(s)>
  accent:           <key(s)>
  emissive:         <key or none; Union red only on Union optics/tells; cyan only Inheritance/absorbed;
                     free = warm amber/white/phosphor>
  off-palette hex:  <none | list each with "extension, pending Nick">
RESERVED-COLOUR CHECK: black+red? off-white dominant? red/cyan emissive? -> must be "no" unless the
                    faction above owns it

SILHOUETTE:
  at 30 m:          <outline + dominant value + light read; what makes it its faction at a glance>
  at 15 m:          <livery blocking / material separation>
  at 5 m:           <marks (as blank geometry), repairs, fasteners, faces/screens>
  against:          <the enemy or actor that will stand in front of / beside it, and why they separate>
SCALE:              <metres; doorway / server solid / rig volume reference>
MARKS AND TEXT:     <blank plates/seal bosses/tags requested; decal i18n keys to add later; "no text">

MOTION / PARTS:     <separate moving parts and pivots; tell parts (lens, optics, panel); poses needed;
                     rig or local pivots>
STATES:             <intact | freed | absorbed | damaged | years-later variants derived from same source>

REFERENCES:         <approved image paths + sha256; style board images; what NOT to copy>
PROMPT:             <subject text>
NEGATIVES ADDED:    <beyond the spec default: e.g. "red light", "off-white body", "police livery">

INTEGRATION SLOT:   <presenter / decoration id / scene JSON key / ship_furnishings slot / map + coords>
COLLISION:          <authoritative solid needed? cosmetic only?>
CEILING:            <credits or $; preflight receipt path>
NICK GATE:          <yes: named identity | enemy sheet | emblem | still | crowd | taste item; no>
```

## Audio asset brief

```text
id:                 <e.g. E-12-paver-prep / E-2-host-rampage-v2 / radio-country-NN>
tool and model:     <audiogen batch|tts|dialogue|design; eleven_v3|eleven_v4|music_v2_5|sfx>
FACTION / SOURCE:   Union | free | Inheritance | absorbed | league | neutral | narrator | Host
PLACE / LEVEL:      <L## beat or MP mode or station>
SPEAKER + REGISTER: <row from lore-gate 9.1, quoted register line>
VOICE:              <voice id, owned/designed/library (notice period), never "famous", never cloned>
TEXT:               <exact approved caption/source string; localization key; frozen strings exact>
CANON LINES:        <at least 2 quotes>
IDENTITY:           <station row (9.2) or score cue family (9.3) or tell (ENEMIES.md row)>
TELL TIMING:        <windup start/commit in seconds; caption text key> (enemies only)
MEASURE:            <target loudness per sound-pass-20261002; peak <= -1 dBTP; loop points>
INTEGRATION SLOT:   <path + bus + presenter>
CEILING:            <credits; dry-run receipt path>
NICK GATE:          <casting | music | emotional-peak narration | no>
```

## Worked example (from current canon, for calibration)

```text
id:                 E-turnstile (L19 concourse)
FACTION:            Union (Office civic control), overrun by evacuees; issued state: issued
PLACE:              Earth Union institution, L19 evacuation concourse, wipe
CANON LINES:        - "Registration is joined to access, access to compliance, and compliance to the
                      right to work, travel ..." (lore/history.md, Years 22-30)
                    - "a Collector working the turnstiles" (campaign/l19-planned-works.md)
PALETTE:            dominant institutional_green + union_steel; accent union_red (seal rim only);
                    emissive none (lamp unlit)
SILHOUETTE 30 m:    mid-dark green/steel block, clearly darker than the matte-bone Collector beside it
           15 m:    three-arm barrier, card reader hood
           5 m:     blank riveted type-approval plate, blank round seal boss, repeated identical bolts
MARKS AND TEXT:     no text; decals later: WORLD_M19_* gate keys (German + English, language review)
INTEGRATION SLOT:   M-4 turnstile, blocking solid in m19 concourse
NICK GATE:          no
```
