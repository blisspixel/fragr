//! A host's fun metrics, read back as the tables the bot survey and the 1.0
//! bar use. Records are folded by mode, map and bot tier with the same
//! `MatchTally::add` and the same [`shared_row`] the bot survey
//! (`fragr-playtest --bot-survey`) uses, so a host's frag a minute is the
//! survey's frag a minute. One implementation serves both readers:
//! `fragr-server --fun-summary` on a release package and
//! `fragr-playtest --fun-summary` in a checkout. Reading only: the summary
//! never writes into the host's folder.
use super::{per_minute, share, spread, FunRecord, MatchTally, Spread, TickHealth, WeaponTable};
use crate::protocol::{GameMode, WeaponType};
use crate::sim::{BotSkill, MapKind};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::Path;

/// Where a fighter stood still or stood inside geometry, for a hunt.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Spot {
    pub seed: u64,
    pub tick: u64,
    pub fighter: String,
    /// Feet position.
    pub at: [f32; 3],
    pub seconds: f64,
    pub in_vehicle: bool,
    /// The fighter was asking to move: a wedge, not a hold.
    pub pushing: bool,
}

/// Folded facts for one scenario across its seeds.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct ScenarioReport {
    pub scenario: String,
    pub matches: u32,
    pub live_seconds: f64,
    pub frags: u64,
    pub frags_per_minute: f64,
    pub spawns: u64,
    pub spawn_deaths: u64,
    /// Deaths inside three seconds of the victim's own spawn, per spawn.
    pub spawn_deaths_per_spawn: f64,
    pub hits: u64,
    /// Hits on a body while two or more other shooters also hit it inside one
    /// second: three guns on one target at once.
    pub volley_hits: u64,
    pub volley_hit_share: f64,
    /// Frags whose victim took hits from three or more shooters in its last second.
    pub focus_frags: u64,
    /// Hits landed on a target outside the shooter's 120 degree view.
    pub hits_outside_view: u64,
    pub hits_outside_view_share: f64,
    /// Frags whose killer opened the fight from outside the victim's view:
    /// flanks and ambushes that worked.
    pub blindside_frags: u64,
    pub blindside_share: f64,
    pub pickups: u64,
    pub pickups_per_minute: f64,
    /// Returns of a weapon or armour pad during live play.
    pub power_returns: u64,
    /// Power claims inside one second of the pad's return.
    pub appointments: u64,
    pub appointment_share: f64,
    /// Mean seconds a returned power pad sat untouched before a claim.
    pub mean_power_wait_s: f64,
    /// Frags within 8 m of a power pad inside 5 s of its return, per frag.
    pub pad_contest_index: f64,
    /// Resolved shots by weapon, as a share of all shots; rockets launched
    /// count as Rocket shots.
    pub shot_share: BTreeMap<String, f64>,
    /// Share of living fighter ticks each gun was in hand, and share of them
    /// it was owned with rounds: what a body carries against what it fires,
    /// so a gun share reads as supply or as choice.
    pub hand_share: BTreeMap<String, f64>,
    pub owned_share: BTreeMap<String, f64>,
    /// Frags by the weapon that landed them.
    pub frag_weapons: BTreeMap<String, u64>,
    /// Damaging traced hits by the zone they struck (`ShotResult.zone`).
    #[serde(default)]
    pub zone_hits: BTreeMap<String, u64>,
    /// Killing shots by the zone they struck.
    #[serde(default)]
    pub kill_zones: BTreeMap<String, u64>,
    /// Head kills as a share of kills that named a zone (hitscan kills).
    #[serde(default)]
    pub head_kill_share: f64,
    /// Killing shots by the gun and the zone they struck. A Scatter blast
    /// reports its most telling pellet, so one pellet in the head makes the
    /// whole blast a head kill; the single-ray guns read aim.
    #[serde(default)]
    pub weapon_kill_zones: BTreeMap<String, BTreeMap<String, u64>>,
    /// Head kills as a share of zoned kills by single-ray guns (every zoned
    /// gun but the Scatter): the share the 1.0 bar's 15 to 35 percent reads.
    #[serde(default)]
    pub single_ray_head_kill_share: f64,
    /// Captures in CTF; Conquest sites changing hands.
    pub objective_events: u64,
    /// Claims of the power armour (the Custody Plate), per three live minutes.
    pub plate_claims: u64,
    pub plate_claims_per_3min: f64,
    /// Claims of a Rocket pad.
    pub rocket_claims: u64,
    /// Frags landed by the Rocket, as a share of all frags.
    pub rocket_frag_share: f64,
    /// Fighters killed by their own blast.
    pub self_deaths: u64,
    /// Rockets fired, and those that hurt somebody.
    pub rocket_launches: u64,
    pub rocket_damaging: u64,
    /// Guns dropped on death, and how many were taken before they went.
    pub guns_dropped: u64,
    pub drop_claims: u64,
    /// Dropped Rockets taken.
    pub rocket_drop_claims: u64,
    /// Rocket lives: from the moment a fighter holds a launcher with rounds
    /// until it dies or fires the last one.
    pub rocket_lives: u64,
    /// Mean seconds a Rocket life lasts.
    pub rocket_life_seconds: f64,
    /// Share of Rocket lives that ended in the holder's death, not a dry rack.
    pub rocket_lives_died: f64,
    /// Share of a Rocket life the launcher was the gun in hand.
    pub rocket_in_hand_share: f64,
    /// Rule bots' objective callouts said to a side, per live minute.
    pub side_calls_per_minute: f64,
    /// Times the sole leader changed hands (fighter in free-for-all and Duel,
    /// side in team deathmatch and CTF), per match. The first lead is not a change.
    pub lead_changes: u64,
    pub lead_changes_per_match: f64,
    /// Over-five-second stalls by the roster's rule, and the longest one.
    pub stalls: u64,
    /// Stalls where the fighter kept asking to move: wedged on geometry.
    pub pushing_stalls: u64,
    pub longest_stall_seconds: f64,
    pub stall_spots: Vec<Spot>,
    /// Living fighter ticks with the body inside a map solid, or outside the
    /// playable square; either is a collision bug, never play.
    pub in_solid_ticks: u64,
    pub in_solid_spots: Vec<Spot>,
    pub out_of_bounds_ticks: u64,
    /// The lowest feet height a living fighter reached.
    pub lowest_feet: f32,
    /// Authored pads nobody claimed in any surveyed match: a route failure or
    /// a pad nobody wants.
    pub unclaimed_pads: Vec<String>,
    /// Fighter seconds spent in a vehicle seat (Holdfast's jeeps, boats and
    /// aircraft).
    pub vehicle_seconds: f64,
    /// Seconds from a spawn to first contact: the fighter sees an opponent
    /// or is seen by one (120 degree cone, 64 m, clear sight), or a shot
    /// lands either way.
    pub respawn_to_contact_s: Spread,
    /// Seconds from a spawn to the first shot that lands either way: the
    /// fight joined, not only seen.
    pub respawn_to_hit_s: Spread,
    /// Metres between killer and victim when the frag landed, by weapon.
    pub kill_distance_m: BTreeMap<String, Spread>,
    /// Seconds from the first damage a victim took from somebody else in
    /// that life to the frag: the kill time the 1.0 bar reads.
    pub time_to_kill_s: Spread,
    /// Sabotage rounds decided, and the attack's share of them.
    pub sabotage_rounds: u32,
    pub sabotage_attack_share: f64,
    /// Two second windows walked three metres or more with nobody in view,
    /// and the share that went back and forth (`sight::DitherTracker`).
    pub moving_windows: u64,
    pub dither_share: f64,
}

