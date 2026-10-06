//! Sabotage on the authoritative sim: the match's rounds and halves, the
//! muster hold, the charge, the held Use that plants or defuses it, the round
//! outcome and the side swap. `crate::rules` owns the format arithmetic; this
//! module owns every transition, from authoritative positions, input and tick.
use super::{
    ArenaPickup, GameState, PickupKind, Player, RoundState, Standing, PLAYER_FLOOR_Y, PLAYER_MAX_HP,
};
use crate::protocol::{
    ChargeState, ChargeStatus, EquipmentPolicy, GameEvent, GameMode, ProgressKind,
    SabotageEventKind, SabotagePhase, SabotageProgress, SabotageReason, SabotageResult,
    SabotageState, SiteId, SupplyClaim, Team, TeamScores, WeaponType,
};
use crate::rules::{match_outcome, round_slot, MatchOutcome};
use std::collections::HashSet;
use uuid::Uuid;

mod bots;
pub mod controller;

/// A living attacker this close to a loose charge takes it.
pub const CHARGE_TOUCH_RADIUS: f32 = 1.5;
/// Vertical slack for taking the charge, planting and defusing.
pub const USE_HEIGHT: f32 = 1.0;
/// A defender this close to the planted charge, horizontally, can defuse it.
pub const DEFUSE_REACH: f32 = 1.75;
/// A dropped charge stays on the floor this long before anyone can take it,
/// so every reader sees the drop.
const DROP_TOUCH_GRACE_TICKS: u64 = 10;
/// Pickup ids of primaries dropped by the fallen. Cleared every round.
pub(crate) const DROPPED_WEAPON_PREFIX: &str = "dropped_";
/// A fighter whose feet moved further than this in a tick is not standing.
const STILL_EPSILON: f32 = 0.01;
/// Spawn rings beyond the authored points, each offset two metres further back.
const SPAWN_RINGS: usize = 3;
/// Primaries in the order a death drops them.
const PRIMARIES: [WeaponType; 3] = [WeaponType::Rail, WeaponType::Scatter, WeaponType::Flechette];

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Charge {
    pub carrier: Option<Uuid>,
    /// Feet position: the carrier's while carried, otherwise where it lies.
    pub position: [f32; 3],
    pub dropped_at: Option<u64>,
    pub planted: Option<(SiteId, u64)>,
    /// Defused or Detonated once the round is decided by it.
    pub resolved: Option<ChargeStatus>,
}

impl Charge {
    fn status(&self) -> ChargeStatus {
        if let Some(resolved) = self.resolved {
            resolved
        } else if self.planted.is_some() {
            ChargeStatus::Planted
        } else if self.carrier.is_some() {
            ChargeStatus::Carried
        } else {
            ChargeStatus::Dropped
        }
    }

    fn loose(&self) -> bool {
        self.carrier.is_none() && self.planted.is_none() && self.resolved.is_none()
    }
}

/// A held Use in progress: who, where they stood and how much they could
/// lose before it counted as damage.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Hold {
    pub kind: ProgressKind,
    pub player: Uuid,
    pub site: SiteId,
    pub ticks: u32,
    feet: [f32; 3],
    vitality: i32,
}

/// The match: rounds, score by current uniform, the round in play and its
/// charge. Present only on a Sabotage server.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Sabotage {
    /// Round of this match, counting from 1. Zero before the first.
    pub round: u32,
    /// Round wins by current uniform.
    pub score: TeamScores,
    pub phase: SabotagePhase,
    pub phase_started: u64,
    pub charge: Option<Charge>,
    pub hold: Option<Hold>,
    /// The site rule bots attack this round, drawn from the seeded stream.
    pub attack_site: SiteId,
    /// Rule-bot coordination, never on the wire: the attack has gathered (or
    /// waited long enough) and now takes its site together. Sticky per round.
    pub bot_push: bool,
    /// Rule-bot coordination: the site the defence has seen attackers at.
    pub bot_contact: Option<SiteId>,
    /// The last decided round's result. Tells the next round to swap or to
    /// begin a new match.
    pub result: Option<SabotageResult>,
    drops: u32,
}

impl Sabotage {
    fn new() -> Self {
        Self {
            round: 0,
            score: TeamScores::default(),
            phase: SabotagePhase::Muster,
            phase_started: 0,
            charge: None,
            hold: None,
            attack_site: SiteId::A,
            bot_push: false,
            bot_contact: None,
            result: None,
            drops: 0,
        }
    }
}

