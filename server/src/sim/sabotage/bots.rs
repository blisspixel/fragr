//! Sabotage rule bots. The attack carries the charge to the round's site,
//! takes it, plants and holds; the defence anchors both sites, rotates to the
//! one under attack, retakes a planted site and defuses. Every bot fights a
//! visible enemy with its own personality first and returns to the objective
//! when the lane is clear. Movement goes through the shared navigator.
use super::{feet, horizontal, spawn_point, Sabotage, DEFUSE_REACH};
use crate::maps::SabotageLayout;
use crate::navigation::NavigationGoal;
use crate::protocol::{Action, ProgressKind, SabotagePhase, SiteId, SupplyClaim, Team, WeaponType};
use crate::sim::{BotController, BotIntent, GameState, PickupKind, Player, PLAYER_FLOOR_Y};
use std::f32::consts::PI;

/// A carrier inside this much of the plant radius stops and plants.
const PLANT_MARGIN: f32 = 0.7;
/// A loose charge or a pickup this close counts as reached.
const ARRIVED: f32 = 0.9;
/// An armed bot detours for a better weapon only this close, with nobody in sight.
const UPGRADE_REACH: f32 = 12.0;
/// A defuser keeps working unless an enemy is this close and in sight.
const WORK_THREAT: f32 = 10.0;
/// A carrier only starts a plant with no enemy in sight this close: one shot
/// would interrupt it.
const PLANT_THREAT: f32 = 20.0;
/// On the way to its stage the attack keeps walking past enemies further than
/// this; chasing a far defender through a door was how attacks died.
const ROUTE_THREAT: f32 = 15.0;
/// A holding fighter stands its ground and only steps in this close.
const HOLD_BREAK: f32 = 8.0;
/// The attack pushes from its stage once gathered, or at the latest this long
/// after the round goes live, so a straggler never runs out the clock.
const PUSH_LATEST_TICKS: u64 = 20 * 40;
/// Gathered: within this of the stage.
const GATHERED: f32 = 12.0;
/// An attacker this close to its site means the push is on.
const PUSHED: f32 = 25.0;
/// The defence calls a site when it sees an attacker this close to it.
const CONTACT_RADIUS: f32 = 30.0;
/// A muster zone's own pad is always within this of its spawn points.
const MUSTER_REACH: f32 = 12.0;
/// Bots do not start fights beyond this, even with a long weapon.
const ENGAGE_MAX: f32 = 45.0;

fn ranged(weapon: WeaponType) -> bool {
    weapon.ammo_pool().is_some()
}

/// The best usable weapon for a fight at `distance`.
fn best_weapon(bot: &Player, distance: f32) -> WeaponType {
    let order: [WeaponType; 6] = if distance < 10.0 {
        [
            WeaponType::Scatter,
            WeaponType::Flechette,
            WeaponType::Tack,
            WeaponType::Rail,
            WeaponType::Shiv,
            WeaponType::Fists,
        ]
    } else if distance < 30.0 {
        [
            WeaponType::Flechette,
            WeaponType::Rail,
            WeaponType::Tack,
            WeaponType::Scatter,
            WeaponType::Shiv,
            WeaponType::Fists,
        ]
    } else {
        [
            WeaponType::Rail,
            WeaponType::Flechette,
            WeaponType::Tack,
            WeaponType::Scatter,
            WeaponType::Shiv,
            WeaponType::Fists,
        ]
    };
    order
        .into_iter()
        .find(|weapon| bot.inventory.usable(*weapon))
        .unwrap_or(WeaponType::Fists)
}

fn armed(bot: &Player) -> bool {
    [
        WeaponType::Tack,
        WeaponType::Flechette,
        WeaponType::Scatter,
        WeaponType::Rail,
    ]
    .into_iter()
    .any(|weapon| bot.inventory.usable(weapon))
}

/// Walk to a point; stop when there.
fn walk(bot: &Player, to: [f32; 3]) -> BotIntent {
    if horizontal(feet(bot), to) <= ARRIVED {
        return BotIntent::default();
    }
    let goal_angle = (to[2] - bot.z).atan2(to[0] - bot.x);
    let diff = (goal_angle - bot.yaw + PI).rem_euclid(2.0 * PI) - PI;
    let action = Action {
        forward: true,
        turn_right: diff > 0.18,
        turn_left: diff < -0.18,
        ..Action::default()
    };
    BotIntent {
        action,
        goal: Some(NavigationGoal {
            feet: to,
            combat: false,
        }),
    }
}

/// Stand still holding Use: a plant or a defuse.
fn work() -> BotIntent {
    BotIntent {
        action: Action {
            interact: true,
            ..Action::default()
        },
        goal: None,
    }
}

