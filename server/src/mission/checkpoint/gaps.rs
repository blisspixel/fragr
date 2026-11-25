//! Checkpoint gaps measured on every campaign level.
//!
//! One solo run per level, played by the carried-arsenal route controller the
//! late-campaign route tests use (`late_routes.rs`): the shared mission
//! controller, tell reading and an accurate-aim combat action. This is
//! authoring evidence about where the checkpoints fall on a played route, not
//! fresh-player acceptance. A death spends a continue at once, so play time
//! lost to a death is measured from the save the retry returned to.
//!
//! `cargo test -p localexception-server --release --lib checkpoint_gap_survey -- --ignored --nocapture`
//! prints the table; `LOCALEXCEPTION_CHECKPOINT_GAPS=<path>` also writes it as JSON.
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

/// Full-state authoring recovery, not a fresh-player perception model. After
/// five seconds without damage dealt or two metres of movement, search for
/// the encounter's remaining actors. Each objective starts a fresh search.
#[derive(Default)]
struct RouteRecovery {
    objective: Option<(u32, MissionPhase, String)>,
    progressed_at: u64,
    damage: u32,
    position: Option<[f32; 2]>,
    searching: bool,
}

impl RouteRecovery {
    fn observe(
        &mut self,
        tick: u64,
        objective: (u32, MissionPhase, &str),
        position: [f32; 3],
        damage: u32,
    ) -> bool {
        if self
            .objective
            .as_ref()
            .map(|(attempt, phase, id)| (*attempt, *phase, id.as_str()))
            != Some(objective)
        {
            self.objective = Some((objective.0, objective.1, objective.2.into()));
            self.progressed_at = tick;
            self.position = None;
            self.searching = false;
        }
        if self
            .position
            .is_none_or(|p| (p[0] - position[0]).hypot(p[1] - position[2]) > 2.0)
            || self.damage != damage
        {
            self.position = Some([position[0], position[2]]);
            self.damage = damage;
            self.progressed_at = tick;
        }
        self.searching |= tick.saturating_sub(self.progressed_at) >= 100;
        self.searching
    }
}

