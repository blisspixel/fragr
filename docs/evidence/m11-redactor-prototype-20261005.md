# Right of Search Redactor behavior checkpoint

Status: In flight. This is source and native behavior evidence for a new role,
not a selected character skin, playable M11, release or difficulty approval.

The prototype is based on the frozen Common Carrier source dependency. It keeps
an ordinary 1.8 m body, 90 HP, 0.6 walking gait and the existing pool-less Shiv.
The one-strike tell/recovery windows are provisionally 24/30, 18/24 and 14/18
ticks for Assisted, Standard and Severe. Earlier enemy tuning and campaign rules
revision 3 are unchanged. The full build is tracked in
[the owning plan](../plans/m11-right-of-search-prototype.md).

## Ordinary behavior proved

The nine focused native tests use the actual Session and GameState movement,
living contacts, encounter lifecycle and shot resolution where behavior is
claimed. They prove:

- A visible lateral approach moves continuously at the ordinary gait without
  body overlap or floor changes. Its held point is selected from two fixed
  clearance candidates and uses the unchanged shared Session navigator.
- A close windup keeps its original position and yaw, waits the full Standard
  tell, resolves one 35-damage Shiv strike, then holds recovery without extra
  attacks. Union guards do not receive participant records.
- An ordinary sidestep evades that locked ray. An ordinary walk behind an opaque
  records rack cancels the committed strike when real sight is lost.
- A rack between guard and participant requires actual walking around it before
  a strike. The guard does not cross its authoritative solid.
- Resolved ordinary pistol damage interrupts the tell. Continued ordinary
  gunfire produces a grounded death and one participant kill.
- Fixed local approach probes refuse a rack-crossing segment, low headroom,
  outer world edge and a raised support whose center cannot support the body.
- A selected approach point stays fixed while its visible quarry moves, retires
  after 60 ticks without immediately selecting a fresh point, and resets after
  loss of sight or an interrupt. No private path search or invisible live-target
  knowledge is added.
- A map placing this role requires the reserved capability 37. With the current
  advertised capability still 36, actual server startup refuses it before
  readiness. This is deliberate protection against presenting partial M11
  content, not a claim that admission for a completed M11 has passed.

The focused final receipt is `.agents/m11-structure-redactor-fifth.log` with
numeric exit 0 and all nine tests passing. The owning server Clippy run is
`.agents/m11-lints-redactor-first.err.log`, numeric exit 0 with warnings denied.
Formatting and patch whitespace checks pass. The complete locked workspace run
also passes at numeric exit 0, including 996 server unit tests, three existing
ignored diagnostics and all 18 local child-process tests. Its retained receipts
are `.agents/m11-workspace-redactor-live-first.log` and the paired stderr log.
Expected rejection diagnostics from negative child-process tests are retained,
not relabeled as renderer errors. This also checks the earlier finite Remote
Mine component and strict save-14 changes in this composed leaf.

## Client boundary

The existing actor boundary accepts the seven ordinary Redactor phases and
rejects invisible, leaping, charging and repair-channel states. The existing
actor harness passed on the pinned headless client with a clean error log:
`.agents/redactor-client-first.log`, numeric exit 0 and
`test_actor_state: PASS`. It does not inspect a new Redactor mesh or provide
rendered combat evidence.

## Retained failures and limitations

The first focused attempt caught source construction mistakes in the new test
and contact-key lookup. A separate command-shell quoting error overwrote the
local protocol file during a search; it was restored from its committed source
and the three-line reserved-capability addition was reapplied. That failed
compiler receipt remains retained. No accepted main source was affected.

A later fixture incorrectly tried to read a participant record for a Union
guard. The corrected fixture explicitly verifies that no such record exists;
the resolved shot count and damage assertions remain unchanged. The next
network fixture expected admission at capability 37 while the unfinished
runtime still advertised only 36. The actual refusal was preserved and the
fixture now verifies that required protection rather than lifting it early.

Actual imported geometry, skin, grounded gait, independent held Shiv grip,
moving red optic, readable heat distortion with sound muted, directional atlas,
native-resolution played combat, complete M11 and package checks remain open.
No generic or tinted guard is accepted as the final presentation. This
checkpoint contains no rendered claim and consumes no external credits.