fn feet(player: &Player) -> [f32; 3] {
    [player.x, player.y - PLAYER_FLOOR_Y, player.z]
}

fn horizontal(a: [f32; 3], b: [f32; 3]) -> f32 {
    (a[0] - b[0]).hypot(a[2] - b[2])
}

fn moving(player: &Player) -> bool {
    let action = &player.pending_action;
    action.forward || action.back || action.left || action.right || action.jump
}

impl Player {
    /// Standing in the round: alive, placed and not out of it.
    pub(crate) fn standing(&self) -> bool {
        self.contestant() && self.hp > 0 && self.respawn_timer.is_none() && !self.eliminated
    }
}

impl GameState {
    /// The Sabotage rule set on a map built for it.
    pub(crate) fn sabotage_active(&self) -> bool {
        self.config.rules.mode() == GameMode::Sabotage && self.map.sabotage_layout().is_some()
    }

    /// Discovery equipment in Sabotage, with profile-owned fresh starts;
    /// otherwise the map's own policy.
    pub(crate) fn equipment_policy(&self) -> EquipmentPolicy {
        if self.sabotage.is_some() {
            EquipmentPolicy::Discovery
        } else {
            self.map.equipment_policy()
        }
    }

    pub(super) fn reset_sabotage(&mut self) {
        self.sabotage = self.sabotage_active().then(Sabotage::new);
    }

    /// The fresh arsenal a fighter starts a life with under these rules.
    fn fresh_inventory(&self) -> (crate::inventory::Inventory, WeaponType) {
        if self.sabotage_active() && self.sabotage.is_some() && self.config.sabotage.five_vs_five {
            let mut inventory = crate::inventory::Inventory::new(EquipmentPolicy::Discovery);
            inventory.grant_weapon(WeaponType::Tack);
            return (inventory, WeaponType::Tack);
        }
        match self.config.rules.only_weapon() {
            Some(weapon) => (crate::inventory::Inventory::restricted(weapon), weapon),
            None => (
                crate::inventory::Inventory::new(EquipmentPolicy::Discovery),
                WeaponType::Fists,
            ),
        }
    }

    /// The static layout readers receive in `MapInfo`.
    pub(crate) fn wire_sabotage_map(&self) -> Option<crate::protocol::SabotageMap> {
        self.sabotage.as_ref()?;
        self.map.sabotage_layout().map(|layout| layout.wire.clone())
    }

    /// A new match begins after a decided one, and at the very first round.
    pub(super) fn sabotage_new_match(&self) -> bool {
        self.sabotage
            .as_ref()
            .is_some_and(|sab| sab.round == 0 || sab.result.as_ref().is_some_and(|r| r.match_over))
    }

    /// Before balance and placement: start the next round of the match, or a
    /// new match, and change every uniform when the last round ended a half.
    pub(super) fn begin_sabotage_round(&mut self) {
        let new_match = self.sabotage_new_match();
        let Some(mut sab) = self.sabotage.take() else {
            return;
        };
        let swap = !new_match && sab.result.as_ref().is_some_and(|r| r.sides_swap);
        if new_match {
            sab.round = 0;
            sab.score = TeamScores::default();
        }
        if swap {
            for player in self.players.iter_mut().filter(|p| p.contestant()) {
                if let Some(team) = player.team {
                    player.team = Some(team.other());
                }
            }
            sab.score = TeamScores {
                union: sab.score.coalition,
                coalition: sab.score.union,
            };
            tracing::info!("SABOTAGE: sides swap");
        }
        sab.round += 1;
        sab.phase = SabotagePhase::Muster;
        sab.phase_started = self.tick;
        sab.hold = None;
        sab.result = None;
        sab.charge = None;
        sab.bot_push = false;
        sab.bot_contact = None;
        sab.attack_site = if self.next_u64().is_multiple_of(2) {
            SiteId::A
        } else {
            SiteId::B
        };
        let score = sab.score;
        self.sabotage = Some(sab);
        if swap {
            self.sabotage_event(SabotageEventKind::SidesSwapped, None, None, score);
        }
    }

