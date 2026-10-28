//! An earned M01 departure carried through the durable run file into a
//! bounded M02 window, played by the same constrained policy as the Recall
//! Notice survey. Every save, promotion and reopen goes through the server's
//! own `DurableRun`; every Continue goes through the session command path.
//! A death ends the session; its pending Continue is reopened from disk in a
//! fresh session before it is spent. This is earned-run evidence for one short
//! window, never an M02 clear or campaign claim.
use super::*;
use fragr_server::local::{preview_run_in, RunPreview};
use fragr_server::net::GameCommand;
use fragr_server::protocol::{AmmoCount, WeaponType};
use fragr_server::run::DurableRun;
use fragr_server::session::Recipient;
use std::path::{Path, PathBuf};

/// Active M02 play after entry, summed across reopened attempts.
pub const M02_WINDOW_TICKS: u64 = 60 * 20;

pub const OBSERVATION: &str = concat!(
    "M01 leg: ",
    recall_notice_observation!(),
    " The M01 leg is written through the server's durable run file after every step. M02 is entered only by reopening that file: the saved departure is promoted and loaded by the same DurableRun code as the local child. Both legs are guided by public objectives and navigation geometry through the shared MissionClient; M02 adds no harness-specific route hints, grants or completion targets. The same constrained perception, turning, aim, reload and supply policy plays a bounded 60-second M02 window of active time. Harness sessions number entities deterministically for reproducible reports, where the local child draws random entity ids, and admit the participant directly rather than through a wire join; the simulation seed is applied after the run file opens, as in the local child. A death ends the session. Its pending Continue is reopened from disk in a fresh session. Every session opens with the trial seed, as the local child opens every process with its one seed; the game itself runs each retry on a stream derived from that seed, the run id and the attempt, recorded in each segment. A request dropped before delivery must leave the saved file unchanged; stale mission/run/attempt requests and a duplicate after acceptance are sent through the ordinary session command path and must be refused. Only the accepted request may spend a continue. Restoration is compared with the M02 entry kit live and again from a copy of the saved file. Immediate Continue with no menu delay; no M02 clear, campaign, human-population or rendered-readability claim."
);

/// HP, armor and the ordinary authoritative loadout, without its clock.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Kit {
    pub hp: i32,
    pub armor: i32,
    pub loadout: LoadoutState,
}

impl Kit {
    fn of(session: &GameSession, id: Uuid) -> Result<Self, String> {
        let player = session
            .state
            .players
            .iter()
            .find(|p| p.id == id)
            .ok_or("participant missing")?;
        let mut loadout = player
            .inventory
            .state(id, player.weapon, session.state.tick)
            .ok_or("loadout missing")?;
        loadout.tick = 0;
        Ok(Self {
            hp: player.hp,
            armor: player.armor,
            loadout,
        })
    }

    /// What a saved exit carries: everything but personal pickup claims and
    /// the per-gun magazine split, which a joining human re-arms.
    fn carried(&self) -> (i32, i32, WeaponType, &[WeaponType], &[AmmoCount], [u16; 3]) {
        let l = &self.loadout;
        (
            self.hp,
            self.armor,
            l.selected,
            &l.weapons,
            &l.ammo,
            [l.grenades, l.proximity_mines, l.remote_mines],
        )
    }
}

/// The seed of the stream M02 `attempt` runs on. Every session opens with the
/// trial seed, as the local child does; the first attempt runs on it and the
/// game starts each retry on its own stream (`retry_seed`), so a reopened
/// death is a new fight rather than a replay. The policy's aim phase keeps
/// the trial seed.
pub fn attempt_seed(seed: u64, run_id: Uuid, attempt: u32) -> u64 {
    if attempt <= 1 {
        seed
    } else {
        fragr_server::mission::retry_seed(seed, run_id, attempt)
    }
}

/// One session of M02 play, ended by death, exhaustion, a clear or the window.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Segment {
    pub attempt: u32,
    /// The seed of the simulation stream this attempt ran on.
    pub sim_seed: u64,
    pub outcome: String,
    pub ticks: u64,
    pub shots: u32,
    pub hits: u32,
    pub kills: u32,
    pub reloads: u32,
    /// Feet at the end of the segment; the death position when pending.
    pub end_feet: [f32; 3],
    pub ammo_start: Vec<AmmoCount>,
    pub ammo_end: Vec<AmmoCount>,
}

