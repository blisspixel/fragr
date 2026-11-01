//! Mid-level checkpoints for a solo campaign run.
//!
//! A checkpoint is wanted when a fight is cleared, a mission fact changes, or
//! a minute of play has passed since the last one. It is taken on the first
//! tick after that which is safe: the owner alive, standing on the ground,
//! unhurt for three seconds and out of every vehicle, no woken guard alive,
//! nothing hostile in flight and the Walker, if any, not fighting. Halo's
//! campaign rule is the model: a save waits for safety rather than landing in
//! the middle of a fight.
//!
//! A death with a continue left spends one continue and returns the run to the
//! latest checkpoint of the current level, or to the level entry when there is
//! none. The allowance, the episode refill and exhaustion are unchanged
//! (`docs/CAMPAIGN.md`). Checkpoints live with the run in this process; the
//! run file on disk keeps the level entry, so a reopened save starts the level
//! again, as it always has.
use super::*;
use crate::encounters::GroupMark;
use crate::inventory::Inventory;
use crate::protocol::{CampaignRunStatus, GameEvent, MissionContinue, WeaponType};
use crate::sim::WorldSave;

#[cfg(test)]
mod gaps;
#[cfg(test)]
mod tests;

/// A minute of play without a checkpoint asks for one.
pub(crate) const CHECKPOINT_INTERVAL_TICKS: u64 = 1_200;
/// Two checkpoints are never closer than thirty seconds.
pub(crate) const CHECKPOINT_SPACING_TICKS: u64 = 600;
/// Damage within the last three seconds makes the moment unsafe.
pub(crate) const CHECKPOINT_HURT_QUIET_TICKS: u64 = 60;
/// Feet within this of the ground beneath them count as standing on it.
const GROUNDED: f32 = 0.05;

/// When this level's checkpoints were taken and the latest one.
#[derive(Default)]
pub(super) struct Schedule {
    saved: Option<Box<Checkpoint>>,
    /// The tick of the latest checkpoint or restore; the level start before.
    last_at: Option<u64>,
    due: bool,
    seen_complete: usize,
    seen_changed: u64,
    vitals: Option<i32>,
    hurt_at: Option<u64>,
    /// Ticks at which checkpoints were taken this level, in order.
    taken: Vec<u64>,
}

impl Schedule {
    pub(super) fn has_checkpoint(&self) -> bool {
        self.saved.is_some()
    }

    /// A retry starts the clock again from the save it returned to; the
    /// next checkpoint waits for a new trigger or another quiet minute.
    pub(super) fn restart(&mut self, tick: u64) {
        self.last_at = Some(tick);
        self.due = false;
        self.seen_changed = tick;
        self.vitals = None;
        self.hurt_at = None;
    }

    #[cfg(test)]
    pub(super) fn taken(&self) -> &[u64] {
        &self.taken
    }
}

struct Checkpoint {
    tick: u64,
    strip_hits: u64,
    owner: OwnerSave,
    score: u32,
    facts: MissionFacts,
    groups: Vec<GroupMark>,
    world: WorldSave,
}

struct OwnerSave {
    position: [f32; 3],
    yaw: f32,
    pitch: f32,
    hp: i32,
    armor: i32,
    weapon: WeaponType,
    last_non_blade_weapon: WeaponType,
    inventory: Inventory,
    jetpack: Option<crate::movement::jetpack::Pack>,
    ducking: bool,
    statistics: crate::statistics::CombatLedger,
}

/// Every mission fact an attempt changes. The run's identity, rules, attempt,
/// readiness and continue allowance are not facts of the attempt.
#[derive(Clone)]
struct MissionFacts {
    m02: Option<m02::M02Progress>,
    m03: Option<m03::M03Progress>,
    m04: Option<m04::M04Progress>,
    m05: Option<m05::M05Progress>,
    m06: Option<m06::M06Progress>,
    m07: Option<m07::M07Progress>,
    m08: Option<m08::M08Progress>,
    m09: Option<m09::M09Progress>,
    m10: Option<m10::M10Progress>,
    m11: Option<m11::M11Progress>,
    m12: Option<m12::M12Progress>,
    m13: Option<m13::M13Progress>,
    m14: Option<m14::M14Progress>,
    m15: Option<m15::M15Progress>,
    m16: Option<m16::M16Progress>,
    m17: Option<m17::M17Progress>,
    m18: Option<m18::M18Progress>,
    m19: Option<m19::M19Progress>,
    m20: Option<m20::M20Progress>,
    companion: m02::companion::Support,
    phase: MissionPhase,
    started_at: Option<u64>,
}