impl BotController {
    pub(crate) fn sabotage_intent(&self, state: &GameState, bot: &Player) -> BotIntent {
        let (Some(sab), Some(layout), Some(team)) = (
            state.sabotage.as_ref(),
            state.map.sabotage_layout(),
            bot.team,
        ) else {
            return BotIntent::default();
        };
        if !bot.standing()
            || bot.detached
            || state.round_state != crate::sim::RoundState::Active
            || sab.phase == SabotagePhase::Over
        {
            return BotIntent::default();
        }
        let slot = state
            .players
            .iter()
            .filter(|p| p.contestant() && p.team == Some(team))
            .position(|p| p.id == bot.id)
            .unwrap_or(0);
        let enemy = nearest_visible_enemy(state, bot);
        let swap = |intent: BotIntent, distance: f32| {
            let wanted = best_weapon(bot, distance);
            let mut intent = intent;
            if wanted != bot.weapon {
                intent.action.weapon_swap = Some(wanted);
            }
            intent
        };

        if sab.phase == SabotagePhase::Muster {
            // Only the spawn zone's pad: muster holds everyone inside it.
            if let Some(pad) = supply(state, bot, MUSTER_REACH, !armed(bot)) {
                return swap(walk(bot, pad), 20.0);
            }
            let [x, floor, z, _] = spawn_point(layout, team.index(), slot);
            return swap(walk(bot, [x, floor, z]), 20.0);
        }

        let objective = match team {
            Team::Coalition => self.attack(state, sab, layout, bot, slot, enemy),
            Team::Union => self.defend(state, sab, layout, bot, slot, enemy),
        };
        let distance = enemy.map_or(20.0, |(_, d)| d);
        if let Some(intent) = objective {
            return swap(intent, distance);
        }
        // Nobody in sight and nothing pressing: arm up or upgrade nearby.
        if let Some(pad) = supply(state, bot, UPGRADE_REACH, !armed(bot)) {
            return swap(walk(bot, pad), distance);
        }
        swap(BotIntent::default(), distance)
    }

    /// The objective intent for an attacker, or None to fight what it sees.
    fn attack(
        &self,
        state: &GameState,
        sab: &Sabotage,
        layout: &SabotageLayout,
        bot: &Player,
        slot: usize,
        enemy: Option<(&Player, f32)>,
    ) -> Option<BotIntent> {
        let charge = sab.charge.as_ref()?;
        let threatened = enemy.is_some_and(|(_, d)| d < WORK_THREAT);
        let fight = |hold: bool| enemy.map(|(target, d)| self.fight(state, bot, target, d, hold));
        if let Some((site, _)) = charge.planted {
            // Post-plant: guard the charge from cover, and rush a defuser.
            let defuser = sab
                .hold
                .as_ref()
                .filter(|hold| hold.kind == ProgressKind::Defuse)
                .and_then(|hold| state.players.iter().find(|p| p.id == hold.player));
            if let Some(target) = defuser {
                let dist = horizontal(feet(bot), feet(target));
                if visible(state, bot, target) {
                    return Some(self.fight(state, bot, target, dist, false));
                }
                return Some(walk(bot, charge.position));
            }
            if enemy.is_some() {
                return fight(enemy.is_some_and(|(_, d)| d >= HOLD_BREAK));
            }
            return Some(walk(bot, hold_spot(layout, site, slot)));
        }
        let site = &layout.wire.sites[sab.attack_site.index()];
        // Gather out of sight first, then take the site together.
        let pushing = sab.bot_push;
        let stage = stage_spot(layout, sab.attack_site, slot);
        // Through mid first: still east of the mid wall and short of the
        // site's end of mid, walk to the approach point.
        let approach = layout.approaches[sab.attack_site.index()];
        let short_of = |p: &Player| {
            p.x > -20.0 && (p.z - approach[2]).abs() > 8.0 && p.z.abs() < approach[2].abs()
        };
        let stage = if !pushing && short_of(bot) {
            approach
        } else {
            stage
        };
        if charge.carrier == Some(bot.id) {
            let inside = horizontal(feet(bot), site.center) <= site.radius - PLANT_MARGIN;
            let planting = sab
                .hold
                .as_ref()
                .is_some_and(|hold| hold.kind == ProgressKind::Plant);
            if inside && (planting || !enemy.is_some_and(|(_, d)| d < PLANT_THREAT)) {
                return Some(work());
            }
            if enemy.is_some_and(|(_, d)| d < if pushing { 20.0 } else { ROUTE_THREAT }) {
                return fight(false);
            }
            return Some(walk(bot, if pushing { site.center } else { stage }));
        }
        if charge.carrier.is_none() {
            // The nearest standing attacker recovers a loose charge.
            let nearest = state
                .players
                .iter()
                .filter(|p| p.standing() && !p.detached && p.team == Some(Team::Coalition))
                .min_by(|a, b| {
                    horizontal(feet(a), charge.position)
                        .total_cmp(&horizontal(feet(b), charge.position))
                })
                .map(|p| p.id);
            if nearest == Some(bot.id) && !threatened {
                return Some(walk(bot, charge.position));
            }
        }
        let in_reach = if pushing { ENGAGE_MAX } else { ROUTE_THREAT };
        if enemy.is_some_and(|(_, d)| d <= in_reach) {
            // Pushing, trade from where contact was made: the attack's edge
            // is numbers, not walking into a held lane.
            return fight(pushing && enemy.is_some_and(|(_, d)| d >= HOLD_BREAK));
        }
        if !armed(bot) {
            if let Some(pad) = supply(state, bot, f32::MAX, true) {
                return Some(walk(bot, pad));
            }
        }
        if !pushing {
            return Some(walk(bot, stage));
        }
        Some(walk(bot, hold_spot(layout, sab.attack_site, slot)))
    }

