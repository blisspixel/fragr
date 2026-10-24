//! A current-format save restored into the live stair worlds: retry spends
//! once, the anchor is exact, and the entry stands and walks on real floor.
use super::*;
use crate::maps::{AuthoredSource, RuntimeMap};
use crate::mission::run_file::{SavedEntry, SavedStep};
use crate::protocol::{AmmoPool, BodyKind};

/// Missions whose entry sits on authored stairs or raised decks.
const STAIR_MISSIONS: [MissionId; 5] = [
    MissionId::CustodianOfRecord,
    MissionId::PassengerManifest,
    MissionId::CommonCarrier,
    MissionId::TermsOfCooperation,
    MissionId::CivicPressureValve,
];

fn entry(mission: MissionId, hash: [u8; 32]) -> RunDocument {
    let mut document = match mission {
        MissionId::CustodianOfRecord => {
            let mut completed = m09_tests::completed_archive();
            let SavedStep::AwaitingMission { exit, .. } = &completed.step else {
                panic!("archive completion")
            };
            completed.step = SavedStep::MissionEntry {
                mission,
                entry: exit.clone(),
            };
            completed.m08_outcome = None;
            completed
        }
        MissionId::PassengerManifest => m09_tests::completed_archive()
            .promote_next(mission, hash)
            .unwrap(),
        MissionId::CommonCarrier => m09_receipt_tests::completed_berth(true, true)
            .promote_next(mission, hash)
            .unwrap(),
        MissionId::TermsOfCooperation => arc_tests::completed_tender()
            .promote_next(mission, hash)
            .unwrap(),
        MissionId::CivicPressureValve => m15_tests::stadium_entry(),
        _ => panic!("not a stair mission"),
    };
    document.content_sha256 = hash;
    document.body = Some(BodyKind::Synthetic);
    document.remaining_continues = 1;
    document.level_start_continues = 2;
    let SavedStep::MissionEntry { entry, .. } = &mut document.step else {
        panic!("mission entry")
    };
    entry.hp = 37;
    entry.armor = 19;
    entry.equipment.grenades = 2;
    entry.equipment.proximity_mines = 3;
    for ammo in &mut entry.equipment.ammo {
        ammo.rounds = match ammo.pool {
            AmmoPool::Bullets => 23,
            AmmoPool::Shells => 7,
            AmmoPool::Cells => 5,
            AmmoPool::Rockets => 0,
        };
    }
    document.validate(hash).unwrap();
    document
}

fn saved_entry(document: &RunDocument) -> SavedEntry {
    match &document.step {
        SavedStep::MissionEntry { entry, .. }
        | SavedStep::PendingContinue { entry, .. }
        | SavedStep::Failed { entry, .. }
        | SavedStep::Abandoned { entry, .. } => entry.clone(),
        SavedStep::AwaitingMission { exit, .. } => exit.clone(),
    }
}

fn assert_standing_support(arena: &crate::movement::Arena, feet: [f32; 3]) {
    let support =
        arena.support_height(feet[0], feet[2], feet[1] + crate::movement::CONTACT_EPSILON);
    assert!(
        (feet[1] - support).abs() <= crate::movement::CONTACT_EPSILON,
        "actual feet {feet:?} must agree with measured support {support}"
    );
    assert!(arena.fits_height(feet[0], feet[2], support, crate::movement::BODY_HEIGHT));
}

