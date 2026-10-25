//! Restoration Paver: a bounded ground strip, an open preparation and a short
//! work cycle. The strip is fixed when the tell begins and never follows a
//! dodge. A hard enough hit during the preparation puts it out.
use super::*;
use crate::movement::{Arena, STEP_UP};

/// Furthest reach of one strip along the floor, from its near edge.
pub(crate) const STRIP_LENGTH: f32 = 15.0;
pub(crate) const STRIP_HALF_WIDTH: f32 = 1.6;
/// The near edge starts just ahead of the projector.
pub(crate) const STRIP_OFFSET: f32 = 0.9;
/// A marked strip shorter than this is not worth committing to: the Paver
/// walks for a better line instead.
pub(crate) const STRIP_MIN_LENGTH: f32 = 4.0;
/// Feet within this height of the strip's floor are inside it. A fighter
/// above the band, on a ledge or under thrust, is not worked.
pub(crate) const STRIP_FLOOR_BAND: f32 = 0.7;
/// The work cycle after the preparation, and its pulses inside it.
pub(crate) const WORK_TICKS: u64 = 12;
pub(crate) const WORK_PULSE_TICKS: u64 = 4;
pub(crate) const WORK_DAMAGE: i32 = 18;
/// Damage landed on the body during one preparation that puts the strip out.
pub(crate) const INTERRUPT_DAMAGE: i32 = 30;
/// The projector reseats after an interruption before it can mark again.
pub(crate) const INTERRUPT_STUN_TICKS: u64 = 30;
/// Sample spacing for the strip's end against walls, drops and the map edge.
const MARK_STEP: f32 = 0.25;

/// One marked strip: a floor rectangle from `origin` along `yaw`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Strip {
    pub origin: [f32; 3],
    pub yaw: f32,
    pub length: f32,
    pub half_width: f32,
}

impl Strip {
    pub(crate) fn axis(&self) -> ([f32; 2], [f32; 2]) {
        let forward = [self.yaw.cos(), self.yaw.sin()];
        (forward, [-forward[1], forward[0]])
    }

    /// Strip-local (along, across) coordinates of a floor point.
    pub(crate) fn local(&self, x: f32, z: f32) -> (f32, f32) {
        let (forward, lateral) = self.axis();
        let dx = x - self.origin[0];
        let dz = z - self.origin[2];
        (
            dx * forward[0] + dz * forward[1],
            dx * lateral[0] + dz * lateral[1],
        )
    }

    /// A body is worked when its centre stands on the strip's floor inside it.
    pub(crate) fn contains(&self, feet: [f32; 3]) -> bool {
        let (along, across) = self.local(feet[0], feet[2]);
        (0.0..=self.length).contains(&along)
            && across.abs() <= self.half_width
            && (feet[1] - self.origin[1]).abs() <= STRIP_FLOOR_BAND
    }
}

/// Mark the longest clear strip from `feet` along `yaw`, ending at the first
/// wall, raised edge, drop or map boundary under any of its three lines.
pub(crate) fn mark(arena: &Arena, feet: [f32; 3], yaw: f32) -> Option<Strip> {
    if !feet.iter().all(|v| v.is_finite()) || !yaw.is_finite() {
        return None;
    }
    let floor = feet[1];
    let forward = [yaw.cos(), yaw.sin()];
    let lateral = [-forward[1], forward[0]];
    let limit = arena.half - 0.05;
    let clear = |distance: f32| {
        [-STRIP_HALF_WIDTH, 0.0, STRIP_HALF_WIDTH]
            .iter()
            .all(|offset| {
                let x = feet[0] + forward[0] * distance + lateral[0] * offset;
                let z = feet[2] + forward[1] * distance + lateral[1] * offset;
                x.abs() <= limit
                    && z.abs() <= limit
                    && (arena.support_height(x, z, floor + STEP_UP) - floor).abs() <= 0.05
                    && !arena.solids.iter().any(|solid| {
                        solid.covers(x, z) && solid.top > floor + 0.05 && solid.bottom < floor + 1.2
                    })
            })
    };
    let mut reached = None;
    let steps = (STRIP_LENGTH / MARK_STEP).round() as usize;
    for step in 0..=steps {
        let distance = STRIP_OFFSET + step as f32 * MARK_STEP;
        if !clear(distance) {
            break;
        }
        reached = Some(distance);
    }
    let length = reached? - STRIP_OFFSET;
    (length >= STRIP_MIN_LENGTH).then(|| Strip {
        origin: [
            feet[0] + forward[0] * STRIP_OFFSET,
            floor,
            feet[2] + forward[1] * STRIP_OFFSET,
        ],
        yaw: yaw.rem_euclid(TAU),
        length,
        half_width: STRIP_HALF_WIDTH,
    })
}

