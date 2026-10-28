//! Guns dropped on death in the free-for-all Pistol start: a fragged fighter
//! leaves the gun in their hands where they fell, with the rounds it still
//! had, for a short while. Quake and Unreal trade-up: the winner of a fight
//! walks over the loser's Rocket. Only the Pistol start drops, because only
//! there is a gun something found rather than issued; the arsenal kits,
//! weapon-only mutators, Golden Rail (its gun returns to the pad), Sabotage
//! (its own primary drops), the campaign and the benchmark never do.
use super::{GameState, Player, PICKUP_CLAIM_HEIGHT, PICKUP_CLAIM_RADIUS, PLAYER_FLOOR_Y};
use crate::protocol::{GameEvent, PickupState, SupplyClaim, WeaponType};

/// How long a dropped gun lies before it is gone: long enough for the
/// fight's winner to walk over it, short enough that the floor never fills.
/// Tuned on the six-bot Larak Lot survey (`docs/plans/weapon-economy.md`).
pub const DROPPED_GUN_TICKS: u32 = 20 * 15;
/// At most this many guns lie on the floor at once; a new drop past it
/// takes the place of the oldest, so a long brawl never grows the snapshot
/// or the claim scan without bound.
pub const MAX_DROPPED_GUNS: usize = 16;
/// Wire id prefix for a dropped gun in the snapshot's `pickups`.
pub const DROPPED_GUN_PREFIX: &str = "drop_";

/// One gun on the floor.
#[derive(Debug, Clone, PartialEq)]
pub struct DroppedGun {
    pub serial: u32,
    pub weapon: WeaponType,
    /// The rounds it carries: what the fighter still had for it, never more
    /// than a pad of the same gun gives.
    pub rounds: u16,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub floor: f32,
    /// The tick it is gone if nobody takes it.
    pub expires_at: u64,
}

impl DroppedGun {
    pub fn id(&self) -> String {
        format!("{DROPPED_GUN_PREFIX}{}", self.serial)
    }

    pub(super) fn to_state(&self) -> PickupState {
        PickupState {
            claim: SupplyClaim::Contested,
            pool: None,
            id: self.id(),
            kind: "weapon".to_string(),
            weapon: self.weapon.name().to_string(),
            amount: Some(i32::from(self.rounds)),
            x: self.x,
            y: self.y,
            z: self.z,
            available: true,
            dropped: true,
        }
    }
}

/// The gun a fragged fighter leaves, and its rounds: the gun in hand when it
/// is a found gun with rounds left. Fists, the Shiv, the borrowed Article
/// Blade and the Pistol every life starts with stay behind, and so does the
/// Flechette: it is the lot's common pad gun, and dropped Flechettes pushed
/// it past half of all shots on the six-bot survey (50% against the 45%
/// gate; 36% when it stays behind, `docs/plans/bot-and-enemy-ai-excellence-20261017.md`).
pub(super) fn dropped_from(player: &Player) -> Option<(WeaponType, u16)> {
    let weapon = player.weapon;
    if matches!(weapon, WeaponType::Tack | WeaponType::Flechette) || !player.inventory.owns(weapon)
    {
        return None;
    }
    let pool = weapon.ammo_pool()?;
    let rounds = player.inventory.carried(pool).min(weapon.pickup_rounds());
    (rounds > 0).then_some((weapon, rounds))
}

/// How far a gun slides off a ledge face to come to rest, in steps of
/// `RESTING_STEP`: well inside the claim radius of where its fighter fell.
const RESTING_STEPS: usize = 12;
const RESTING_STEP: f32 = 0.1;
/// Directions tried at each slide distance.
const RESTING_BEARINGS: usize = 16;

