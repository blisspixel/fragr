//! A host's fun metrics, read back as the tables the bot survey and the 1.0
//! bar use. Records are folded by mode, map and bot tier with the same
//! `MatchTally::add` and the same `bot_survey::shared_row` the survey uses,
//! so a host's frag a minute is the survey's frag a minute. Reading only:
//! the summary never writes into the host's folder.
use crate::bot_survey::{check_map_targets, shared_row, ScenarioReport};
use fragr_server::fun_metrics::{share, FunRecord, MatchTally, TickHealth};
use fragr_server::protocol::GameMode;
use fragr_server::sim::{BotSkill, MapKind};
use serde::Serialize;
use std::collections::BTreeMap;
use std::path::Path;

/// One mode, map and tier across the host's matches.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct SummaryRow {
    pub mode: GameMode,
    pub map_id: u32,
    pub bot_tier: BotSkill,
    /// Matches that reached their end, of all matches filed.
    pub finished: u32,
    pub mean_fighters_peak: f64,
    /// The shared survey columns for these matches.
    pub row: ScenarioReport,
    /// Kill time quantiles live in `row.time_to_kill_s`; this is the share of
    /// all frags landed by the gun that landed the most.
    pub top_frag_share: f64,
    /// The worst tick p99 and the over-budget ticks across the matches, ms.
    pub worst_tick_p99_ms: f64,
    pub ticks_over_budget: u64,
    /// Conquest: matches won by each side.
    pub conquest_union_wins: u32,
    pub conquest_coalition_wins: u32,
    /// Lines that miss the wave 19 map targets, as the survey prints them.
    pub targets: Vec<String>,
}

#[derive(Debug, Clone, Serialize, PartialEq, Default)]
pub struct Summary {
    pub folder: String,
    pub matches: u32,
    pub refused: Vec<String>,
    pub rows: Vec<SummaryRow>,
}

fn map_slug(map_id: u32) -> String {
    MapKind::ALL
        .iter()
        .find(|map| map.id() == map_id)
        .map_or(format!("map-{map_id}"), |map| {
            map.name().to_ascii_lowercase().replace(' ', "-")
        })
}

fn tier_id(tier: BotSkill) -> String {
    serde_json::to_value(tier)
        .ok()
        .and_then(|value| value.as_str().map(str::to_owned))
        .unwrap_or_default()
}

#[derive(Default)]
struct Group {
    matches: u32,
    finished: u32,
    fighters: u64,
    tally: MatchTally,
    worst_p99_us: u32,
    over_budget: u64,
}

/// Mode id, map number, tier id and mutator ids: one summary row.
type GroupKey = (String, u32, String, String);

/// Fold records by mode, map, tier and mutators, in that order.
pub fn summarise(records: &[FunRecord]) -> Vec<SummaryRow> {
    let mut groups: BTreeMap<GroupKey, (GameMode, BotSkill, Group)> = BTreeMap::new();
    for record in records {
        let twists: String = record
            .mutators
            .iter()
            .map(|mutator| format!("+{}", mutator.id()))
            .collect();
        let key = (
            record.mode.id().to_string(),
            record.map_id,
            tier_id(record.bot_tier),
            twists,
        );
        let (_, _, group) = groups
            .entry(key)
            .or_insert_with(|| (record.mode, record.bot_tier, Group::default()));
        group.matches += 1;
        group.finished += u32::from(record.finished);
        group.fighters += u64::from(record.fighters_peak);
        group.tally.add(&record.tally);
        if let Some(TickHealth {
            p99_us,
            over_budget,
            ..
        }) = &record.tick_health
        {
            group.worst_p99_us = group.worst_p99_us.max(*p99_us);
            group.over_budget += over_budget;
        }
    }
    groups
        .into_iter()
        .map(
            |((mode_id, map_id, tier, twists), (mode, bot_tier, group))| {
                let label = format!("{mode_id}-{}-{tier}{twists}", map_slug(map_id));
                let row = shared_row(label, group.matches, &group.tally);
                let top_frags = group
                    .tally
                    .frag_weapons
                    .0
                    .iter()
                    .copied()
                    .max()
                    .unwrap_or(0);
                SummaryRow {
                    mode,
                    map_id,
                    bot_tier,
                    finished: group.finished,
                    mean_fighters_peak: group.fighters as f64 / f64::from(group.matches.max(1)),
                    top_frag_share: share(top_frags, group.tally.frags),
                    worst_tick_p99_ms: f64::from(group.worst_p99_us) / 1000.0,
                    ticks_over_budget: group.over_budget,
                    conquest_union_wins: group.tally.conquest.union_wins,
                    conquest_coalition_wins: group.tally.conquest.coalition_wins,
                    targets: check_map_targets(&row, mode),
                    row,
                }
            },
        )
        .collect()
}