    /// After balance: every fighter to its side's spawn, the dead with a fresh
    /// arsenal, survivors with what they carried; then the charge to a seeded
    /// attacker. `dead` lists who did not survive the last round.
    pub(super) fn place_sabotage_round(&mut self, dead: &HashSet<Uuid>, fresh: bool) {
        let Some(layout) = self.map.sabotage_layout() else {
            return;
        };
        let mut next = [0usize; 2];
        let ids: Vec<(Uuid, Team)> = self
            .players
            .iter()
            .filter(|p| p.contestant())
            .filter_map(|p| p.team.map(|team| (p.id, team)))
            .collect();
        for (id, team) in ids {
            let side = team.index();
            let slot = next[side];
            next[side] += 1;
            let point = spawn_point(layout, side, slot);
            let restart = fresh || dead.contains(&id);
            let (inventory, weapon) = self.fresh_inventory();
            let Some(player) = self.players.iter_mut().find(|p| p.id == id) else {
                continue;
            };
            place(player, point);
            if restart {
                player.inventory = inventory;
                player.weapon = weapon;
                player.armor = 0;
                player.golden = false;
            } else {
                player.inventory.clear_claims();
            }
            let name = player.name.clone();
            if restart {
                self.events.push(GameEvent::Respawn { player: name });
            }
        }
        self.assign_charge();
    }

    /// The charge goes to a seeded standing attacker, when there is one.
    fn assign_charge(&mut self) {
        let attackers: Vec<(Uuid, [f32; 3])> = self
            .players
            .iter()
            .filter(|p| p.standing() && p.team == Some(Team::Coalition))
            .map(|p| (p.id, feet(p)))
            .collect();
        if attackers.is_empty() {
            return;
        }
        let pick = (self.next_u64() % attackers.len() as u64) as usize;
        let (carrier, position) = attackers[pick];
        if let Some(sab) = self.sabotage.as_mut() {
            sab.charge = Some(Charge {
                carrier: Some(carrier),
                position,
                dropped_at: None,
                planted: None,
                resolved: None,
            });
        }
        tracing::info!("SABOTAGE: charge starts with {carrier}");
    }

    /// A joiner during muster takes a spawn point in its zone; a later joiner
    /// waits out the round watching living teammates.
    pub(super) fn admit_sabotage_joiner(&mut self, id: Uuid) {
        let Some(sab) = self.sabotage.as_ref() else {
            return;
        };
        let Some(layout) = self.map.sabotage_layout() else {
            return;
        };
        let phase = sab.phase;
        let active = self.round_state == RoundState::Active;
        let Some(team) = self
            .players
            .iter()
            .find(|p| p.id == id)
            .and_then(|p| p.team)
        else {
            return;
        };
        let side = team.index();
        let slot = self
            .players
            .iter()
            .filter(|p| p.contestant() && p.team == Some(team) && p.id != id)
            .count();
        let (inventory, weapon) = self.fresh_inventory();
        let Some(player) = self.players.iter_mut().find(|p| p.id == id) else {
            return;
        };
        place(player, spawn_point(layout, side, slot));
        player.inventory = inventory;
        player.weapon = weapon;
        if active && phase != SabotagePhase::Muster {
            player.eliminated = true;
            player.lives = Some(0);
        }
        let attacker_needs_charge = team == Team::Coalition
            && active
            && phase == SabotagePhase::Muster
            && sab.charge.is_none();
        if attacker_needs_charge {
            self.assign_charge();
        }
    }

    pub(super) fn sabotage_event(
        &mut self,
        kind: SabotageEventKind,
        player: Option<Uuid>,
        site: Option<SiteId>,
        score: TeamScores,
    ) {
        let name = player.and_then(|id| {
            self.players
                .iter()
                .find(|p| p.id == id)
                .map(|p| p.name.clone())
        });
        tracing::info!("SABOTAGE: {:?} {:?} {:?}", kind, name, site);
        self.events.push(GameEvent::Sabotage {
            kind,
            player: name,
            player_id: player,
            site,
            score,
        });
    }

    /// The charge leaves a carrier who died, left, detached or changed side,
    /// at their feet on the supporting floor.
    pub(crate) fn drop_charge_from(&mut self, player: Uuid) {
        if self.round_state != RoundState::Active {
            return;
        }
        let at = self.players.iter().find(|p| p.id == player).map(|p| {
            let feet_y = p.y - PLAYER_FLOOR_Y;
            [p.x, self.map.arena().support_height(p.x, p.z, feet_y), p.z]
        });
        let tick = self.tick;
        let Some(sab) = self.sabotage.as_mut() else {
            return;
        };
        let interrupted = sab
            .hold
            .as_ref()
            .filter(|hold| hold.player == player && hold.kind == ProgressKind::Plant)
            .map(|hold| hold.site);
        if interrupted.is_some() {
            sab.hold = None;
        }
        let Some(charge) = sab.charge.as_mut() else {
            return;
        };
        if charge.carrier != Some(player) {
            return;
        }
        charge.carrier = None;
        charge.dropped_at = Some(tick);
        if let Some(at) = at {
            charge.position = at;
        }
        let score = sab.score;
        if let Some(site) = interrupted {
            self.sabotage_event(
                SabotageEventKind::PlantInterrupted,
                Some(player),
                Some(site),
                score,
            );
        }
        self.sabotage_event(SabotageEventKind::ChargeDropped, Some(player), None, score);
    }