    /// The objective intent for a defender, or None to fight what it sees.
    fn defend(
        &self,
        state: &GameState,
        sab: &Sabotage,
        layout: &SabotageLayout,
        bot: &Player,
        slot: usize,
        enemy: Option<(&Player, f32)>,
    ) -> Option<BotIntent> {
        let planted = sab
            .charge
            .as_ref()
            .and_then(|c| c.planted.map(|p| (p.0, c.position)));
        if let Some((site, at)) = planted {
            // Retake: the defender nearest the charge defuses; the rest hold the site.
            let defuser = state
                .players
                .iter()
                .filter(|p| p.standing() && !p.detached && p.team == Some(Team::Union))
                .min_by(|a, b| horizontal(feet(a), at).total_cmp(&horizontal(feet(b), at)))
                .map(|p| p.id);
            let defusing = sab
                .hold
                .as_ref()
                .is_some_and(|hold| hold.kind == ProgressKind::Defuse && hold.player == bot.id);
            let threatened = enemy.is_some_and(|(_, d)| d < WORK_THREAT);
            let fight =
                |hold: bool| enemy.map(|(target, d)| self.fight(state, bot, target, d, hold));
            if defuser == Some(bot.id) {
                let close = horizontal(feet(bot), at) <= DEFUSE_REACH - 0.5;
                if (defusing || close) && !threatened {
                    return Some(work());
                }
                if enemy.is_some() {
                    return fight(false);
                }
                return Some(walk(bot, at));
            }
            if enemy.is_some() {
                return fight(false);
            }
            return Some(walk(bot, hold_spot(layout, site, slot + 1)));
        }
        if let Some((target, d)) = enemy {
            // Before a plant the defence holds its angles rather than chasing.
            return Some(self.fight(state, bot, target, d, d >= HOLD_BREAK));
        }
        if !armed(bot) {
            if let Some(pad) = supply(state, bot, f32::MAX, true) {
                return Some(walk(bot, pad));
            }
        }
        let anchor = if slot.is_multiple_of(2) {
            SiteId::A
        } else {
            SiteId::B
        };
        // The last defender of a side of three or more keeps the far site.
        let side = state
            .players
            .iter()
            .filter(|p| p.contestant() && p.team == Some(Team::Union))
            .count();
        let keeps = side >= 3 && slot + 1 == side;
        let site = if keeps {
            anchor
        } else {
            hot_site(sab).unwrap_or(anchor)
        };
        let spot = if site == anchor { slot / 2 } else { slot };
        Some(walk(bot, hold_spot(layout, site, spot)))
    }

    /// Fight one visible enemy with this bot's personality. A holding fighter
    /// strafes and shoots but does not walk in or back off.
    fn fight(
        &self,
        state: &GameState,
        bot: &Player,
        target: &Player,
        dist: f32,
        hold: bool,
    ) -> BotIntent {
        let target_angle = (target.z - bot.z).atan2(target.x - bot.x);
        let angle_diff = (target_angle - bot.yaw + PI).rem_euclid(2.0 * PI) - PI;
        let eye = [
            bot.x,
            bot.y - PLAYER_FLOOR_Y + crate::combat::stance_eye(bot.campaign, bot.ducking),
            bot.z,
        ];
        let centre = crate::combat::aim_point_for(
            [target.x, target.y - PLAYER_FLOOR_Y, target.z],
            target.campaign,
            target.ducking,
        );
        let action = Action {
            pitch: crate::combat::aim_at(eye, centre).map(|(_, pitch)| pitch),
            ..Action::default()
        };
        let mut intent = self.engage(state, bot, target, dist, angle_diff, action);
        // In clear sight and in reach, fight now. A navigator still walking an
        // objective route would hold the trigger until it searched again,
        // which handed every stationary defender the first shots.
        if dist <= bot.weapon.range_units() {
            intent.goal = None;
            if hold {
                intent.action.forward = false;
                intent.action.back = false;
            }
        }
        intent
    }
}