impl MissionFacts {
    fn of(run: &MissionRun) -> Self {
        Self {
            m02: run.m02.clone(),
            m03: run.m03.clone(),
            m04: run.m04.clone(),
            m05: run.m05.clone(),
            m06: run.m06.clone(),
            m07: run.m07.clone(),
            m08: run.m08.clone(),
            m09: run.m09.clone(),
            m10: run.m10.clone(),
            m11: run.m11.clone(),
            m12: run.m12.clone(),
            m13: run.m13.clone(),
            m14: run.m14.clone(),
            m15: run.m15.clone(),
            m16: run.m16.clone(),
            m17: run.m17.clone(),
            m18: run.m18.clone(),
            m19: run.m19.clone(),
            m20: run.m20.clone(),
            companion: run.companion.clone(),
            phase: run.phase,
            started_at: run.started_at,
        }
    }

    /// Put these facts back into `run`, `by` ticks after they were saved.
    fn restore(mut self, run: &mut MissionRun, by: u64) {
        let shift = |tick: &mut Option<u64>| *tick = tick.map(|t| t.saturating_add(by));
        if let Some(p) = self.m05.as_mut() {
            p.shift_ticks(by);
        }
        if let Some(p) = self.m11.as_mut() {
            shift(&mut p.challenges.counter_boarding_started);
            shift(&mut p.challenges.signal_due);
            shift(&mut p.challenges.bridge_taken_at);
        }
        if let Some(p) = self.m12.as_mut() {
            shift(&mut p.challenges.first_pump_damage_at);
            shift(&mut p.challenges.shelter_route_secured_at);
        }
        if let Some(p) = self.m14.as_mut() {
            p.shift_ticks(by);
        }
        if let Some(p) = self.m17.as_mut() {
            shift(&mut p.custody_started);
        }
        if let Some(p) = self.m18.as_mut() {
            shift(&mut p.turn_started);
        }
        if let Some(p) = self.m20.as_mut() {
            shift(&mut p.pier_reached_at);
            shift(&mut p.reprieve_at);
            for crew in &mut p.crew {
                crew.depart_at = crew.depart_at.saturating_add(by);
            }
        }
        self.companion.shift_ticks(by);
        shift(&mut self.started_at);
        run.m02 = self.m02;
        run.m03 = self.m03;
        run.m04 = self.m04;
        run.m05 = self.m05;
        run.m06 = self.m06;
        run.m07 = self.m07;
        run.m08 = self.m08;
        run.m09 = self.m09;
        run.m10 = self.m10;
        run.m11 = self.m11;
        run.m12 = self.m12;
        run.m13 = self.m13;
        run.m14 = self.m14;
        run.m15 = self.m15;
        run.m16 = self.m16;
        run.m17 = self.m17;
        run.m18 = self.m18;
        run.m19 = self.m19;
        run.m20 = self.m20;
        run.companion = self.companion;
        run.phase = self.phase;
        run.started_at = self.started_at;
    }
}

/// The owner's health, armor and weapon and each pad's availability.
#[cfg(test)]
pub(crate) type CheckpointView = (i32, i32, WeaponType, Vec<(String, bool)>);

/// What the checkpoint pass reads before it decides, so the decision can
/// borrow the schedule mutably.
struct Moment {
    owner: Uuid,
    started_at: u64,
    complete: usize,
    changed_at: u64,
    vitals: i32,
    feet: [f32; 3],
    safe_body: bool,
}

impl GameState {
    /// The checkpoint ticks of this level so far, for evaluation.
    #[cfg(test)]
    pub(crate) fn campaign_checkpoint_ticks(&self) -> Vec<u64> {
        self.mission
            .as_ref()
            .and_then(|run| run.solo.as_ref())
            .map(|solo| solo.checkpoints.taken().to_vec())
            .unwrap_or_default()
    }

