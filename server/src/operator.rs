//! Operator overview for a dedicated server on an interactive terminal.
//!
//! The overview is line output, never a repaint: a ready card once the
//! process answers its own `GET /status`, then one pulse line at the status
//! interval and whenever the room changes. Every number comes from the same
//! `LiveStatus` snapshot `/status` serves, so the terminal and the probe
//! cannot disagree. Escape sequences appear only when the colour gate allows.

use crate::bot_fill::BotPolicy;
use crate::preflight::{JoinReport, JoinScope};
use crate::protocol::{GameMode, HealthReason, LiveStatus};
use std::fmt::Write as _;
use std::time::{Duration, Instant};

/// Change-triggered pulses wait at least this long after the previous line.
pub const PULSE_MIN_GAP: Duration = Duration::from_secs(2);

/// Escape sequences for the card and pulse. Bold labels, green ok, yellow
/// warnings, dim detail: the #415 roles, with no magenta.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Style {
    pub ansi: bool,
}

impl Style {
    fn wrap(self, code: &str, text: &str) -> String {
        if self.ansi {
            format!("\x1b[{code}m{text}\x1b[0m")
        } else {
            text.to_string()
        }
    }
    fn bold(self, text: &str) -> String {
        self.wrap("1", text)
    }
    fn dim(self, text: &str) -> String {
        self.wrap("2", text)
    }
    fn good(self, text: &str) -> String {
        self.wrap("32", text)
    }
    fn warn(self, text: &str) -> String {
        self.wrap("33", text)
    }
}

/// Whether the venue desk reads this terminal.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeskState {
    Off,
    On,
    /// `--console` was given, but this match has no desk (authored or campaign).
    Unavailable,
}

/// Facts fixed at readiness. Counts and health come from each pulse.
#[derive(Debug, Clone)]
pub struct ReadyFacts {
    pub version: String,
    pub map: String,
    pub rules: String,
    pub campaign: bool,
    pub playlist: bool,
    pub map_rotate: bool,
    pub bot_policy: BotPolicy,
    pub bots: usize,
    pub fill_target: usize,
    pub joins: JoinReport,
    pub ticketed: bool,
    pub spectator_tickets: bool,
    pub ban_list: bool,
    pub allow_list: bool,
    pub connection_cap: usize,
    pub address_cap: usize,
    pub desk: DeskState,
    pub status_every_s: u64,
    /// UDP 6768 presence packets are on (any bind that is not loopback).
    pub lan_beacon: bool,
}

/// The ready card printed under the `ready ws://...` line.
pub fn ready_card(facts: &ReadyFacts, style: Style) -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "{} No game window: the match runs in this process, and bots fight whether or not anyone watches.",
        style.bold(&format!("fragr dedicated server {}.", facts.version))
    );
    let row = |out: &mut String, label: &str, text: &str| {
        let _ = writeln!(out, "  {} {text}", style.bold(&format!("{label:<7}")));
    };
    let mut show = format!("{}, {}.", facts.map, facts.rules);
    if facts.playlist {
        show.push_str(" Night playlist: the map and mode change between shows.");
    } else if facts.map_rotate {
        show.push_str(" The map rotates each round.");
    }
    row(&mut out, "Match", &format!("{show} {}", bot_line(facts)));
    write_joins(&mut out, &facts.joins, facts.lan_beacon, style);
    row(&mut out, "Admit", &admit_line(facts));
    row(
        &mut out,
        "Watch",
        "Start fragr, open Multiplayer and join an address above. Watching and joining are optional.",
    );
    row(&mut out, "Desk", desk_line(facts.desk));
    row(
        &mut out,
        "Stop",
        "Ctrl-C, or close this window. Either ends the match for everyone connected.",
    );
    let cadence = if facts.status_every_s > 0 {
        format!(
            "A status line follows every {} s and when the room changes.",
            facts.status_every_s
        )
    } else {
        "A status line follows when the room changes.".to_string()
    };
    row(
        &mut out,
        "Output",
        &format!(
            "Overview. {cadence} Bot frags, pickups and spawns are hidden; --output log prints every event."
        ),
    );
    out
}

