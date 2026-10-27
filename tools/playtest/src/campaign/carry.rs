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

pub const OBSERVATION: &str = "Earned M01 departure from the constrained Recall Notice policy, written through the server's durable run file after every step. M02 is entered only by reopening that file: the saved departure is promoted and loaded by the same code as the local child. The same constrained perception, turning, aim, reload and supply policy then plays a bounded 60-second M02 window of active time; there are no M02 route hints, grants or completion targets. A death ends the session. Its pending Continue is reopened from disk in a fresh session with a declared per-attempt simulation seed (trial seed plus 1000 per earlier attempt; an unchanged seed replays a deterministic controller's death exactly), where a dropped request, stale mission/run/attempt requests and a duplicate after acceptance are sent through the ordinary session command path; only the accepted request may spend a continue. Restoration is compared with the M02 entry kit live and again from a copy of the saved file. Immediate Continue with no menu delay; no M02 clear, campaign, human-population or rendered-readability claim.";

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

/// Simulation seed of the session that plays M02 `attempt`. The local child
/// launches every process with one fixed seed, so an unchanged seed and entry
/// replay a deterministic controller's previous death exactly. Each reopened
/// attempt therefore declares its own simulation stream; the policy's aim
/// phase keeps the trial seed.
pub fn attempt_seed(seed: u64, attempt: u32) -> u64 {
    seed.wrapping_add(u64::from(attempt.saturating_sub(1)) * 1_000)
}

/// One session of M02 play, ended by death, exhaustion, a clear or the window.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Segment {
    pub attempt: u32,
    pub sim_seed: u64,
    pub outcome: String,
    pub ticks: u64,
    pub shots: u32,
    pub hits: u32,
    pub kills: u32,
    pub reloads: u32,
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
    /// Requests refused by the server, each leaving the saved file unchanged.
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
    session.state.seed(seed);
    let run = DurableRun::open(&mut session, directory, resume, Some(difficulty))
        .map_err(|e| e.to_string())?;
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
    let mut rejected = vec!["dropped_before_delivery".to_owned()];
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
        let attempt = run_state(&session)?.0;
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
            sim_seed: attempt_seed(seed, attempt),
            outcome: part.outcome.clone(),
            ticks,
            shots: part.shots,
            hits: part.hits,
            kills: part.kills,
            reloads: part.reloads,
            ammo_start,
            ammo_end: Kit::of(&session, id)?.loadout.ammo,
        });
        match part.outcome.as_str() {
            "pending_continue" => {
                drop(run);
                drop(session);
                let (next, next_run, _, retry) = reopen_pending(
                    &directory.0,
                    attempt_seed(seed, attempt + 1),
                    difficulty,
                    &entry,
                )?;
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
        // Earned-run evidence: seed 42 reference/Severe departs M01 with
        // finite earned supply and dies in its M02 window. Every lifecycle
        // check inside `trial` is a hard error, never a reported outcome.
        let mut reviews = Reviews::default();
        let row = trial(
            42,
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
            super::super::trial(42, PROFILES[0], CampaignDifficulty::Severe, 12_000).unwrap();
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
            for label in [
                "dropped_before_delivery",
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
        assert!(carry
            .segments
            .iter()
            .all(|s| s.sim_seed == attempt_seed(42, s.attempt)));
        let fatal = reviews.fatal.expect("the M02 death keeps its scene window");
        assert_eq!(fatal["event"], "fatal_hit");
        assert_eq!(fatal["attempt"], 1);
    }

    #[test]
    fn an_exhausted_carry_saves_failure_without_a_retry() {
        // Seed 43 deliberate/Assisted spends all three continues in M01 and
        // still departs; its first M02 death exhausts the run on disk.
        let mut reviews = Reviews::default();
        let row = trial(
            43,
            PROFILES[1],
            CampaignDifficulty::Assisted,
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

    #[test]
    fn attempt_seeds_are_declared_and_distinct() {
        assert_eq!(attempt_seed(42, 1), 42);
        assert_eq!(attempt_seed(42, 2), 1_042);
        assert_ne!(attempt_seed(42, 3), attempt_seed(42, 2));
    }
}
