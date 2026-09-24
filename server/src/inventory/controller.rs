//! Equipment decisions shared by rule, scripted, playtest and decision clients.
use crate::protocol::{
    Action, LoadoutState, LookAt, PickupState, Snapshot, SupplyClaim, WeaponType,
};
use uuid::Uuid;

fn weapon_from_name(name: &str) -> Option<WeaponType> {
    WeaponType::ALL
        .into_iter()
        .find(|weapon| weapon.name().eq_ignore_ascii_case(name))
}

fn usable(loadout: &LoadoutState, weapon: WeaponType) -> bool {
    loadout.owns(weapon) && loadout.shots(weapon).is_none_or(|shots| shots > 0)
}

fn useful_supply(loadout: &LoadoutState, pickup: &PickupState, seek_upgrade: bool) -> bool {
    if !pickup.available
        || (pickup.claim == SupplyClaim::Personal && loadout.personal_claims.contains(&pickup.id))
    {
        return false;
    }
    match pickup.kind.as_str() {
        "weapon" => weapon_from_name(&pickup.weapon).is_some_and(|weapon| {
            (seek_upgrade && !loadout.owns(weapon))
                || weapon
                    .ammo_pool()
                    .is_some_and(|pool| loadout.ammo(pool) < weapon.pickup_rounds())
        }),
        "ammo" => pickup.pool.is_some_and(|pool| {
            loadout.ammo(pool) < pool.capacity()
                && loadout
                    .weapons
                    .iter()
                    .any(|weapon| weapon.ammo_pool() == Some(pool))
        }),
        _ => false,
    }
}

/// Keep ordinary combat intent when supplied, otherwise switch or route to supply.
/// None is the explicit legacy full-arsenal path and returns identical actions.
pub fn control_action(
    id: Uuid,
    snapshot: &Snapshot,
    loadout: Option<&LoadoutState>,
    action: Action,
) -> Action {
    control_action_with_objective(id, snapshot, loadout, action, false)
}

/// An active objective takes priority over optional resupply while a ranged
/// weapon is usable. Running dry still routes to supply through the same rules.
pub fn control_action_with_objective(
    id: Uuid,
    snapshot: &Snapshot,
    loadout: Option<&LoadoutState>,
    action: Action,
    has_objective: bool,
) -> Action {
    control_action_with_target_filter(id, snapshot, loadout, action, has_objective, |_, _| true)
}

/// Restrict combat interruptions to targets the caller can actually engage.
/// Arena callers retain the legacy unrestricted target policy.
pub fn control_action_with_target_filter(
    id: Uuid,
    snapshot: &Snapshot,
    loadout: Option<&LoadoutState>,
    mut action: Action,
    has_objective: bool,
    engageable: impl Fn(&crate::protocol::PlayerState, &crate::protocol::PlayerState) -> bool,
) -> Action {
    let Some(loadout) = loadout else {
        return action;
    };
    let Some(me) = snapshot
        .players
        .iter()
        .find(|player| player.id == id && player.hp > 0)
    else {
        return Action::default();
    };
    let nearest = snapshot
        .players
        .iter()
        .filter(|p| me.is_hostile_to(p) && engageable(me, p))
        .min_by(|a, b| {
            (a.x - me.x)
                .hypot(a.z - me.z)
                .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
        });
    if action
        .look_at
        .as_ref()
        .and_then(|aim| aim.player_id)
        .is_some_and(|target| {
            !snapshot.players.iter().any(|player| {
                player.id == target && me.is_hostile_to(player) && engageable(me, player)
            })
        })
    {
        action.look_at = None;
        action.fire = false;
    }
    let held = loadout.selected;
    let selected = action
        .weapon_swap
        .filter(|weapon| usable(loadout, *weapon))
        .or_else(|| usable(loadout, held).then_some(held))
        .filter(|weapon| *weapon != WeaponType::Fists)
        .or_else(|| {
            [
                WeaponType::Flechette,
                WeaponType::Tack,
                WeaponType::Scatter,
                WeaponType::Rail,
            ]
            .into_iter()
            .find(|weapon| usable(loadout, *weapon))
        })
        .unwrap_or(WeaponType::Fists);
    action.weapon_swap = (selected != held).then_some(selected);
    let dry = !usable(loadout, selected);
    if dry {
        action.fire = false;
    }

    if selected == WeaponType::Fists || (nearest.is_none() && !has_objective) {
        let supply = snapshot
            .pickups
            .iter()
            .filter(|p| useful_supply(loadout, p, true))
            .min_by(|a, b| {
                (a.x - me.x)
                    .hypot(a.z - me.z)
                    .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
            });
        if let Some(supply) = supply {
            return Action {
                forward: true,
                weapon_swap: action.weapon_swap,
                look_at: Some(LookAt {
                    x: Some(supply.x),
                    y: Some(supply.y),
                    z: Some(supply.z),
                    player_id: None,
                }),
                ..Action::default()
            };
        }
    }
    if let Some(target) = nearest {
        let distance = (target.x - me.x).hypot(target.z - me.z);
        if action.look_at.is_none() {
            action.look_at = Some(LookAt {
                player_id: Some(target.id),
                ..LookAt::default()
            });
            action.forward = distance > selected.preferred_range().1;
            action.fire = !dry;
        }
        action.fire &= distance <= selected.range_units();
        if selected == WeaponType::Fists {
            action.forward = distance > 1.3;
            action.back = false;
            action.fire = distance <= selected.range_units();
            action.look_at = Some(LookAt {
                player_id: Some(target.id),
                ..LookAt::default()
            });
        }
    }
    action
}