    /// The latest checkpoint's owner health, armor and weapon and its pads.
    #[cfg(test)]
    pub(crate) fn campaign_checkpoint_view(&self) -> Option<CheckpointView> {
        let saved = self
            .mission
            .as_ref()?
            .solo
            .as_ref()?
            .checkpoints
            .saved
            .as_ref()?;
        Some((
            saved.owner.hp,
            saved.owner.armor,
            saved.owner.weapon,
            saved.world.pads(),
        ))
    }

    /// The level-clock start of the current attempt, for evaluation.
    #[cfg(test)]
    pub(crate) fn campaign_attempt_started_at(&self) -> Option<u64> {
        self.mission.as_ref().and_then(|run| run.started_at)
    }

    fn checkpoint_moment(&self) -> Option<Moment> {
        let run = self.mission.as_ref()?;
        let solo = run.solo.as_ref()?;
        if run.epilogue.is_some()
            || !solo.playing()
            || !run.started
            || !matches!(
                run.phase,
                MissionPhase::FindTransfer | MissionPhase::ReachLift | MissionPhase::InProgress
            )
        {
            return None;
        }
        let owner = solo.owner()?;
        let started_at = run.started_at?;
        let player = self.players.iter().find(|p| p.id == owner)?;
        let feet = player.y - PLAYER_FLOOR_Y;
        let ground = self.current_arena().support_height(
            player.x,
            player.z,
            feet + crate::movement::STEP_UP,
        );
        let safe_body = player.hp > 0
            && player.respawn_timer.is_none()
            && !player.detached
            && player.vy == 0.0
            && !player.jet_thrusting
            && (feet - ground).abs() <= GROUNDED
            && self.vehicle_seat(owner).is_none();
        Some(Moment {
            owner,
            started_at,
            complete: self.encounters.complete_count(),
            changed_at: run.changed_at,
            vitals: player.hp + player.armor,
            feet: [player.x, feet, player.z],
            safe_body,
        })
    }

    /// One tick of the checkpoint schedule. Runs after the tick's movement and
    /// combat, so a save sees the state the next snapshot publishes.
    pub(crate) fn update_campaign_checkpoint(&mut self) {
        let Some(moment) = self.checkpoint_moment() else {
            return;
        };
        let tick = self.tick;
        let quiet = self.checkpoint_world_quiet()
            && !self.encounters.engaged(&self.players, Some(moment.feet));
        let Some(solo) = self.mission.as_mut().and_then(|run| run.solo.as_mut()) else {
            return;
        };
        let schedule = &mut solo.checkpoints;
        let Some(last) = schedule.last_at else {
            schedule.last_at = Some(moment.started_at);
            schedule.seen_complete = moment.complete;
            schedule.seen_changed = moment.changed_at;
            schedule.vitals = Some(moment.vitals);
            return;
        };
        if schedule.vitals.is_some_and(|vitals| moment.vitals < vitals) {
            schedule.hurt_at = Some(tick);
        }
        schedule.vitals = Some(moment.vitals);
        if moment.complete > schedule.seen_complete || moment.changed_at > schedule.seen_changed {
            schedule.due = true;
        }
        schedule.seen_complete = moment.complete;
        schedule.seen_changed = moment.changed_at;
        let since = tick.saturating_sub(last);
        if since >= CHECKPOINT_INTERVAL_TICKS {
            schedule.due = true;
        }
        let unhurt = schedule
            .hurt_at
            .is_none_or(|at| tick.saturating_sub(at) >= CHECKPOINT_HURT_QUIET_TICKS);
        if !schedule.due
            || since < CHECKPOINT_SPACING_TICKS
            || !unhurt
            || !quiet
            || !moment.safe_body
        {
            return;
        }
        let Some(groups) = self.encounters.marks(self, Some(moment.feet)) else {
            return;
        };
        let Some(player) = self.players.iter().find(|p| p.id == moment.owner) else {
            return;
        };
        let owner = OwnerSave {
            position: [player.x, player.y, player.z],
            yaw: player.yaw,
            pitch: player.pitch,
            hp: player.hp,
            armor: player.armor,
            weapon: player.weapon,
            last_non_blade_weapon: player.last_non_blade_weapon,
            inventory: player.inventory.clone(),
            jetpack: player.jetpack,
            ducking: player.ducking,
            statistics: player.statistics.clone(),
        };
        let score = self.scores.get(&moment.owner).copied().unwrap_or(0);
        let world = self.save_checkpoint_world();
        let strip_hits = self.paver_strip_hits;
        let Some(run) = self.mission.as_mut() else {
            return;
        };
        let facts = MissionFacts::of(run);
        let Some(solo) = run.solo.as_mut() else {
            return;
        };
        let schedule = &mut solo.checkpoints;
        schedule.saved = Some(Box::new(Checkpoint {
            tick,
            strip_hits,
            owner,
            score,
            facts,
            groups,
            world,
        }));
        schedule.last_at = Some(tick);
        schedule.due = false;
        schedule.taken.push(tick);
        self.events.push(GameEvent::Checkpoint {});
        tracing::info!(tick, "Campaign checkpoint saved");
    }

