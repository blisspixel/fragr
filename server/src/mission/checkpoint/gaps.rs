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
    let mut session =
        GameSession::with_authored_map(AuthoredSource::Mission(mission).load().unwrap());
    let id = Uuid::from_u128(5270);
    session.state.use_replay_ids();
    session.state.seed(seed);
    session.state.enable_campaign_run().unwrap();
    session
        .state
        .add_player(id, "Gap route".into(), Role::Agent);
    {
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
                    && (other.x - me.x).hypot(other.z - me.z) <= if awake { 32.0 } else { 20.0 }
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
    row
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