/// Read a host's folder and fold it.
pub fn summarise_folder(folder: &Path) -> std::io::Result<Summary> {
    let (records, refused) = fragr_server::fun_metrics::FunStore::read_all(folder)?;
    Ok(Summary {
        folder: folder.display().to_string(),
        matches: records.len() as u32,
        refused,
        rows: summarise(&records),
    })
}

/// The table, in the 1.0 bar's columns, then each row's kill distances and
/// the target misses.
pub fn table(summary: &Summary) -> String {
    use std::fmt::Write as _;
    let mut out = String::new();
    let _ = writeln!(
        out,
        "fun metrics: {} matches in {}",
        summary.matches, summary.folder
    );
    let _ = writeln!(
        out,
        "| Row | Matches (finished) | Live min | Frags/min | Lead changes/match | Top gun (shots) | Top frag share | Kill time median s (p25 to p75) | Spawn deaths/spawn | Spawn to first hit median s | Pad contest | Sabotage attack share (rounds) | Tick p99 worst ms (over budget) |"
    );
    let _ = writeln!(out, "|---|---|---|---|---|---|---|---|---|---|---|---|---|");
    for summary_row in &summary.rows {
        let row = &summary_row.row;
        let (gun, gun_share) = row.top_gun();
        let kill = &row.time_to_kill_s;
        let sabotage = if row.sabotage_rounds > 0 {
            format!(
                "{:.0}% ({})",
                row.sabotage_attack_share * 100.0,
                row.sabotage_rounds
            )
        } else {
            "n/a".to_string()
        };
        let _ = writeln!(
            out,
            "| {} | {} ({}) | {:.1} | {:.1} | {:.1} | {} {:.0}% | {:.0}% | {:.2} ({:.2} to {:.2}) | {:.3} | {:.1} | {:.1}% | {} | {:.2} ({}) |",
            row.scenario,
            row.matches,
            summary_row.finished,
            row.live_seconds / 60.0,
            row.frags_per_minute,
            row.lead_changes_per_match,
            if gun.is_empty() { "none" } else { gun.as_str() },
            gun_share * 100.0,
            summary_row.top_frag_share * 100.0,
            kill.median,
            kill.p25,
            kill.p75,
            row.spawn_deaths_per_spawn,
            row.respawn_to_hit_s.median,
            row.pad_contest_index * 100.0,
            sabotage,
            summary_row.worst_tick_p99_ms,
            summary_row.ticks_over_budget,
        );
    }
    for summary_row in &summary.rows {
        let row = &summary_row.row;
        let distances: Vec<String> = row
            .kill_distance_m
            .iter()
            .map(|(weapon, metres)| {
                format!(
                    "{weapon} {:.1} m ({:.1} to {:.1}, n {})",
                    metres.median, metres.p25, metres.p75, metres.count
                )
            })
            .collect();
        if !distances.is_empty() {
            let _ = writeln!(
                out,
                "{}: kill distance {}",
                row.scenario,
                distances.join(", ")
            );
        }
        if summary_row.mode == GameMode::Conquest {
            let _ = writeln!(
                out,
                "{}: Conquest won by the Union {} and the coalition {}",
                row.scenario, summary_row.conquest_union_wins, summary_row.conquest_coalition_wins
            );
        }
        for miss in &summary_row.targets {
            let _ = writeln!(out, "target: {miss}");
        }
    }
    for refusal in &summary.refused {
        let _ = writeln!(out, "refused: {refusal}");
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use fragr_server::fun_metrics::record::RECORD_SCHEMA;
    use fragr_server::protocol::WeaponType;

    fn record(mode: GameMode, frags: u64, rail: u64) -> FunRecord {
        let mut tally = MatchTally {
            rounds: 1,
            live_ticks: 20 * 60,
            frags,
            spawns: 20,
            spawn_deaths: 1,
            lead_changes: 4,
            ..MatchTally::default()
        };
        *tally.shots.get_mut(WeaponType::Rail) = rail;
        *tally.shots.get_mut(WeaponType::Flechette) = (100 - rail) / 2;
        *tally.shots.get_mut(WeaponType::Scatter) = (100 - rail) / 2;
        *tally.frag_weapons.get_mut(WeaponType::Rail) = frags / 2;
        tally.time_to_kill_ticks.push(20);
        tally.respawn_to_hit_ticks.push(20 * 8);
        FunRecord {
            schema: RECORD_SCHEMA,
            map_id: 1,
            mode,
            mutators: Vec::new(),
            friendly_fire: false,
            bot_tier: BotSkill::Regular,
            finished: true,
            match_ticks: 20 * 60,
            fighters_peak: 6,
            bots_peak: 4,
            tally,
            tick_health: Some(TickHealth {
                ticks: 1200,
                p50_us: 300,
                p99_us: 900,
                max_us: 1200,
                over_budget: 0,
            }),
        }
    }

    #[test]
    fn a_host_s_matches_fold_into_the_survey_s_columns() {
        let records = [
            record(GameMode::Ffa, 12, 30),
            record(GameMode::Ffa, 8, 30),
            record(GameMode::Tdm, 20, 60),
            FunRecord {
                mutators: vec![fragr_server::protocol::Mutator::RailOnly],
                ..record(GameMode::Ffa, 10, 100)
            },
        ];
        let rows = summarise(&records);
        assert_eq!(rows.len(), 3, "a rule twist is its own row");
        assert_eq!(rows[1].row.scenario, "ffa-larak-lot-regular+rail-only");
        let ffa = &rows[0];
        assert_eq!(ffa.row.scenario, "ffa-larak-lot-regular");
        assert_eq!(ffa.row.matches, 2);
        assert_eq!(ffa.row.frags_per_minute, 10.0);
        assert_eq!(ffa.row.lead_changes_per_match, 4.0);
        assert_eq!(ffa.row.time_to_kill_s.median, 1.0);
        assert_eq!(ffa.mean_fighters_peak, 6.0);
        assert_eq!(ffa.worst_tick_p99_ms, 0.9);
        assert!(ffa.targets.is_empty(), "{:?}", ffa.targets);
        let tdm = &rows[2];
        assert_eq!(tdm.row.scenario, "tdm-larak-lot-regular");
        assert_eq!(tdm.top_frag_share, 0.5);
        assert!(
            tdm.targets
                .iter()
                .any(|t| t.contains("Rail fires 60 percent")),
            "{:?}",
            tdm.targets
        );
        let printed = table(&Summary {
            folder: "x".into(),
            matches: 3,
            refused: vec!["bad.json: nope".into()],
            rows,
        });
        assert!(printed
            .contains("| ffa-larak-lot-regular | 2 (2) | 2.0 | 10.0 | 4.0 | Flechette 35% |"));
        assert!(printed.contains("target: tdm-larak-lot-regular: Rail fires 60 percent"));
        assert!(printed.contains("refused: bad.json: nope"));
    }

    #[test]
    fn a_folder_is_read_and_its_strangers_refused() {
        let dir = std::env::temp_dir().join(format!("fragr-fun-summary-{}", std::process::id()));
        let store = fragr_server::fun_metrics::FunStore::open(&dir).unwrap();
        store
            .write(&record(GameMode::Ffa, 10, 20), std::time::SystemTime::now())
            .unwrap();
        std::fs::write(dir.join("match-1999-01-01-0001.json"), "{}").unwrap();
        let summary = summarise_folder(&dir).unwrap();
        assert_eq!(summary.matches, 1);
        assert_eq!(summary.refused.len(), 1);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
