# CTF carrier contact and return

Status: **planned**, 2026-10-15. A bounded follow-on inside the existing
multiplayer-quality rung of the [full build order](../ROADMAP.md#full-build-order).
This plan does not replace the Sector 9 cover or composed verification gates.
Parent integration owns the plan index and scheduling.

## Finding and limits

The retained second-candidate Sector 9 contested socket observation finishes
0-0 after 181.95 seconds, with thirteen frags, one take, one drop and one return.
Its carrier advances from 137.73 m to 85.07 m from home during 228 observed
ticks, then loses the flag in a same-tick combat death. The episode has zero
own-flag-away and home-blocked ticks. This is combat attrition during a moving
return, not evidence that the carrier was waiting at home or unable to route.
One carry does not establish which policy caused the match's low conversion.
The corrected cover candidate's composed check is a separate observation:
0-0 at 181.95 seconds, fifteen frags, two takes, one combat drop and one return.
Its first carrier advances 137.73 m to 86.07 m over 224 ticks before death;
its second advances 139.51 m to 44.56 m over 391 ticks before the clock ends.
Both have zero own-flag-away and home-blocked ticks. This again shows progress
and attrition, while the late take leaves too little time to establish a full
return. It does not isolate carrier policy as the cause of the timeout.

There is a concrete controller limitation worth testing:

- `tools/playtest/src/lib.rs::policy_action` excludes every carrier from the
  visible-nearby-enemy branch and returns a default action with `fire=false`.
  `ctf_policy_fights_a_visible_blocker_then_resumes_the_flag_route` explicitly
  retains that behavior for both external test policies.
- `agents/brain/src/plan.rs::ctf_micro_action_with_visibility` similarly excludes
  carriers from general nearby combat. Its exception is a lone carrier
  intercepting the thief carrying its own flag. That exception does not apply
  when its home flag is safe and an ordinary hostile blocks the return.
- Server rule-bot carriers use their separate `BotController` objective logic.
  The larger-roster support branch deliberately leaves carrier shooting off;
  the smaller-roster branch only defends against its own flag thief at contact.
  These are distinct populations, not interchangeable measurements.
- `Navigator::steer_with_visibility` suppresses fire on noncombat goals.
  Setting a fire bit on a flag-route action therefore cannot establish actual
  self-defense. Changing the aim target to an enemy can instead change routing
  into pursuit. Verify the full controller path before claiming an improvement.

## Bounded change

First prove and address close-contact self-defense in the player-facing free
brain controller and the matching contested external-agent observation. Reuse
the current 1.5 m contact scale for the initial experiment, current visibility,
hostility, ammunition and weapon timing. A living enemy physically obstructing
the immediate return should permit a bounded defensive shot opportunity while
retaining the flag return as the objective. No enemy pursuit, target chasing
through cover or unbounded stationary fight. Resume the return when the contact
clears, dies, becomes ineligible or exhausts that defensive opportunity.

Use ordinary Action and shared navigation/body avoidance. Any small retained
contact state belongs in the existing local controller lifecycle and clears on
death, respawn, role/map change and flag loss. Prefer one shared pure eligibility
decision over duplicated side and visibility rules; do not create a second
navigation model. The controlled `RouteProbe` remains unopposed and never fires.
Do not silently promote the experiment to server rule bots. Their separate
roster and ordinary-human opposition need a later, explicit acceptance decision.

No scoring, touch radius, return timer, capture limit, map geometry, shield,
damage, weapon range, server outcome authority, protocol or paid-model change.
Keep the established home-flag recovery and defender/escort responsibilities.

## Verification and acceptance

1. Retain the current exact source/binary boundary and a failing actual-action
   scenario: finite armed carrier, valid enemy flag, home flag safe, a visible
   hostile at contact on its homeward path. Drive the existing controller,
   navigator, Action ingestion and damage resolution. Record that the current
   route-only carrier does not defend; no forced damage or teleport during the
   exercised behavior.
2. Prove bounded defense and subsequent return progress through that same path.
   Cover teammate, dead/detached/inactive hostile, blocked LOS, outside contact,
   empty weapon, fresh respawn, changed map, lost flag and recovered own flag.
   Verify no remote enemy can pull the carrier off its return and no stale
   defensive state survives a lifecycle change. Preserve the harmless probe.
3. Repeat baseline and candidate observations with the same settled Sector 9
   geometry, seeds 40-44, four alternating Reflex/Planner clients, capture limit
   one and a 180-second clock. Retain every timeout and failure. Tabulate takes,
   drops, combat drops, returns, captures, carry distance/progress, home denial,
   frags and stalls. Use live status to disclose concurrent workload; do not
   describe these asynchronous observations as deterministic replays.
4. Run the real free brain socket CTF case separately and preserve its bounded
   spend-free configuration. Keep existing four-rule-bot scored/seed regressions
   and controlled socket capture passing without retuning rules or assertions.
   Check at least one other supported CTF venue to avoid a Sector 9-only policy.
5. Accept only an actual defensive opportunity with prompt objective resumption
   and no demonstrated routing/role regression. The measured scoring table is
   evidence, not a guaranteed capture count. If the contact policy increases
   stalls or losses, retain the failed candidate and withhold it. Human fun,
   spectator readability and physical LAN acceptance remain separate.

## Spend and delivery

$0. Local free controllers only; no decision-model API, cloud or asset service.
No new dependency or runtime. Record the before/after action trace and complete
observation table in a dedicated evidence receipt before marking implemented.
Current full gates continue before this follow-on changes runtime source.
