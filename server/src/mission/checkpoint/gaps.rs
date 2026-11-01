//! Checkpoint gaps measured on every campaign level.
//!
//! One solo run per level, played by the carried-arsenal route controller the
//! late-campaign route tests use (`late_routes.rs`): the shared mission
//! controller, tell reading and an accurate-aim combat action. This is
//! authoring evidence about where the checkpoints fall on a played route, not
//! fresh-player acceptance. A death spends a continue at once, so play time
//! lost to a death is measured from the save the retry returned to.
//!
//! `cargo test -p fragr-server --release --lib checkpoint_gap_survey -- --ignored --nocapture`
//! prints the table; `FRAGR_CHECKPOINT_GAPS=<path>` also writes it as JSON.
use crate::inventory::control_action_with_target_filter;
use crate::maps::AuthoredSource;
use crate::mission::route_skill::{FutileTargets, TellReader};
use crate::mission::MissionClient;
use crate::navigation::{Navigation, Navigator};
use crate::protocol::{
    Action, CampaignActor, CampaignRunStatus, EnemyPhase, MissionContinue, MissionId, MissionPhase,
    MissionReady, Role, ServerMessage, WeaponType,
};
use crate::session::GameSession;
use uuid::Uuid;

/// The longest a level is played before the row is reported as a timeout.
const MAX_TICKS: u64 = 18_000;
/// How far the route shoots back at a woken hostile it can see: a spotter on
/// its tower or a drone over the water is answered, as a player would.
const AWAKE_RANGE: f32 = 60.0;

#[derive(Debug, serde::Serialize)]
pub(super) struct Row {
    pub mission: MissionId,
    pub outcome: String,
    pub level_seconds: f64,
    pub deaths: u32,
    pub checkpoints: usize,
    /// Match seconds of each checkpoint.
    pub checkpoint_seconds: Vec<f64>,
    /// The longest stretch of live play since the last save point: the level
    /// start, a checkpoint or the save a continue returned to.
    pub longest_gap_seconds: f64,
}