fn bot_line(facts: &ReadyFacts) -> String {
    if facts.campaign {
        return "Mission rules: no arcade bots.".to_string();
    }
    match (facts.bot_policy, facts.bots) {
        (BotPolicy::Auto, _) => format!(
            "Bots: automatic fill toward {} fighters; a joining human or agent takes a bot's place.",
            facts.fill_target
        ),
        (BotPolicy::None, _) | (BotPolicy::Fixed, 0) => "Bots: none.".to_string(),
        (BotPolicy::Fixed, 1) => {
            "Bots: 1 fixed rule bot (--bots). People join beside it.".to_string()
        }
        (BotPolicy::Fixed, count) => {
            format!("Bots: {count} fixed rule bots (--bots). People join beside them.")
        }
    }
}

fn write_joins(out: &mut String, joins: &JoinReport, lan_beacon: bool, style: Style) {
    let mut first = true;
    let mut push = |out: &mut String, text: String| {
        let label = if first { "Join" } else { "" };
        first = false;
        let _ = writeln!(out, "  {} {text}", style.bold(&format!("{label:<7}")));
    };
    let width = joins
        .entries
        .iter()
        .map(|entry| entry.addr.to_string().len())
        .max()
        .unwrap_or(0)
        + 5;
    for entry in &joins.entries {
        let url = format!("ws://{}", entry.addr);
        let result = match &entry.answered {
            Ok(()) => style.good("answered here"),
            Err(error) => style.warn(&format!("did not answer here ({error})")),
        };
        push(
            out,
            format!(
                "{:<7} {url:<width$} {result}; {}",
                entry.scope.label(),
                entry.scope.audience()
            ),
        );
    }
    if let Some(error) = &joins.listing_error {
        push(
            out,
            style.warn(&format!("Network addresses could not be listed: {error}.")),
        );
    } else if joins.loopback_bind {
        push(
            out,
            style.dim(
                "Other computers cannot join a loopback bind. Use --bind 0.0.0.0:6767 to invite them.",
            ),
        );
    } else if joins
        .entries
        .iter()
        .all(|entry| entry.scope == JoinScope::ThisComputer)
    {
        push(
            out,
            style.warn("No network address was found besides this computer. Other computers cannot join until one is up."),
        );
    }
    if !joins.skipped.is_empty() {
        push(
            out,
            style.dim(&format!("Not offered: {}.", joins.skipped.join(", "))),
        );
    }
    if lan_beacon {
        push(
            out,
            style.dim("The join page on this network lists this server (UDP 6768 beacon). The beacon is not a join."),
        );
    }
    push(
        out,
        style.dim("A check from this computer does not prove another computer can connect."),
    );
}

fn admit_line(facts: &ReadyFacts) -> String {
    let mut text = if facts.ticketed {
        if facts.spectator_tickets {
            "Tickets required for fighters and watchers (FRAGR_JOIN_SECRET).".to_string()
        } else {
            "Tickets required for fighters (FRAGR_JOIN_SECRET); watchers need none.".to_string()
        }
    } else {
        "Open: no join ticket. Anyone who can reach the port may watch or join.".to_string()
    };
    if facts.ban_list {
        text.push_str(" Ban list on.");
    }
    if facts.allow_list {
        text.push_str(" Allow list on.");
    }
    let _ = write!(
        text,
        " Up to {} connections, {} per address; watchers count, bots do not.",
        facts.connection_cap, facts.address_cap
    );
    text
}

fn desk_line(desk: DeskState) -> &'static str {
    match desk {
        DeskState::On => "On. Type help, status, who, stats, shows, kick, ban, say, next or map. Closing input leaves the match running.",
        DeskState::Off => "Off. Restart with --console to type status, who, kick, ban, say, stats, shows, next and map here.",
        DeskState::Unavailable => "Not available for this match. The venue desk serves a dedicated arcade match.",
    }
}