impl EnemyController {
    /// Intent for one tick. `damage` is the authoritative health lost since the
    /// previous intent, so trading shooters and pellets add up together.
    /// `may_prepare` holds when the body stands on its floor and a ranged
    /// token on the participant is free: a strip on screen is an attack.
    #[allow(clippy::too_many_arguments)]
    pub(super) fn paver(
        &mut self,
        arena: &Arena,
        target: Option<&crate::protocol::PlayerState>,
        feet: [f32; 3],
        may_prepare: bool,
        damage: i32,
        timing: (u64, u64),
        tick: u64,
    ) -> BotIntent {
        let mut action = Action::default();
        if self.phase == EnemyPhase::Windup {
            self.prep_damage = self.prep_damage.saturating_add(damage.max(0));
            if self.prep_damage >= INTERRUPT_DAMAGE {
                self.paver_strip = None;
                self.paver_interruptions = self.paver_interruptions.saturating_add(1);
                self.enter(EnemyPhase::Hit, tick, INTERRUPT_STUN_TICKS);
                return BotIntent::default();
            }
            action.yaw = Some(self.aim.0);
            if tick >= self.until {
                self.enter(EnemyPhase::Firing, tick, WORK_TICKS);
            }
            return BotIntent { action, goal: None };
        }
        if self.phase == EnemyPhase::Firing {
            if tick >= self.until {
                self.paver_strip = None;
                self.enter(EnemyPhase::Recovery, tick, timing.1);
                return BotIntent::default();
            }
            action.yaw = Some(self.aim.0);
            return BotIntent { action, goal: None };
        }
        if damage >= STAGGER_DAMAGE && self.stagger_ready && self.phase != EnemyPhase::Hit {
            self.stagger_ready = false;
            self.enter(EnemyPhase::Hit, tick, stun(self.kind));
            return BotIntent::default();
        }
        if matches!(self.phase, EnemyPhase::Hit | EnemyPhase::Recovery) && tick < self.until {
            return BotIntent::default();
        }
        let destination = target.map_or(self.last_known, |p| [p.x, p.y - PLAYER_FLOOR_Y, p.z]);
        let distance = (destination[0] - feet[0]).hypot(destination[2] - feet[2]);
        if let Some(target) = target.filter(|_| may_prepare) {
            let at = [target.x, target.y - PLAYER_FLOOR_Y, target.z];
            if (at[1] - feet[1]).abs() <= STRIP_FLOOR_BAND
                && distance <= STRIP_OFFSET + STRIP_LENGTH
            {
                let yaw = (at[2] - feet[2]).atan2(at[0] - feet[0]).rem_euclid(TAU);
                if let Some(strip) = mark(arena, feet, yaw).filter(|strip| strip.contains(at)) {
                    self.paver_strip = Some(strip);
                    self.prep_damage = 0;
                    self.stagger_ready = true;
                    self.aim = (yaw, 0.0);
                    self.head = yaw;
                    self.enter(EnemyPhase::Windup, tick, timing.0);
                    action.yaw = Some(yaw);
                    return BotIntent { action, goal: None };
                }
            }
        }
        // A Paver works the floor it stands on. A target on another level is
        // watched, not followed off a roof or up a stair.
        if (destination[1] - feet[1]).abs() > STRIP_FLOOR_BAND + 0.8 {
            if self.phase != EnemyPhase::Idle {
                self.enter(EnemyPhase::Idle, tick, 0);
            }
            action.yaw = Some((destination[2] - feet[2]).atan2(destination[0] - feet[0]));
            return BotIntent { action, goal: None };
        }
        if distance > 1.5 && (target.is_some() || tick <= self.search_until) {
            if self.phase != EnemyPhase::Moving {
                self.enter(EnemyPhase::Moving, tick, 0);
            }
            action.forward = true;
            action.yaw = Some((destination[2] - feet[2]).atan2(destination[0] - feet[0]));
            return BotIntent {
                action,
                goal: Some(NavigationGoal {
                    feet: destination,
                    combat: target.is_some(),
                }),
            };
        }
        if self.phase != EnemyPhase::Idle {
            self.enter(EnemyPhase::Idle, tick, 0);
        }
        BotIntent::default()
    }

    /// The marked strip while it is being prepared or worked.
    pub(in crate::encounters) fn paver_strip(&self) -> Option<Strip> {
        (self.kind == EnemyKind::Paver
            && matches!(self.phase, EnemyPhase::Windup | EnemyPhase::Firing))
        .then_some(self.paver_strip)
        .flatten()
    }