/// Where a gun dropped at `(x, z)` comes to rest on `floor`: there, when a
/// body can stand on that spot, otherwise the nearest spot on the same floor
/// that one can. A fighter standing on the lip of a deck or a stair has its
/// centre out over the floor below, so the gun falls to the foot of the
/// face, inside a body's width of it; nobody can stand there, and a
/// controller routing to it finds no floor and stops dead.
fn resting_spot(arena: &crate::movement::Arena, x: f32, z: f32, floor: f32) -> (f32, f32) {
    let standable = |x: f32, z: f32| {
        (arena.support_height(x, z, floor) - floor).abs() < 1e-3
            && !arena.blocked_body_at(x, z, floor, floor + crate::movement::STEP_UP)
            && arena.clamp(x, z) == (x, z)
    };
    if standable(x, z) {
        return (x, z);
    }
    (1..=RESTING_STEPS)
        .flat_map(|step| {
            let reach = step as f32 * RESTING_STEP;
            (0..RESTING_BEARINGS).map(move |bearing| {
                let angle = std::f32::consts::TAU * bearing as f32 / RESTING_BEARINGS as f32;
                (x + angle.cos() * reach, z + angle.sin() * reach)
            })
        })
        .find(|&(x, z)| standable(x, z))
        .unwrap_or((x, z))
}

impl GameState {
    /// Guns dropped on death since this state began, for surveys.
    pub fn guns_dropped(&self) -> u32 {
        self.drop_serial
    }

    /// Whether these rules drop guns on death: the free-for-all Pistol start.
    pub(crate) fn drops_guns(&self) -> bool {
        self.sidearm_start() && !self.map.is_campaign() && !self.solo_broadcast.enabled
    }

    /// Leave the gun in a fragged fighter's hands where they fell.
    pub(super) fn drop_gun_from(&mut self, victim: usize) {
        if !self.drops_guns() {
            return;
        }
        let player = &self.players[victim];
        if !player.contestant() {
            return;
        }
        let Some((weapon, rounds)) = dropped_from(player) else {
            return;
        };
        let feet_y = player.y - PLAYER_FLOOR_Y;
        let (x, z, floor) = {
            let arena = self.current_arena();
            let floor = arena.support_height(player.x, player.z, feet_y);
            let (x, z) = resting_spot(&arena, player.x, player.z, floor);
            (x, z, floor)
        };
        self.drop_serial = self.drop_serial.wrapping_add(1);
        let gun = DroppedGun {
            serial: self.drop_serial,
            weapon,
            rounds,
            x,
            y: floor + 0.4,
            z,
            floor,
            expires_at: self.tick + u64::from(DROPPED_GUN_TICKS),
        };
        tracing::info!(target: crate::logging::FEED_TARGET, "DROP: {} dropped the {} ({} rounds)", player.name, weapon.name(), rounds);
        if self.dropped_guns.len() >= MAX_DROPPED_GUNS {
            self.dropped_guns.remove(0);
        }
        self.dropped_guns.push(gun);
    }

    /// Expire old drops and hand each remaining one to the first living
    /// fighter standing on it who can use it.
    pub(super) fn tick_dropped_guns(&mut self) {
        let tick = self.tick;
        self.dropped_guns.retain(|gun| gun.expires_at > tick);
        let mut index = 0;
        while index < self.dropped_guns.len() {
            let gun = self.dropped_guns[index].clone();
            let taker = self.players.iter().position(|player| {
                player.contestant()
                    && player.hp > 0
                    && player.respawn_timer.is_none()
                    && !player.detached
                    && !player.eliminated
                    && player.inventory.weapon_pad_useful(gun.weapon)
                    && (player.y - PLAYER_FLOOR_Y - gun.floor).abs() <= PICKUP_CLAIM_HEIGHT
                    && (player.x - gun.x).hypot(player.z - gun.z) <= PICKUP_CLAIM_RADIUS
            });
            let Some(taker) = taker else {
                index += 1;
                continue;
            };
            self.dropped_guns.remove(index);
            let player = &mut self.players[taker];
            let discovered = !player.inventory.owns(gun.weapon);
            player.inventory.grant_weapon_rounds(gun.weapon, gun.rounds);
            if discovered {
                player.inventory.release_trigger();
                player.weapon = gun.weapon;
            }
            let (name, player_id) = (player.name.clone(), player.id);
            tracing::info!(target: crate::logging::FEED_TARGET, "PICKUP: {} claimed a dropped {} ({})", name, gun.weapon.name(), gun.id());
            self.events.push(GameEvent::Pickup {
                player: name,
                player_id,
                kind: "weapon".to_string(),
                weapon: gun.weapon.name().to_string(),
                amount: Some(i32::from(gun.rounds)),
                pickup_id: gun.id(),
                secret: false,
            });
        }
    }
}

#[cfg(test)]
mod tests;