/// One status line from the served snapshot.
pub fn pulse_line(status: &LiveStatus, uptime: Duration, style: Style) -> String {
    let uptime = status
        .ops
        .as_ref()
        .map(|ops| Duration::from_secs_f64(ops.process.uptime_s.max(0.0)))
        .unwrap_or(uptime);
    let mode = GameMode::ALL
        .into_iter()
        .find(|mode| mode.id() == status.mode)
        .map(GameMode::name)
        .unwrap_or(status.mode.as_str());
    let mut show = if status.kind == "campaign" {
        format!("{}, mission", status.map)
    } else {
        format!("{}, {mode}", status.map)
    };
    for mutator in &status.mutators {
        let _ = write!(show, " + {mutator}");
    }
    let watching = status
        .ops
        .as_ref()
        .map(|ops| ops.connections.spectators.to_string())
        .unwrap_or_else(|| "?".to_string());
    let room = format!(
        "{} {}, {} {}, {} {}, {watching} watching",
        status.humans,
        plural(status.humans, "human", "humans"),
        status.agents,
        plural(status.agents, "agent", "agents"),
        status.bots,
        plural(status.bots, "bot", "bots"),
    );
    let tick = match status.ops.as_ref() {
        Some(ops) if ops.tick.window.count > 0 => format!(
            "tick p99 {:.1} of {:.0} ms, {} over",
            ops.tick.window.p99_ms, ops.tick.budget_ms, ops.tick.window.over_budget
        ),
        _ => "tick warming up".to_string(),
    };
    let health = match status.health.as_ref() {
        Some(health) if health.is_ok() => style.good("ok"),
        Some(health) => {
            let reasons: Vec<&str> = health.reasons.iter().map(|r| reason_words(*r)).collect();
            style.warn(&format!("degraded: {}", reasons.join(", ")))
        }
        None => "starting".to_string(),
    };
    let round = if status.round == 0 {
        "before round 1".to_string()
    } else {
        format!("round {}", status.round)
    };
    format!(
        "{} {} | {show}, {round} | {room} | {tick} | {health}",
        style.dim(&crate::logging::uptime_stamp(uptime)),
        style.bold("running"),
    )
}

fn plural<'a>(count: usize, one: &'a str, many: &'a str) -> &'a str {
    if count == 1 {
        one
    } else {
        many
    }
}

fn reason_words(reason: HealthReason) -> &'static str {
    match reason {
        HealthReason::TickP99OverBudget => "slow ticks over the 50 ms budget",
        HealthReason::TickRateLow => "ticks skipped",
        HealthReason::OutboundDrops => "a slow reader dropped updates",
        HealthReason::Stale => "status not refreshed",
    }
}

/// The desk's `status`: the pulse, the join addresses, then the `who` table.
pub fn desk_status(pulse: &str, joins: &JoinReport, who: &str) -> String {
    let mut out = String::from(pulse);
    for entry in &joins.entries {
        let _ = write!(
            out,
            "\n{} ws://{} ({})",
            entry.scope.label(),
            entry.addr,
            entry.scope.audience()
        );
    }
    if !who.is_empty() {
        out.push('\n');
        out.push_str(who);
    }
    out
}

/// What a pulse line compares. Round changes already log their own line.
#[derive(Debug, Clone, PartialEq, Eq)]
struct PulseKey {
    humans: usize,
    agents: usize,
    bots: usize,
    spectators: Option<usize>,
    map: String,
    mode: String,
    healthy: Option<bool>,
}

impl PulseKey {
    fn of(status: &LiveStatus) -> Self {
        Self {
            humans: status.humans,
            agents: status.agents,
            bots: status.bots,
            spectators: status.ops.as_ref().map(|ops| ops.connections.spectators),
            map: status.map.clone(),
            mode: status.mode.clone(),
            healthy: status.health.as_ref().map(|health| health.is_ok()),
        }
    }
}

/// Decides when a pulse line is due: every interval, and on a room, show or
/// health change, never closer than [`PULSE_MIN_GAP`]. A change inside the
/// gap is printed by the first observation after it.
#[derive(Debug)]
pub struct PulseClock {
    every: Option<Duration>,
    last_print: Option<Instant>,
    last_key: Option<PulseKey>,
}

impl PulseClock {
    pub fn new(every_s: u64) -> Self {
        Self {
            every: (every_s > 0).then(|| Duration::from_secs(every_s)),
            last_print: None,
            last_key: None,
        }
    }

