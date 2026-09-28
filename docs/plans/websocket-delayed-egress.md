# Delayed WebSocket combat probe

**Status:** implemented, 2026-09-28. Stacked after the [continuous moving-combat
probe](websocket-moving-combat-probe.md). The two-machine and human-feel gates
remain open. External spend $0.

## Goal and reason

Measure the existing predicted WebSocket fight when server Acks and snapshots
arrive later than on loopback. The current 20-second receipt has near-zero
loopback delay, zero fallbacks and one 0.354 m peak same-tick correction. It
cannot show whether the same client remains continuous with delayed server
traffic. Do this bounded test before building a UDP path.

## Setup and scope

- Build the exact branch's Rust server in the installed WSL Linux distro and
  connect the native Windows Godot 4.7.2-stable client to its WSL address.
  Use Arena Duel, seed 1, one rule bot, and the existing
  `client/qa/websocket-moving-combat.json` 20-second state. Launch the Godot
  script directly, since `tools/qa_tour.sh` starts a separate local server.
- Run an unshaped control, then fixed 40 ms and 80 ms egress delays with Linux
  `tc netem` on the WSL server interface. Repeat each condition three times
  if the first run is valid. Verify the actual Windows-to-WSL ping distribution
  and capture the queue setting before and during every condition.
- Record the existing Ack, snapshot, correction, fallback, traffic, sampled
  movement and shot fields. Keep manifest, client and server logs under
  ignored `.agents/`. Mark a failed or interrupted window invalid, not zero.
- Check the initial root queue setting before changing it. If it differs from
  the observed WSL default, stop. A cleanup handler removes the temporary
  netem root queue even if a run fails, then checks that the initial default
  returned. Do not shape another interface or leave a persistent rule.

