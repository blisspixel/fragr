//! The free local agent's controller plays Local Exception end to end on
//! every tier: the same `MissionClient`, `Navigator` and combat selection the
//! adapter and the local brain use, with the carried late-campaign kit and no
//! replenishment beyond what the map and its crates hold.
use super::*;
use crate::inventory::control_action_with_target_filter;
use crate::navigation::{Navigation, Navigator};
use crate::protocol::{Action, CampaignActor, EnemyPhase, MissionPhase, Role, WeaponType};

struct Run {
    /// The drive's goal was reached (departure for a full run).
    departed: bool,
    ticks: u64,
    hp: i32,
    challenges: M20ChallengeState,
    killed: usize,
    deaths: u32,
}

fn play(difficulty: CampaignDifficulty) -> Run {
    drive(
        difficulty,
        |_, _| {},
        |state| state.phase == MissionPhase::Departed,
        false,
        26_000,
    )
}

/// One agent body driven by the shared controller until `done` holds.
/// `sight_only` uses the scripted adapter's target choice (any hostile in
/// line of sight) instead of the local brain's ranged one.
fn drive(
    difficulty: CampaignDifficulty,
    prepare: impl FnOnce(&mut crate::session::GameSession, uuid::Uuid),
    done: impl Fn(&crate::protocol::MissionState) -> bool,
    sight_only: bool,
    limit: u32,
) -> Run {
    let (mut session, id) = super::tests::session_with(difficulty, Role::Agent);
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
            WeaponType::Arc,
            WeaponType::Rocket,
        ] {
            player.inventory.grant_weapon(weapon);
        }
        player.weapon = WeaponType::Repeater;
        player.armor = 50;
    }
    prepare(&mut session, id);
    let mut client = MissionClient::default();
    let mut navigator = Navigator::default();
    let mut previous = None;
    let mut navigation = None;
    let mut killed = 0;
    let mut deaths = 0;
    let mut seen_dead = std::collections::HashSet::new();
    for _ in 0..limit {
        let map = &session.state.map;
        if previous.as_ref() != Some(map) {
            client
                .replace_map_with_id(
                    map.id(),
                    None,
                    false,
                    None,
                    map.half_extent(),
                    &map.arena().solids,
                    map.presentation_ref(),
                )
                .unwrap();
            client
                .replace_map_with_m20(
                    map.m20_geometry().as_ref(),
                    map.half_extent(),
                    &map.arena().solids,
                    map.presentation_ref(),
                )
                .unwrap();
            navigation = Some(Navigation::shared(map.arena().clone()).unwrap());
            previous = Some(map.clone());
            navigator.clear();
        }
        let state = session.state.mission_state().unwrap();
        client.observe(session.state.tick, state.clone()).unwrap();
        if done(&state) {
            let player = session.state.players.iter().find(|p| p.id == id).unwrap();
            return Run {
                departed: true,
                ticks: session.state.tick,
                hp: player.hp,
                challenges: state.m20.unwrap().challenges,
                killed,
                deaths,
            };
        }
        for p in &session.state.players {
            if p.is_campaign_enemy() && p.hp <= 0 && seen_dead.insert(p.id) {
                killed += 1;
            }
        }
        let player = session.state.players.iter().find(|p| p.id == id).unwrap();
        if player.hp <= 0 {
            // The free agent does not get a free life: count and stop.
            deaths += 1;
            break;
        }
        let loadout = player
            .inventory
            .state(id, player.weapon, session.state.tick)
            .unwrap();
        let snapshot = session.state.snapshot();
        let solids = session.state.map.arena().solids.clone();
        let combat = control_action_with_target_filter(
            id,
            &snapshot,
            Some(&loadout),
            Action::default(),
            false,
            |me, other| {
                let awake = matches!(other.campaign, Some(CampaignActor::Hostile { phase, .. }) if !matches!(phase, EnemyPhase::Idle | EnemyPhase::Dead));
                (sight_only
                    || (other.x - me.x).hypot(other.z - me.z) <= if awake { 40.0 } else { 24.0 })
                    && crate::combat::line_of_sight(
                        [
                            me.x,
                            me.y - PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT,
                            me.z,
                        ],
                        [
                            other.x,
                            other.y - PLAYER_FLOOR_Y + crate::combat::aim_height(other.campaign),
                            other.z,
                        ],
                        &solids,
                    )
            },
        );
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
        session.state.set_action(id, action);
        session.tick_messages(0.05);
    }
    let player = session.state.players.iter().find(|p| p.id == id).unwrap();
    let state = session.state.mission_state().unwrap();
    panic!(
        "{difficulty:?} stalled at [{},{},{}] hp {} deaths {deaths} killed {killed} tick {}: {:?}",
        player.x,
        player.y,
        player.z,
        player.hp,
        session.state.tick,
        state
            .m20
            .map(|f| (f.completed, f.refuge_integrity, f.challenges))
    );
}

fn assert_completes(difficulty: CampaignDifficulty) {
    let run = play(difficulty);
    eprintln!(
        "{difficulty:?}: departed at tick {} with {} HP, {} machines down, {:?}",
        run.ticks, run.hp, run.killed, run.challenges
    );
    assert!(run.departed);
    assert_eq!(run.deaths, 0);
    assert!(run.hp > 0);
    assert!(run.challenges.crew_crossed, "the crew crossed on their own");
    assert!(
        run.killed >= 20,
        "the hold was a fight: {} kills",
        run.killed
    );
}

/// The Surveyor never walks and its tower hides it from much of the gallery.
/// With both sweepers down and the agent left standing in a sluice channel,
/// the agent must climb out, find a sightline and finish the lesson rather
/// than wait forever.
#[test]
fn an_unseen_surveyor_does_not_stall_the_sluice_lesson() {
    for sight_only in [false, true] {
        let run = drive(
            CampaignDifficulty::Standard,
            |session, id| {
                session.tick_messages(0.05);
                for i in 0..session.state.players.len() {
                    let p = &session.state.players[i];
                    if p.hp > 0
                        && matches!(p.campaign, Some(CampaignActor::Hostile { kind, .. }) if kind != EnemyKind::Surveyor)
                    {
                        let damage = p.hp + p.armor;
                        session.state.environmental_self_damage(i, damage);
                    }
                }
                // Down in the second sluice channel beside the catwalk,
                // below the pump tower's lip: where a live scripted agent
                // once stood for minutes when the channels were a trap.
                let me = session
                    .state
                    .players
                    .iter_mut()
                    .find(|p| p.id == id)
                    .unwrap();
                [me.x, me.y, me.z] = [-41.7, 0.6 + PLAYER_FLOOR_Y, -2.4];
            },
            |state| state.m20.as_ref().is_some_and(|f| !f.completed.is_empty()),
            sight_only,
            1_800,
        );
        assert!(
            run.departed,
            "the sluice lesson completes after finding the Surveyor (sight_only {sight_only})"
        );
        assert!(run.killed >= 1);
    }
}

#[test]
fn free_agent_holds_the_pier_on_assisted() {
    assert_completes(CampaignDifficulty::Assisted);
}

#[test]
fn free_agent_holds_the_pier_on_standard() {
    assert_completes(CampaignDifficulty::Standard);
}

#[test]
fn free_agent_holds_the_pier_on_severe() {
    assert_completes(CampaignDifficulty::Severe);
}
