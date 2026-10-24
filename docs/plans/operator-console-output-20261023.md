# Operator console output (#438)

Status: **implemented** (2026-10-23, branch `wave1/operator-console`; Windows evidence outstanding).

## Goal

A dedicated `fragr-server` started in an interactive terminal (including a
Windows double-click of `fragr-server.exe`) shows a calm operator overview:
ready state, map and mode, human, agent, bot and spectator counts, uptime,
tick health, join addresses with their scope, how to stop, and how to use
the existing venue desk. It is no longer buried under bot FRAG and PICKUP
lines, self-probe connection debug lines and a full STATUS JSON block every
minute. Detailed events stay available through an explicit output choice.

The October 23 report and its follow-up comment narrow the problem to
operator output, not a graphical launch path: the dedicated process has no
window and renders nothing. Its terminal was a scrolling event feed.

## Root causes (reproduced on Linux, `e4cec37`)

Captured with `script` on a pseudo terminal, `--status-every-s 10`,
log under `.agents/baseline-tty.log`:

1. The default filter is `info,fragr_server=debug` for every serving mode.
   A terminal operator receives the same stream a log file does: four
   `Spawned bot` lines with UUIDs, `FRAG`, `PICKUP`, `HOST REACTION`,
   compliance pings, drone spawns, and a `DEBUG New connection` for every
   `GET /status` probe (the client's LAN scan and Check host probe too).
2. `STATUS {json}` is a multi-hundred-byte single line every
   `--status-every-s` (default 60).
3. The human ready line (#415) is printed once, between startup lines, and
   scrolls away within seconds once bots fight.
4. `primary_join_addr` takes the first adapter the OS lists. On the
   reporter's Windows host that was a 100.64/10 overlay while a LAN address
   was described separately, so the ready line named the overlay.
5. On Windows the #415 colour gate emits ANSI SGR whenever stderr is a
   console, but nothing enables virtual terminal processing. A classic
   console host without VT mode shows raw `ESC[32m` text. Windows Terminal
   enables VT itself, so this is invisible there.

## Design

Line-oriented, no repaint, no new dependency. A line console meets the
issue's needs, so the optional TUI from item 5 of #438 is not built.

- `--output auto|overview|log` (Hosting and access). `auto` picks
  `overview` only when both stdout and stderr are terminals and `TERM` is
  not `dumb`; otherwise `log`. Redirected output, pipes, services, Compose
  and CI therefore keep the existing log stream. Only the dedicated serving
  path uses it; `--desktop-host`, `--ready-line`, the local mission child,
  benchmarks and the preview refuse an explicit `--output`.
- `log` keeps the existing filter, formatter and STATUS JSON unchanged.
- `overview`:
  - Default filter `warn,fragr_server=info,fragr_server::feed=warn,fragr_server::startup=warn`.
    `RUST_LOG` still replaces the filter in every mode.
  - Routine match feed lines move to target `fragr_server::feed`
    (FRAG, TEAM KILL, BOSS DOWN, PICKUP, HOST REACTION, bot spawns and
    refills, compliance pings, drone and Auditor spawns, boss wipe, team
    balance, Sabotage play-by-play). Startup narrative the card summarises
    moves to `fragr_server::startup`. Only targets change; message text is
    unchanged. Warnings on those targets still print.
  - Compact log format: `+HH:MM:SS` process uptime, level word only for
    WARN and ERROR, no module target.
  - After readiness, a ready card on stdout under the unchanged
    `ready ws://... Ctrl-C stops` first line: what the process is (no
    window, bots fight without a viewer), match and bot policy, join
    addresses grouped LAN / other / overlay / this computer with the result
    of the existing self probe and the existing "does not prove another
    computer can connect" caveat, admission (ticket required or open, the
    two connection caps), how to watch, desk state and verbs, how to stop,
    and which output mode is active with the switch to `--output log`.
  - A one-line pulse on stdout from the existing `/status` snapshot
    (`LiveStatus` plus `ops`): uptime, map, mode, round, humans, agents,
    bots, watching, window tick p99 against the 50 ms budget with
    over-budget count, and health. It prints every `--status-every-s`
    (0 disables the periodic line) and when the room, map, mode or health
    changes, at most once per two seconds.
- Join addresses: preflight builds one scoped report from the existing
  adapter filter and probe; the existing log lines are produced from it,
  the card reads it, and the ready line prefers LAN, then other, then
  overlay, then loopback.
- Venue desk: `status` (today an alias of `who`) prints the pulse and the
  join addresses before the same `who` table, so existing use keeps its
  output. Help, banner and the unknown-verb hint name it.
- Colour: on Windows, a resolved colour choice first enables VT processing
  through `nu_ansi_term::enable_ansi_support` (already in the lockfile
  through `tracing-subscriber`, now a direct dependency at the same
  version). `auto` falls back to plain text when the console refuses;
  `always` still asks for VT mode first and keeps colour either way. The card and pulse use the same gate on stdout.

## Non-goals

- No change to gameplay defaults (four fixed bots, Arena Duel FFA, respawn,
  starting weapon) and no forced startup wizard.
- No automatic desk: `--console` stays opt-in. Open question below.
- No change to the `/status` wire, `ArenaReady`, `--ready-line`, the
  desktop stdin lease, or the desk's ownership semantics.
- No screen repaint, alternate screen, cursor movement, or TUI crate.
- No Windows service wrapper, log file writer, or pause-on-exit.
- Client changes (the app-owned host page) are not in this lane.

## Protocol and API changes

None on the wire. New CLI flag `--output`. New log targets
`fragr_server::feed` and `fragr_server::startup` (text unchanged). Desk
`status` output becomes a superset of `who`.

## Verification

- Unit tests: output resolution matrix (auto with/without terminals,
  `TERM=dumb`, explicit choices), overview filter hides feed and startup
  info but keeps warnings (captured subscriber), compact formatter has no
  escape bytes with colour off, card and pulse rendering (scopes, desk
  on/off, ticket on/off, degraded health, missing ops), pulse cadence and
  change throttling, join report ordering and primary address preference,
  desk `status` parse and outcome, CLI conflicts.
- Integration: a spawned release binary with redirected output keeps the
  log format and STATUS JSON and contains no ESC byte; under `script`
  (pseudo terminal) auto picks overview, prints the card and pulses, and
  hides FRAG/PICKUP. `NO_COLOR=1` removes escapes in both.
- `cargo fmt --check`, `cargo clippy --workspace --all-targets --locked -D warnings`,
  `cargo test --workspace --locked`, `cargo deny check licenses bans sources`.
- Windows: not reproducible on this Linux host. A packaged Windows
  walkthrough (Windows Terminal and classic console, double-click and
  PowerShell, `> file 2>&1`, `NO_COLOR`) remains required evidence.

## Success criteria

- Interactive default shows the card and pulses; FRAG, PICKUP, bot spawn,
  probe debug and STATUS JSON lines do not appear unless asked for.
- Redirected or `--output log` output is byte-for-byte the old format apart
  from the two new target names, and has no escape sequences without
  forced colour.
- The ready line never prefers an overlay over a LAN address.
- `docs/HOSTING.md` has a Windows section: which executable does what,
  what a double-click starts, how to stop, desk, logs to a file, colour.

## Open questions for Nick

1. Should an interactive dedicated launch open the venue desk without
   `--console`? Kept opt-in here.
2. Should a double-clicked Windows server keep its window open after a
   startup error (port taken)? Today the window closes with the message.

## Evidence (2026-10-23, Linux host)

Logs are under the lane's ignored `.agents/` directory.

| Check | Result |
|---|---|
| Baseline pseudo terminal, `e4cec37` (`baseline-tty.log`) | Ready line among bot spawns, FRAG, PICKUP, HOST REACTION, DEBUG probe and STATUS JSON lines |
| Pseudo terminal, `auto`, wildcard bind (`after-tty-auto.log`) | Card with LAN, overlay and local scopes, LAN first; pulses at 0, 15 and 30 s; round line visible; no feed, probe or STATUS lines |
| Pseudo terminal, `NO_COLOR=1` | Overview, zero escape bytes |
| Pseudo terminal, `TERM=dumb` | Plain log (feed lines present), no card, zero escape bytes |
| Redirected to a file | Plain log, STATUS JSON every 2 s, `fragr_server::feed` and `::startup` targets, no card, zero escape bytes |
| `cargo test -p fragr-server --test operator_output` | 6 passed: redirected log, forced overview card and pulses, forced colour without magenta, desk `status` and closed input leaving the match running, taken port with no card, a watcher changing the room line |
| Unit tests (`logging`, `operator`, `preflight`, `desk`, CLI) | Pass: filter audiences through the real formatter, output resolution matrix, card and pulse rendering, pulse clock, scope ordering and failure paths |
| `cargo clippy -p fragr-server --lib --bins --target x86_64-pc-windows-gnu -D warnings` | Pass (compile check of the Windows-only VT path; not linked or run) |
| `cargo fmt --check`, workspace clippy `-D warnings`, `cargo deny check licenses bans sources` | Pass |
| `cargo test --workspace --locked --no-fail-fast` (load average about 65 on 16 cores, six lanes) | 9 failures, all readiness or timing deadlines: adapter `scripted_bot_uses_raised_geometry...` (4 s), three `geometry_owned_local_*` (30 s), `four_readers_share_one_start...`, five `local_child` (10 s child readiness). Every other crate and test passed |
| Isolated reruns of those failures (load 41 to 57) | Adapter test 3 of 3 pass; the four lib tests pass; `local_child` 18 of 18 pass. Base `e4cec37` `local_child` also 18 of 18 at similar load. None touches the overview path: local children keep the plain log |

Status after this round: **implemented** locally on `wave1/operator-console`;
CI on the PR is the next gate.

The desk was exercised through piped stdin in the integration test; an
interactive typed session under a pseudo terminal was not captured.

Not run here: any Windows execution (Windows Terminal, classic console,
double-click, PowerShell redirect, VT refusal fallback), the packaged
walkthrough, the Godot checks (no client change), coverage and the
playtest/soak jobs.

## Independent review round (2026-10-23, Linux host)

Reviewed `310261d..fa01da2` against `origin/main` (`e4cec37`) and issue #438
with its follow-up comment.

Fixed in review:

- `--color always` skipped the Windows VT switch entirely, because the
  `always` check short-circuited before `console_accepts_ansi()`. A classic
  console would then print raw `ESC[` text even when it accepts VT mode. The
  gate now always asks the console when colour is wanted. Compile-checked
  for `x86_64-pc-windows-gnu` only; not run on Windows.
- The taken-port integration test now asserts the single error line it
  claimed (and no escape bytes), not only the absence of the card.
- The HOSTING.md leave table names both places **Stop server** appears
  (the Run a match page and the pause menu while watching that match).

Re-run in review (logs under `.agents/`): `cargo fmt --check`, workspace
clippy `-D warnings`, Windows-target clippy for `fragr-server`,
`cargo deny check licenses bans sources`, the `operator_output` integration
test (6 of 6), the full `fragr-server` test suite (every target passed
except three `geometry_owned_local_*` 30 s readiness deadlines at load
average about 57; those three passed 3 of 3 on an isolated rerun at load 28,
and they do not use the overview path), and a pseudo-terminal
capture of the release binary under `auto` with a wildcard bind
(`review-tty-auto.log`: card with LAN, overlay and local scopes in that order,
pulses at 0, 10 and 20 s, the round line, no feed, probe or STATUS lines).

Status after review: **implemented on Linux, Windows evidence outstanding.**
Still not run: any Windows execution (Windows Terminal, classic console,
double-click, PowerShell redirect, VT refusal fallback, Firewall prompt),
the packaged walkthrough, coverage, and the playtest/soak jobs. CI on the PR
is the gate for the workspace suite and the coverage floor.
