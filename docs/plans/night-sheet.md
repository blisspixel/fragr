# Night sheet

**Status:** implemented in source (2026-10-06). Focused server checks passed. Not merged. The running night process was built at 07:39 and does not serve this. It was left running: today's source speaks gameplay 37, and the published client speaks 36.

## Goal

A host can see how the night went: how many rounds finished, how busy the room got, and which show had the top score. The public probe gains only the three counts.

## Non-goals

A phone-home, a paid analytics product, Prometheus, a file ledger, accounts, or a public ladder. Player service records stay the local profile in [benchmark and stats](benchmark-and-stats.md). Ratings stay deferred. This does not start a mode, bump gameplay, or replace the live process. Kernel checks and client surveillance stay out.

## Architecture

`server/src/sheet.rs` keeps an in-memory card on the session. Each tick notes the participant room the same way `live_status` does: a human counts as a human, a joined agent and a rule bot count as fighters, a spectator does not. When a round ends, the card stores that show (map, mode, round, reason, top score, frags, and the room) and the process logs one `SHEET` JSON line. The card keeps the latest 32 shows. The finished-round count is the full count.

Campaign rounds land on the same card. The mode label is `campaign` there. An arcade show uses the rule-set id, or `ffa` when the map has none.

The playlist advances at the start of the next round, so the ending tick still names the show that finished. Recording stays in the existing round-end log path. There is no new disk write on the tick.

## Protocol or API

`ops.version` stays 1. `ops.night` is additive: `rounds_finished`, `peak_humans`, `peak_fighters`. Older status JSON that omits it reads as zeros. The block has no callsign, address, ticket, or token. The plain body stays under 2048 bytes.

The desk verb is `stats`, with no arguments. `status` remains an alias of `who`. The desk card may name the top score. `GET /status` does not.

## Verification

`sheet` unit checks cover peaks, a named show, the 32-show cap, and totals with no callsign. The desk parse check accepts `stats` and still treats `status` as `who`. A session tick that ends a round fills the card and leaves the address off it. The status size check expects `ops.night` at zero and still rejects a body that contains `name`.

## Spend

$0.

## Success

An operator of the night process can read the card from the desk, grep `SHEET` in the log, or read the three counts from `GET /status`. A neighbor on the LAN who probes the host still cannot read callsigns from that probe.