#[test]
fn saved_stair_entries_retry_once_and_stand_on_the_live_world() {
    use crate::protocol::{Action, MissionContinue, MissionReady, Role};
    use crate::sim::{GameState, PLAYER_FLOOR_Y};
    let mut hashes = m09_tests::HASHES;
    let maps: Vec<_> = STAIR_MISSIONS
        .iter()
        .map(|mission| {
            let map = AuthoredSource::Mission(*mission).load().unwrap();
            let hash = RuntimeMap::Authored(map.clone()).content_sha256().unwrap();
            hashes[stage_index(*mission)] = hash;
            (*mission, map, hash)
        })
        .collect();
    for (mission, map, hash) in maps {
        for pending in [false, true] {
            let mut source = entry(mission, hash);
            if pending {
                source.step = SavedStep::PendingContinue {
                    mission,
                    entry: saved_entry(&source),
                };
            }
            let anchor = saved_entry(&source);
            let RunProbe::Compatible(document) =
                RunStore::inspect_bytes(&serde_json::to_vec(&source).unwrap(), hashes)
            else {
                panic!("current {mission:?} entry must read back")
            };
            assert_eq!(*document, source);
            let mut state = GameState::with_authored_map(map.clone());
            state.load_campaign_run(&document).unwrap();
            let owner = Uuid::new_v4();
            state.add_player(owner, "Visitor".into(), Role::Human);
            if pending {
                let request = MissionContinue {
                    id: mission,
                    run_id: document.id,
                    attempt: document.attempt(),
                };
                assert!(state.continue_mission(owner, request));
                assert!(
                    !state.continue_mission(owner, request),
                    "a repeated continue cannot spend twice"
                );
            }
            let saved = state.campaign_run_document().unwrap().unwrap();
            assert_eq!(saved.content_sha256, hash);
            assert_eq!(
                saved.remaining_continues,
                document.remaining_continues - u8::from(pending)
            );
            assert_eq!(saved.level_start_continues, document.level_start_continues);
            assert_eq!(saved_entry(&saved), anchor);
            assert_eq!(saved.body, document.body);
            assert_eq!(saved.m08_outcome, document.m08_outcome);
            assert_eq!(saved.m09_outcome, document.m09_outcome);
            assert_eq!(saved.m10_transit, document.m10_transit);
            assert_eq!(saved.m12_outcome, document.m12_outcome);
            assert_eq!(saved.m14_outcome, document.m14_outcome);
            assert_eq!(
                state.acknowledge_mission(
                    owner,
                    MissionReady {
                        id: mission,
                        attempt: saved.attempt(),
                    },
                ),
                !pending,
                "a restored continue keeps readiness; a fresh entry still needs it"
            );
            let player = state.players.iter().find(|p| p.id == owner).unwrap();
            assert_eq!(SavedEntry::from_player(player).unwrap(), anchor);
            let start = [player.x, player.y - PLAYER_FLOOR_Y, player.z];
            assert_standing_support(state.map.arena(), start);
            state.set_action(
                owner,
                Action {
                    forward: true,
                    yaw: Some(std::f32::consts::FRAC_PI_2),
                    ..Action::default()
                },
            );
            for _ in 0..6 {
                state.tick(0.05);
                let player = state.players.iter().find(|p| p.id == owner).unwrap();
                assert!(!player.ducking, "{mission:?} entry has full standing room");
                assert_standing_support(
                    state.map.arena(),
                    [player.x, player.y - PLAYER_FLOOR_Y, player.z],
                );
                assert!(player.hp > 0);
            }
            let player = state.players.iter().find(|p| p.id == owner).unwrap();
            assert!(
                player.z - start[2] >= 1.0,
                "ordinary initial route became blocked in {mission:?}"
            );
            assert!(
                (player.y - PLAYER_FLOOR_Y - start[1]).abs() < 0.05,
                "{mission:?} entry lost its real floor"
            );
        }
    }
}

#[test]
fn an_unfinished_entry_never_promotes_to_its_successor() {
    let successors = [
        MissionId::PassengerManifest,
        MissionId::CommonCarrier,
        MissionId::RightOfSearch,
        MissionId::WeightOfPermission,
        MissionId::FreedomOfMovement,
    ];
    for (mission, next) in STAIR_MISSIONS.into_iter().zip(successors) {
        let hash = m09_tests::HASHES[stage_index(mission)];
        let document = entry(mission, hash);
        assert!(
            document
                .promote_next(next, m09_tests::HASHES[stage_index(next)])
                .is_err(),
            "{mission:?} entry promoted without completing"
        );
    }
}