    /// Spend one continue and return the dead owner to the latest checkpoint.
    /// The caller has validated the request and that a checkpoint exists.
    pub(super) fn continue_from_checkpoint(
        &mut self,
        player_id: Uuid,
        request: MissionContinue,
    ) -> bool {
        let tick = self.tick;
        let Some(solo) = self.mission.as_mut().and_then(|run| run.solo.as_mut()) else {
            return false;
        };
        let Some(checkpoint) = solo.checkpoints.saved.take() else {
            return false;
        };
        let by = tick.saturating_sub(checkpoint.tick);
        let Some(player) = self
            .players
            .iter_mut()
            .find(|p| p.id == player_id && p.hp <= 0)
        else {
            solo.checkpoints.saved = Some(checkpoint);
            return false;
        };
        solo.state.continues -= 1;
        solo.state.status = CampaignRunStatus::Playing;
        let saved = &checkpoint.owner;
        [player.x, player.y, player.z] = saved.position;
        player.yaw = saved.yaw;
        player.pitch = saved.pitch;
        player.vx = 0.0;
        player.vy = 0.0;
        player.vz = 0.0;
        player.hp = saved.hp;
        player.armor = saved.armor;
        player.weapon = saved.weapon;
        player.last_non_blade_weapon = saved.last_non_blade_weapon;
        player.inventory.restore_entry(&saved.inventory);
        player.jetpack = saved.jetpack;
        player.jet_thrusting = false;
        player.ducking = saved.ducking;
        player.statistics.restore_attempt(&saved.statistics);
        player.interaction_requested = false;
        player.clear_input();
        player.just_fired = false;
        player.fire_cooldown = 0;
        player.respawn_timer = None;
        player.killstreak = 0;
        self.scores.insert(player_id, checkpoint.score);
        // The retry draws its own stream, as a retry from the entry does.
        self.restart_stream(retry_seed(
            self.seed_base(),
            request.run_id,
            request.attempt.saturating_add(1),
        ));
        self.restore_checkpoint_world(&checkpoint.world, by);
        let mut encounters = std::mem::take(&mut self.encounters);
        encounters.restore_marks(&checkpoint.groups, self);
        self.encounters = encounters;
        let strip_hits = self.paver_strip_hits.saturating_sub(checkpoint.strip_hits);
        let complete = self.encounters.complete_count();
        let Some(run) = self.mission.as_mut() else {
            return false;
        };
        checkpoint.facts.clone().restore(run, by);
        if let Some(m19) = run.m19.as_mut() {
            m19.forgive_strip_hits(strip_hits);
        }
        run.attempt = run.attempt.saturating_add(1);
        run.changed_at = tick;
        run.started = true;
        if let Some(solo) = run.solo.as_mut() {
            solo.checkpoints.restart(tick);
            solo.checkpoints.seen_complete = complete;
            solo.checkpoints.saved = Some(checkpoint);
        }
        self.ensure_m03_companion();
        self.ensure_m04_companion();
        self.ensure_m05_companion();
        self.ensure_m06_companion();
        self.ensure_m08_companion();
        self.ensure_m07_companion();
        self.ensure_m09_companion();
        self.ensure_m10_companion();
        tracing::info!(
            attempt = request.attempt + 1,
            "Campaign continue spent; checkpoint restored"
        );
        true
    }
}
