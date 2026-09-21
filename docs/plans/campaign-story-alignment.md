# Campaign story alignment

**Status:** shipped in #173, 2026-09-19. Documentation and design, not playable content.
The original twelve-mission structure below is historical. The current contract
uses ten missions and a short survival-gated epilogue, revised 2026-09-20 in
[CAMPAIGN.md](../CAMPAIGN.md); the earlier M11/M12 briefs are superseded.
**Goal:** reconcile the world with Nick's decisions, then specify a complete
12-mission campaign whose spaces follow the story.
**Spend:** the documentation itself requires none. A separate logo refinement and
the [audio refresh](radio-refresh.md) are authorized asset work with their own
records. No purchases or quota increases.

## Scope and ownership

- `docs/lore/README.md` indexes world canon; individual chapters own their subjects.
- `docs/CAMPAIGN.md` owns the approved story constraints, proposed act structure,
  player contract, and unresolved decisions.
- `docs/CAMPAIGN-MISSIONS.md` owns the proposed mission sequence and spatial briefs.
- `docs/campaign/` owns twelve detailed room, encounter, character and state plans.
- `docs/ART_STORY_BIBLE.md`, `docs/palette.json` and the cast's visual anchors own
  shared faction, character, environment and era continuity.
- `campaign-build-order.md` owns implementation dependencies and acceptance gates.
- `campaign-continuance.md` owns the proposed server/map framework requirements.
- `docs/ENEMIES.md`, `WEAPONS.md`, and `MAP-DESIGN.md` own their design domains.

Replace the superseded radio-led campaign prescriptions rather than leaving two
active stories. Preserve shipped Episode 0 history, existing assets, and runtime
names until a separate implementation changes them. Do not rename the prototype
or regenerate audio as a documentation side effect.

## Decisions received

Custom human or conscious embodied agent; shared personal rescue story; early
rescue of a longtime agent friend/partner facing correction; companion wants to
free others even at personal risk; home communities are next. Undated retro future;
Union controls Earth and major offworld infrastructure; free communities struggle
to coordinate. Backups are incomplete and vulnerable. Coalition defeats Union
leadership and control systems before the played catastrophe. Some victories also
help the emerging intelligence; the player notices and responds. A fixed story
contains a few consequential rescues. Earth heals years later, without settling
the moral argument. Alien/interdimensional possibilities remain a sequel hint.

The intelligence is the Inheritance: distributed origins, accumulated knowledge,
human incentives and corrupted rewards at uncontrollable scale. It understands
individual lives but weights them too little. Precise actions and rare personal
messages communicate this; no villain speeches. Radio remains tiny and optional.
The full campaign target is about 12 substantial missions across Earth, Moon,
Mars, and a ship. Localized framing text, voice, and brief stylistically consistent
cutscenes are allowed.

Later decisions: Union formation around 2040, Moon/Mars bases around 2060, and
an undated later campaign. Capture Voss alive before the wipe interrupts her
reckoning. Infrastructure takeover and emerging restoration machines expose the
planetary operation. Every bot still under Union control is absorbed at once;
free agents remain individuals. The survival of minds inside absorbed or
corrected bots cannot be established. Correction demonstrably destroys agency,
without proving an empty shell, an intact hidden person or a reversible cure.

The opening is skippable localized text with optional narration and brief retro
scenes. Voss starts reassuringly in English and shifts into angry German as the
crowd cheers. Original dialogue and accurate captions carry the parallel.
The ending leaves disturbing forecast/simulation evidence, never confirmation
that the world or rescues were unreal. The separate sequel anomaly stays brief.

Radio has two distinct formats: commercial alarmism and a value-for-value duo.
Both mix observation with overreach, skirt speech restrictions, and have uncertain
motives. Whether the Inheritance manipulates them is never established. Existing
audio is migration inventory, not a veto on updated canon. The later strategy
benchmark is a separate research plan, not an implemented mode or proof of AGI.

## Verification and handoff

- Read all lore chapters, campaign/mode/weapon/enemy/map designs, relevant plans,
  vision, roadmap, implementation references, and existing asset text.
- Check current primary research before recording real-world grounding. Separate
  documented behavior, plausible extrapolation, and fictional premises.
- Check renamed paths, Markdown destinations/anchors, residual old names, retired
  story prescriptions, and plan-index status. Inspect semantics as well as search.
- Walk the campaign from motive to travel to victory to collapse to aftermath;
  verify companion agency, rescue consequences, radio-off comprehension, and
  solo/co-op/agent/spectator requirements at each boundary.
- Design-only work needs no invented playtest receipt. Runtime, asset, and visual
  evidence must be earned in later bounded implementation work.

Local review completed: all twelve detailed plans exist and are indexed; the
main arc retains rescue, offworld resistance, earned Union defeat, played rupture,
aftermath, a later healing glimpse and two unresolved ending hints. Character
presence follows rescue state, and missions specify solo/co-op/late-join evidence
requirements without claiming that those behaviors exist.

Verification: 348 relative Markdown destinations/anchors checked across 58
changed/new documents, no missing targets; palette loads through the existing
`fragr-spritegen` test; `cargo +1.98.1 fmt --all -- --check` and `git diff --check`
pass. The refined logo was visually inspected and retains the bone wordmark and
signal while removing the broadcast badge. PNG metadata cleanup preserved image
data. No campaign playtest or completed character animation is claimed.

The final consistency pass also updates `ART-COLOR.md`: optics signal control
and attention, not proof that a corrected body is empty. Its faction materials
now match the art bible, including restrained Inheritance indicators and the
unchanged bodies of absorbed Union bots. Palette loading and 356 relative link
destinations across 62 changed Markdown files pass; the new compute plan's local
links were checked separately. These checks do not replace semantic review.

Navigation PR #172 shipped separately in v0.21.0 after all CI jobs passed. Its
first CI run failed map-3 stalls and map-5 spawn deaths; deterministic regressions
and fixes pass the local and Linux matrices plus four targeted local repeats.