fn route_objective(
    state: &crate::protocol::MissionState,
) -> Option<&crate::protocol::MissionObjective> {
    [
        state.m02.as_ref().and_then(|f| f.current.as_ref()),
        state.m03.as_ref().and_then(|f| f.current.as_ref()),
        state.m04.as_ref().and_then(|f| f.current.as_ref()),
        state.m05.as_ref().and_then(|f| f.current.as_ref()),
        state.m06.as_ref().and_then(|f| f.current.as_ref()),
        state.m07.as_ref().and_then(|f| f.current.as_ref()),
        state.m08.as_ref().and_then(|f| f.current.as_ref()),
        state.m09.as_ref().and_then(|f| f.current.as_ref()),
        state.m10.as_ref().and_then(|f| f.current.as_ref()),
        state.m11.as_ref().and_then(|f| f.current.as_ref()),
        state.m12.as_ref().and_then(|f| f.current.as_ref()),
        state.m13.as_ref().and_then(|f| f.current.as_ref()),
        state.m14.as_ref().and_then(|f| f.current.as_ref()),
        state.m15.as_ref().and_then(|f| f.current.as_ref()),
        state.m16.as_ref().and_then(|f| f.current.as_ref()),
        state.m17.as_ref().and_then(|f| f.current.as_ref()),
        state.m18.as_ref().and_then(|f| f.current.as_ref()),
        state.m19.as_ref().and_then(|f| f.current.as_ref()),
        state.m20.as_ref().and_then(|f| f.current.as_ref()),
    ]
    .into_iter()
    .flatten()
    .next()
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
    let mut recovery = RouteRecovery::default();
    let mut supply_target = SupplyDetour::default();
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
        let me = snapshot.players.iter().find(|p| p.id == id).unwrap();
        let objective = route_objective(&state);
        let departing = objective.is_some_and(|o| o.id == "party_departed");
        let exploring = recovery.observe(
            session.state.tick,
            (
                state.attempt,
                state.phase,
                objective.map_or("", |o| o.id.as_str()),
            ),
            [player.x, player.y, player.z],
            me.damage,
        );
        let search_range = loadout
            .weapons
            .iter()
            .copied()
            .filter(|weapon| loadout.shots(*weapon).is_none_or(|shots| shots > 0))
            .map(WeaponType::range_units)
            .fold(20.0_f32, f32::max);
        let choose = |snapshot: &crate::protocol::Snapshot| {
            let mut combat = control_action_with_target_filter(
                id,
                snapshot,
                Some(&loadout),
                Action::default(),
                departing,
                |me, other| {
                    let awake = matches!(other.campaign, Some(CampaignActor::Hostile { phase, .. }) if !matches!(phase, EnemyPhase::Idle | EnemyPhase::Dead));
                    !futile.skips(other.id, session.state.tick)
                        && (other.x - me.x).hypot(other.z - me.z)
                            <= if exploring {
                                search_range
                            } else if awake {
                                AWAKE_RANGE
                            } else {
                                20.0
                            }
                        && (exploring
                            || crate::combat::line_of_sight(
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
                            ))
                },
            );
            if player.hp < 70 && !departing {
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
            combat
        };
        let combat = reachable_choice(
            navigation.as_ref().unwrap(),
            [player.x, player.y - crate::sim::PLAYER_FLOOR_Y, player.z],
            &snapshot,
            &mut supply_target,
            choose,
        );
        let visible_target = combat
            .look_at
            .as_ref()
            .and_then(|look| look.player_id)
            .and_then(|id| snapshot.players.iter().find(|p| p.id == id))
            .is_some_and(|target| {
                crate::combat::line_of_sight(
                    [
                        player.x,
                        player.y - crate::sim::PLAYER_FLOOR_Y + crate::movement::EYE_HEIGHT,
                        player.z,
                    ],
                    [
                        target.x,
                        target.y - crate::sim::PLAYER_FLOOR_Y
                            + crate::combat::aim_height(target.campaign),
                        target.z,
                    ],
                    &arena.solids,
                )
            });
        // Visible ineffective pursuits need the original combat intent;
        // navigation can replace it with a waypoint. Occluded recovery
        // targets instead get time to reach that waypoint before being timed.
        if visible_target {
            futile.observe(&snapshot, &combat);
        }
        let mut action = client.steer_with_equipment(
            &mut navigator,
            navigation.as_ref().unwrap(),
            id,
            &snapshot,
            combat,
            Some(&loadout),
        );
        if !visible_target {
            futile.observe(&snapshot, &action);
        }
        if action.fire
            && action
                .look_at
                .as_ref()
                .is_some_and(|look| look.player_id.is_some())
        {
            action.left = (session.state.tick / 20).is_multiple_of(2);
            action.right = !action.left;
        }
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

/// A supply behind a closed gate must not hold the survey off the objective
/// that opens it. Optional detours must also permit returning: a one-way
/// drop to ammunition must not strand the route outside a sealed arena. A
/// search that runs out of budget is inconclusive and retains its intent.
/// This only filters pickup intent, never a shot at a world control or actor.
fn reachable_supply(
    world: &Navigation,
    feet: [f32; 3],
    pickups: &[crate::protocol::PickupState],
    mut action: Action,
) -> Action {
    use crate::navigation::{RouteStatus, SEARCH_LIMIT};
    let Some(look) = action
        .look_at
        .as_ref()
        .filter(|look| look.player_id.is_none())
    else {
        return action;
    };
    let (Some(x), Some(y), Some(z)) = (look.x, look.y, look.z) else {
        return action;
    };
    if !pickups
        .iter()
        .any(|p| p.available && [p.x, p.y, p.z] == [x, y, z])
    {
        return action;
    }
    let unreachable = world.coordinate_floor([x, y, z]).is_none_or(|floor| {
        matches!(
            world.route(feet, [x, floor, z], SEARCH_LIMIT).status,
            RouteStatus::Unreachable | RouteStatus::InvalidPoint
        ) || matches!(
            world.route([x, floor, z], feet, SEARCH_LIMIT).status,
            RouteStatus::Unreachable | RouteStatus::InvalidPoint
        )
    });
    if unreachable {
        action.look_at = None;
        action.forward = false;
    }
    action
}

#[derive(Default)]
struct SupplyDetour {
    target: Option<String>,
    previous: Option<String>,
    changed_at: u64,
    committed: bool,
}

/// Keep choosing through the same inventory policy after a proven-unreachable
/// supply is rejected. Otherwise a nearer locked supply can cancel a useful
/// detour halfway round its cover and trap the route in a movement loop.
fn reachable_choice(
    world: &Navigation,
    feet: [f32; 3],
    snapshot: &crate::protocol::Snapshot,
    retained: &mut SupplyDetour,
    choose: impl Fn(&crate::protocol::Snapshot) -> Action,
) -> Action {
    let pickup_for = |action: &Action| {
        let look = action
            .look_at
            .as_ref()
            .filter(|look| look.player_id.is_none())?;
        snapshot.pickups.iter().find(|pickup| {
            pickup.available
                && [Some(pickup.x), Some(pickup.y), Some(pickup.z)] == [look.x, look.y, look.z]
        })
    };
    let fresh = choose(snapshot);
    let Some(selected) = pickup_for(&fresh) else {
        *retained = SupplyDetour::default();
        return fresh;
    };
    if !retained.committed && snapshot.tick.saturating_sub(retained.changed_at) > 200 {
        *retained = SupplyDetour::default();
    }
    if let Some(previous) = retained
        .target
        .as_ref()
        .filter(|_| retained.committed)
        .and_then(|id| snapshot.pickups.iter().find(|p| p.id == *id && p.available))
    {
        // A needed health pickup can interrupt an ammunition detour. Otherwise
        // keep a still-useful destination while its route goes around cover;
        // Euclidean nearest-supply selection can alternate forever on that walk.
        if selected.kind != "health" || previous.kind == "health" {
            let mut committed = snapshot.clone();
            for pickup in &mut committed.pickups {
                pickup.available &= pickup.id == previous.id;
            }
            let action = choose(&committed);
            if pickup_for(&action).is_some_and(|p| p.id == previous.id)
                && reachable_supply(world, feet, &committed.pickups, action.clone()).look_at
                    == action.look_at
            {
                return action;
            }
        }
    }
    if retained.committed {
        *retained = SupplyDetour::default();
    }
    let mut observed = std::borrow::Cow::Borrowed(snapshot);
    loop {
        let action = choose(&observed);
        let filtered = reachable_supply(world, feet, &observed.pickups, action.clone());
        if filtered.look_at == action.look_at {
            let next = pickup_for(&action).map(|p| p.id.clone());
            if next.is_none() {
                *retained = SupplyDetour::default();
            } else if next != retained.target {
                // Preserve ordinary inventory choices until a recent A-B-A
                // reversal proves oscillation. Committing every first choice
                // changes healthy combat/resupply paths in other levels.
                retained.committed = next == retained.previous;
                retained.previous = retained.target.take();
                retained.target = next;
                retained.changed_at = snapshot.tick;
            }
            return action;
        }
        let look = action.look_at.unwrap();
        for pickup in &mut observed.to_mut().pickups {
            if [Some(pickup.x), Some(pickup.y), Some(pickup.z)] == [look.x, look.y, look.z] {
                pickup.available = false;
            }
        }
    }
}

#[test]
fn persons_unknown_supply_detours_finish_across_seeds() {
    for seed in [40, 41, 42, 43] {
        let row = play(MissionId::PersonsUnknown, seed);
        assert_eq!(row.outcome, "departed", "seed {seed}: {row:?}");
        assert!(row.longest_gap_seconds <= 180.0, "seed {seed}: {row:?}");
    }
}

#[test]
fn supply_detours_keep_their_destination_and_release_obsolete_targets() {
    use crate::movement::{Arena, Solid};
    use crate::protocol::{LookAt, PickupState, Snapshot, SupplyClaim};
    fn nearest(snapshot: &Snapshot, feet: [f32; 3]) -> Action {
        let pickup = snapshot
            .pickups
            .iter()
            .filter(|p| p.available)
            .min_by(|a, b| {
                (a.x - feet[0])
                    .hypot(a.z - feet[2])
                    .total_cmp(&(b.x - feet[0]).hypot(b.z - feet[2]))
            });
        Action {
            forward: pickup.is_some(),
            look_at: pickup.map(|p| LookAt {
                x: Some(p.x),
                y: Some(p.y),
                z: Some(p.z),
                player_id: None,
            }),
            ..Default::default()
        }
    }
    let world = Navigation::new(Arena {
        half: 8.0,
        solids: vec![Solid {
            min_x: 0.0,
            max_x: 0.5,
            min_z: -8.0,
            max_z: 8.0,
            bottom: 0.0,
            top: 3.0,
        }],
    })
    .unwrap();
    let pickup = |id: &str, x, z| PickupState {
        id: id.into(),
        x,
        y: 0.4,
        z,
        available: true,
        claim: SupplyClaim::Contested,
        pool: None,
        kind: "ammo".into(),
        weapon: String::new(),
        amount: None,
        dropped: false,
    };
    let mut snapshot = crate::sim::GameState::default().snapshot();
    snapshot.pickups = vec![
        pickup("closed", 1.5, 0.0),
        pickup("north", -6.0, 6.0),
        pickup("south", -6.0, -6.0),
    ];
    let mut retained = SupplyDetour::default();
    let start = [-1.0, 0.0, 0.0];
    let first = reachable_choice(&world, start, &snapshot, &mut retained, |s| {
        nearest(s, start)
    });
    assert_eq!(
        first.look_at.unwrap().z,
        Some(6.0),
        "skip the nearer closed supply"
    );
    assert_eq!(retained.target.as_deref(), Some("north"));
    assert!(
        snapshot.pickups.iter().all(|p| p.available),
        "selection never claims or hides real supplies"
    );
    let detour = [-4.0, 0.0, -2.0];
    assert_eq!(nearest(&snapshot, detour).look_at.unwrap().z, Some(-6.0));
    let switched = reachable_choice(&world, detour, &snapshot, &mut retained, |s| {
        nearest(s, detour)
    });
    assert_eq!(
        switched.look_at.unwrap().z,
        Some(-6.0),
        "ordinary fresh supply choices stay unchanged"
    );
    assert!(!retained.committed);
    reachable_choice(&world, start, &snapshot, &mut retained, |s| {
        nearest(s, start)
    });
    assert!(
        retained.committed,
        "a recent north-south-north reversal establishes oscillation"
    );
    let kept = reachable_choice(&world, detour, &snapshot, &mut retained, |s| {
        nearest(s, detour)
    });
    assert_eq!(
        kept.look_at.unwrap().z,
        Some(6.0),
        "continue around cover instead of reversing destinations"
    );
    let mut delayed = SupplyDetour::default();
    let mut later = snapshot.clone();
    for (tick, feet) in [(0, start), (1, detour), (202, start)] {
        later.tick = tick;
        reachable_choice(&world, feet, &later, &mut delayed, |s| nearest(s, feet));
    }
    assert!(
        !delayed.committed,
        "old reversals do not establish current oscillation"
    );
    // A new combat action interrupts the detour without changing its aim.
    let shot = Action {
        fire: true,
        look_at: Some(LookAt {
            player_id: Some(Uuid::from_u128(50)),
            ..Default::default()
        }),
        ..Default::default()
    };
    let actual = reachable_choice(&world, detour, &snapshot, &mut retained, |_| shot.clone());
    assert_eq!(actual.look_at, shot.look_at);
    assert!(actual.fire);
    assert!(
        retained.target.is_none(),
        "combat clears prior supply history"
    );
    for feet in [start, detour, start] {
        reachable_choice(&world, feet, &snapshot, &mut retained, |s| nearest(s, feet));
    }
    assert!(retained.committed);
    snapshot.pickups[2].kind = "health".into();
    let health = reachable_choice(&world, detour, &snapshot, &mut retained, |s| {
        nearest(s, detour)
    });
    assert_eq!(
        health.look_at.unwrap().z,
        Some(-6.0),
        "urgent health may interrupt ammunition collection"
    );
    snapshot.pickups[2].available = false;
    let replacement = reachable_choice(&world, detour, &snapshot, &mut retained, |s| {
        nearest(s, detour)
    });
    assert_eq!(
        replacement.look_at.unwrap().z,
        Some(6.0),
        "a claimed target releases the commitment"
    );
    // Still present but no longer useful: the chooser stops requesting it.
    let finished = reachable_choice(&world, detour, &snapshot, &mut retained, |_| {
        Action::default()
    });
    assert!(finished.look_at.is_none());
    snapshot.pickups[1].available = false;
    let closed_only = reachable_choice(&world, detour, &snapshot, &mut retained, |s| {
        nearest(s, detour)
    });
    assert!(closed_only.look_at.is_none());
    assert!(retained.target.is_none());
}

/// Globally preferring objectives over supplies strands this route at arrival.
#[test]
fn common_carrier_keeps_reachable_supply_detours() {
    let row = play(MissionId::CommonCarrier, 41);
    assert_eq!(row.outcome, "departed", "{row:?}");
    assert!(row.longest_gap_seconds <= 180.0, "{row:?}");
}

#[test]
fn civic_pressure_valve_departs_with_the_temporary_blade() {
    let (row, session) = play_until(MissionId::CivicPressureValve, 41, true, |_| false);
    let player = session
        .state
        .players
        .iter()
        .find(|p| p.id == Uuid::from_u128(5270))
        .unwrap();
    assert!(player.inventory.owns(WeaponType::ArticleBlade));
    let exit = crate::mission::run_file::SavedEntry::from_player(player).unwrap();
    assert!(!exit.equipment.weapons.contains(&WeaponType::ArticleBlade));
    assert_eq!(row.outcome, "departed", "{row:?}");
    assert!(row.longest_gap_seconds <= 180.0, "{row:?}");
}

#[test]
fn route_recovery_waits_for_quiet_and_resets_when_the_objective_advances() {
    let mut recovery = RouteRecovery::default();
    let first = (1, MissionPhase::InProgress, "hall");
    let next = (1, MissionPhase::InProgress, "gallery");
    assert!(!recovery.observe(1, first, [0.0; 3], 0));
    assert!(!recovery.observe(80, first, [3.0, 0.0, 0.0], 0));
    assert!(!recovery.observe(150, first, [3.0, 0.0, 0.0], 10));
    assert!(!recovery.observe(249, first, [3.0, 0.0, 0.0], 10));
    assert!(recovery.observe(250, first, [3.0, 0.0, 0.0], 10));
    assert!(recovery.observe(251, first, [6.0, 0.0, 0.0], 20));
    assert!(!recovery.observe(252, next, [6.0, 0.0, 0.0], 20));
    assert!(!recovery.observe(351, next, [6.0, 0.0, 0.0], 20));
    assert!(recovery.observe(352, next, [6.0, 0.0, 0.0], 20));
    assert!(!recovery.observe(353, (2, next.1, next.2), [6.0, 0.0, 0.0], 20));
}

#[test]
fn archive_and_berth_routes_depart_across_seeds() {
    for seed in [40, 41, 42, 43] {
        for mission in [MissionId::CustodianOfRecord, MissionId::PassengerManifest] {
            let row = play(mission, seed);
            assert_eq!(row.outcome, "departed", "seed {seed}: {row:?}");
            assert!(row.longest_gap_seconds <= 180.0, "seed {seed}: {row:?}");
        }
    }
}

#[test]
fn distant_and_occluded_campaign_encounters_finish_across_seeds() {
    for seed in [40, 41, 42, 43] {
        for mission in [
            MissionId::DeclaredGoods,
            MissionId::LaunchAuthority,
            MissionId::CivicPressureValve,
        ] {
            let row = play(mission, seed);
            assert_eq!(row.outcome, "departed", "seed {seed}: {row:?}");
            assert!(row.longest_gap_seconds <= 180.0, "seed {seed}: {row:?}");
        }
    }
}

#[test]
fn supply_filter_rejects_closed_routes_but_keeps_detours_and_other_intent() {
    use crate::movement::{Arena, Solid};
    use crate::protocol::{LookAt, PickupState, SupplyClaim};
    let same = |actual: Action, expected: &Action| {
        assert_eq!(
            serde_json::to_value(actual).unwrap(),
            serde_json::to_value(expected).unwrap()
        );
    };
    let feet = [-4.0, 0.0, 0.0];
    let pickup = PickupState {
        claim: SupplyClaim::Personal,
        pool: None,
        id: "health".into(),
        kind: "health".into(),
        weapon: String::new(),
        amount: None,
        x: 4.0,
        y: 0.4,
        z: 0.0,
        available: true,
        dropped: false,
    };
    let action = Action {
        forward: true,
        reload: true,
        weapon_swap: Some(WeaponType::Tack),
        look_at: Some(LookAt {
            x: Some(pickup.x),
            y: Some(pickup.y),
            z: Some(pickup.z),
            player_id: None,
        }),
        ..Default::default()
    };
    let pickups = [pickup];
    let wall = Solid {
        min_x: -0.5,
        max_x: 0.5,
        min_z: -8.0,
        max_z: 8.0,
        bottom: 0.0,
        top: 3.0,
    };
    let closed = Navigation::new(Arena {
        half: 8.0,
        solids: vec![wall],
    })
    .unwrap();
    let blocked = reachable_supply(&closed, feet, &pickups, action.clone());
    assert!(blocked.look_at.is_none());
    assert!(!blocked.forward);
    assert!(blocked.reload);
    assert_eq!(blocked.weapon_swap, action.weapon_swap);

    let ledge = Navigation::new(Arena {
        half: 8.0,
        solids: vec![Solid {
            min_x: -8.0,
            max_x: 0.0,
            min_z: -8.0,
            max_z: 8.0,
            bottom: 0.0,
            top: 3.0,
        }],
    })
    .unwrap();
    let above = [-4.0, 3.0, 0.0];
    assert_eq!(
        ledge
            .route(above, [4.0, 0.0, 0.0], crate::navigation::SEARCH_LIMIT)
            .status,
        crate::navigation::RouteStatus::Complete
    );
    let stranded = reachable_supply(&ledge, above, &pickups, action.clone());
    assert!(
        stranded.look_at.is_none(),
        "optional supplies cannot strand the route below a one-way drop"
    );
    assert!(stranded.reload);

    let open = Navigation::new(Arena {
        half: 8.0,
        solids: vec![Solid {
            min_z: -2.0,
            max_z: 2.0,
            ..wall
        }],
    })
    .unwrap();
    assert!(!open.walkable(feet, [4.0, 0.0, 0.0]));
    same(
        reachable_supply(&open, feet, &pickups, action.clone()),
        &action,
    );
    same(
        reachable_supply(&closed, feet, &[], action.clone()),
        &action,
    );
    let actor = Action {
        look_at: Some(LookAt {
            player_id: Some(Uuid::from_u128(7)),
            ..Default::default()
        }),
        ..action.clone()
    };
    same(
        reachable_supply(&closed, feet, &pickups, actor.clone()),
        &actor,
    );

    let outside = PickupState {
        x: 20.0,
        ..pickups[0].clone()
    };
    let invalid = Action {
        look_at: Some(LookAt {
            x: Some(outside.x),
            ..action.look_at.clone().unwrap()
        }),
        ..action
    };
    assert!(reachable_supply(&closed, feet, &[outside], invalid)
        .look_at
        .is_none());
}

#[test]
#[ignore = "per-level survey: cargo test -p localexception-server --release --lib checkpoint_gap_survey -- --ignored --nocapture"]
fn checkpoint_gap_survey() {
    let only: Option<String> = std::env::var("LOCALEXCEPTION_CHECKPOINT_LEVEL").ok();
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
    if let Ok(path) = std::env::var("LOCALEXCEPTION_CHECKPOINT_GAPS") {
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

/// Navigation must not hide an ineffective combat pursuit from the route's
/// target tracker. Both routes previously stayed stuck until the survey cap.
#[test]
fn late_campaign_routes_finish_and_keep_checkpoint_gaps_bounded() {
    for mission in [MissionId::WeightOfPermission, MissionId::PlannedWorks] {
        let row = play(mission, 41);
        assert_eq!(row.outcome, "departed", "{row:?}");
        assert!(row.longest_gap_seconds <= 180.0, "{row:?}");
    }
}

/// The focused Auditor lesson preserves the earned full-level route.
#[test]
fn custodian_of_record_lesson_routes_depart_across_seeds() {
    for seed in 40..44 {
        let row = play(MissionId::CustodianOfRecord, seed);
        eprintln!("Auditor lesson seed {seed}: {row:?}");
        assert_eq!(row.outcome, "departed", "seed {seed}: {row:?}");
        assert_eq!(row.deaths, 0, "seed {seed}: {row:?}");
        assert!(row.longest_gap_seconds <= 180.0, "seed {seed}: {row:?}");
    }
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