/// The wave 19 fun targets for every map in rotation.
pub const MAP_FRAGS_PER_MINUTE: f64 = 10.0;
pub const MAP_LEAD_CHANGES: f64 = 3.0;
pub const MAP_TOP_GUN_SHARE: f64 = 0.45;
/// A Duel finds its fight on every map (#517): one frag a minute between two.
pub const MAP_DUEL_FRAGS_PER_MINUTE: f64 = 1.0;
/// Median seconds from a spawn to the first landed shot either way in the
/// deathmatch modes (`docs/plans/fun-craft-targets.md`, contact).
pub const MAP_CONTACT_SECONDS: (f64, f64) = (6.0, 15.0);
/// Moving windows that dither, at most (`sight::DitherTracker`).
pub const MAP_DITHER_SHARE: f64 = 0.05;

impl ScenarioReport {
    /// The gun that fired the most shots and its share.
    pub fn top_gun(&self) -> (String, f64) {
        self.shot_share
            .iter()
            .fold((String::new(), 0.0), |best, (gun, share)| {
                if *share > best.1 {
                    (gun.clone(), *share)
                } else {
                    best
                }
            })
    }
}

/// The columns a host's fun metrics and the survey share, read from one
/// folded match tally: frag pace, spawns, pads, gun shares, lead changes,
/// kill distances, kill time and contact. Survey-only columns stay at zero;
/// `fold` fills them for a survey row.
pub fn shared_row(label: String, matches: u32, shared: &MatchTally) -> ScenarioReport {
    let live = shared.live_ticks;
    let shots = shared.total_shots();
    let tick = 1.0 / super::TICKS_PER_SECOND;
    let named = |table: &WeaponTable<u64>| -> BTreeMap<String, u64> {
        table
            .iter()
            .filter(|(_, count)| **count > 0)
            .map(|(weapon, count)| (weapon.name().to_string(), *count))
            .collect()
    };
    let zones = |tally: &super::ZoneTally| -> BTreeMap<String, u64> {
        [
            ("head", tally.head),
            ("torso", tally.torso),
            ("legs", tally.legs),
            ("plate", tally.plate),
            ("weak", tally.weak),
        ]
        .into_iter()
        .filter(|(_, count)| *count > 0)
        .map(|(zone, count)| (zone.to_string(), count))
        .collect()
    };
    let sabotage = &shared.sabotage;
    ScenarioReport {
        scenario: label,
        matches,
        live_seconds: live as f64 * tick,
        frags: shared.frags,
        frags_per_minute: per_minute(shared.frags, live),
        spawns: shared.spawns,
        spawn_deaths: shared.spawn_deaths,
        spawn_deaths_per_spawn: share(shared.spawn_deaths, shared.spawns),
        hits: shared.hits,
        pickups: shared.pickups,
        pickups_per_minute: per_minute(shared.pickups, live),
        power_returns: shared.power_returns,
        appointments: shared.appointments,
        appointment_share: share(shared.appointments, shared.power_returns),
        mean_power_wait_s: if shared.power_claims == 0 {
            0.0
        } else {
            shared.power_wait_ticks as f64 / shared.power_claims as f64 * tick
        },
        pad_contest_index: share(shared.contested_frags, shared.frags),
        shot_share: named(&shared.shots)
            .into_iter()
            .map(|(weapon, count)| (weapon, share(count, shots)))
            .collect(),
        frag_weapons: named(&shared.frag_weapons),
        zone_hits: zones(&shared.zone_hits),
        kill_zones: zones(&shared.kill_zones),
        head_kill_share: share(shared.kill_zones.head, shared.kill_zones.total()),
        objective_events: shared.captures
            + u64::from(
                shared.conquest.union_sites_at_end + shared.conquest.coalition_sites_at_end,
            ),
        plate_claims: shared.plate_claims,
        plate_claims_per_3min: per_minute(shared.plate_claims, live) * 3.0,
        rocket_claims: shared.rocket_claims,
        rocket_frag_share: share(*shared.frag_weapons.get(WeaponType::Rocket), shared.frags),
        self_deaths: shared.self_deaths,
        drop_claims: shared.drop_claims,
        lead_changes: shared.lead_changes,
        lead_changes_per_match: if matches == 0 {
            0.0
        } else {
            shared.lead_changes as f64 / f64::from(matches)
        },
        respawn_to_contact_s: spread(&shared.respawn_to_contact_ticks.scaled(tick)),
        respawn_to_hit_s: spread(&shared.respawn_to_hit_ticks.scaled(tick)),
        time_to_kill_s: spread(&shared.time_to_kill_ticks.scaled(tick)),
        kill_distance_m: shared
            .kill_distance_cm
            .iter()
            .filter(|(_, samples)| !samples.is_empty())
            .map(|(weapon, samples)| (weapon.name().to_string(), spread(&samples.scaled(0.01))))
            .collect(),
        sabotage_rounds: sabotage.rounds,
        sabotage_attack_share: share(u64::from(sabotage.attack_wins), u64::from(sabotage.rounds)),
        ..ScenarioReport::default()
    }
}

