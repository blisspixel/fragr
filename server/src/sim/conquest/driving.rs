//! Simple, honest vehicle use for Conquest rule bots: a bot whose ordered
//! site is a long walk away takes an empty jeep standing near it, drives the
//! shared navigation route toward the site, and gets out short of it to take
//! the site on foot. It never boards a vehicle anyone sits in, never takes a
//! seat a person on its side is close enough to want, and gets out of a jeep
//! that is wrecked or stuck, so the seat goes back to the room.
//!
//! The driving is the ordinary seat rules (`sim/vehicle.rs`): an interact
//! press to board and to get out, the movement keys to steer, a held jump to
//! brake. Routes come from the map's walking navigation, replanned on a slow
//! cadence; the jeep steers for the first route point a few metres ahead.

use super::{BotController, BotIntent, CapturePoint, GameState, Player, PLAYER_FLOOR_Y};
use crate::protocol::{Action, Role, VehicleKind, VehicleSeat};
use std::collections::HashMap;
use std::f32::consts::{FRAC_PI_2, PI, TAU};
use uuid::Uuid;

/// An ordered site at least this far off is worth a jeep, in metres.
pub(super) const BOARD_FAR: f32 = 60.0;
/// A bot walks to an empty jeep this close to it.
const BOARD_REACH: f32 = 30.0;
/// A jeep further than this from the site than the bot is never helps.
const BOARD_DETOUR: f32 = 10.0;
/// A person on the bot's side this close to a jeep has it.
const LEAVE_FOR_PEOPLE: f32 = 15.0;
/// Get out this close to the site.
const DISMOUNT: f32 = 14.0;
/// Brake from this close.
const BRAKE: f32 = 26.0;
/// Speed above which the jeep brakes for the stop, metres a second.
const BRAKE_SPEED: f32 = 5.0;
/// A jeep that has not made this much ground in `STUCK_TICKS` is stuck:
/// get out and walk. Ground, not speed: a jeep nosed into a wall picks up
/// speed every tick and loses it against the wall.
const STUCK_PROGRESS: f32 = 2.0;
const STUCK_TICKS: u32 = 60;
/// A jeep below this much of its plating is left before it burns.
const WRECK_HP: i32 = 100;
/// Ticks between route searches for one driver.
const REPLAN_TICKS: u64 = 40;
/// The jeep steers for the first route point at least this far ahead.
const LOOKAHEAD: f32 = 7.0;
/// Steering dead zone, radians.
const STEER_SLACK: f32 = 0.08;
/// A turn this sharp at speed lifts off the throttle.
const SHARP_TURN: f32 = 1.1;
const SHARP_TURN_SPEED: f32 = 8.0;

/// One rule bot's drive: its route and how long it has crawled.
#[derive(Debug, Clone, Default)]
pub(in crate::sim) struct Drive {
    route: Vec<[f32; 3]>,
    planned_at: Option<u64>,
    /// Where the jeep last made ground, and ticks since.
    anchor: Option<[f32; 3]>,
    slow_ticks: u32,
}

fn flat(a: [f32; 3], b: [f32; 3]) -> f32 {
    (a[0] - b[0]).hypot(a[2] - b[2])
}

fn feet(player: &Player) -> [f32; 3] {
    [player.x, player.y - PLAYER_FLOOR_Y, player.z]
}

/// A rising-edge press, every other tick.
fn press(tick: u64) -> bool {
    tick.is_multiple_of(2)
}