/// The site the defence should rotate to: a plant under way, or the site
/// where a defender has seen the attack.
fn hot_site(sab: &Sabotage) -> Option<SiteId> {
    if let Some(hold) = sab.hold.as_ref().filter(|h| h.kind == ProgressKind::Plant) {
        return Some(hold.site);
    }
    sab.bot_contact
}

/// Once a tick before the bots think: the attack's push and the defence's
/// call. Both are sticky for the round and stay off the wire.
pub(super) fn coordinate(state: &GameState, sab: &mut Sabotage, layout: &SabotageLayout) {
    let attackers: Vec<&Player> = state
        .players
        .iter()
        .filter(|p| p.standing() && !p.detached && p.team == Some(Team::Coalition))
        .collect();
    if !sab.bot_push {
        let stage = layout.stages[sab.attack_site.index()][0];
        let site = layout.wire.sites[sab.attack_site.index()].center;
        let gathered = attackers
            .iter()
            .filter(|p| horizontal(feet(p), stage) <= GATHERED)
            .count();
        let late = state.tick.saturating_sub(sab.phase_started) >= PUSH_LATEST_TICKS;
        let near = attackers
            .iter()
            .any(|p| horizontal(feet(p), site) <= PUSHED);
        let ready = !attackers.is_empty() && gathered + 1 >= attackers.len().max(2);
        sab.bot_push = late || near || ready;
    }
    if sab.bot_contact.is_none() {
        let defenders: Vec<&Player> = state
            .players
            .iter()
            .filter(|p| p.standing() && p.team == Some(Team::Union))
            .collect();
        for site in &layout.wire.sites {
            let seen = attackers.iter().any(|a| {
                horizontal(feet(a), site.center) <= CONTACT_RADIUS
                    && defenders.iter().any(|d| visible(state, d, a))
            });
            if seen {
                sab.bot_contact = Some(site.id);
                break;
            }
        }
    }
}

fn stage_spot(layout: &SabotageLayout, site: SiteId, slot: usize) -> [f32; 3] {
    let spots = &layout.stages[site.index()];
    spots[slot % spots.len()]
}

fn hold_spot(layout: &SabotageLayout, site: SiteId, slot: usize) -> [f32; 3] {
    let spots = &layout.holds[site.index()];
    spots[slot % spots.len()]
}

fn visible(state: &GameState, bot: &Player, target: &Player) -> bool {
    let eye = [
        bot.x,
        bot.y - PLAYER_FLOOR_Y + crate::combat::stance_eye(bot.campaign, bot.ducking),
        bot.z,
    ];
    let centre = crate::combat::aim_point_for(
        [target.x, target.y - PLAYER_FLOOR_Y, target.z],
        target.campaign,
        target.ducking,
    );
    crate::combat::line_of_sight(eye, centre, &state.map.arena().solids)
}

/// The nearest standing enemy in clear sight and within fighting distance.
fn nearest_visible_enemy<'a>(state: &'a GameState, bot: &Player) -> Option<(&'a Player, f32)> {
    let reach = if armed(bot) {
        ENGAGE_MAX
    } else {
        // Unarmed, only a fight already at arm's length is worth taking.
        4.0
    };
    state
        .players
        .iter()
        .filter(|p| p.standing() && p.team.is_some() && p.team != bot.team)
        .map(|p| (p, horizontal(feet(bot), feet(p))))
        .filter(|(_, d)| *d <= reach)
        .filter(|(p, _)| visible(state, bot, p))
        .min_by(|a, b| a.1.total_cmp(&b.1))
}

/// The nearest pad that would arm or upgrade this bot, within `reach`.
/// `any` accepts any useful weapon; otherwise only a weapon not yet owned.
fn supply(state: &GameState, bot: &Player, reach: f32, any: bool) -> Option<[f32; 3]> {
    if bot.inventory.only().is_some() {
        return None;
    }
    state
        .pickups
        .iter()
        .filter(|pad| pad.available)
        .filter(|pad| pad.claim != SupplyClaim::Personal || !bot.inventory.claimed(&pad.id))
        .filter(|pad| match pad.kind {
            PickupKind::Weapon(weapon) if ranged(weapon) => {
                !bot.inventory.owns(weapon)
                    || (any
                        && weapon
                            .ammo_pool()
                            .is_some_and(|pool| bot.inventory.needs_ammo(pool)))
            }
            _ => false,
        })
        .map(|pad| {
            (
                [pad.x, pad.floor, pad.z],
                horizontal(feet(bot), [pad.x, 0.0, pad.z]),
            )
        })
        .filter(|(_, d)| *d <= reach)
        .min_by(|a, b| a.1.total_cmp(&b.1))
        .map(|(at, _)| at)
}
