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

/// Metres a Pistol-only fighter will walk for a gun with a rival in range.
const UPGRADE_DETOUR: f32 = 8.0;

/// A gun worth leaving the Pistol for.
fn is_upgrade(weapon: WeaponType) -> bool {
    weapon.ammo_pool().is_some() && !matches!(weapon, WeaponType::Tack)
}

/// The free-for-all start: nothing carried but the Pistol and melee.
fn sidearm_only(loadout: &LoadoutState) -> bool {
    loadout.owns(WeaponType::Tack) && !loadout.weapons.iter().any(|w| is_upgrade(*w))
}

/// The best melee in hand: a found Shiv, otherwise fists.
fn melee(loadout: &LoadoutState) -> WeaponType {
    if loadout.owns(WeaponType::Shiv) {
        WeaponType::Shiv
    } else {
        WeaponType::Fists
    }
}

/// How close melee closes before it stops walking in, inside its reach.
fn melee_close(weapon: WeaponType) -> f32 {
    weapon.range_units() - 0.5
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
        "grenade" => loadout.grenades < 6,
        "proximity_mine" => loadout.proximity_mines < crate::protocol::MINE_CARRY_CAP,
        "remote_mine" => loadout.remote_mines < crate::protocol::REMOTE_MINE_CARRY_CAP,
        _ => false,
    }
}