impl GameState {
    /// Carry each seated rule bot's drive forward one tick: how long it has
    /// crawled, and a fresh route on its slow cadence. Off a seat, the drive
    /// is forgotten.
    pub(super) fn plan_drives(
        &self,
        controllers: &[BotController],
        mut previous: HashMap<Uuid, Drive>,
        site_of: impl Fn(Uuid) -> Option<[f32; 3]>,
    ) -> HashMap<Uuid, Drive> {
        let mut drives = HashMap::new();
        let world = self.map.navigation();
        for controller in controllers {
            let id = controller.player_id;
            let Some((index, VehicleSeat::Driver)) = self.vehicle_seat(id) else {
                continue;
            };
            let jeep = &self.vehicles[index].state;
            let mut drive = previous.remove(&id).unwrap_or_default();
            if drive
                .anchor
                .is_none_or(|anchor| flat(anchor, jeep.position) > STUCK_PROGRESS)
            {
                drive.anchor = Some(jeep.position);
                drive.slow_ticks = 0;
            } else {
                drive.slow_ticks = drive.slow_ticks.saturating_add(1);
            }
            let due = drive
                .planned_at
                .is_none_or(|at| self.tick.saturating_sub(at) >= REPLAN_TICKS);
            if let Some(site) = site_of(id).filter(|_| due) {
                let route = world.route(jeep.position, site, crate::navigation::SEARCH_LIMIT);
                drive.route = route.points;
                drive.planned_at = Some(self.tick);
            }
            drives.insert(id, drive);
        }
        drives
    }
}

impl BotController {
    /// A driver's controls toward `site`, or the press that gets it out.
    pub(super) fn drive_intent(
        &self,
        state: &GameState,
        index: usize,
        seat: VehicleSeat,
        site: &CapturePoint,
        drive: Option<&Drive>,
    ) -> BotIntent {
        let jeep = &state.vehicles[index].state;
        let tick = state.tick;
        let leave = |action: Action| BotIntent {
            action: Action {
                jump: jeep.speed.abs() > crate::vehicles::ENTRY_SPEED * 0.5,
                interact: jeep.speed.abs() <= crate::vehicles::ENTRY_SPEED && press(tick),
                ..action
            },
            goal: None,
        };
        let arrived = flat(jeep.position, site.position) <= DISMOUNT;
        let slow = drive.map_or(0, |drive| drive.slow_ticks);
        if slow > STUCK_TICKS && (slow / STUCK_TICKS).is_multiple_of(2) {
            // Wedged with no clear door to get out by: back off the wall,
            // wheel turned, then try the door again.
            return BotIntent {
                action: Action {
                    back: true,
                    right: true,
                    ..Action::default()
                },
                goal: None,
            };
        }
        if seat != VehicleSeat::Driver || arrived || slow > STUCK_TICKS || jeep.hp < WRECK_HP {
            return leave(Action::default());
        }
        let target = drive
            .and_then(|drive| {
                drive
                    .route
                    .iter()
                    .find(|point| flat(jeep.position, **point) >= LOOKAHEAD)
                    .copied()
            })
            .unwrap_or(site.position);
        let heading = (target[2] - jeep.position[2]).atan2(target[0] - jeep.position[0]);
        let turn = (heading - jeep.yaw + PI).rem_euclid(TAU) - PI;
        let distance = flat(jeep.position, site.position);
        let sharp = turn.abs() > SHARP_TURN && jeep.speed > SHARP_TURN_SPEED;
        let action = Action {
            forward: !sharp,
            right: turn > STEER_SLACK,
            left: turn < -STEER_SLACK,
            jump: distance <= BRAKE && jeep.speed > BRAKE_SPEED,
            ..Action::default()
        };
        BotIntent { action, goal: None }
    }

    /// An empty jeep worth walking to for an order `site` a long way off:
    /// close to the bot, no further from the site, nobody in it and no
    /// person on the bot's side near enough to want it.
    pub(super) fn jeep_for(
        &self,
        state: &GameState,
        bot: &Player,
        site: [f32; 3],
    ) -> Option<usize> {
        let here = feet(bot);
        let walk = flat(here, site);
        if walk < BOARD_FAR {
            return None;
        }
        state
            .vehicles
            .iter()
            .enumerate()
            .filter(|(_, vehicle)| {
                let jeep = &vehicle.state;
                jeep.kind == VehicleKind::Jeep
                    && jeep.hp >= WRECK_HP
                    && jeep.driver.is_none()
                    && jeep.gunner.is_none()
                    && jeep.speed.abs() <= crate::vehicles::ENTRY_SPEED
                    && (jeep.position[1] - here[1]).abs() <= 2.0
                    && flat(here, jeep.position) <= BOARD_REACH
                    && flat(jeep.position, site) <= walk + BOARD_DETOUR
                    && !state.players.iter().any(|other| {
                        other.id != bot.id
                            && matches!(other.role, Role::Human)
                            && other.team == bot.team
                            && state.contact_eligible(other)
                            && flat(feet(other), jeep.position) <= LEAVE_FOR_PEOPLE
                    })
            })
            .min_by(|(_, a), (_, b)| {
                flat(here, a.state.position).total_cmp(&flat(here, b.state.position))
            })
            .map(|(index, _)| index)
    }

