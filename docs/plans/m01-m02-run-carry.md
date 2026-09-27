# M01 to M02 durable solo run carry

**Status:** in flight, 2026-09-27. Stacked after the Latch release in
[draft PR #272](https://github.com/blisspixel/fragr/pull/272).

## Goal and reason

After completing Recall Notice, Continue Run should start Persons Unknown as
the same solo run. Preserve its ID, difficulty, selected protagonist body,
remaining Episode I continues, health, armor, owned weapons, ammunition and
selected weapon. Start M02 at attempt 1, regardless of M01 retries. A death
in M02 restarts M02 at its saved entry and spends one shared continue only when
the player accepts Continue. Closing the game must preserve that decision.

Today the disk document stops at `awaiting_mission`. The menu reports M02 as
pending, and `--local-mission persons_unknown` uses development-party rules
without the saved run. The M01 run document also predates player body choice.
Neither the map nor the client may infer missing run facts from a profile or a
control role.

## Boundaries

- Keep the existing single local child, `RunStore`, solo recovery, mission
  controller, wire action channel and Godot local-process lifecycle. The
  server remains authority for all outcomes and the continue allowance.
- Preserve the independent M02 development entry for QA. It remains a fresh
  party without a save file. A saved M02 launch is a distinct Continue Run path.
- Keep one run file and one process-level lock. No account, cloud sync,
  mid-mission checkpoint, co-op save or new scripting runtime enters this rung.
- A continue restarts only the current level. Continues refill at the next
  episode, not between M01 and M02. No refill is implemented here.
- Latch's guarded release, free-agent identity and Low Water lead remain as in
  the accepted M02 brief. Save carry does not imply a controllable companion.
- Existing v2 files remain recoverable. A migration must validate the legacy
  document against the M01 content it names and preserve its original bytes
  before replacement. Never turn a corrupt or future-version document into a
  fresh run without explicit New Run.

## Architecture and data contract

1. Introduce run document v3 with a per-level continue baseline. Its attempt
   is `level_start_continues - remaining_continues + 1` while playing or
   awaiting a Continue. Keep the episode starting allowance separately. A
   transition to M02 sets its level baseline to the exact remaining allowance;
   it never increments or refills that allowance. A successful M01 exit with
   zero continues still enters M02 at attempt 1 and fails on its next death.
   Validate ordering and bounds on every load and save.
2. Persist chosen `BodyKind` once the owner explicitly joins. The initial
   pre-admission file and legacy v2 files may lack a choice. A later explicit
   body selection binds that run; subsequent resumes restore the saved choice
   even if the current profile preference differs.
   Do not use the human/agent control role as fictional body identity. Expose
   the bound or missing choice in the read-only preview so the menu can present
   the correct action. Legacy body selection must be visible and intentional.
3. Validate a saved step against its own mission content identity. An M01
   `AwaitingMission` document still names the exact M01 bytes. Under the
   writer lock, promote it once to an M02 entry document naming the exact M02
   bytes and retaining the same ID, rules, allowance and M01 exit equipment.
   Archive the validated source bytes and use the existing synced replacement
   path. After a crash, either side of promotion must be readable and must not
   grant an extra continue. A second promotion must be inert.
4. Reuse `SavedEntry` as the mission-entry equipment snapshot. The M02 entry
   becomes the retry anchor and the disk restart anchor. Carry HP, armor,
   weapons, ammunition and selection from the M01 frozen exit. Reconstruct
   M02 enemies, local supplies, gates, mission progress, clock and input
   sequence from the M02 map. Clear M01-specific pickup claims and controller
   state. Verify that M02's Shotgun pickup is still claimable. The first M02
   join must restore the same equipment before its first authoritative loadout
   is sent. M02 has `m02_objectives()` rather than M01 `MissionGeometry`, so
   every run projection must identify both authored mission shapes.
5. Generalize solo recovery and run-file projection for both missions.
   `CampaignRunStatus::Complete` at the M02 dock needs an honest next state;
   do not record another M01-to-M02 transition or claim Episode I complete.
   Record `scheduled_service` (level 3) as a pending string, keep the M02 run
   after departure, and do not offer an unsupported M03 launch. Low Water is
   the later level 4 destination, not a place the player reached in M02 or M03.
   The saved run may complete a development graybox route without certifying
   the authored level, Latch's autonomous escape or a human story gate.
   Preserve the frozen exit if the owner disconnects after departure.
6. Add the needed bootstrap and preview fields to the existing local contract.
   The menu offers Continue Run into M02 for a compatible M01 completion,
   retains the chosen body and selected difficulty, and distinguishes a
   missing legacy body choice from an incompatible file. Starting New Run
   archives the previous file as today. Update Rust wire types, Godot strict
   validators, adapter documentation and `docs/protocol.md` together if any
   on-wire shape changes. Avoid a second campaign command or save parser in
   Godot. The preview command must discover the saved mission; probing only
   the M01 content hash will misclassify a promoted M02 run. Keep the exact
   readiness mission and capability checks, and bump the gameplay capability
   when M02 gains a run and the run state gains a level baseline.

## Implementation order

1. Write v3 schema, bounded legacy v2 decoder and invariant tests. Cover M01
   active, pending, failed and complete documents, plus M02 active/pending/
   failed/complete. Refuse unknown fields, unsupported missions, invalid body,
   invalid equipment, mismatched hash and impossible allowance.
2. Add store migration and mission promotion under its existing lock. Fault
   injection must cover before rename, after rename reconciliation, archives,
   repeated launch and two competing local children. Preview stays read-only;
   launch revalidates and commits before readiness.
3. Generalize solo recovery and owner admission. Test M01 exit to M02 entry
   including spent continues, body and loadout, M02 wipe, accepted Continue,
   process restart and dock departure. Assert the first M02 attempt is 1.
4. Wire the menu and local child, then run an isolated end-to-end restart with
   `FRAGR_RUN_DIR`. Exercise a current v3 run and a real v2 fixture from the
   previous release. The user must see the correct destination and body
   selection before any migration.
5. Update README's concise play summary and its linked playing guide,
   roadmap, plan index, campaign status and protocol to match implemented
   behavior. Keep detailed save instructions in the guide.

## Verification and acceptance

- Deterministic Rust tests prove exact allowance, attempt, body and inventory
  across departure, promotion, M02 entry, wipe, continue, quit and restart.
  Include M01 exit with zero remaining continues followed by M02 failure on
  the first death, without an invented retry.
  Validate a human and an agent owner through the same server state. Check
  old v2 and malformed files without reading the user's real run directory.
- Godot harnesses prove menu states, saved body, difficulty, correct M02 local
  readiness, retry, terminal state and no duplicate opening. Capture and
  inspect player-visible menu and M02 states with the standard tour.
- Run full format, Clippy, workspace tests, unfiltered 90 percent coverage,
  release build, dependency policy, benchmark, four live playtests, six-map
  roster, 120-second soak and pinned Godot checks before a draft PR is called
  reviewable. CI must pass on the combined stack. Report local platform limits.
- An unsteered player can explain what Continue Run will start and how many
  continues remain. That human gate can stay open after engineering proof.

## Spend and release gate

This sprint needs $0 external API or cloud spend. The current $20 external
build allowance and repository $50 cap remain untouched. No cloud apply,
paid assets, merge, tag or release is part of this branch.

## Progress

- 2026-09-27: Source audit found v2 M01-only `SavedEntry`, `RunStore` bound
  to a single content hash, M01-only solo admission and an attempt formula
  based on all Episode I continues spent. The old file must be migrated and
  promoted before M02 can honestly use the same run.
- 2026-09-27: Client audit found that the boot menu always resumes M01, the
  local child refuses M02 durable mode, M02 mission and record validators
  reject a run, and the preview command compares only the M01 hash. The new
  preview will identify the saved mission instead of making Godot inspect the
  save or guess the map. The development M02 entry remains separate.
- 2026-09-27: Lore audit confirmed the same character and Episode I allowance
  across the two levels, and found stale Low Water level numbers in the lore
  gazetteer and cast pages. The copy must keep level 3 at the rail yard and Low
  Water at level 4, while M02 remains a development rescue slice.
- 2026-09-27: The draft v3 document adds a per-level continue baseline and an
  optional bound body. A validated M01 departure promotes to an M02 entry with
  its ID, difficulty, allowance and exit equipment intact. Legacy v2 M01 saves
  have an explicit decoder and retain exact source bytes in a content-addressed
  archive. Wrong-destination launch leaves them untouched. Archive reads are
  bounded, and retries reuse the exact archive after a failed replacement.
- 2026-09-27: The durable local child now advertises gameplay capability 18,
  including M01 without `--run-mode`; the independent M02 development child
  remains at 17. A saved body overrides a changed profile in both Welcome and
  the authoritative pawn. The menu names the saved mission, difficulty, body
  and allowance; the pending level 3 state is read-only. No M03 launch exists.
- 2026-09-27: A real Godot M02 child and restart carried Severe difficulty,
  two continues, a Synthetic body, 61 HP, 7 armor, Tack and 29 Bullets. The
  first private Loadout on each join matched the saved equipment after moving
  the optional gallery shells beyond every spawn pickup radius. The final
  gallery position passed all 13 M02 route tests and eight authored M02 tests;
  its strict headless and rendered client smokes also passed. A compact ammo
  packet and label keep the first view readable. Inspected rendered evidence
  is indexed in [the screenshot record](../screenshots/m02-run-carry/README.md).
  Earlier frames showing an automatic spawn pickup or a clipped crate were
  discarded.
- 2026-09-27: Four asserted multiplayer playtests passed. The six-map mixed
  roster passed at 2, 6, 6, 8, 12 and 16 agents; map 4 still recorded two
  post-opening spawn deaths and none at the opening. Pinned Godot checks and
  their verifier-injection tests passed after updating the story replay
  harness for the Practice page. Format, Clippy, full workspace tests, release
  build, dependency policy, and the deterministic bench passed. Unfiltered
  workspace coverage was 93.73 percent. The published tour passed all 32
  states; the current menu and M02 frames were inspected. The asserted
  120-second local soak passed with four agents, four bots, two spectators,
  and rotating arenas. The combined CI gate remains in progress. External
  spend remains $0.

| Local soak sample (2026-09-27) | Measured result |
|---|---:|
| Duration and samples | 120 seconds, 9 samples |
| Tick rate | 20.00 Hz |
| Lifetime tick p99 and maximum | 0.52 ms, 1.44 ms |
| Resident memory, first to peak | 37.6 MiB to 38.7 MiB |
| Average outbound per connected client | 50,453 bytes/s |

These are local Windows loopback measurements with eight fighters and two
spectators, not a public-host or larger-map capacity result. The raw samples
and server log are under `.agents/soak/carry-ci.*` in the worktree.

Independent source and screenshot review caught two presentation errors before
handoff: the playing guide overstated what the pause menu's Leave action does,
and JSON preview numbers rendered as decimal continue counts. Both were fixed;
the M02 menu proof frame was recaptured and inspected. No other actionable
review finding remains. The unsteered player and difficulty acceptance gates
remain open for the mission itself.