/// Equip a real finite ray weapon for a registered shootable world control.
/// Combat targeting stays with the caller. This neither creates ammunition nor
/// substitutes projectile splash for the control's resolved ray impact.
pub fn control_ray_objective(
    id: Uuid,
    snapshot: &Snapshot,
    loadout: &LoadoutState,
    mut action: Action,
) -> Option<Action> {
    let me = snapshot.players.iter().find(|p| p.id == id && p.hp > 0)?;
    let ray = |w: WeaponType| w != WeaponType::Rocket && w.ammo_pool().is_some();
    // Count carried reserve as usable: a human must reload its actual magazine.
    let supplied = |w: WeaponType| {
        ray(w)
            && loadout.owns(w)
            && w.ammo_pool().is_some_and(|pool| {
                loadout.shots(w).is_some_and(|n| n > 0)
                    || loadout.ammo(pool)
                        > loadout
                            .loaded
                            .iter()
                            .filter(|m| m.weapon.ammo_pool() == Some(pool))
                            .map(|m| m.rounds)
                            .sum::<u16>()
            })
    };
    let selected = action
        .weapon_swap
        .filter(|w| supplied(*w))
        .or_else(|| supplied(loadout.selected).then_some(loadout.selected))
        .or_else(|| {
            [
                WeaponType::Tack,
                WeaponType::Flechette,
                WeaponType::Repeater,
                WeaponType::Rail,
                WeaponType::Sniper,
                WeaponType::Scatter,
                WeaponType::Arc,
            ]
            .into_iter()
            .find(|w| supplied(*w))
        });
    action.fire = false;
    action.throw_grenade = false;
    action.place_mine = false;
    action.place_remote_mine = false;
    action.trigger_remote_mines = false;
    if let Some(weapon) = selected {
        action.weapon_swap = (weapon != loadout.selected).then_some(weapon);
        action.reload = loadout
            .loaded
            .iter()
            .any(|m| m.weapon == weapon && m.rounds == 0 && m.ready_at.is_none());
        return Some(action);
    }
    let supply = snapshot
        .pickups
        .iter()
        .filter(|p| {
            useful_supply(loadout, p, true)
                && match p.kind.as_str() {
                    "weapon" => weapon_from_name(&p.weapon).is_some_and(ray),
                    "ammo" => p.pool.is_some_and(|pool| {
                        pool != crate::protocol::AmmoPool::Rockets
                            && loadout
                                .weapons
                                .iter()
                                .any(|w| ray(*w) && w.ammo_pool() == Some(pool))
                    }),
                    _ => false,
                }
        })
        .min_by(|a, b| {
            (a.x - me.x)
                .hypot(a.z - me.z)
                .total_cmp(&(b.x - me.x).hypot(b.z - me.z))
        })?;
    Some(Action {
        forward: true,
        look_at: Some(LookAt {
            x: Some(supply.x),
            y: Some(supply.y),
            z: Some(supply.z),
            player_id: None,
        }),
        ..Action::default()
    })
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
    // A channeling Auditor comes before any nearer hostile.
    let key = |p: &crate::protocol::PlayerState| {
        crate::combat::engagement_key(p.campaign, (p.x - me.x).hypot(p.z - me.z))
    };
    let nearest = snapshot
        .players
        .iter()
        .filter(|p| me.is_hostile_to(p) && engageable(me, p))
        .min_by(|a, b| key(a).0.cmp(&key(b).0).then(key(a).1.total_cmp(&key(b).1)));
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
        action.throw_grenade = false;
    }
    let held = loadout.selected;
    // A deliberate throw keeps its aim. Resupply and melee steering must not
    // silently replace a world-point lob with a different target.
    if action.throw_grenade {
        action.weapon_swap = action.weapon_swap.filter(|weapon| loadout.owns(*weapon));
        action.throw_grenade = loadout.grenades > 0;
        return action;
    }
    // A deliberate placement keeps its aim, like a throw, and never spends a
    // mine the loadout does not hold.
    if action.place_mine {
        action.weapon_swap = action.weapon_swap.filter(|weapon| loadout.owns(*weapon));
        action.place_mine = loadout.proximity_mines > 0;
        return action;
    }
    if action.place_remote_mine {
        action.weapon_swap = action.weapon_swap.filter(|weapon| loadout.owns(*weapon));
        action.place_remote_mine = loadout.remote_mines > 0;
        return action;
    }
    // A trigger remains useful with empty carry because the owned charges
    // already exist in the world. It never grants stock or invents a charge.
    if action.trigger_remote_mines {
        action.weapon_swap = action.weapon_swap.filter(|weapon| loadout.owns(*weapon));
        return action;
    }
    let requested = action.weapon_swap.filter(|weapon| usable(loadout, *weapon));
    let mut selected = requested
        .or_else(|| usable(loadout, held).then_some(held))
        .filter(|weapon| weapon.ammo_pool().is_some())
        .or_else(|| {
            [
                WeaponType::Repeater,
                WeaponType::Flechette,
                WeaponType::Tack,
                WeaponType::Scatter,
                WeaponType::Rail,
                WeaponType::Sniper,
                WeaponType::Arc,
                WeaponType::Rocket,
            ]
            .into_iter()
            .find(|weapon| usable(loadout, *weapon))
        })
        .unwrap_or_else(|| melee(loadout));
    // A hostile beyond the chosen gun's reach but inside the Sniper's takes
    // the carried Sniper. An explicit usable request is never overridden.
    if requested.is_none()
        && usable(loadout, WeaponType::Arc)
        && nearest.is_some_and(|target| {
            (target.x - me.x).hypot(target.z - me.z) <= WeaponType::Arc.range_units()
                && (target.armor > 0
                    || matches!(
                        target.campaign,
                        Some(crate::protocol::CampaignActor::Union {
                            kind: crate::protocol::EnemyKind::Auditor
                                | crate::protocol::EnemyKind::Assessor,
                            ..
                        })
                    ))
        })
    {
        selected = WeaponType::Arc;
    }
    if requested.is_none()
        && selected != WeaponType::Arc
        && usable(loadout, WeaponType::Rocket)
        && nearest.is_some_and(|target| {
            let distance = (target.x - me.x).hypot(target.z - me.z);
            (6.0..=48.0).contains(&distance)
        })
    {
        selected = WeaponType::Rocket;
    }
    if requested.is_none()
        && selected == WeaponType::Rocket
        && nearest.is_some_and(|target| (target.x - me.x).hypot(target.z - me.z) < 6.0)
    {
        selected = [
            WeaponType::Repeater,
            WeaponType::Flechette,
            WeaponType::Tack,
            WeaponType::Scatter,
            WeaponType::Rail,
            WeaponType::Sniper,
            WeaponType::Arc,
        ]
        .into_iter()
        .find(|weapon| usable(loadout, *weapon))
        .unwrap_or_else(|| melee(loadout));
    }
    if requested.is_none()
        && usable(loadout, WeaponType::Sniper)
        && nearest.is_some_and(|target| {
            let distance = (target.x - me.x).hypot(target.z - me.z);
            distance > selected.range_units() && distance <= WeaponType::Sniper.range_units()
        })
    {
        selected = WeaponType::Sniper;
    }
    action.weapon_swap = (selected != held).then_some(selected);
    let dry = !usable(loadout, selected);
    if dry {
        action.fire = false;
    }

    let melee_only = selected.ammo_pool().is_none();
    // A free-for-all life starts on the Pistol. Holding nothing stronger, it
    // goes and takes a gun from a contested pad: always when nobody is in
    // the Pistol's reach, and even with a fight on when the pad
    // is a few steps away. An objective keeps its priority, and a campaign
    // participant keeps its mission's own pacing.
    if !has_objective
        && me.campaign.is_none()
        && snapshot.sabotage.is_none()
        && !melee_only
        && sidearm_only(loadout)
    {
        let distance_to = |p: &PickupState| (p.x - me.x).hypot(p.z - me.z);
        let gun = snapshot
            .pickups
            .iter()
            .filter(|p| {
                p.available
                    && p.claim == SupplyClaim::Contested
                    && p.kind == "weapon"
                    && weapon_from_name(&p.weapon)
                        .is_some_and(|w| !loadout.owns(w) && is_upgrade(w))
            })
            .min_by(|a, b| distance_to(a).total_cmp(&distance_to(b)));
        let crowded = nearest.is_some_and(|target| {
            (target.x - me.x).hypot(target.z - me.z) <= WeaponType::Tack.range_units()
        });
        if let Some(gun) = gun.filter(|gun| !crowded || distance_to(gun) <= UPGRADE_DETOUR) {
            return Action {
                forward: true,
                weapon_swap: action.weapon_swap,
                look_at: Some(LookAt {
                    x: Some(gun.x),
                    y: Some(gun.y),
                    z: Some(gun.z),
                    player_id: None,
                }),
                ..Action::default()
            };
        }
    }
    if melee_only || (nearest.is_none() && !has_objective) {
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
        if melee_only {
            action.forward = distance > melee_close(selected);
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