    /// Walk to the jeep at `index` and press to board once beside it.
    pub(super) fn board_intent(&self, state: &GameState, bot: &Player, index: usize) -> BotIntent {
        let jeep = &state.vehicles[index].state;
        let reach = crate::vehicles::entry_radius(jeep.kind) - 0.2;
        let here = feet(bot);
        if flat(here, jeep.position) <= reach {
            return BotIntent {
                action: Action {
                    interact: press(state.tick),
                    // Another bot can reach the same empty jeep this tick.
                    // Ask for its wheel, never the fallback gunner seat.
                    seat: Some(VehicleSeat::Driver),
                    ..Action::default()
                },
                goal: None,
            };
        }
        // Beside the door, on the bot's side of the hull: the nose and tail
        // stand further from the centre than a body can board from.
        let side = [FRAC_PI_2, -FRAC_PI_2]
            .map(|turn| {
                crate::vehicles::local_point(jeep.position, jeep.yaw + turn, [1.5, 0.0, 0.0])
            })
            .into_iter()
            .min_by(|a, b| flat(here, *a).total_cmp(&flat(here, *b)))
            .unwrap_or(jeep.position);
        BotIntent {
            action: super::super::face_flag_goal(bot, side),
            goal: Some(crate::navigation::NavigationGoal {
                feet: side,
                combat: false,
            }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{GameMode, Team};
    use crate::sim::{BotBehavior, MapKind, MatchConfig};

    /// Holdfast in Conquest with one Union rule bot six metres beside the
    /// harbour jeep, and a Union person far away.
    fn harbour() -> (GameState, BotController, usize) {
        let mut state = GameState::with_map(MapKind::HoldfastAtoll, false);
        state.apply_config(MatchConfig {
            rules: crate::rules::RuleSet::new(GameMode::Conquest, &[], false).unwrap(),
            ..MatchConfig::default()
        });
        state.start_round();
        let bot = BotController::new(Uuid::from_u128(1), BotBehavior::Balanced);
        state.add_player(bot.player_id, "Driver".into(), Role::Agent);
        state.add_player(Uuid::from_u128(2), "Person".into(), Role::Human);
        let index = state
            .vehicles
            .iter()
            .position(|vehicle| {
                vehicle.state.kind == VehicleKind::Jeep && vehicle.state.position[0] < -100.0
            })
            .expect("the harbour jeep");
        let jeep = state.vehicles[index].state.position;
        for (player, offset) in state.players.iter_mut().zip([6.0, 80.0]) {
            player.team = Some(Team::Union);
            player.respawn_timer = None;
            player.x = jeep[0] + offset;
            player.z = jeep[2];
            player.y = jeep[1] + PLAYER_FLOOR_Y;
        }
        (state, bot, index)
    }

    const VILLAGE: [f32; 3] = [-100.0, 3.0, -35.0];

    #[test]
    fn a_far_site_and_an_empty_jeep_nearby_is_a_ride() {
        let (state, bot, index) = harbour();
        let me = &state.players[0];
        assert_eq!(bot.jeep_for(&state, me, VILLAGE), Some(index));
        // A site close by is walked to.
        let near = [me.x + 20.0, me.y - PLAYER_FLOOR_Y, me.z];
        assert_eq!(bot.jeep_for(&state, me, near), None);
        // Walking to it, the bot heads for the door, then presses to board.
        let walk = bot.board_intent(&state, me, index);
        let side = walk.goal.expect("it walks to the jeep").feet;
        let jeep = state.vehicles[index].state.position;
        assert!(flat(side, jeep) < crate::vehicles::entry_radius(VehicleKind::Jeep));
        assert!(!walk.action.interact);
    }

    #[test]
    fn boarding_requests_the_wheel_without_a_gunner_fallback() {
        let (mut state, bot, index) = harbour();
        let jeep = state.vehicles[index].state.position;
        state.players[0].x = jeep[0];
        state.players[0].z = jeep[2] + crate::vehicles::entry_radius(VehicleKind::Jeep) - 0.3;
        state.tick = 2;
        let board = bot.board_intent(&state, &state.players[0], index);
        assert!(board.action.interact);
        assert_eq!(board.action.seat, Some(VehicleSeat::Driver));
    }

    #[test]
    fn a_jeep_a_person_on_the_side_could_take_is_left_for_them() {
        let (mut state, bot, index) = harbour();
        let jeep = state.vehicles[index].state.position;
        state.players[1].x = jeep[0] - 5.0;
        assert_eq!(bot.jeep_for(&state, &state.players[0], VILLAGE), None);
        // An opponent near it is no reason to leave it.
        state.players[1].team = Some(Team::Coalition);
        assert_eq!(
            bot.jeep_for(&state, &state.players[0], VILLAGE),
            Some(index)
        );
        // A jeep somebody sits in is never boarded.
        state.vehicles[index].assign(VehicleSeat::Gunner, Some(state.players[1].id));
        assert_eq!(bot.jeep_for(&state, &state.players[0], VILLAGE), None);
    }

    #[test]
    fn a_driver_steers_brakes_and_gets_out_at_the_site_or_when_stuck() {
        let (mut state, bot, index) = harbour();
        state.vehicles[index].assign(VehicleSeat::Driver, Some(bot.player_id));
        state.follow_vehicle_seats();
        let site = state.conquest.as_ref().unwrap().points[1].clone();
        assert_eq!(site.id, "village");
        let drive = Drive {
            route: vec![VILLAGE],
            planned_at: Some(0),
            anchor: None,
            slow_ticks: 0,
        };
        // Facing east, the village lies north: a hard turn.
        state.vehicles[index].state.yaw = 0.0;
        let going = bot.drive_intent(&state, index, VehicleSeat::Driver, &site, Some(&drive));
        assert!(going.action.forward && !going.action.interact);
        assert!(
            going.action.left && !going.action.right,
            "it turns for the site"
        );
        // Stuck: it gets out, pressing on alternate ticks.
        let stuck = Drive {
            slow_ticks: STUCK_TICKS + 1,
            ..drive.clone()
        };
        let presses: Vec<bool> = (0..4)
            .map(|tick| {
                state.tick = tick;
                bot.drive_intent(&state, index, VehicleSeat::Driver, &site, Some(&stuck))
                    .action
                    .interact
            })
            .collect();
        assert_eq!(presses, [true, false, true, false]);
        // Still there a door's worth later: no way out, so it backs off the
        // wall and tries again.
        let wedged = Drive {
            slow_ticks: 2 * STUCK_TICKS + 1,
            ..drive.clone()
        };
        let reverse = bot.drive_intent(&state, index, VehicleSeat::Driver, &site, Some(&wedged));
        assert!(reverse.action.back && !reverse.action.forward && !reverse.action.interact);
        // At the site, it brakes and gets out once slow.
        state.vehicles[index].state.position = [VILLAGE[0] + 5.0, VILLAGE[1], VILLAGE[2]];
        state.vehicles[index].state.speed = 9.0;
        state.tick = 0;
        let arriving = bot.drive_intent(&state, index, VehicleSeat::Driver, &site, Some(&drive));
        assert!(arriving.action.jump && !arriving.action.interact);
        state.vehicles[index].state.speed = 0.5;
        let out = bot.drive_intent(&state, index, VehicleSeat::Driver, &site, Some(&drive));
        assert!(out.action.interact);
    }
}