    /// A work pulse lands on this tick of the work cycle.
    pub(in crate::encounters) fn paver_pulse(&self, tick: u64) -> Option<Strip> {
        let elapsed = tick.checked_sub(self.started)?;
        (self.phase == EnemyPhase::Firing
            && elapsed < WORK_TICKS
            && elapsed.is_multiple_of(WORK_PULSE_TICKS))
        .then(|| self.paver_strip())
        .flatten()
    }

    pub(in crate::encounters) fn paver_interruptions(&self) -> u32 {
        self.paver_interruptions
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::movement::Solid;

    fn open(half: f32) -> Arena {
        Arena {
            half,
            solids: Vec::new(),
        }
    }

    fn paver(tick: u64) -> EnemyController {
        EnemyController::new(
            Uuid::from_u128(19),
            EnemyKind::Paver,
            [0.0, 0.0, 0.0],
            0.0,
            tick,
            false,
        )
    }

    fn visitor(x: f32, z: f32) -> crate::protocol::PlayerState {
        let mut game = GameState::new();
        game.add_player(
            Uuid::from_u128(1),
            "Visitor".into(),
            crate::protocol::Role::Human,
        );
        let mut target = game.snapshot().players.remove(0);
        target.x = x;
        target.z = z;
        target.y = PLAYER_FLOOR_Y;
        target
    }

    #[test]
    fn a_strip_ends_at_walls_drops_and_the_map_edge_on_all_three_lines() {
        let full = mark(&open(40.0), [0.0; 3], 0.0).unwrap();
        assert_eq!(full.length, STRIP_LENGTH);
        assert_eq!(full.origin, [STRIP_OFFSET, 0.0, 0.0]);
        assert!(full.contains([8.0, 0.0, 1.5]));
        assert!(!full.contains([8.0, 0.0, 1.7]), "outside the edge");
        assert!(!full.contains([0.5, 0.0, 0.0]), "behind the near edge");
        assert!(!full.contains([8.0, 0.8, 0.0]), "above the floor band");

        // A wall that only blocks one edge line still ends the strip.
        let mut walled = open(40.0);
        walled
            .solids
            .push(Solid::from_center_top(8.0, 1.5, 0.5, 0.3, 4.5));
        let clipped = mark(&walled, [0.0; 3], 0.0).unwrap();
        assert!(clipped.length < 7.6 - STRIP_OFFSET && clipped.length > 6.0);

        // A raised kerb, a drop off a deck and the map boundary all stop it.
        let mut kerb = open(40.0);
        kerb.solids
            .push(Solid::from_center_top(10.0, 0.0, 0.5, 4.0, 0.3));
        assert!(mark(&kerb, [0.0; 3], 0.0).unwrap().length < 9.5 - STRIP_OFFSET);
        let mut deck = open(40.0);
        deck.solids
            .push(Solid::from_center_top(4.0, 0.0, 6.0, 4.0, 3.0));
        let on_deck = mark(&deck, [0.0, 3.0, 0.0], 0.0).unwrap();
        assert!(on_deck.length < 10.0 - STRIP_OFFSET + 0.01);
        assert_eq!(on_deck.origin[1], 3.0);
        assert!(mark(&open(8.0), [0.0; 3], 0.0).unwrap().length <= 8.0 - STRIP_OFFSET);
        // Too short to be worth a tell.
        let mut boxed = open(40.0);
        boxed
            .solids
            .push(Solid::from_center_top(3.5, 0.0, 0.5, 4.0, 4.5));
        assert!(mark(&boxed, [0.0; 3], 0.0).is_none());
    }

    #[test]
    fn preparation_locks_the_strip_works_three_pulses_and_never_follows_a_dodge() {
        for (tier, windup, recovery) in [
            (CampaignDifficulty::Assisted, 44, 50),
            (CampaignDifficulty::Standard, 34, 40),
            (CampaignDifficulty::Severe, 28, 32),
        ] {
            assert_eq!(attack_timing(EnemyKind::Paver, tier), (windup, recovery));
            let arena = open(40.0);
            let mut enemy = paver(10);
            let near = visitor(8.0, 0.0);
            let first = enemy.paver(
                &arena,
                Some(&near),
                [0.0; 3],
                true,
                0,
                (windup, recovery),
                10,
            );
            assert_eq!(enemy.phase, EnemyPhase::Windup);
            assert_eq!(enemy.until, 10 + windup);
            assert!(first.goal.is_none() && !first.action.forward && !first.action.fire);
            let strip = enemy.paver_strip().unwrap();
            let dodged = visitor(8.0, 6.0);
            for tick in 11..10 + windup {
                let intent = enemy.paver(
                    &arena,
                    Some(&dodged),
                    [0.0; 3],
                    true,
                    0,
                    (windup, recovery),
                    tick,
                );
                assert_eq!(intent.action.yaw, Some(0.0), "locked");
                assert_eq!(enemy.paver_strip(), Some(strip), "never re-aimed");
                assert!(enemy.paver_pulse(tick).is_none(), "no work during the tell");
            }
            enemy.paver(
                &arena,
                Some(&dodged),
                [0.0; 3],
                true,
                0,
                (windup, recovery),
                10 + windup,
            );
            assert_eq!(enemy.phase, EnemyPhase::Firing);
            let pulses: Vec<u64> = (10 + windup..10 + windup + WORK_TICKS)
                .filter(|tick| enemy.paver_pulse(*tick).is_some())
                .collect();
            assert_eq!(pulses, vec![10 + windup, 14 + windup, 18 + windup]);
            let end = 10 + windup + WORK_TICKS;
            enemy.paver(&arena, None, [0.0; 3], true, 0, (windup, recovery), end);
            assert_eq!(enemy.phase, EnemyPhase::Recovery);
            assert_eq!(enemy.until, end + recovery);
            assert!(enemy.paver_strip().is_none());
            assert_eq!(enemy.paver_interruptions(), 0);
        }
    }

    #[test]
    fn hits_during_preparation_put_the_strip_out_and_a_short_one_does_not() {
        let arena = open(40.0);
        let timing = attack_timing(EnemyKind::Paver, CampaignDifficulty::Standard);
        let near = visitor(6.0, 0.0);
        let mut enemy = paver(0);
        enemy.paver(&arena, Some(&near), [0.0; 3], true, 0, timing, 1);
        // Two light hits below the threshold keep the tell running.
        enemy.paver(&arena, Some(&near), [0.0; 3], true, 12, timing, 2);
        enemy.paver(&arena, Some(&near), [0.0; 3], true, 12, timing, 3);
        assert_eq!(enemy.phase, EnemyPhase::Windup);
        assert!(enemy.paver_strip().is_some());
        // A third hit crosses it: the strip goes out and the body reseats.
        let out = enemy.paver(&arena, Some(&near), [0.0; 3], true, 12, timing, 4);
        assert_eq!(enemy.phase, EnemyPhase::Hit);
        assert_eq!(enemy.until, 4 + INTERRUPT_STUN_TICKS);
        assert!(!out.action.forward && out.action.yaw.is_none() && out.goal.is_none());
        assert!(enemy.paver_strip().is_none() && enemy.paver_pulse(4).is_none());
        assert_eq!(enemy.paver_interruptions(), 1);
        // Damage during the work cycle does not cancel committed work.
        let mut working = paver(0);
        working.paver(&arena, Some(&near), [0.0; 3], true, 0, timing, 1);
        working.paver(&arena, Some(&near), [0.0; 3], true, 0, timing, 1 + timing.0);
        working.paver(
            &arena,
            Some(&near),
            [0.0; 3],
            true,
            60,
            timing,
            2 + timing.0,
        );
        assert_eq!(working.phase, EnemyPhase::Firing);
        assert_eq!(working.paver_interruptions(), 0);
    }

    #[test]
    fn a_target_beyond_reach_draws_the_paver_closer_but_another_floor_is_only_watched() {
        let arena = open(40.0);
        let timing = attack_timing(EnemyKind::Paver, CampaignDifficulty::Standard);
        let mut far = paver(0);
        let distant = visitor(30.0, 0.0);
        let walk = far.paver(&arena, Some(&distant), [0.0; 3], true, 0, timing, 1);
        assert_eq!(far.phase, EnemyPhase::Moving);
        assert!(walk.action.forward && walk.goal.is_some());
        let mut low = paver(0);
        let mut raised = visitor(6.0, 0.0);
        raised.y = PLAYER_FLOOR_Y + 3.0;
        let watch = low.paver(&arena, Some(&raised), [0.0; 3], true, 0, timing, 1);
        assert_eq!(low.phase, EnemyPhase::Idle, "never follows off its floor");
        assert!(!watch.action.forward && watch.goal.is_none() && watch.action.yaw.is_some());
        // An airborne Paver never begins a strip.
        let mut falling = paver(0);
        falling.paver(
            &arena,
            Some(&visitor(6.0, 0.0)),
            [0.0; 3],
            false,
            0,
            timing,
            1,
        );
        assert_ne!(falling.phase, EnemyPhase::Windup);
    }
}