/// Rows that miss the wave 19 fun targets. Frag pace is read on the
/// deathmatch modes in rotation, and on Duel against its own lower floor (two
/// seats trade far fewer frags by nature), lead changes on free-for-all, gun
/// share everywhere.
pub fn check_map_targets(row: &ScenarioReport, mode: GameMode) -> Vec<String> {
    let mut misses = Vec::new();
    if matches!(mode, GameMode::Ffa | GameMode::Tdm) && row.frags_per_minute < MAP_FRAGS_PER_MINUTE
    {
        misses.push(format!(
            "{}: {:.1} frags/min, want {MAP_FRAGS_PER_MINUTE} or more",
            row.scenario, row.frags_per_minute
        ));
    }
    if mode == GameMode::Duel && row.frags_per_minute < MAP_DUEL_FRAGS_PER_MINUTE {
        misses.push(format!(
            "{}: {:.1} Duel frags/min, want {MAP_DUEL_FRAGS_PER_MINUTE} or more",
            row.scenario, row.frags_per_minute
        ));
    }
    if mode == GameMode::Ffa && row.lead_changes_per_match < MAP_LEAD_CHANGES {
        misses.push(format!(
            "{}: {:.1} lead changes per match, want {MAP_LEAD_CHANGES} or more",
            row.scenario, row.lead_changes_per_match
        ));
    }
    // Contact as the targets mean it: the fight joined, the first shot that
    // lands either way. Sight alone comes within a second on a small floor.
    let contact = row.respawn_to_hit_s.median;
    if matches!(mode, GameMode::Ffa | GameMode::Tdm)
        && row.respawn_to_hit_s.count > 0
        && !(MAP_CONTACT_SECONDS.0..=MAP_CONTACT_SECONDS.1).contains(&contact)
    {
        misses.push(format!(
            "{}: {contact:.1} s median from spawn to the first landed shot, want {:.0} to {:.0}",
            row.scenario, MAP_CONTACT_SECONDS.0, MAP_CONTACT_SECONDS.1
        ));
    }
    if row.dither_share >= MAP_DITHER_SHARE {
        misses.push(format!(
            "{}: dithers in {:.1} percent of moving windows, want under {:.0}",
            row.scenario,
            row.dither_share * 100.0,
            MAP_DITHER_SHARE * 100.0
        ));
    }
    let (gun, share) = row.top_gun();
    if share >= MAP_TOP_GUN_SHARE {
        misses.push(format!(
            "{}: {gun} fires {:.0} percent of shots, want under {:.0}",
            row.scenario,
            share * 100.0,
            MAP_TOP_GUN_SHARE * 100.0
        ));
    }
    misses
}

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

