# Native island and vehicle integration evidence

Local verification on 2026-10-06, before the separate M11 integration. This is
working-tree evidence, not a deployed release or a human play acceptance.

## Functional gates

The composed Rust source passed `cargo check --locked --workspace --all-targets`
and `cargo clippy --locked --workspace --all-targets -- -D warnings`.
`cargo fmt --all` completed. The focused server filters passed: `conquest`
8 tests, `water` 12, `vehicle` 28, `net::outbound` 11 and `bot_senses` 12.
These filters overlap and must not be added into one total. The adapter's
`vehicle` filter passed two strict input and observation tests. The dedicated
binary's Conquest match-config test also passed, verifying its 600-second
clock and absence of frag, capture-count, boss and compliance-ping endings.

The unchanged seven-map roster behavior gate passed: every existing bot
personality moved, fired and hit. Conquest now shares delayed observation,
bounded turn speed and angular error while preserving capture destinations.
New water negatives reject nonfinite bounds, impossible depth, overlap,
inverted rectangles, excessive region counts and unknown fields. Adjacent
regions may share an edge.

Eighteen client vehicle golden vectors match native motion within 0.00088303;
six swimming vectors match within 0.00000057. Both remain below the unchanged
0.001 tolerance. Live client driving checks separately exercised Jeep and
boat entry, movement, braking, mounted fire and exit. Their detailed rendered
and socket receipts belong to the vehicle client evidence, not this CPU gate.

## Same-binary CPU comparison

Machine: AMD Ryzen 7 7840U, eight cores and sixteen logical processors,
Windows x86_64 build 26200, Balanced power plan. These are release builds.
The source is the shared working tree above base
`dff173655e828a811992b917ed51a473354a90eb`, with gameplay capability 41.
The measured executable SHA-256 is
`0a643e8921934d9bc7c2dd4c2a4292831a7025d90b42a69c7aa5c32ac4797b6a`.

Each sample uses the existing benchmark with 1,200 ticks, seed 42, a repeated
trace check and the unchanged budget assertion. No renderer, headless client
suite or build ran during the retained comparison. An earlier sample overlapped
a finishing headless client suite and is retained separately with the
`-concurrent-headless` suffix; it is not the table below.

| Map | Rule bots | Ending fighters | Mean tick ms | p99 tick ms | Max tick ms | Ticks over 50 ms |
|---|---:|---:|---:|---:|---:|---:|
| Arena Duel | 16 | 16 | 0.1683 | 0.6881 | 5.7636 | 0 |
| Arena Duel | 64 | 64 | 0.8065 | 3.2768 | 6.4545 | 0 |
| Holdfast Atoll | 16 | 17 | 0.2539 | 1.7695 | 3.9032 | 0 |
| Holdfast Atoll | 64 | 65 | 0.6912 | 2.8836 | 11.2722 | 0 |

All four repeated traces are identical. Holdfast's normal arcade boss accounts
for its extra fighter. These are actual rule bots sharing the ordinary session
tick, not spectator connections. The harness measures session work and JSON
encoding once per broadcast or targeted message. It excludes per-recipient
fanout, sockets, rendering and trace output. It uses ordinary FFA rules and
round transitions, not Conquest. The registered fleet is present but the bots
do not drive it. These results do not prove 64 network players, dense ongoing
combat on every tick, client frame rate or cross-machine capacity.

Reproduce from the same source and release build:

```text
cargo build --locked --release -p fragr-server --bin fragr-server
fragr-server --bench N --bench-ticks 1200 --map M --seed 42 --bench-check --bench-assert
```

Use `N` of 16 and 64, and `M` of 1 and 7. Local JSON reports and environment
metadata are under `.agents/native-quality-20261006/`. The later composed Rust
suite, coverage gate and CI result must be recorded separately after M11 lands.