    /// A Sabotage death leaves the best carried primary where the fighter
    /// fell, for anyone to take. Weapon-only arsenals drop nothing.
    pub(super) fn drop_primary_from(&mut self, victim: usize) {
        let Some(sab) = self.sabotage.as_mut() else {
            return;
        };
        let player = &self.players[victim];
        if player.inventory.only().is_some() || !player.contestant() {
            return;
        }
        let weapon = if PRIMARIES.contains(&player.weapon) && player.inventory.owns(player.weapon) {
            Some(player.weapon)
        } else {
            PRIMARIES
                .into_iter()
                .find(|weapon| player.inventory.owns(*weapon))
        };
        let Some(weapon) = weapon else {
            return;
        };
        sab.drops = sab.drops.wrapping_add(1);
        let id = format!("{DROPPED_WEAPON_PREFIX}{}", sab.drops);
        let feet_y = player.y - PLAYER_FLOOR_Y;
        let floor = self.map.arena().support_height(player.x, player.z, feet_y);
        let (x, z, name) = (player.x, player.z, player.name.clone());
        tracing::info!("SABOTAGE: {name} dropped the {}", weapon.name());
        self.pickups.push(ArenaPickup {
            claim: SupplyClaim::Contested,
            id,
            kind: PickupKind::Weapon(weapon),
            amount: 0,
            x,
            y: floor + 0.4,
            z,
            floor,
            available: true,
            respawn_timer: None,
            secret: false,
        });
    }

    /// Spawn-zone pistols on top of the map's own pads.
    pub(super) fn add_sabotage_pads(&mut self) {
        if self.config.rules.mode() != GameMode::Sabotage {
            return;
        }
        if let Some(layout) = self.map.sabotage_layout() {
            self.pickups.extend(layout.pads.iter().cloned());
        }
    }