The delay is applied to **server egress only**. It delays Acks and snapshots,
while client Actions travel to WSL without the same added delay. WSL and
Windows also share one physical machine. This is a controlled diagnostic, not
symmetrical 40/80 ms network RTT, a two-machine LAN proof, a human feel test,
or a public-server capacity result. Ping to the WSL address is a reachability
and timing check; record what it actually measures rather than assuming it
exactly matches gameplay RTT. Linux `tc-netem` documents egress delay and
warns that TCP queue behavior can depend on where emulation is placed
([manual](https://man7.org/linux/man-pages/man8/tc-netem.8.html)).

## Verification and decision

The existing moving-combat gate requires one connected human-role client,
20 seconds of ordinary moving and firing, a live opponent, selected Acks and
snapshots across the window, at least 10 correction samples per second, no
death or role change, and no gap above 250 ms. Compare median, p95, p99 and
maximum same-tick correction; peak context; Ack timeout and unknown-sequence
fallbacks; selected Action-to-Ack time; snapshot gaps; text payload bytes;
and sampled movement and shots against the unshaped control. Any invalid
window, fallback or p99 over 0.1 m is an investigation result, not an
automatic reason to change transport.

The first 80 ms run exposed repeated `unknown_seq` prediction fallback. A
pre-tracking Action selected by a delayed Ack is consistent with the receipt;
the focused test reproduces that failure. Fix the client bootstrap boundary,
then repeat the same conditions on the fixed exact head. Keep any
failure receipt rather than recasting it as a valid baseline. Protocol, pin
and hosted resources stay unchanged. The result should say whether a real
two-machine LAN session is ready and what to watch there. UDP remains a
separate measured spike. No paid API, cloud resource or external billing is
used.

## Implementation and evidence

The predictor now remembers the first Action it successfully records in each
replay epoch. An advancing Ack for a preceding Action can establish an
authoritative baseline even when that Action is absent from local history. An
unknown selected Action at or after the recorded boundary still causes
snapshot fallback. Map resets and epoch changes clear the boundary. Focused
tests cover a delayed bootstrap, a failed send, an epoch change, sequence wrap
and the later unknown-Action fallback. No on-wire field or server outcome
changed. The QA observer polls twice per 50 ms server tick so phase alignment
does not hide snapshots; ordinary client input pacing is unchanged.

The first 80 ms run before the bootstrap fix had 210 `unknown_seq` fallbacks
and zero correction samples. A later exploratory 80 ms run with the fix had
420 wire snapshots, zero fallbacks and 420 correction samples, but its observer
sampled 299 snapshots against a 300-snapshot gate. It was marked failed. The
first failure's precise cause is inferred from the focused reproduction and
the successful rerun, since the receipt did not record the selected sequence
at every Ack. The 299/300 miss came from the tour's 50 ms polling phase, not a
wire snapshot gap. Both receipts remain under ignored `.agents/qa/delayed-egress/`.

The final matrix ran on the same frozen source state after those fixes:
`01e97e2` plus working diff hash `1f5b0f7e1228edbb48316b79bbd3c6d6e5e9c608`.
Windows Godot 4.7.2-stable used its OpenGL renderer on an AMD Radeon 780M;
the release Rust server ran in WSL `numinous-linux`, seed 1, Arena Duel and one
bot. The server restarted before each 20-second capture. Ping is the mean of
five Windows-to-WSL ICMP samples taken while the condition was active. Server
egress had 0, 40 or 80 ms fixed delay, with no injected packet loss or jitter.

| Run | Ping mean ms | Action-to-Ack p95 ms | Same-tick error p95 / p99 / max m | Fallbacks | Wire / observed snapshots | Sampled shots | Sampled move m |
|---|---:|---:|---:|---:|---:|---:|---:|
| Control 7 | 0 | 14 | 0 / 0 / 0.2367 | 0 | 419 / 419 | 105 | 86.367 |
| 40 ms 7 | 39 | 86 | 0.2069 / 0.3541 / 0.3556 | 0 | 419 / 417 | 104 | 86.488 |
| 80 ms 7 | 80 | 136 | 0.3528 / 0.3559 / 0.3577 | 0 | 420 / 334 | 67 | 85.877 |
| Control 8 | 0 | 14 | 0 / 0 / 0.3536 | 0 | 419 / 419 | 105 | 86.832 |
| 40 ms 8 | 40 | 88 | 0.3092 / 0.3552 / 0.4097 | 0 | 419 / 417 | 103 | 90.327 |
| 80 ms 8 | 79 | 137 | 0.3195 / 0.3570 / 0.3698 | 0 | 419 / 340 | 84 | 78.841 |
| Control 9 | 0 | 14 | 0 / 0 / 0.0008 | 0 | 418 / 419 | 105 | 86.535 |
| 40 ms 9 | 39 | 87 | 0.2500 / 0.3547 / 0.3556 | 0 | 420 / 415 | 102 | 86.521 |
| 80 ms 9 | 85 | 137 | 0.3152 / 0.3567 / 0.3799 | 0 | 418 / 354 | 82 | 78.939 |

All nine gates passed. Each run had 418 to 420 correction samples, selected
Ack gaps at most 91 ms, wire snapshot gaps at most 97 ms, and 78.841 to
90.327 m of sampled server movement. Text payloads were 696,487 to 702,258
bytes received and 382,005 to 387,754 bytes sent per window. The 80 ms
observer saw fewer distinct snapshot ticks even though the wire received
roughly the same count. Sampled shots and movement are lower bounds from its
polling, not total server outcomes. The observer can count a snapshot already
held when the timed wire probe begins, so one control shows one more observed
tick than in-window wire snapshot arrivals. Control p99 rounded to zero in all three
runs, but two controls still had isolated 0.24 to 0.35 m maxima. Delay raised
p95 and p99 of same-tick replay error; the 40 ms and 80 ms p99 ranges overlap
near 0.35 m. This statistic does not measure presented camera displacement or
input-to-photon latency. The data do not identify a transport-only cause.

The WSL root queue was `mq` before and after every shaped run. It is `mq`
after the matrix, and the server process was stopped. No hosted resource or
paid API was used. The next gate is a real two-machine human session with
two-way timing, loss/jitter conditions and inspected motion before deciding
whether a UDP spike should lead the networking work.

The pinned Godot check passed after the predictor change. The first two
32-state visual tours failed the Railgun aim check because a bot killed the
joined QA fighter immediately before that static still. A later stricter tour
found that the initial weapon select could time out while that fighter was
dead. The tour now waits for a live authoritative pawn before weapon and aim
setup, restores the setup if death occurs before the still, and requires a
live pawn and requested weapon after capture. It keeps the strict
server-versus-camera pitch check. The final `tools/qa_tour.sh --publish` run
passed all 32 states and refreshed 13 approved stills. Its contact sheet,
Railgun still and both shot-effect strips were inspected. The successful
Railgun state recorded pitch 0.0 on both the camera and server, with Rail
selected and 100 HP. That QA recovery helper was added after the frozen
nine-run matrix; it does not change the moving-combat measurement loop. The
full pinned `tools/godot_check.sh` suite passed on the final code.