    pub fn due(&mut self, now: Instant, status: &LiveStatus) -> bool {
        let key = PulseKey::of(status);
        let since = self
            .last_print
            .map(|last| now.saturating_duration_since(last));
        let periodic = matches!((self.every, since), (Some(every), Some(since)) if since >= every);
        let changed = self.last_key.as_ref() != Some(&key)
            && since.is_none_or(|since| since >= PULSE_MIN_GAP);
        if periodic || changed {
            self.last_print = Some(now);
            self.last_key = Some(key);
            true
        } else {
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::preflight::JoinEntry;
    use crate::protocol::{
        BuildInfo, Health, NightTotals, OpsStatus, ProcessInfo, RoleCounts, TickSummary,
        TickTiming, TrafficTotals,
    };

    fn joins() -> JoinReport {
        JoinReport {
            entries: vec![
                JoinEntry {
                    addr: "192.168.44.46:6767".parse().unwrap(),
                    scope: JoinScope::Lan,
                    answered: Ok(()),
                },
                JoinEntry {
                    addr: "100.83.110.16:6767".parse().unwrap(),
                    scope: JoinScope::Overlay,
                    answered: Err("timed out".into()),
                },
                JoinEntry {
                    addr: "127.0.0.1:6767".parse().unwrap(),
                    scope: JoinScope::ThisComputer,
                    answered: Ok(()),
                },
            ],
            skipped: vec!["vEthernet (WSL) (172.17.208.1)".into()],
            listing_error: None,
            loopback_bind: false,
        }
    }

    fn facts() -> ReadyFacts {
        ReadyFacts {
            version: "0.90.0".into(),
            map: "Larak Lot".into(),
            rules: "Free-for-all".into(),
            campaign: false,
            playlist: false,
            map_rotate: false,
            bot_policy: BotPolicy::Fixed,
            bots: 4,
            fill_target: 0,
            joins: joins(),
            ticketed: false,
            spectator_tickets: false,
            ban_list: false,
            allow_list: false,
            connection_cap: 64,
            address_cap: 32,
            desk: DeskState::Off,
            status_every_s: 60,
            lan_beacon: true,
        }
    }

    fn ops(spectators: usize, p99: f64, count: u64) -> OpsStatus {
        let summary = TickSummary {
            count,
            p50_ms: 0.1,
            p95_ms: 0.2,
            p99_ms: p99,
            max_ms: p99,
            over_budget: u64::from(p99 >= 50.0),
        };
        OpsStatus {
            version: 1,
            build: BuildInfo {
                crate_version: "0.1.0".into(),
                release: None,
                commit: "unknown".into(),
            },
            process: ProcessInfo {
                started_unix_s: 0,
                uptime_s: 3723.4,
            },
            tick: TickTiming {
                budget_ms: 50.0,
                scope: "tick_handler".into(),
                window_s: 60,
                rate_hz: Some(20.0),
                window: summary.clone(),
                lifetime: summary,
            },
            connections: RoleCounts {
                total: spectators,
                spectators,
                humans: 0,
                agents: 0,
            },
            traffic: TrafficTotals::default(),
            clients: None,
            night: NightTotals::default(),
            rewind: Default::default(),
        }
    }

    fn status() -> LiveStatus {
        LiveStatus {
            humans: 1,
            agents: 0,
            bots: 4,
            fighters: 5,
            round: 3,
            mode: "tdm".into(),
            mutators: vec!["rail-only".into()],
            health: Some(Health::from_reasons(Vec::new())),
            ops: Some(ops(2, 0.84, 1200)),
            ..LiveStatus::default()
        }
    }

    #[test]
    fn ready_card_names_scopes_desk_stop_and_output_without_escapes() {
        let card = ready_card(&facts(), Style { ansi: false });
        assert!(!card.contains('\x1b'), "{card}");
        assert!(card.is_ascii(), "legacy consoles: {card}");
        for needle in [
            "fragr dedicated server 0.90.0.",
            "No game window",
            "Larak Lot, Free-for-all.",
            "Bots: 4 fixed rule bots",
            "LAN     ws://192.168.44.46:6767",
            "answered here; computers on the same network",
            "overlay ws://100.83.110.16:6767",
            "did not answer here (timed out); only computers on that private overlay",
            "local   ws://127.0.0.1:6767",
            "Not offered: vEthernet (WSL)",
            "does not prove another computer can connect",
            "Open: no join ticket",
            "Up to 64 connections, 32 per address",
            "Restart with --console",
            "lists this server (UDP 6768 beacon). The beacon is not a join.",
            "Ctrl-C, or close this window",
            "every 60 s",
            "--output log",
        ] {
            assert!(card.contains(needle), "missing {needle:?} in\n{card}");
        }
        // LAN comes before the overlay, whatever order adapters arrive in.
        assert!(card.find("LAN").unwrap() < card.find("overlay").unwrap());
        for line in card.lines() {
            assert!(!line.contains('\u{2014}') && !line.contains('\u{2013}'));
        }
    }

    #[test]
    fn ready_card_variants_follow_policy_tickets_lists_and_desk() {
        let mut facts = facts();
        facts.bot_policy = BotPolicy::Auto;
        facts.bots = 0;
        facts.fill_target = 8;
        facts.ticketed = true;
        facts.ban_list = true;
        facts.allow_list = true;
        facts.desk = DeskState::On;
        facts.status_every_s = 0;
        facts.playlist = true;
        facts.lan_beacon = false;
        let card = ready_card(&facts, Style { ansi: false });
        assert!(!card.contains("UDP 6768"), "{card}");
        assert!(card.contains("automatic fill toward 8 fighters"), "{card}");
        assert!(card.contains("watchers need none"), "{card}");
        assert!(card.contains("Ban list on. Allow list on."), "{card}");
        assert!(card.contains("On. Type help, status"), "{card}");
        assert!(card.contains("when the room changes."), "{card}");
        assert!(!card.contains("every 0 s"), "{card}");
        assert!(card.contains("Night playlist"), "{card}");

        facts.spectator_tickets = true;
        facts.bot_policy = BotPolicy::None;
        facts.desk = DeskState::Unavailable;
        facts.playlist = false;
        facts.map_rotate = true;
        let card = ready_card(&facts, Style { ansi: false });
        assert!(card.contains("fighters and watchers"), "{card}");
        assert!(card.contains("Bots: none."), "{card}");
        assert!(card.contains("Not available for this match"), "{card}");
        assert!(card.contains("rotates each round"), "{card}");

        facts.bot_policy = BotPolicy::Fixed;
        facts.bots = 1;
        assert!(ready_card(&facts, Style { ansi: false }).contains("1 fixed rule bot "));
        facts.campaign = true;
        assert!(ready_card(&facts, Style { ansi: false }).contains("no arcade bots"));
    }

    #[test]
    fn ready_card_explains_loopback_and_unlisted_networks() {
        let mut facts = facts();
        facts.joins = JoinReport {
            entries: vec![JoinEntry {
                addr: "127.0.0.1:6767".parse().unwrap(),
                scope: JoinScope::ThisComputer,
                answered: Ok(()),
            }],
            skipped: Vec::new(),
            listing_error: None,
            loopback_bind: true,
        };
        let card = ready_card(&facts, Style { ansi: false });
        assert!(
            card.contains("Other computers cannot join a loopback bind"),
            "{card}"
        );

        facts.joins.loopback_bind = false;
        let card = ready_card(&facts, Style { ansi: false });
        assert!(card.contains("No network address was found"), "{card}");

        facts.joins.listing_error = Some("access denied".into());
        let card = ready_card(&facts, Style { ansi: false });
        assert!(
            card.contains("could not be listed: access denied"),
            "{card}"
        );
        assert!(!card.contains("loopback bind"), "{card}");
        assert!(!card.contains("No network address"), "{card}");
    }

    #[test]
    fn colour_uses_the_gate_roles_and_never_magenta() {
        let card = ready_card(&facts(), Style { ansi: true });
        assert!(card.contains("\x1b[1m"), "bold labels");
        assert!(card.contains("\x1b[32manswered here"), "green ok");
        assert!(card.contains("\x1b[33mdid not answer"), "yellow warning");
        assert!(!card.contains("\x1b[35m") && !card.contains("\x1b[95m"));
        let line = pulse_line(&status(), Duration::ZERO, Style { ansi: true });
        assert!(line.contains("\x1b[32mok\x1b[0m"), "{line}");
    }

    #[test]
    fn pulse_reads_the_served_snapshot() {
        let line = pulse_line(&status(), Duration::ZERO, Style { ansi: false });
        assert_eq!(
            line,
            "+01:02:03 running | Larak Lot, Team Deathmatch + rail-only, round 3 | 1 human, 0 agents, 4 bots, 2 watching | tick p99 0.8 of 50 ms, 0 over | ok"
        );

        let mut slow = status();
        slow.ops = Some(ops(0, 61.0, 1200));
        slow.health = Some(Health::from_reasons(vec![
            HealthReason::TickP99OverBudget,
            HealthReason::OutboundDrops,
        ]));
        let line = pulse_line(&slow, Duration::ZERO, Style { ansi: false });
        assert!(line.contains("tick p99 61.0 of 50 ms, 1 over"), "{line}");
        assert!(
            line.contains(
                "degraded: slow ticks over the 50 ms budget, a slow reader dropped updates"
            ),
            "{line}"
        );

        // Before the first refresh there is no ops block or health.
        let fresh = LiveStatus {
            round: 0,
            ..LiveStatus::default()
        };
        let line = pulse_line(&fresh, Duration::from_secs(5), Style { ansi: false });
        assert!(line.starts_with("+00:00:05 running"), "{line}");
        assert!(
            line.contains("Larak Lot, Free-for-all, before round 1"),
            "{line}"
        );
        assert!(line.contains("? watching"), "{line}");
        assert!(line.contains("tick warming up"), "{line}");
        assert!(line.ends_with("starting"), "{line}");

        let mut mission = LiveStatus {
            kind: "campaign".into(),
            map: "Recall Notice".into(),
            mode: "unknown-mode".into(),
            ..LiveStatus::default()
        };
        mission.health = Some(Health::from_reasons(vec![
            HealthReason::TickRateLow,
            HealthReason::Stale,
        ]));
        let line = pulse_line(&mission, Duration::ZERO, Style { ansi: false });
        assert!(line.contains("Recall Notice, mission"), "{line}");
        assert!(
            line.contains("ticks skipped, status not refreshed"),
            "{line}"
        );
    }

    #[test]
    fn pulse_clock_prints_on_interval_and_on_change_but_not_in_a_burst() {
        let start = Instant::now();
        let mut clock = PulseClock::new(60);
        let quiet = status();
        assert!(clock.due(start, &quiet), "first observation prints");
        assert!(!clock.due(start + Duration::from_secs(1), &quiet));
        assert!(!clock.due(start + Duration::from_secs(59), &quiet));
        assert!(
            clock.due(start + Duration::from_secs(60), &quiet),
            "interval"
        );

        let mut joined = quiet.clone();
        joined.humans = 2;
        // Inside the gap the change waits, then prints once.
        assert!(!clock.due(start + Duration::from_secs(61), &joined));
        assert!(clock.due(start + Duration::from_secs(62), &joined));
        assert!(!clock.due(start + Duration::from_secs(63), &joined));

        // A round change alone is not a room change.
        let mut next_round = joined.clone();
        next_round.round += 1;
        assert!(!clock.due(start + Duration::from_secs(70), &next_round));

        let mut degraded = next_round.clone();
        degraded.health = Some(Health::from_reasons(vec![HealthReason::Stale]));
        assert!(clock.due(start + Duration::from_secs(71), &degraded));

        let mut off = PulseClock::new(0);
        assert!(off.due(start, &quiet));
        assert!(
            !off.due(start + Duration::from_secs(3600), &quiet),
            "0 disables periodic"
        );
        let mut watched = quiet.clone();
        watched.ops = Some(ops(5, 0.8, 1200));
        assert!(
            off.due(start + Duration::from_secs(3601), &watched),
            "a new watcher"
        );
    }

    #[test]
    fn desk_status_is_pulse_addresses_then_who() {
        let text = desk_status("PULSE", &joins(), "Room\nAda human 3");
        let lines: Vec<&str> = text.lines().collect();
        assert_eq!(lines[0], "PULSE");
        assert_eq!(
            lines[1],
            "LAN ws://192.168.44.46:6767 (computers on the same network)"
        );
        assert!(lines[2].starts_with("overlay ws://100.83.110.16:6767"));
        assert!(lines[3].starts_with("local ws://127.0.0.1:6767"));
        assert_eq!(&lines[4..], ["Room", "Ada human 3"]);
        assert_eq!(desk_status("P", &JoinReport::default(), ""), "P");
    }
}