    /// During muster: the zone a fighter of this side may not leave.
    pub(super) fn muster_hold(&self) -> Option<&'static crate::maps::SabotageLayout> {
        let sab = self.sabotage.as_ref()?;
        (self.round_state == RoundState::Active && sab.phase == SabotagePhase::Muster)
            .then(|| self.map.sabotage_layout())
            .flatten()
    }

    /// Muster holds fire, throws and mine placements. Weapons go live with
    /// the round. A press held across that boundary is a new press once the
    /// hold releases, which is the same edge the throw already used.
    pub(super) fn hold_muster_fire(&mut self) {
        if self.muster_hold().is_none() {
            return;
        }
        for player in self.players.iter_mut().filter(|p| p.contestant()) {
            player.pending_action.fire = false;
            player.pending_action.throw_grenade = false;
            player.pending_action.place_mine = false;
            player.throw_requested = false;
            player.place_requested = false;
        }
    }

    /// One tick of the round after combat has resolved.
    pub(super) fn tick_sabotage(&mut self) {
        if self.round_state != RoundState::Active {
            return;
        }
        let Some(layout) = self.map.sabotage_layout() else {
            return;
        };
        let Some(mut sab) = self.sabotage.take() else {
            return;
        };
        let config = self.config.sabotage.clone();
        // A claimed dropped primary is gone, not respawning.
        self.pickups
            .retain(|pad| !pad.id.starts_with(DROPPED_WEAPON_PREFIX) || pad.available);

        if sab.phase == SabotagePhase::Muster {
            if !self
                .players
                .iter()
                .any(|p| p.contestant() && p.team.is_some() && !p.detached)
            {
                // Empty or parked-only rooms retain the full joining countdown.
                sab.phase_started = self.tick;
            } else if self.tick.saturating_sub(sab.phase_started) >= u64::from(config.muster_ticks)
            {
                sab.phase = SabotagePhase::Live;
                sab.phase_started = self.tick;
                self.push_sabotage(&sab, SabotageEventKind::Live, None, None);
            }
        }

        self.carry_charge(&mut sab);
        if sab.phase == SabotagePhase::Live {
            bots::coordinate(self, &mut sab, layout);
        }
        self.progress_plant(&mut sab, layout, config.plant_ticks);
        let defused = self.progress_defuse(&mut sab, config.defuse_ticks);

        let outcome = self.sabotage_outcome(&sab, defused, &config);
        if let Some((winner, reason)) = outcome {
            if let Some(charge) = sab.charge.as_mut() {
                match reason {
                    SabotageReason::Defused => charge.resolved = Some(ChargeStatus::Defused),
                    SabotageReason::Detonation => {
                        charge.resolved = Some(ChargeStatus::Detonated);
                    }
                    _ => {}
                }
            }
            match reason {
                SabotageReason::Defused => {
                    let defuser = sab.hold.as_ref().map(|hold| hold.player);
                    let site = sab.charge.as_ref().and_then(|c| c.planted.map(|p| p.0));
                    self.push_sabotage(&sab, SabotageEventKind::Defused, defuser, site);
                }
                SabotageReason::Detonation => {
                    let site = sab.charge.as_ref().and_then(|c| c.planted.map(|p| p.0));
                    self.push_sabotage(&sab, SabotageEventKind::Detonated, None, site);
                }
                _ => {}
            }
            sab.hold = None;
            self.sabotage = Some(sab);
            self.finish_sabotage_round(winner, reason);
            return;
        }
        self.sabotage = Some(sab);
    }

    fn push_sabotage(
        &mut self,
        sab: &Sabotage,
        kind: SabotageEventKind,
        player: Option<Uuid>,
        site: Option<SiteId>,
    ) {
        self.sabotage_event(kind, player, site, sab.score);
    }

    /// Follow the carrier, drop from a carrier who is gone, and let a living
    /// attacker take a loose charge after the drop grace.
    fn carry_charge(&mut self, sab: &mut Sabotage) {
        let Some(mut charge) = sab.charge.take() else {
            return;
        };
        if let Some(carrier) = charge.carrier {
            let holder = self.players.iter().find(|p| {
                p.id == carrier && p.standing() && !p.detached && p.team == Some(Team::Coalition)
            });
            match holder {
                Some(player) => charge.position = feet(player),
                None => {
                    charge.carrier = None;
                    charge.dropped_at = Some(self.tick);
                    charge.position[1] = self.map.arena().support_height(
                        charge.position[0],
                        charge.position[2],
                        charge.position[1],
                    );
                    if sab.hold.as_ref().is_some_and(|h| h.player == carrier) {
                        sab.hold = None;
                    }
                    self.push_sabotage(sab, SabotageEventKind::ChargeDropped, Some(carrier), None);
                }
            }
        }
        let grace_over = charge
            .dropped_at
            .is_none_or(|at| self.tick.saturating_sub(at) >= DROP_TOUCH_GRACE_TICKS);
        if charge.loose() && grace_over {
            let taker = self.players.iter().find(|p| {
                p.standing()
                    && !p.detached
                    && p.team == Some(Team::Coalition)
                    && horizontal(feet(p), charge.position) <= CHARGE_TOUCH_RADIUS
                    && (feet(p)[1] - charge.position[1]).abs() <= 2.0
            });
            if let Some(player) = taker {
                let id = player.id;
                charge.carrier = Some(id);
                charge.dropped_at = None;
                charge.position = feet(player);
                self.push_sabotage(sab, SabotageEventKind::ChargeTaken, Some(id), None);
            }
        }
        sab.charge = Some(charge);
    }

    /// The carrier, standing in a plant area with Use held, plants after the
    /// plant time. Release, any movement, leaving the area or damage restart it.
    fn progress_plant(
        &mut self,
        sab: &mut Sabotage,
        layout: &crate::maps::SabotageLayout,
        needed: u32,
    ) {
        if sab.phase != SabotagePhase::Live {
            return;
        }
        let Some(carrier) = sab.charge.as_ref().and_then(|c| c.carrier) else {
            return;
        };
        let Some(player) = self.players.iter().find(|p| p.id == carrier) else {
            return;
        };
        let here = feet(player);
        let site = layout.wire.sites.iter().find(|site| {
            horizontal(here, site.center) <= site.radius
                && (here[1] - site.center[1]).abs() <= USE_HEIGHT
        });
        let vitality = player.hp + player.armor;
        let able = player.standing() && !player.detached && player.pending_action.interact;
        let still = !moving(player) && player.vy.abs() < f32::EPSILON;
        if let Some(mut hold) = sab.hold.take() {
            let kept = hold.kind == ProgressKind::Plant
                && hold.player == carrier
                && able
                && still
                && site.is_some_and(|s| s.id == hold.site)
                && horizontal(here, hold.feet) <= STILL_EPSILON
                && vitality >= hold.vitality;
            if !kept {
                self.push_sabotage(
                    sab,
                    SabotageEventKind::PlantInterrupted,
                    Some(hold.player),
                    Some(hold.site),
                );
                return;
            }
            hold.ticks += 1;
            hold.vitality = vitality;
            if hold.ticks < needed {
                sab.hold = Some(hold);
                return;
            }
            let site = hold.site;
            if let Some(charge) = sab.charge.as_mut() {
                charge.carrier = None;
                charge.dropped_at = None;
                charge.position = here;
                charge.planted = Some((site, self.tick));
            }
            sab.phase = SabotagePhase::Planted;
            sab.phase_started = self.tick;
            self.push_sabotage(sab, SabotageEventKind::Planted, Some(carrier), Some(site));
            return;
        }
        if let (true, true, Some(site)) = (able, still, site) {
            sab.hold = Some(Hold {
                kind: ProgressKind::Plant,
                player: carrier,
                site: site.id,
                ticks: 0,
                feet: here,
                vitality,
            });
            let site = site.id;
            self.push_sabotage(
                sab,
                SabotageEventKind::PlantStarted,
                Some(carrier),
                Some(site),
            );
        }
    }

    /// One defender at a time, at the planted charge with Use held, defuses
    /// after the defuse time. Interruption loses all progress. Returns whether
    /// the charge was defused this tick.
    fn progress_defuse(&mut self, sab: &mut Sabotage, needed: u32) -> bool {
        if sab.phase != SabotagePhase::Planted {
            return false;
        }
        let Some((site, _)) = sab.charge.as_ref().and_then(|c| c.planted) else {
            return false;
        };
        let at = sab.charge.as_ref().map(|c| c.position).unwrap_or_default();
        let reach = |player: &Player| {
            let here = feet(player);
            player.standing()
                && !player.detached
                && player.team == Some(Team::Union)
                && player.pending_action.interact
                && !moving(player)
                && player.vy.abs() < f32::EPSILON
                && horizontal(here, at) <= DEFUSE_REACH
                && (here[1] - at[1]).abs() <= USE_HEIGHT
        };
        if let Some(mut hold) = sab.hold.take() {
            let kept = self
                .players
                .iter()
                .find(|p| p.id == hold.player)
                .is_some_and(|p| {
                    reach(p)
                        && horizontal(feet(p), hold.feet) <= STILL_EPSILON
                        && p.hp + p.armor >= hold.vitality
                });
            if !kept || hold.kind != ProgressKind::Defuse {
                self.push_sabotage(
                    sab,
                    SabotageEventKind::DefuseInterrupted,
                    Some(hold.player),
                    Some(site),
                );
                return false;
            }
            hold.ticks += 1;
            if let Some(player) = self.players.iter().find(|p| p.id == hold.player) {
                hold.vitality = player.hp + player.armor;
            }
            let done = hold.ticks >= needed;
            sab.hold = Some(hold);
            return done;
        }
        let starter = self.players.iter().find(|p| reach(p));
        if let Some(player) = starter {
            let id = player.id;
            sab.hold = Some(Hold {
                kind: ProgressKind::Defuse,
                player: id,
                site,
                ticks: 0,
                feet: feet(player),
                vitality: player.hp + player.armor,
            });
            self.push_sabotage(sab, SabotageEventKind::DefuseStarted, Some(id), Some(site));
        }
        false
    }

    /// The round's result this tick, in the documented order: defuse,
    /// detonation, elimination, then the live clock.
    fn sabotage_outcome(
        &self,
        sab: &Sabotage,
        defused: bool,
        config: &crate::rules::SabotageConfig,
    ) -> Option<(Team, SabotageReason)> {
        if defused {
            return Some((Team::Union, SabotageReason::Defused));
        }
        let planted = sab.charge.as_ref().and_then(|c| c.planted);
        if let Some((_, at)) = planted {
            if self.tick.saturating_sub(at) >= u64::from(config.charge_ticks) {
                return Some((Team::Coalition, SabotageReason::Detonation));
            }
        }
        if sab.phase == SabotagePhase::Muster {
            return None;
        }
        let present = |team: Team| {
            self.players
                .iter()
                .any(|p| p.contestant() && p.team == Some(team))
        };
        let standing = |team: Team| {
            self.players
                .iter()
                .any(|p| p.standing() && p.team == Some(team))
        };
        if present(Team::Union) && present(Team::Coalition) {
            if planted.is_some() {
                if !standing(Team::Union) {
                    return Some((Team::Coalition, SabotageReason::Elimination));
                }
            } else if !standing(Team::Coalition) {
                return Some((Team::Union, SabotageReason::Elimination));
            } else if !standing(Team::Union) {
                return Some((Team::Coalition, SabotageReason::Elimination));
            }
        }
        if sab.phase == SabotagePhase::Live
            && self.tick.saturating_sub(sab.phase_started) >= u64::from(config.live_ticks)
        {
            return Some((Team::Union, SabotageReason::Time));
        }
        None
    }

    /// Score the round, decide the match and close the round.
    fn finish_sabotage_round(&mut self, winner: Team, reason: SabotageReason) {
        let format = self.config.sabotage.format;
        let Some(sab) = self.sabotage.as_mut() else {
            return;
        };
        sab.score.add(winner);
        sab.phase = SabotagePhase::Over;
        sab.phase_started = self.tick;
        let outcome = match_outcome(format, sab.round, sab.score);
        let match_over = outcome != MatchOutcome::Continue;
        let result = SabotageResult {
            reason,
            round: sab.round,
            score: sab.score,
            sides_swap: round_slot(format, sab.round).swap_after && !match_over,
            match_over,
            match_winner: match outcome {
                MatchOutcome::Won(team) => Some(team),
                _ => None,
            },
        };
        sab.result = Some(result);
        let text = match (outcome, reason) {
            (MatchOutcome::Won(_), _) => "Match decided",
            (MatchOutcome::Draw, _) => "Match drawn",
            (_, SabotageReason::Elimination) => "Side eliminated",
            (_, SabotageReason::Detonation) => "Charge detonated",
            (_, SabotageReason::Defused) => "Charge defused",
            (_, SabotageReason::Time) => "Round clock expired",
        };
        self.finish_round(text.to_string(), Some(Standing::Side(Some(winner))));
    }

    /// The Host's line for a decided Sabotage round.
    pub(super) fn sabotage_host_line(&self, winner: Option<Team>) -> Option<String> {
        let result = self.sabotage.as_ref()?.result.as_ref()?;
        let winner = winner?;
        if result.match_over && result.match_winner.is_none() {
            return Some(crate::protocol::sabotage_draw_host_line(result.score));
        }
        Some(crate::protocol::sabotage_round_host_line(
            winner,
            result.reason,
            result.score,
            result.match_over,
        ))
    }

    /// How long the result card holds before the next round.
    pub(crate) fn sabotage_end_delay(&self) -> Option<u32> {
        let sab = self.sabotage.as_ref()?;
        let config = &self.config.sabotage;
        Some(match sab.result.as_ref() {
            Some(result) if result.sides_swap || result.match_over => config.swap_end_ticks,
            _ => config.round_end_ticks,
        })
    }

    /// Ticks left on the clock that matters now.
    fn sabotage_clock(&self, sab: &Sabotage) -> u32 {
        let config = &self.config.sabotage;
        let since = |from: u64| self.tick.saturating_sub(from).min(u64::from(u32::MAX)) as u32;
        match sab.phase {
            SabotagePhase::Muster => config.muster_ticks.saturating_sub(since(sab.phase_started)),
            SabotagePhase::Live => config.live_ticks.saturating_sub(since(sab.phase_started)),
            SabotagePhase::Planted => sab
                .charge
                .as_ref()
                .and_then(|c| c.planted)
                .map_or(0, |(_, at)| config.charge_ticks.saturating_sub(since(at))),
            SabotagePhase::Over => 0,
        }
    }

    /// The round as readers see it. Absent before the first round.
    pub(crate) fn wire_sabotage(&self) -> Option<SabotageState> {
        let sab = self.sabotage.as_ref()?;
        if sab.round == 0 {
            return None;
        }
        let format = self.config.sabotage.format;
        let slot = round_slot(format, sab.round);
        let count = |team: Team| {
            self.players
                .iter()
                .filter(|p| p.standing() && p.team == Some(team))
                .count() as u32
        };
        Some(SabotageState {
            format,
            phase: sab.phase,
            round: sab.round,
            period: slot.period,
            half: slot.half,
            half_rounds: slot.half_rounds,
            rounds_to_win: slot.rounds_to_win,
            score: sab.score,
            alive: TeamScores {
                union: count(Team::Union),
                coalition: count(Team::Coalition),
            },
            clock_ticks: self.sabotage_clock(sab),
            charge: sab.charge.as_ref().map(|charge| ChargeState {
                status: charge.status(),
                position: charge.position,
                carrier: charge.carrier,
                site: charge.planted.map(|(site, _)| site),
            }),
            progress: sab.hold.as_ref().map(|hold| SabotageProgress {
                kind: hold.kind,
                player_id: hold.player,
                site: hold.site,
                ticks: hold.ticks,
                needed: match hold.kind {
                    ProgressKind::Plant => self.config.sabotage.plant_ticks,
                    ProgressKind::Defuse => self.config.sabotage.defuse_ticks,
                },
            }),
            swap_after: slot.swap_after,
        })
    }
}

