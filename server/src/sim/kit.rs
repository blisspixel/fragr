//! The kit a fresh arena life is issued, and where it is issued: a join, a
//! respawn, a round start and a playlist show change. `crate::rules` decides
//! what the kit is; this module puts it in a fighter's hands.
use super::{GameState, WeaponType};
use crate::inventory::Inventory;
use crate::protocol::{EquipmentPolicy, GameMode};
use crate::rules::StartKit;
use uuid::Uuid;

impl GameState {
    /// The arena kit these rules issue, or None where the map or the
    /// Episode 0 prototype owns equipment instead.
    pub(crate) fn start_kit(&self) -> Option<StartKit> {
        if self.map.is_authored() {
            // A campaign mission owns its equipment. An authored arena keeps
            // its authored policy, except that a weapon-only rule still hands
            // everyone that one weapon.
            if self.map.is_campaign() {
                return None;
            }
            return self.config.rules.only_weapon().map(StartKit::Only);
        }
        if self.solo_broadcast.enabled {
            return Some(
                self.config
                    .rules
                    .only_weapon()
                    .map_or(StartKit::Arsenal, StartKit::Only),
            );
        }
        if self.config.rules.mode() == GameMode::Sabotage {
            // A prepared Sabotage instance owns its starts, not the rules
            // label alone.
            let five = self.sabotage_active()
                && self.sabotage.is_some()
                && self.config.sabotage.five_vs_five;
            return Some(if five {
                StartKit::Found { sidearm: true }
            } else {
                self.config
                    .rules
                    .only_weapon()
                    .map_or(StartKit::Found { sidearm: false }, StartKit::Only)
            });
        }
        Some(self.config.rules.start_kit(&self.config.sabotage))
    }

    /// Discovery equipment wherever weapons are owned (Sabotage, the
    /// free-for-all Pistol start, discovery venues); otherwise the arsenal.
    pub(crate) fn equipment_policy(&self) -> EquipmentPolicy {
        if self.sabotage.is_some() {
            return EquipmentPolicy::Discovery;
        }
        if self.config.rules.mode() == GameMode::Sabotage {
            return self.map.equipment_policy();
        }
        match self.start_kit() {
            Some(kit) => kit.policy(),
            None => self.map.equipment_policy(),
        }
    }

    /// The free-for-all Pistol start, where every stronger gun is a pickup.
    pub(crate) fn sidearm_start(&self) -> bool {
        self.config.rules.mode().free_for_all()
            && self.start_kit() == Some(StartKit::Found { sidearm: true })
    }

    /// A fresh arsenal for one life and the weapon it holds.
    pub(crate) fn fresh_inventory(&self) -> (Inventory, WeaponType) {
        let Some(kit) = self.start_kit() else {
            let policy = self.map.equipment_policy();
            let weapon = match policy {
                EquipmentPolicy::Discovery => WeaponType::Fists,
                EquipmentPolicy::FullArsenal => WeaponType::default(),
            };
            return (Inventory::new(policy), weapon);
        };
        let inventory = match kit {
            StartKit::Only(weapon) => Inventory::restricted(weapon),
            StartKit::Arsenal => Inventory::new(EquipmentPolicy::FullArsenal),
            StartKit::Found { sidearm } => {
                let mut inventory = Inventory::new(EquipmentPolicy::Discovery);
                if sidearm {
                    inventory.grant_weapon(WeaponType::Tack);
                }
                inventory
            }
        };
        (inventory, kit.selected())
    }

    /// Put a fresh kit in one fighter's hands: a human keeps magazines, and
    /// nothing carried from the last life survives. Counters that readers
    /// watch (revision, dry fire) keep counting forward.
    pub(crate) fn issue_kit(&mut self, id: Uuid) {
        let (mut fresh, weapon) = self.fresh_inventory();
        let Some(player) = self.players.iter_mut().find(|p| p.id == id) else {
            return;
        };
        if player.inventory.armed() {
            fresh.arm_magazines();
        }
        player.inventory.restore_entry(&fresh);
        player.weapon = weapon;
        player.last_non_blade_weapon = weapon;
        player.pending_action.weapon_swap = None;
    }
}

/// Fixtures that measure the arcade guns themselves (damage, cooldown,
/// spread, shot geometry) rather than the kit run the `full-arsenal` rule.
#[cfg(test)]
impl GameState {
    /// `GameState::new()` with every fighter armed with the arcade three.
    pub(crate) fn arsenal() -> Self {
        let mut state = Self::new();
        state.config.rules = crate::rules::RuleSet::arsenal();
        state
    }
}

#[cfg(test)]
impl super::MatchConfig {
    /// The default clocks under the `full-arsenal` rule.
    pub(crate) fn arsenal() -> Self {
        Self {
            rules: crate::rules::RuleSet::arsenal(),
            ..Self::default()
        }
    }
}

#[cfg(test)]
mod tests;