fn configure(client: &mut MissionClient, message: &ServerMessage) -> Result<(), &'static str> {
    let ServerMessage::MapInfo {
        map_id,
        half_extent,
        solids,
        presentation,
        mission,
        m02_objectives,
        m02_side_ward,
        m03,
        m04,
        m05,
        m06,
        m07,
        m08,
        m09,
        m10,
        m11,
        m12,
        m13,
        m14,
        m15,
        m16,
        m17,
        m18,
        m19,
        m20,
        ..
    } = message
    else {
        return Ok(());
    };
    let half = *half_extent;
    let presentation = presentation.as_ref();
    client.replace_map_with_id(
        *map_id,
        *m02_objectives,
        *m02_side_ward,
        mission.as_ref(),
        half,
        solids,
        presentation,
    )?;
    client.replace_map_with_m03(m03.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m04(m04.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m05(m05.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m06(m06.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m07(m07.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m08(m08.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m09(m09.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m10(m10.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m11(m11.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m12(m12.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m13(m13.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m14(m14.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m15(m15.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m16(m16.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m17(m17.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m18(m18.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m19(m19.as_ref(), half, solids, presentation)?;
    client.replace_map_with_m20(m20.as_ref(), half, solids, presentation)?;
    Ok(())
}

pub(super) fn play(mission: MissionId, seed: u64) -> Row {
    play_until(mission, seed, true, |_| false).0
}

/// Play `mission` until `stop` holds or the level ends, returning the row so
/// far and the session as it stands.
fn play_until(
    mission: MissionId,
    seed: u64,
    arsenal: bool,
    stop: impl Fn(&GameSession) -> bool,
) -> (Row, GameSession) {
    let mut session =
        GameSession::with_authored_map(AuthoredSource::Mission(mission).load().unwrap());
    let id = Uuid::from_u128(5270);
    session.state.use_replay_ids();
    session.state.seed(seed);
    session.state.enable_campaign_run().unwrap();
    session
        .state
        .add_player(id, "Gap route".into(), Role::Agent);
    if arsenal {
        let player = session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap();
        for weapon in [
            WeaponType::Tack,
            WeaponType::Flechette,
            WeaponType::Repeater,
            WeaponType::Scatter,
            WeaponType::Rail,
            WeaponType::Sniper,
            WeaponType::Arc,
            WeaponType::Rocket,
        ] {
            player.inventory.grant_weapon(weapon);
        }
        player.weapon = WeaponType::Repeater;
    }
    session.state.acknowledge_mission(
        id,
        MissionReady {
            id: mission,
            attempt: 1,
        },
    );
    let mut client = MissionClient::default();
    let mut navigator = Navigator::default();
    let mut tells = TellReader::default();
    let mut futile = FutileTargets::default();
    let mut navigation = None;
    let mut map_seen = None;
    let mut row = Row {
        mission,
        outcome: "timeout".into(),
        level_seconds: 0.0,
        deaths: 0,
        checkpoints: 0,
        checkpoint_seconds: Vec::new(),
        longest_gap_seconds: 0.0,
    };
    let mut saved_at: Option<(u64, u32)> = None;
    let mut seen_checkpoints = 0;
    while session.state.tick < MAX_TICKS {
        if stop(&session) {
            break;
        }
        if map_seen.as_ref() != Some(&session.state.map) {
            if configure(&mut client, &session.state.map_info()).is_err() {
                row.outcome = "controller_refused_map".into();
                break;
            }
            navigation = Some(Navigation::shared(session.state.map.arena().clone()).unwrap());
            map_seen = Some(session.state.map.clone());
            navigator.clear();
        }
        let state = session.state.mission_state().unwrap();
        if client.observe(session.state.tick, state.clone()).is_err() {
            row.outcome = "controller_refused_state".into();
            break;
        }
        if state.phase == MissionPhase::Departed {
            row.outcome = "departed".into();
            break;
        }
        let ticks = session.state.campaign_checkpoint_ticks();
        if ticks.len() > seen_checkpoints {
            seen_checkpoints = ticks.len();
            saved_at = saved_at.map(|(_, attempt)| (*ticks.last().unwrap(), attempt));
        }
        let live = !matches!(state.phase, MissionPhase::Briefing);
        if live && saved_at.is_none_or(|(_, attempt)| attempt != state.attempt) {
            saved_at = Some((session.state.tick, state.attempt));
        }
        let Some(player) = session
            .state
            .players
            .iter()
            .find(|p| p.id == id && p.hp > 0)
        else {
            row.deaths += 1;
            let run = state.run.unwrap();
            if run.status == CampaignRunStatus::Failed {
                row.outcome = "exhausted".into();
                break;
            }
            if run.status == CampaignRunStatus::Continue {
                assert!(session.state.continue_mission(
                    id,
                    MissionContinue {
                        id: mission,
                        run_id: run.id,
                        attempt: state.attempt,
                    }
                ));
            }
            session.tick_messages(0.05);
            continue;
        };
        if let Some((at, _)) = saved_at.filter(|_| live) {
            row.longest_gap_seconds = row
                .longest_gap_seconds
                .max(session.state.tick.saturating_sub(at) as f64 / 20.0);
        }
        let loadout = player
            .inventory
            .state(id, player.weapon, session.state.tick)
            .unwrap();
        let snapshot = session.state.snapshot();
        let arena = session.state.map.arena();
        let mut combat = control_action_with_target_filter(
            id,
            &snapshot,
            Some(&loadout),
            Action::default(),
            false,
            |me, other| {
                let awake = matches!(other.campaign, Some(CampaignActor::Hostile { phase, .. }) if !matches!(phase, EnemyPhase::Idle | EnemyPhase::Dead));
                !futile.skips(other.id, session.state.tick)
                    && (other.x - me.x).hypot(other.z - me.z)
                        <= if awake { AWAKE_RANGE } else { 20.0 }
                    && crate::combat::line_of_sight(
                        [
                            me.x,
                            me.y - crate::sim::PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT,
                            me.z,
                        ],
                        [
                            other.x,
                            other.y - crate::sim::PLAYER_FLOOR_Y
                                + crate::combat::aim_height(other.campaign),
                            other.z,
                        ],
                        &arena.solids,
                    )
            },
        );
        if player.hp < 70 {
            if let Some(health) = snapshot
                .pickups
                .iter()
                .filter(|p| p.available && p.kind == "health")
                .min_by(|a, b| {
                    (a.x - player.x)
                        .hypot(a.z - player.z)
                        .total_cmp(&(b.x - player.x).hypot(b.z - player.z))
                })
            {
                combat = Action {
                    forward: true,
                    look_at: Some(crate::protocol::LookAt {
                        x: Some(health.x),
                        y: Some(health.y),
                        z: Some(health.z),
                        player_id: None,
                    }),
                    ..Default::default()
                };
            }
        }
        let mut action = client.steer_with_equipment(
            &mut navigator,
            navigation.as_ref().unwrap(),
            id,
            &snapshot,
            combat,
            Some(&loadout),
        );
        if action.fire
            && action
                .look_at
                .as_ref()
                .is_some_and(|look| look.player_id.is_some())
        {
            action.left = (session.state.tick / 20).is_multiple_of(2);
            action.right = !action.left;
        }
        futile.observe(&snapshot, &action);
        let action = tells.evade(&session.state, &snapshot, id, action);
        session.state.set_action(id, action);
        session.tick_messages(0.05);
    }
    let ticks = session.state.campaign_checkpoint_ticks();
    row.checkpoints = ticks.len();
    row.checkpoint_seconds = ticks.iter().map(|t| *t as f64 / 20.0).collect();
    // The level clock of the final attempt: from its start or the save it
    // resumed, to departure or the end of the measured window.
    if let Some(started) = session.state.campaign_attempt_started_at() {
        row.level_seconds = session.state.tick.saturating_sub(started) as f64 / 20.0;
    }
    (row, session)
}

#[test]
#[ignore = "per-level survey: cargo test -p fragr-server --release --lib checkpoint_gap_survey -- --ignored --nocapture"]
fn checkpoint_gap_survey() {
    let only: Option<String> = std::env::var("FRAGR_CHECKPOINT_LEVEL").ok();
    let mut rows = Vec::new();
    for mission in MissionId::ALL {
        if mission == MissionId::StillHere
            || only
                .as_ref()
                .is_some_and(|name| !format!("{mission:?}").eq_ignore_ascii_case(name))
        {
            continue;
        }
        let row = play(mission, 41);
        eprintln!(
            "| {:?} | {} | {:.0} | {} | {} | {:.0} |",
            row.mission,
            row.outcome,
            row.level_seconds,
            row.deaths,
            row.checkpoints,
            row.longest_gap_seconds
        );
        rows.push(row);
    }
    if let Ok(path) = std::env::var("FRAGR_CHECKPOINT_GAPS") {
        std::fs::write(path, serde_json::to_string_pretty(&rows).unwrap() + "\n").unwrap();
    }
}

/// Level 1 on the route controller keeps every stretch under three minutes.
#[test]
fn recall_notice_route_keeps_checkpoints_within_three_minutes() {
    let row = play(MissionId::RecallNotice, 41);
    assert_eq!(row.outcome, "departed", "{row:?}");
    assert!(row.longest_gap_seconds <= 180.0, "{row:?}");
}

/// Level 20 on the route controller, the pier hold and its wave breaks
/// included, keeps every stretch under three minutes (367 s before #527's
/// wave 23 work).
#[test]
fn local_exception_route_keeps_checkpoints_within_three_minutes() {
    let row = play(MissionId::LocalException, 41);
    assert_eq!(row.outcome, "departed", "{row:?}");
    assert!(row.longest_gap_seconds <= 180.0, "{row:?}");
}

/// Every level's first checkpoint, encoded as the run file carries it and read
/// back into a fresh session of the same mission, resumes the same world: the
/// same map facts, the owner where and as they were, the same hostiles, and
/// a mission state that stays valid as play goes on. Each level starts its
/// own run here, so later levels lack the carried outcomes a whole run file
/// needs; the file itself is covered by `disk_tests`.
#[test]
fn every_level_reopens_at_its_first_checkpoint() {
    let id = Uuid::from_u128(5270);
    for mission in MissionId::ALL {
        if mission == MissionId::StillHere {
            continue;
        }
        let (row, mut original) = play_until(mission, 41, true, |s| {
            !s.state.campaign_checkpoint_ticks().is_empty()
        });
        let saved = original
            .state
            .mission
            .as_ref()
            .and_then(|run| run.solo.as_ref())
            .and_then(|solo| solo.checkpoints.saved_to_disk())
            .cloned()
            .unwrap_or_else(|| panic!("{mission:?} took no checkpoint: {row:?}"));
        let world = serde_json::to_value(original.state.map_info()).unwrap();
        let owner = |s: &GameSession| {
            let p = s.state.players.iter().find(|p| p.id == id).unwrap();
            ([p.x, p.y, p.z], p.hp, p.armor, p.weapon)
        };
        let hostiles = |s: &GameSession| {
            let mut bodies: Vec<(String, [f32; 2])> = s
                .state
                .players
                .iter()
                .filter(|p| p.is_campaign_enemy() && p.hp > 0)
                .map(|p| (p.name.clone(), [p.x, p.z]))
                .collect();
            bodies.sort_by(|a, b| a.0.cmp(&b.0));
            bodies
        };
        let owner_then = owner(&original);
        // One quiet tick on: groups the save left unwoken stand at their posts.
        original.state.set_action(id, Action::default());
        original.state.tick(0.05);
        let then = (owner_then, hostiles(&original));
        let text = serde_json::to_string(&saved).unwrap();
        eprintln!("{mission:?}: checkpoint of {} bytes", text.len());
        let read: crate::mission::run_file::SavedCheckpoint = serde_json::from_str(&text).unwrap();
        let mut reopened =
            GameSession::with_authored_map(AuthoredSource::Mission(mission).load().unwrap());
        reopened.state.use_replay_ids();
        reopened.state.seed(41);
        reopened.state.enable_campaign_run().unwrap();
        reopened
            .state
            .load_campaign_checkpoint(&read)
            .unwrap_or_else(|e| panic!("{mission:?}: {e}"));
        assert!(reopened.state.tick >= saved.tick, "{mission:?}");
        reopened
            .state
            .add_player(id, "Gap route".into(), Role::Agent);
        reopened.state.acknowledge_mission(
            id,
            MissionReady {
                id: mission,
                attempt: 1,
            },
        );
        let mut resumed = false;
        for _ in 0..40 {
            reopened.state.tick(0.05);
            if reopened.state.take_events().iter().any(|event| {
                matches!(
                    event,
                    crate::protocol::GameEvent::Checkpoint { resumed: true }
                )
            }) {
                resumed = true;
                break;
            }
        }
        assert!(resumed, "{mission:?} never resumed its checkpoint");
        assert_eq!(
            serde_json::to_value(reopened.state.map_info()).unwrap(),
            world,
            "{mission:?} rebuilt another world"
        );
        assert_eq!(owner(&reopened), then.0, "{mission:?}");
        // Groups not yet woken stand at their posts again on the next tick.
        reopened.state.tick(0.05);
        let now = hostiles(&reopened);
        assert_eq!(
            now.iter().map(|(name, _)| name).collect::<Vec<_>>(),
            then.1.iter().map(|(name, _)| name).collect::<Vec<_>>(),
            "{mission:?} hostiles"
        );
        // A woken guard resumes where it stood; one the save left unwoken
        // (a drone may drift along its patrol before waking) is at its post.
        let definitions = reopened.state.map.encounters();
        for ((name, at), (_, was)) in now.iter().zip(&then.1) {
            let post = definitions
                .iter()
                .flat_map(|group| &group.enemies)
                .find(|enemy| enemy.id == *name)
                .map(|enemy| enemy.feet)
                .unwrap();
            assert!(
                (at[0] - was[0]).hypot(at[1] - was[1]) < 0.5
                    || (at[0] - post[0]).hypot(at[1] - post[2]) < 0.5,
                "{mission:?} {name} stood at {was:?}, resumed at {at:?}"
            );
        }
        for _ in 0..60 {
            reopened.tick_messages(0.05);
            reopened
                .state
                .mission_state()
                .unwrap()
                .validate(reopened.state.tick)
                .unwrap_or_else(|e| panic!("{mission:?}: {e}"));
        }
    }
}