#[cfg(test)]
impl GameState {
    /// Land `damage` from `shooter` on `victim` through the ordinary hit
    /// resolution, so drops, lives and frags follow the real path. Returns
    /// whether the victim died.
    pub(crate) fn hit_for_test(&mut self, shooter: Uuid, victim: Uuid, damage: i32) -> bool {
        let shooter = self
            .players
            .iter()
            .position(|p| p.id == shooter)
            .expect("shooter");
        let victim = self
            .players
            .iter()
            .position(|p| p.id == victim)
            .expect("victim");
        self.spawn_shields.clear();
        self.resolve_fighter_hit(shooter, victim, damage, None).2
    }
}

/// The `slot`-th fighter of a side: the authored points first, then the same
/// points stepped two metres further back from the front, ring by ring.
pub(crate) fn spawn_point(
    layout: &crate::maps::SabotageLayout,
    side: usize,
    slot: usize,
) -> [f32; 4] {
    let points = &layout.spawns[side];
    let [x, floor, z, yaw] = points[slot % points.len()];
    let ring = (slot / points.len()).min(SPAWN_RINGS - 1) as f32;
    // Back is away from the yaw the side faces.
    [
        x - yaw.cos() * ring * 2.0,
        floor,
        z - yaw.sin() * ring * 2.0,
        yaw,
    ]
}

