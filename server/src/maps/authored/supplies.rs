use super::{identity, invalid, standing};
use crate::movement::Arena;
use crate::protocol::{AmmoPool, EquipmentPolicy, SupplyClaim, WeaponType};
use crate::sim::{ArenaPickup, PickupKind};
use serde::Deserialize;
use std::collections::HashSet;
use std::io;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    id: String,
    feet: [f32; 3],
    grant: Grant,
    claim: SupplyClaim,
    /// Optional and found by exploring. Never an objective or a required gun.
    #[serde(default)]
    secret: bool,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum Grant {
    Weapon { weapon: WeaponType },
    Ammo { pool: AmmoPool, amount: u16 },
    Health { amount: u16 },
    Armor { amount: u16 },
    Grenade { amount: u16 },
    ProximityMine { amount: u16 },
    RemoteMine { amount: u16 },
}

pub(super) fn build(
    definitions: Vec<Definition>,
    policy: EquipmentPolicy,
    arena: &Arena,
    seen: &mut HashSet<String>,
) -> io::Result<Vec<ArenaPickup>> {
    if !definitions.is_empty() && policy != EquipmentPolicy::Discovery {
        return Err(invalid("authored supplies require discovery equipment"));
    }
    definitions
        .into_iter()
        .map(|supply| {
            identity(&supply.id, seen)?;
            if !standing(arena, supply.feet) {
                return Err(invalid(&format!(
                    "supply {} needs supported feet and full clearance",
                    supply.id,
                )));
            }
            let (kind, amount) = match supply.grant {
                Grant::Weapon { weapon } if weapon != WeaponType::Fists => {
                    (PickupKind::Weapon(weapon), 0)
                }
                Grant::Ammo { pool, amount } if amount > 0 && amount <= pool.capacity() => (
                    PickupKind::Ammo {
                        pool,
                        rounds: amount,
                    },
                    0,
                ),
                Grant::Health { amount } if amount > 0 && amount <= 100 => {
                    (PickupKind::Health, amount)
                }
                Grant::Armor { amount } if amount > 0 && amount <= 100 => {
                    (PickupKind::Armor, amount)
                }
                Grant::Grenade { amount } if amount > 0 && amount <= 6 => {
                    (PickupKind::Grenade { count: amount }, 0)
                }
                Grant::ProximityMine { amount }
                    if amount > 0 && amount <= crate::protocol::MINE_CARRY_CAP =>
                {
                    (PickupKind::ProximityMine { count: amount }, 0)
                }
                Grant::RemoteMine { amount }
                    if amount > 0 && amount <= crate::protocol::REMOTE_MINE_CARRY_CAP =>
                {
                    (PickupKind::RemoteMine { count: amount }, 0)
                }
                _ => return Err(invalid("unsupported supply grant or amount")),
            };
            if supply.claim == SupplyClaim::Personal
                && !matches!(
                    kind,
                    PickupKind::Weapon(_)
                        | PickupKind::Grenade { .. }
                        | PickupKind::ProximityMine { .. }
                        | PickupKind::RemoteMine { .. }
                )
            {
                return Err(invalid(
                    "personal supplies must grant a weapon, grenade or mine",
                ));
            }
            Ok(ArenaPickup {
                id: supply.id,
                kind,
                amount: i32::from(amount),
                claim: supply.claim,
                x: supply.feet[0],
                floor: supply.feet[1],
                y: supply.feet[1] + 0.4,
                z: supply.feet[2],
                available: true,
                respawn_timer: None,
                secret: supply.secret,
            })
        })
        .collect()
}
