# Launch Authority composition: native verification

Status: implemented, 2026-10-15. Delivery is tracked by [PR #404](https://github.com/blisspixel/fragr/pull/404). This receipt records local native verification of
the composed M14 campaign, strict save version 18, Sector 9 cover and build
identity changes. It does not establish human enjoyment, physical LAN, rendered
hardware performance, release packages or deployment. Mission-specific proof is
in [the M14 receipt](m14-native-20261015.md); map iteration and rejection history
are in [the Sector 9 receipt](sector9-spawn-exits-20261015.md).

Final native source, including the MCP Rocket correction, passes formatting,
strict workspace Clippy, all 2,100 workspace tests, unfiltered coverage at
93.01% lines and the complete release workspace build. Five intentional ignores
remain, with no filtered tests. Earlier gate results and rejected changes below
are retained as history, not substituted for this final source check.

## Source and method

Shared branch work starts at `fd8c527`, following the Walker foundation merge.
Native tools use Rust 1.97.1 and locked dependencies. Full tests use two test
threads and builds use two jobs to bound concurrent work. Logs and exact
commands are retained under `.agents/launch-authority-20261015/`. No production
credentials, paid API or cloud host participate.

The preserved third-candidate binaries include composed gameplay 49 and final
M14 validation, before the subsequent build-label refresh and test-expectation
corrections. Neither later correction changes game simulation. Their SHA-256
bindings identify the actual local gameplay binaries used by directional
network observations and isolated benchmark/soak:

- Server: `f988abd4be6d1603120d4a7f7b7b48d7218dc131a53b3200df3b9e8dfdf4fef5`.
- Playtest: `0256d895764d6586a05b32195beaef0ea215767457e12684d2a66fdd7577fa44`.

Those binaries contain cached historical build-label strings. The hashes and
retained source diff bind these observations; the labels are not source proof.
The first final compilation still retains the old labels, exposing a second
cache boundary described below. The watcher alone is not claimed as the fix.

## Retained failures and corrections

The first composed workspace run reaches 1,455 passing server tests and two
failures. The second Sector 9 cover candidate overlaps Sabotage B's plant area
and holding spot. The third candidate shortens only the two lengthened rows;
all fifty existing Sabotage checks, nineteen spawn-filter checks, map validation,
flag-base navigation and the scored rule-bot CTF case pass. Existing assertions,
plant boundaries, timers and shields are unchanged.

The next full run passes all 1,457 server unit tests, with four intentional
ignores, then finds four stale current-writer expectations in the older
`local_child` integration tests. They expect save version 17 while the current
writer correctly emits 18. Only those output assertions change; historical
v3-v6 input documents and archive/resource checks stay intact. All eighteen
focused local-child process tests then pass. Both failed full logs remain.

The first preserved-binary soak invocation refuses to start because the renamed
playtest executable has no sibling named `fragr-server`. Its error remains in
`soak-v3.log`. The corrected command uses the supported explicit `--soak-server`
path, with the same binary and no changed acceptance thresholds.

After those gates, the actual release `--version` remains stale. Cargo's cached
build-script dependency record points to the external include in an earlier
worktree sharing the target directory. A real Cargo-cache regression reproduces
the failure, and rejects an attempted `CARGO_MANIFEST_DIR` include wrapper too.
The implementation now lives in the private std-only `fragr-build-metadata`
path build-dependency, with seven tiny callers. Both actual-topology cache tests
pass. The manifest change triggers fresh complete native verification; earlier
successful gates remain recorded separately. The initial dependency-policy run
rejects omitted version requirements on those path edges. Explicit `0.1.0`
requirements satisfy the unchanged policy; the corrected license/ban/source
check passes. No third-party package is added. The real license generator writes
notices for 95 linked third-party crates, excluding the private build-only helper.

## Native gates

The first settled source includes the watcher and current-writer assertions.
`native-final-status.txt` records each gate's actual exit, with separate logs:

| Gate | Result |
|---|---|
| Workspace formatting | Pass |
| Workspace/all-target Clippy, warnings denied | Pass |
| Complete workspace tests, locked | Pass |
| Unfiltered workspace coverage, minimum 90% lines | Pass, 93.07% |
| Complete release workspace build, locked | Pass, stale-label discovery retained |
| License, ban and source policy | Pass |
| Godot checker failure-injection selftests | Ten pass |

The complete workspace run reports 2,098 passed tests and five intentional
ignores across its test groups, with no failures or filtered tests. This
includes the real Cargo-cache identity regression and all eighteen child-process
tests, not only the server library.

Coverage reports 86,715 lines with 6,011 missed, 92.60% regions and 91.15%
functions. It runs the complete workspace without file/test filters or a
reduced threshold. The renderer remains stopped through this instrumented run;
the window is released after the coverage result. The private build-dependency
follow-up has separate `native-metadata-status.txt` and logs. Formatting,
workspace/all-target Clippy, the complete workspace tests and the complete
release workspace build pass again. That test run reports 2,099 passed, five
intentional ignores and zero failures or filtered tests across 49 test groups.
The unfiltered coverage rerun also passes with exit zero: 92.99% lines
(86,787 total, 6,082 missed), 92.51% regions and 90.93% functions. All 2,099
tests pass again with five intentional ignores and no filters. The final rerun
overlaps bounded client verification and is a correctness gate, not an isolated
performance measurement. No threshold or source exclusion is added.

The actual rebuilt release now reports `fragr-server v0.84.0`. An owned loopback
server's `/status` independently reports release `v0.84.0` and commit
`fd8c527763f8a15e23052c98df634f6b86969505`, matching the current Git identity.
The corrected server SHA-256 is
`c5a5b28502f01847e5f2b71f469c439c225fdec11fc0089e291d43c07df8411a`;
the playtest SHA-256 is
`b8a3b367358d43e8d5531f0dafca466906ff05db5815ee8a70a9afb834c6f886`.
The CLI, JSON status and hash receipts use the `-metadata` suffix, preserving
the earlier stale-label evidence. These identify the local uncommitted build,
not a published release package.

The license check reports existing unmatched allowlist warnings, not a license
failure. Client harnesses are discovered from `client/scripts/test_*.gd`, so the
new Walker and M14 harnesses enter the existing checker automatically. Full
Godot results and rendered reviews belong to parent integration.

Final adapter review then finds an independent availability defect: MCP's act
weapon selector still lists nine weapons and refuses Rocket, although native
combat and the campaign support it. The new negative regression reproduces the
omission. The schema and strict validator now derive from `WeaponType::ALL`,
and the test sends every supported selection through an actual `tools/call`
request into the pending action channel. All 61 focused MCP tests pass. A fresh
composed native chain is recorded separately in `native-rocket-status.txt` and
`*-mcp-rocket.log`. Every gate exits zero: formatting, strict workspace Clippy,
all 2,100 tests, unfiltered coverage and complete release workspace compilation.
The final coverage run executes all 2,100 tests again, with five intentional
ignores and zero filters. It reports 93.01% lines (86,820 total, 6,072 missed),
92.52% regions and 90.96% functions. No game simulation changes for this adapter
correction, and the previous complete gate results remain.

Server and playtest hashes stay identical to the corrected metadata build.
The final adapter SHA-256 is
`ee4e1f18af7d253ef5569b968006f56cefe2cbf6a28e02db9faad6f0fbbd7641`;
its actual CLI reports `fragr-agent-adapter v0.84.0`.

PR #404's first CI run (`38767699224`, head `7f84761`) finds a test-fixture
portability defect after the local gates: both build-identity tests compare
Cargo's plain `Fresh metadata-fixture` output, while CI sets
`CARGO_TERM_COLOR=always`. ANSI escapes interrupt that substring. The same
compiled local tests reproduce both exact failures with forced color in 0.49 s;
the earlier baked-identity assertions pass. The fixture now forces
`CARGO_TERM_COLOR=never` only for its nested Cargo command, preserving the cache
assertions and normal CI color outside the fixture. No production build helper
or gameplay changes. The failed CI log and local before/after receipts are
retained as `pr404-test-failure.log` and `metadata-ci-color-*.log`. Both tests
pass under forced-color outer environment in 1.55 s; formatting and strict
target Clippy also pass. The updated PR
reruns complete CI rather than treating the earlier local gates as exact-head
CI evidence.

## Live network checks

All eight required cases pass on the corrected gameplay binary: four-client
FFA, TDM, Rail-only, licence-to-kill TDM, controlled CTF capture, contested CTF,
controlled Sabotage plant/defuse and contested Sabotage. Commands, per-case JSON
and logs are in `network/`; `network/status.txt` retains all eight zero exits.
These bounded observations overlap native tests and some software-rendered QA.
They are gameplay checks, not isolated capacity benchmarks.

The contested CTF case still ends 0-0 at 181.95 seconds, with fifteen frags, two
takes, one combat drop and one return. Both carries make substantial homeward
progress, with no own-flag-away or home-blocked ticks. Passing combat/replication
assertions does not mean a successful contested capture. The carrier-contact
[follow-on plan](../plans/ctf-carrier-contact-20261015.md) preserves that limit.
The contested Sabotage case plants and ends by elimination, with two frags and
four pickups in 26.60 seconds; the separate controlled case proves defuse.

The required `tools/playtest_roster.sh` completes with exit zero:

| Map | Clients | Seed | Frags | Early deaths | Opening deaths |
|---:|---:|---:|---:|---:|---:|
| 1 | 2 | 67 | 5 | 0 | 0 |
| 2 | 6 | 42 | 29 | 0 | 0 |
| 3 | 6 | 19 | 24 | 0 | 0 |
| 4 | 8 | 42 | 34 | 0 | 0 |
| 5 | 12 | 42 | 43 | 1 | 0 |
| 6 | 16 | 42 | 53 | 1 | 0 |
| 7 | 16 | 42 | 50 | 0 | 0 |

The corrected Sector 9 observation has no early deaths. The two other venues'
early deaths remain in their reports. This roster uses the first final-release
playtest SHA `195eb0f65e550b2ec054e7eac9953bb4cad2adddf2b1f1adfa3f7ae7efa707a0`,
before the private build-dependency correction and with its stale label noted.
No gameplay source changes between that roster and the metadata correction.

## Isolated CPU benchmark and soak

The renderer and other owned native jobs are stopped for these observations.
The prescribed release benchmark uses sixteen rule bots, 1,200 ticks, seed 42
and both deterministic and timing assertions. It passes with session/encoding
p99 0.557 ms, maximum 0.935 ms and zero ticks over the 50 ms budget. This is
CPU simulation/encoding evidence with zero network clients, not GPU or
large-room network capacity evidence. Trace hash:
`6e8c0355280a158524ed20061b0ffaa531d7385f308e60709acec4da2becba0c`.

The prescribed 120-second soak runs four rule bots, four agent sockets and two
spectators, with map rotation enabled and samples every fifteen seconds. All
nine samples pass; measured tick rate is 19.9998 Hz. There are zero degraded
samples, zero queue overflows and zero over-budget ticks. Lifetime p99 is
0.623 ms and maximum is 1.140 ms. Process RSS rises from 66.0 MiB to 68.1 MiB.
Mean observed payload is about 58,105 outgoing and 2,314 incoming bytes per
client per second. These are loopback observations over two minutes, not a
long-duration memory guarantee, cloud billing estimate or physical LAN proof.
The complete verdict is retained in `soak-v3-explicit-server.ndjson`.

External spend is $0. Final integration, exact-head CI and release packaging
remain parent-owned gates.
