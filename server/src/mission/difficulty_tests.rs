use super::*;
use crate::maps::AuthoredMap;
use crate::protocol::{Action, EnemyKind, EnemyPhase, Role};
use crate::session::GameSession;
use serde_json::json;

fn fixture(difficulty: CampaignDifficulty, kind: EnemyKind) -> (GameSession, Uuid) {
    let mut definition = super::tests::definition();
    definition["encounters"] = json!([{
        "id":"encounter", "regions":[{"min":[-1,0,-7],"max":[1,2,-4]}],
        "enemies":[{"id":"guard", "kind":kind, "feet":[2,0,-3], "yaw":0}]
    }]);
    let map = AuthoredMap::read(serde_json::to_vec(&definition).unwrap().as_slice()).unwrap();
    let mut session = GameSession::with_authored_map(map);
    session.state.set_campaign_difficulty(difficulty).unwrap();
    let id = Uuid::from_u128(67);
    session.state.add_player(id, "Visitor".into(), Role::Human);
    session.state.acknowledge_mission(
        id,
        MissionReady {
            id: crate::protocol::MissionId::RecallNotice,
            attempt: 1,
        },
    );
    (session, id)
}

fn phase(session: &GameSession) -> (EnemyPhase, u64, u64) {
    let guard = session
        .state
        .players
        .iter()
        .find(|p| p.is_campaign_enemy())
        .unwrap();
    match guard.campaign.unwrap() {
        CampaignActor::Union {
            phase,
            phase_started,
            phase_ends,
            ..
        } => (phase, phase_started, phase_ends),
        _ => panic!("expected Union guard"),
    }
}

#[test]
fn every_tier_keeps_real_tells_committed_aim_and_retaliation_windows() {
    for kind in [EnemyKind::Clerk, EnemyKind::Sweeper] {
        let mut timings = Vec::new();
        for difficulty in [
            CampaignDifficulty::Assisted,
            CampaignDifficulty::Standard,
            CampaignDifficulty::Severe,
        ] {
            for dodge in [false, true] {
                let (mut session, id) = fixture(difficulty, kind);
                for _ in 0..2 {
                    session.tick_messages(0.05);
                }
                let (current, start, end) = phase(&session);
                assert_eq!(current, EnemyPhase::Windup);
                assert!(end - start >= 10, "every tier preserves a readable tell");
                if dodge {
                    session.state.set_action(
                        id,
                        Action {
                            right: true,
                            yaw: Some(0.0),
                            ..Default::default()
                        },
                    );
                }
                while session.state.tick < end - 1 {
                    session.tick_messages(0.05);
                    assert!(session.state.shot_results.is_empty());
                    assert_eq!(session.state.players[0].hp, 100);
                }
                session.tick_messages(0.05);
                assert_eq!(phase(&session).0, EnemyPhase::Firing);
                assert_eq!(session.state.shot_results.len(), 1);
                let shot = &session.state.shot_results[0];
                if dodge {
                    assert!(shot.target_id.is_none());
                    assert_eq!(session.state.players[0].hp, 100);
                } else {
                    assert_eq!(shot.target_id, Some(id));
                    assert_eq!(shot.damage, if kind == EnemyKind::Clerk { 20 } else { 25 });
                }
                let mut shots = 1;
                for _ in 0..20 {
                    session.tick_messages(0.05);
                    shots += session.state.shot_results.len();
                    if phase(&session).0 == EnemyPhase::Recovery {
                        break;
                    }
                }
                let (current, recovery_start, recovery_end) = phase(&session);
                assert_eq!(current, EnemyPhase::Recovery);
                assert_eq!(shots, if kind == EnemyKind::Clerk { 1 } else { 3 });
                if dodge {
                    assert_eq!(session.state.players[0].hp, 100);
                } else {
                    timings.push((end - start, recovery_end - recovery_start));
                }
            }
        }
        assert!(timings
            .windows(2)
            .all(|pair| pair[0].0 > pair[1].0 && pair[0].1 > pair[1].1));
        assert_eq!(
            timings[1],
            if kind == EnemyKind::Clerk {
                (12, 20)
            } else {
                (14, 26)
            }
        );
    }
}

#[test]
fn difficulty_is_fixed_before_admission_and_retained_across_party_reset() {
    let mut arcade = GameState::new();
    assert!(arcade
        .set_campaign_difficulty(CampaignDifficulty::Severe)
        .is_err());
    let (mut session, id) = fixture(CampaignDifficulty::Severe, EnemyKind::Clerk);
    assert!(session
        .state
        .set_campaign_difficulty(CampaignDifficulty::Assisted)
        .is_err());
    session.tick_messages(0.05);
    session.state.players[0].hp = 0;
    session.tick_messages(0.05);
    let state = session.state.mission_state().unwrap();
    assert_eq!(state.attempt, 2);
    assert_eq!(state.rules, CampaignRules::new(CampaignDifficulty::Severe));
    session.state.remove_player(id);
    assert!(session
        .state
        .set_campaign_difficulty(CampaignDifficulty::Standard)
        .is_err());
}

#[test]
fn mission_rules_reject_unknown_revisions_missing_fields_and_midrun_changes() {
    let (session, _) = fixture(CampaignDifficulty::Assisted, EnemyKind::Clerk);
    let state = session.state.mission_state().unwrap();
    let mut invalid = state.clone();
    invalid.rules.revision = 2;
    assert!(invalid.validate(0).is_err());
    for bad in [
        json!({"difficulty":"nightmare","revision":1}),
        json!({"difficulty":"standard"}),
        json!({"difficulty":"standard","revision":1,"adaptive":true}),
    ] {
        assert!(serde_json::from_value::<CampaignRules>(bad).is_err());
    }
    let mut observer = MissionClient::default();
    let map = &session.state.map;
    observer
        .replace_map(
            map.mission(),
            map.arena().half,
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    observer.observe(0, state.clone()).unwrap();
    observer
        .replace_map(
            map.mission(),
            map.arena().half,
            &map.arena().solids,
            map.presentation_ref(),
        )
        .unwrap();
    invalid = state;
    invalid.rules = CampaignRules::new(CampaignDifficulty::Severe);
    assert!(
        observer.observe(0, invalid).is_err(),
        "geometry refresh cannot change a run's rules"
    );
}