fn place(player: &mut Player, point: [f32; 4]) {
    let [x, floor, z, yaw] = point;
    player.reset_movement_baseline();
    player.x = x;
    player.z = z;
    player.y = PLAYER_FLOOR_Y + floor;
    player.vy = 0.0;
    player.yaw = yaw;
    player.pitch = 0.0;
    player.hp = PLAYER_MAX_HP;
    player.respawn_timer = None;
    player.eliminated = false;
    player.lives = Some(1);
    player.fire_cooldown = 0;
    player.inventory.release_trigger();
}

#[cfg(test)]
mod five_start_owner_tests {
    use super::*;

    #[test]
    fn five_seats_fresh_inventory_requires_real_sabotage_owner() {
        let mut arena = GameState::with_map(crate::sim::MapKind::Sector9, false);
        arena.config.sabotage.five_vs_five = true;
        assert_eq!(arena.config.rules.mode(), GameMode::Ffa);
        assert!(arena.sabotage.is_none());
        let (inventory, selected) = arena.fresh_inventory();
        assert_eq!(selected, WeaponType::Fists);
        assert!(!inventory.owns(WeaponType::Tack));

        let map = crate::maps::AuthoredMap::read(
            include_str!("../../maps/m06_port_of_entry.json").as_bytes(),
        )
        .unwrap();
        let mut campaign = GameState::with_authored_map(map);
        // A stale internal option must not turn an authored campaign into a
        // competitive equipment owner, even if its rules also name Sabotage.
        campaign.config.sabotage.five_vs_five = true;
        campaign.config.rules = crate::rules::RuleSet::new(GameMode::Sabotage, &[], false).unwrap();
        assert!(!campaign.sabotage_active());
        let (inventory, selected) = campaign.fresh_inventory();
        assert_eq!(selected, WeaponType::Fists);
        assert!(!inventory.owns(WeaponType::Tack));

        arena.config.rules = crate::rules::RuleSet::new(GameMode::Sabotage, &[], false).unwrap();
        // A prepared instance is required, not the rules label alone.
        assert!(arena.sabotage_active());
        assert_eq!(arena.fresh_inventory().1, WeaponType::Fists);
        arena.reset_sabotage();
        assert_eq!(arena.fresh_inventory().1, WeaponType::Tack);
    }
}
