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
}

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum Grant {
    Weapon { weapon: WeaponType },
    Ammo { pool: AmmoPool, amount: u16 },
    Health { amount: u16 },
    Armor { amount: u16 },
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
                return Err(invalid("supply needs supported feet and full clearance"));
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
                _ => return Err(invalid("unsupported supply grant or amount")),
            };
            if supply.claim == SupplyClaim::Personal && !matches!(kind, PickupKind::Weapon(_)) {
                return Err(invalid("personal supplies must grant a weapon"));
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
            })
        })
        .collect()
}