/// What `fragr-server --fun-summary` prints: the summary table of `folder`,
/// or of the host's own folder under its run directory (`FRAGR_RUN_DIR`, or
/// the platform's user data folder) when none is named. A folder that is not
/// there is an error that says how to make one, never an empty table.
pub fn host_report(folder: Option<&Path>) -> std::io::Result<String> {
    let folder = match folder {
        Some(folder) => folder.to_path_buf(),
        None => super::FunStore::host_dir()?,
    };
    if !folder.is_dir() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            format!(
                "no fun metrics folder at {}; a server started with --fun-metrics files its matches there",
                folder.display()
            ),
        ));
    }
    Ok(table(&summarise_folder(&folder)?))
}

/// Read a host's folder and fold it.
pub fn summarise_folder(folder: &Path) -> std::io::Result<Summary> {
    let (records, refused) = super::FunStore::read_all(folder)?;
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
    use crate::fun_metrics::record::RECORD_SCHEMA;

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
                mutators: vec![crate::protocol::Mutator::RailOnly],
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
        let store = crate::fun_metrics::FunStore::open(&dir).unwrap();
        store
            .write(&record(GameMode::Ffa, 10, 20), std::time::SystemTime::now())
            .unwrap();
        std::fs::write(dir.join("match-1999-01-01-0001.json"), "{}").unwrap();
        let summary = summarise_folder(&dir).unwrap();
        assert_eq!(summary.matches, 1);
        assert_eq!(summary.refused.len(), 1);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_host_s_report_names_a_missing_folder_and_reads_a_real_one() {
        let dir = std::env::temp_dir().join(format!("fragr-fun-report-{}", std::process::id()));
        let missing = host_report(Some(&dir)).expect_err("no folder, no table");
        assert_eq!(missing.kind(), std::io::ErrorKind::NotFound);
        assert!(missing.to_string().contains("--fun-metrics"), "{missing}");
        assert!(!dir.exists(), "a reader never makes the folder");
        let store = crate::fun_metrics::FunStore::open(&dir).unwrap();
        store
            .write(&record(GameMode::Tdm, 12, 20), std::time::SystemTime::now())
            .unwrap();
        let printed = host_report(Some(&dir)).unwrap();
        assert!(
            printed.starts_with("fun metrics: 1 matches in "),
            "{printed}"
        );
        assert!(
            printed.contains("| tdm-larak-lot-regular | 1 (1) |"),
            "{printed}"
        );
        std::fs::remove_dir_all(dir).unwrap();
    }
}