/// Receipts for one pending Continue reopened from disk.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Retry {
    pub attempt: u32,
    pub continues_before: u8,
    pub continues_after: u8,
    /// Saved menu preview of the pending death, before any request.
    pub pending: serde_json::Value,
    /// A request lost before delivery (a failed client enqueue) never reaches
    /// the server; true when the saved pending Continue was left unchanged.
    pub dropped_unchanged: bool,
    /// Requests the server refused, each leaving the saved file unchanged.
    pub rejected: Vec<String>,
    /// Saved menu preview after the accepted request and its duplicate.
    pub resumed: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Metrics {
    /// The constrained M01 trial that earned, or failed to earn, the exit.
    pub m01: Trial,
    pub m01_exit: Option<Kit>,
    pub m02_entry: Option<Kit>,
    pub window_ticks: u64,
    pub segments: Vec<Segment>,
    pub retries: Vec<Retry>,
}

pub fn accepts(trial: &Trial) -> bool {
    trial.carry.as_ref().is_some_and(|carry| {
        carry.m01.outcome == "departed" && carry.m02_entry.is_some() && !carry.segments.is_empty()
    })
}

/// Removes its scratch run directory however the trial ends.
struct Scratch(PathBuf);

impl Scratch {
    fn new(label: &str) -> Result<Self, String> {
        let path = std::env::temp_dir().join(format!("fragr-carry-{label}-{}", Uuid::new_v4()));
        std::fs::create_dir_all(&path).map_err(|e| e.to_string())?;
        Ok(Self(path))
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn preview(directory: &Path) -> Result<serde_json::Value, String> {
    let shown: RunPreview = preview_run_in(directory).map_err(|e| e.to_string())?;
    serde_json::to_value(shown).map_err(|e| e.to_string())
}

fn open(
    mission: MissionId,
    directory: &Path,
    resume: bool,
    seed: u64,
    difficulty: CampaignDifficulty,
) -> Result<(GameSession, DurableRun), String> {
    let mut session = GameSession::with_authored_map(
        AuthoredSource::Mission(mission)
            .load()
            .map_err(|e| e.to_string())?,
    );
    session.state.use_replay_ids();
    let run = DurableRun::open(&mut session, directory, resume, Some(difficulty))
        .map_err(|e| e.to_string())?;
    // The local child seeds after its run file opens.
    session.state.seed(seed);
    Ok((session, run))
}

fn persist(run: &mut DurableRun) -> impl FnMut(&GameSession) -> Result<(), String> + '_ {
    |session| run.persist(&session.state).map_err(|e| e.to_string())
}

fn run_state(
    session: &GameSession,
) -> Result<(u32, fragr_server::protocol::CampaignRunState), String> {
    let state = session.state.mission_state().ok_or("mission vanished")?;
    Ok((state.attempt, state.run.ok_or("campaign run missing")?))
}

/// Send one Continue through the session command path; true if refused.
fn send_continue(session: &mut GameSession, id: Uuid, request: MissionContinue) -> bool {
    session.apply_command(GameCommand::MissionContinue {
        player_id: id,
        request,
    });
    session.take_unicasts().iter().any(|(to, message)| {
        *to == Recipient::Player(id)
            && matches!(message, ServerMessage::Error { code, .. } if code == "continue_rejected")
    })
}

/// Reopen the saved pending Continue in a fresh session, refuse every
/// request that must not spend a continue, then spend exactly one.
fn reopen_pending(
    directory: &Path,
    seed: u64,
    difficulty: CampaignDifficulty,
    entry: &Kit,
) -> Result<(GameSession, DurableRun, Uuid, Retry), String> {
    let pending = preview(directory)?;
    if pending["status"] != "ready" || pending["pending_continue"] != true {
        return Err(format!("saved death is not a pending Continue: {pending}"));
    }
    let (mut session, mut run) =
        open(MissionId::PersonsUnknown, directory, true, seed, difficulty)?;
    let id = Uuid::from_u128(479);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    session.state.arm_joined_magazines(id);
    run.persist(&session.state).map_err(|e| e.to_string())?;
    if session.state.players.iter().any(|p| p.id == id && p.hp > 0) {
        return Err("a reopened pending Continue admitted a living body".into());
    }
    let (attempt, before) = run_state(&session)?;
    if before.status != CampaignRunStatus::Continue
        || pending["attempt"] != attempt
        || pending["continues"] != before.continues
    {
        return Err(format!("reopened run disagrees with its file: {pending}"));
    }
    let request = MissionContinue {
        id: MissionId::PersonsUnknown,
        run_id: before.id,
        attempt,
    };
    let unchanged = |session: &GameSession, run: &mut DurableRun, label: &str| {
        run.persist(&session.state).map_err(|e| e.to_string())?;
        let (now, state) = run_state(session)?;
        if preview(directory)? != pending
            || now != attempt
            || state.continues != before.continues
            || state.status != CampaignRunStatus::Continue
        {
            return Err(format!("{label} changed the pending Continue"));
        }
        Ok(())
    };
    // A request lost before delivery (a failed client enqueue) never reaches
    // the session. The pending attempt must remain available unchanged.
    unchanged(&session, &mut run, "a dropped request")?;
    let mut rejected = Vec::new();
    let mut stale = vec![
        (
            "stale_mission",
            MissionContinue {
                id: MissionId::RecallNotice,
                ..request
            },
        ),
        (
            "stale_run",
            MissionContinue {
                run_id: Uuid::from_u128(0x5a1e),
                ..request
            },
        ),
        (
            "future_attempt",
            MissionContinue {
                attempt: attempt + 1,
                ..request
            },
        ),
    ];
    if attempt > 1 {
        stale.push((
            "previous_attempt",
            MissionContinue {
                attempt: attempt - 1,
                ..request
            },
        ));
    }
    for (label, stale) in stale {
        if !send_continue(&mut session, id, stale) {
            return Err(format!("{label} Continue was accepted"));
        }
        unchanged(&session, &mut run, label)?;
        rejected.push(label.to_owned());
    }
    if send_continue(&mut session, id, request) {
        return Err("the current pending Continue was refused".into());
    }
    if !send_continue(&mut session, id, request) {
        return Err("a duplicate Continue was accepted".into());
    }
    rejected.push("duplicate_after_accept".to_owned());
    run.persist(&session.state).map_err(|e| e.to_string())?;
    let (resumed_attempt, after) = run_state(&session)?;
    let resumed = preview(directory)?;
    if after.status != CampaignRunStatus::Playing
        || after.continues + 1 != before.continues
        || resumed_attempt != attempt + 1
        || resumed["attempt"] != attempt + 1
        || resumed["continues"] != after.continues
        || resumed["pending_continue"] != false
    {
        return Err(format!("Continue did not spend exactly one: {resumed}"));
    }
    if &Kit::of(&session, id)? != entry {
        return Err("Continue did not restore the M02 entry kit".into());
    }
    session.apply_command(GameCommand::MissionReady {
        player_id: id,
        ready: MissionReady {
            id: MissionId::PersonsUnknown,
            attempt: resumed_attempt,
        },
    });
    // The same restoration must survive a reopen of the saved entry. Probe
    // a copy so the live writer lock is never shared or released.
    let probe = Scratch::new("probe")?;
    std::fs::copy(directory.join("run.json"), probe.0.join("run.json"))
        .map_err(|e| e.to_string())?;
    let (mut reopened, _probe_run) =
        open(MissionId::PersonsUnknown, &probe.0, true, seed, difficulty)?;
    admit(&mut reopened, MissionId::PersonsUnknown, resumed_attempt);
    if &Kit::of(&reopened, id)? != entry {
        return Err("the saved entry did not restore the M02 entry kit".into());
    }
    Ok((
        session,
        run,
        id,
        Retry {
            attempt,
            continues_before: before.continues,
            continues_after: after.continues,
            pending,
            dropped_unchanged: true,
            rejected,
            resumed,
        },
    ))
}

/// Collected scene windows: the first M02 fatal hit and the first M02 kill.
#[derive(Default)]
pub(super) struct Reviews {
    pub fatal: Option<serde_json::Value>,
    pub first_kill: Option<serde_json::Value>,
}

impl Reviews {
    fn recording(&self) -> Recording {
        if self.fatal.is_none() {
            Recording::Fatal
        } else if self.first_kill.is_none() {
            Recording::FirstKill
        } else {
            Recording::None
        }
    }
}

fn absorb(total: &mut Trial, part: &Trial) {
    total.deaths += part.deaths;
    total.continues_spent += part.continues_spent;
    if total.first_contact_seconds.is_none() {
        total.first_contact_seconds = part.first_contact_seconds.map(|s| s + total.seconds);
        total.first_contact_distance = part.first_contact_distance;
    }
    total.seconds += part.seconds;
    total.shots += part.shots;
    total.hits += part.hits;
    total.kills += part.kills;
    total.damage_received += part.damage_received;
    total.resolved_damage_outside_view += part.resolved_damage_outside_view;
    for hit in &part.hits_received {
        if total.hits_received.len() < 256 {
            total.hits_received.push(hit.clone());
        } else {
            total.hits_omitted += 1;
        }
    }
    total.hits_omitted += part.hits_omitted;
    total.reloads += part.reloads;
    total.longest_no_progress_seconds = total
        .longest_no_progress_seconds
        .max(part.longest_no_progress_seconds);
    total.last_phase = part.last_phase;
    total.last_feet = part.last_feet;
    total.hp = part.hp;
    total.bullets = part.bullets;
    total.weapons = part.weapons.clone();
    total.final_attempt = part.final_attempt;
}

/// One earned carry: the constrained M01 trial, its saved departure and a
/// bounded M02 window played across reopened Continues.
pub(super) fn trial(
    seed: u64,
    profile: Profile,
    difficulty: CampaignDifficulty,
    m01_ticks: u64,
    window_ticks: u64,
    reviews: &mut Reviews,
) -> Result<Trial, String> {
    validate_trial(profile, m01_ticks)?;
    validate_trial(profile, window_ticks)?;
    let directory = Scratch::new("run")?;
    let leg = |scenario, max_ticks, recording, stop_at_pending| Leg {
        scenario,
        seed,
        profile,
        difficulty,
        max_ticks,
        recording,
        stop_at_pending,
    };
    let (m01, exit) = {
        let (mut session, mut run) = open(
            MissionId::RecallNotice,
            &directory.0,
            false,
            seed,
            difficulty,
        )?;
        let id = admit(&mut session, MissionId::RecallNotice, 1);
        let (m01, _, _) = drive(
            &mut session,
            id,
            leg(Scenario::RecallNotice, m01_ticks, Recording::None, false),
            |action| action,
            persist(&mut run),
        )?;
        let exit = Kit::of(&session, id)?;
        (m01, exit)
    };
    let mut row = Trial {
        outcome: format!("m01_{}", m01.outcome),
        deaths: 0,
        continues_spent: 0,
        seconds: 0.0,
        first_contact_seconds: None,
        first_contact_distance: None,
        shots: 0,
        hits: 0,
        kills: 0,
        damage_received: 0,
        resolved_damage_outside_view: 0,
        hits_received: Vec::new(),
        hits_omitted: 0,
        reloads: 0,
        longest_no_progress_seconds: 0.0,
        carry: None,
        ..m01.clone()
    };
    let mut carry = Metrics {
        m01,
        m01_exit: None,
        m02_entry: None,
        window_ticks,
        segments: Vec::new(),
        retries: Vec::new(),
    };
    if carry.m01.outcome != "departed" {
        row.carry = Some(Box::new(carry));
        return Ok(row);
    }
    let saved = preview(&directory.0)?;
    if saved["status"] != "awaiting_mission" || saved["mission"] != "persons_unknown" {
        return Err(format!("earned departure was not saved: {saved}"));
    }
    carry.m01_exit = Some(exit.clone());
    let (mut session, mut run) = open(
        MissionId::PersonsUnknown,
        &directory.0,
        true,
        seed,
        difficulty,
    )?;
    let id = admit(&mut session, MissionId::PersonsUnknown, 1);
    let entry = Kit::of(&session, id)?;
    if entry.carried() != exit.carried() || !entry.loadout.personal_claims.is_empty() {
        return Err("M02 entry did not carry the earned M01 exit".into());
    }
    carry.m02_entry = Some(entry.clone());
    let mut remaining = window_ticks;
    row.outcome = "window_elapsed".into();
    loop {
        let (attempt, state) = run_state(&session)?;
        let sim_seed = attempt_seed(seed, state.id, attempt);
        let ammo_start = Kit::of(&session, id)?.loadout.ammo;
        let recording = reviews.recording();
        let (part, review, _) = drive(
            &mut session,
            id,
            leg(Scenario::M02Carry, remaining, recording, true),
            |action| action,
            persist(&mut run),
        )?;
        match recording {
            Recording::Fatal => reviews.fatal = review,
            Recording::FirstKill => reviews.first_kill = review,
            _ => {}
        }
        let ticks = session.state.tick;
        remaining = remaining.saturating_sub(ticks);
        absorb(&mut row, &part);
        carry.segments.push(Segment {
            attempt,
            sim_seed,
            outcome: part.outcome.clone(),
            ticks,
            shots: part.shots,
            hits: part.hits,
            kills: part.kills,
            reloads: part.reloads,
            end_feet: part.last_feet,
            ammo_start,
            ammo_end: Kit::of(&session, id)?.loadout.ammo,
        });
        match part.outcome.as_str() {
            "pending_continue" => {
                drop(run);
                drop(session);
                let (next, next_run, _, retry) =
                    reopen_pending(&directory.0, seed, difficulty, &entry)?;
                carry.retries.push(retry);
                row.continues_spent += 1;
                session = next;
                run = next_run;
                if remaining == 0 {
                    break;
                }
            }
            "exhausted" | "departed" => {
                // Exhaustion and a clear are terminal in the saved file too.
                let saved = preview(&directory.0)?;
                let wanted = if part.outcome == "exhausted" {
                    "failed"
                } else {
                    "awaiting_mission"
                };
                if saved["status"] != wanted {
                    return Err(format!("{} was not saved: {saved}", part.outcome));
                }
                row.outcome = part.outcome;
                break;
            }
            _ => break,
        }
    }
    row.carry = Some(Box::new(carry));
    Ok(row)
}

pub(super) fn run(seeds: std::ops::Range<u64>, max_ticks: u64) -> Result<Report, String> {
    if seeds.is_empty() || seeds.end - seeds.start > 64 {
        return Err("campaign survey requires 1..=64 seeds".into());
    }
    let mut reviews = Reviews::default();
    let mut trials = Vec::new();
    for seed in seeds {
        for profile in PROFILES {
            for difficulty in [
                CampaignDifficulty::Assisted,
                CampaignDifficulty::Standard,
                CampaignDifficulty::Severe,
            ] {
                let row = trial(
                    seed,
                    profile,
                    difficulty,
                    max_ticks,
                    M02_WINDOW_TICKS,
                    &mut reviews,
                )?;
                let m01 = &row.carry.as_ref().ok_or("carry missing")?.m01;
                eprintln!("carry {} seed={} {:?}: M01 {} {:.1}s {} deaths; M02 {} {:.1}s, {} shots, {} hits, {} kills, {} deaths, {} continues", row.profile, seed, difficulty, m01.outcome, m01.seconds, m01.deaths, row.outcome, row.seconds, row.shots, row.hits, row.kills, row.deaths, row.continues_spent);
                trials.push(row);
            }
        }
    }
    Ok(Report {
        schema: 3,
        build: env!("FRAGR_CLI_VERSION"),
        commit: env!("FRAGR_BUILD_COMMIT"),
        observation: OBSERVATION,
        profiles: PROFILES,
        decision_hz: 20,
        continuation_delay_seconds: 0,
        scenario: Scenario::M02Carry,
        trials,
        review: reviews.fatal,
        first_kill_review: reviews.first_kill,
        teaching_reviews: Vec::new(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn earned_departure_reopens_m02_retries_through_the_saved_run() {
        // Earned-run evidence: seed 41 reference/Severe departs M01 with
        // finite earned supply and dies in its M02 window. Every lifecycle
        // check inside `trial` is a hard error, never a reported outcome.
        // (Seed 42 served until #489: once M01 retries ran on their own
        // streams, its M02 window held no death.)
        let mut reviews = Reviews::default();
        let row = trial(
            41,
            PROFILES[0],
            CampaignDifficulty::Severe,
            12_000,
            M02_WINDOW_TICKS,
            &mut reviews,
        )
        .unwrap();
        let carry = row.carry.as_ref().unwrap();
        // Durable persistence after every step must not perturb play: the M01
        // leg is the survey's own trial, field for field.
        let survey =
            super::super::trial(41, PROFILES[0], CampaignDifficulty::Severe, 12_000).unwrap();
        assert_eq!(carry.m01, survey);
        assert_eq!(carry.m01.outcome, "departed");
        assert!(accepts(&row));
        let exit = carry.m01_exit.as_ref().unwrap();
        let entry = carry.m02_entry.as_ref().unwrap();
        assert_eq!(entry.carried(), exit.carried());
        assert!(entry.loadout.weapons.len() > 1, "M01 supply was earned");
        assert!(
            !carry.retries.is_empty(),
            "the window includes a real death"
        );
        assert!(
            row.shots > 0 && row.hits > 0,
            "M02 combat used real attacks"
        );
        assert_eq!(row.continues_spent as usize, carry.retries.len());
        for (retry, segment) in carry.retries.iter().zip(&carry.segments) {
            assert_eq!(segment.outcome, "pending_continue");
            assert_eq!(retry.attempt, segment.attempt);
            assert_eq!(retry.continues_after + 1, retry.continues_before);
            assert_eq!(retry.pending["pending_continue"], true);
            assert_eq!(retry.resumed["attempt"], retry.attempt + 1);
            assert!(retry.dropped_unchanged);
            assert!(!retry.rejected.iter().any(|r| r.contains("dropped")));
            for label in [
                "stale_mission",
                "stale_run",
                "future_attempt",
                "duplicate_after_accept",
            ] {
                assert!(retry.rejected.iter().any(|r| r == label), "{label}");
            }
        }
        let active: u64 = carry.segments.iter().map(|s| s.ticks).sum();
        assert!(active <= M02_WINDOW_TICKS);
        assert_eq!(carry.segments[0].sim_seed, 41);
        for pair in carry.segments.windows(2) {
            assert_ne!(
                pair[0].sim_seed, pair[1].sim_seed,
                "each retry has its own stream"
            );
        }
        let fatal = reviews.fatal.expect("the M02 death keeps its scene window");
        assert_eq!(fatal["event"], "fatal_hit");
        assert_eq!(fatal["attempt"], 1);
    }

    #[test]
    fn an_exhausted_carry_saves_failure_without_a_retry() {
        // Seed 43 deliberate/Standard spends all three continues in M01 and
        // still departs; its first M02 death exhausts the run on disk. (Seed
        // 54 served until #489: once M01 retries ran on their own streams it
        // departed M01 after one continue, so its first M02 death was a
        // retry, not exhaustion.)
        let mut reviews = Reviews::default();
        let row = trial(
            43,
            PROFILES[1],
            CampaignDifficulty::Standard,
            12_000,
            M02_WINDOW_TICKS,
            &mut reviews,
        )
        .unwrap();
        let carry = row.carry.as_ref().unwrap();
        assert_eq!(carry.m01.outcome, "departed");
        assert_eq!(carry.m01.continues_spent, 3);
        assert_eq!(row.outcome, "exhausted");
        assert_eq!((row.deaths, row.continues_spent), (1, 0));
        assert!(carry.retries.is_empty());
        assert_eq!(carry.segments.len(), 1);
    }

    #[test]
    fn an_unearned_departure_never_enters_m02() {
        let mut reviews = Reviews::default();
        let row = trial(
            42,
            PROFILES[0],
            CampaignDifficulty::Standard,
            20,
            M02_WINDOW_TICKS,
            &mut reviews,
        )
        .unwrap();
        assert_eq!(row.outcome, "m01_timeout");
        let carry = row.carry.as_ref().unwrap();
        assert!(carry.m02_entry.is_none() && carry.segments.is_empty());
        assert!(!accepts(&row) && reviews.fatal.is_none());
        assert!(
            trial(
                42,
                PROFILES[0],
                CampaignDifficulty::Standard,
                20,
                0,
                &mut reviews
            )
            .is_err(),
            "the M02 window is bounded and non-empty"
        );
    }

    #[test]
    fn a_reopen_without_a_saved_pending_continue_is_refused() {
        let mut session = GameSession::with_authored_map(
            AuthoredSource::Mission(MissionId::PersonsUnknown)
                .load()
                .unwrap(),
        );
        let id = admit(&mut session, MissionId::PersonsUnknown, 1);
        let entry = Kit::of(&session, id).unwrap();
        let empty = Scratch::new("empty").unwrap();
        let refused = reopen_pending(&empty.0, 42, CampaignDifficulty::Standard, &entry)
            .err()
            .unwrap();
        assert!(refused.starts_with("saved death is not a pending Continue"));
        assert!(run(42..42, 20).is_err() && run(0..65, 20).is_err());
    }

    fn leg(seed: u64, scenario: Scenario, max_ticks: u64, stop_at_pending: bool) -> Leg {
        Leg {
            scenario,
            seed,
            profile: PROFILES[0],
            difficulty: CampaignDifficulty::Severe,
            max_ticks,
            recording: Recording::None,
            stop_at_pending,
        }
    }

    /// What one M02 attempt did: outcome, end tick, end feet and shots.
    type Played = (String, u64, [f32; 3], u32);

    /// The earned M01 leg and the first M02 attempt, ending at its saved death.
    fn first_pending(seed: u64) -> (Scratch, Kit, Played) {
        let difficulty = CampaignDifficulty::Severe;
        let directory = Scratch::new("pending").unwrap();
        {
            let (mut session, mut run) = open(
                MissionId::RecallNotice,
                &directory.0,
                false,
                seed,
                difficulty,
            )
            .unwrap();
            let id = admit(&mut session, MissionId::RecallNotice, 1);
            let (m01, _, _) = drive(
                &mut session,
                id,
                leg(seed, Scenario::RecallNotice, 12_000, false),
                |action| action,
                persist(&mut run),
            )
            .unwrap();
            assert_eq!(m01.outcome, "departed");
        }
        let (mut session, mut run) = open(
            MissionId::PersonsUnknown,
            &directory.0,
            true,
            seed,
            difficulty,
        )
        .unwrap();
        let id = admit(&mut session, MissionId::PersonsUnknown, 1);
        let entry = Kit::of(&session, id).unwrap();
        let (part, _, _) = drive(
            &mut session,
            id,
            leg(seed, Scenario::M02Carry, M02_WINDOW_TICKS, true),
            |action| action,
            persist(&mut run),
        )
        .unwrap();
        assert_eq!(part.outcome, "pending_continue");
        let first = (part.outcome, session.state.tick, part.last_feet, part.shots);
        (directory, entry, first)
    }

    /// Reopen a copy of the saved death in a process seeded `sim_seed`, as
    /// the local child opens every process, and play attempt 2 with the
    /// policy of trial seed `trial`.
    fn replay(pending: &Scratch, entry: &Kit, trial: u64, sim_seed: u64) -> Played {
        let copy = Scratch::new("replay").unwrap();
        std::fs::copy(pending.0.join("run.json"), copy.0.join("run.json")).unwrap();
        let (mut session, mut run, id, _) =
            reopen_pending(&copy.0, sim_seed, CampaignDifficulty::Severe, entry).unwrap();
        let (part, _, _) = drive(
            &mut session,
            id,
            leg(trial, Scenario::M02Carry, M02_WINDOW_TICKS, true),
            |action| action,
            persist(&mut run),
        )
        .unwrap();
        (part.outcome, session.state.tick, part.last_feet, part.shots)
    }

    #[test]
    fn a_fixed_process_seed_reopens_the_retry_on_its_own_stream_and_replays_it() {
        // #489: the local child opens every process with one seed. Before the
        // game derived a retry stream, reopening a saved death with that seed
        // replayed it: seed 42 reference/Severe died again at tick 998 at the
        // same feet after 61 shots. Now attempt 2 runs on the stream of its
        // run and attempt: a different fight from attempt 1, and the same
        // fight every time the same death is reopened. (The fixture moved to
        // seed 41: seed 42's M01 retries now run on their own streams, and
        // its M02 window no longer holds a death to reopen.)
        let (pending, entry, first) = first_pending(41);
        let retried = replay(&pending, &entry, 41, 41);
        assert_ne!(retried, first, "a reopened death is not replayed");
        assert_eq!(
            replay(&pending, &entry, 41, 41),
            retried,
            "the same run and attempt reopen the same retry"
        );
        // The process seed still feeds the retry stream.
        let other = replay(&pending, &entry, 41, 42);
        assert_ne!(other, retried);
        eprintln!(
            "attempt 1: {first:?}; reopened attempt 2: {retried:?}; process seed 42: {other:?}"
        );
    }

    #[test]
    fn the_first_attempt_runs_on_the_trial_seed_and_each_retry_on_its_own() {
        let run = Uuid::from_u128(7);
        assert_eq!(attempt_seed(42, run, 1), 42);
        assert_eq!(
            attempt_seed(42, run, 2),
            fragr_server::mission::retry_seed(42, run, 2)
        );
        assert_ne!(attempt_seed(42, run, 2), 42);
        assert_ne!(attempt_seed(42, run, 3), attempt_seed(42, run, 2));
    }
}
