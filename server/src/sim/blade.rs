//! Article Blade plinth lifecycle: available, held, cooling.
use crate::protocol::{
    ArticleBladeInfo, ArticleBladePhase, ArticleBladeState, PickupState, SupplyClaim, WeaponType,
};
use std::collections::BTreeSet;
use uuid::Uuid;

#[allow(dead_code)]
pub const DEFAULT_BLADE_RETURN_TICKS: u32 = 300;
#[allow(dead_code)]
pub const EXPERIMENTAL_LONG_RETURN_TICKS: u32 = 1200;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ArticleBladePlinthPhase {
    Available,
    Held { holder: Uuid },
    Cooling { return_in: u32 },
}

#[derive(Debug, Clone)]
pub struct ArticleBladePlinth {
    pickup_id: String,
    feet: [f32; 3],
    return_ticks: u32,
    phase: ArticleBladePlinthPhase,
    changed_at: u64,
    outside_seen: BTreeSet<Uuid>,
}

#[allow(dead_code)]
impl ArticleBladePlinth {
    pub fn new(info: ArticleBladeInfo) -> Self {
        Self {
            pickup_id: info.pickup_id,
            feet: info.feet,
            return_ticks: info.return_ticks,
            phase: ArticleBladePlinthPhase::Available,
            changed_at: 0,
            outside_seen: BTreeSet::new(),
        }
    }

    pub fn pickup_id(&self) -> &str {
        &self.pickup_id
    }

    pub fn feet(&self) -> [f32; 3] {
        self.feet
    }

    pub fn return_ticks(&self) -> u32 {
        self.return_ticks
    }

    pub fn phase(&self) -> &ArticleBladePlinthPhase {
        &self.phase
    }

    pub fn changed_at(&self) -> u64 {
        self.changed_at
    }

    pub fn is_available(&self) -> bool {
        matches!(self.phase, ArticleBladePlinthPhase::Available)
    }

    pub fn holder(&self) -> Option<Uuid> {
        match self.phase {
            ArticleBladePlinthPhase::Held { holder } => Some(holder),
            _ => None,
        }
    }

    pub fn return_in(&self) -> Option<u32> {
        match self.phase {
            ArticleBladePlinthPhase::Cooling { return_in } => Some(return_in),
            _ => None,
        }
    }

    /// Reset whole plinth lifecycle to initial Available state.
    pub fn reset(&mut self, tick: u64) {
        self.phase = ArticleBladePlinthPhase::Available;
        self.changed_at = tick;
        self.outside_seen.clear();
    }

    /// Record an eligible participant observed outside the claim footprint.
    pub fn record_outside(&mut self, id: Uuid) {
        if self.is_available() {
            self.outside_seen.insert(id);
        }
    }

    /// Check whether a participant was observed outside the claim footprint
    /// while available, preventing pad camping across return.
    pub fn is_eligible_outside(&self, id: Uuid) -> bool {
        self.is_available() && self.outside_seen.contains(&id)
    }

    /// Claim the blade for a winner. Clears approach latches.
    pub fn claim(&mut self, holder: Uuid, tick: u64) {
        self.phase = ArticleBladePlinthPhase::Held { holder };
        self.changed_at = tick;
        self.outside_seen.clear();
    }

    /// Start plinth cooldown after exhaustion, holder death or leave.
    pub fn start_cooling(&mut self, tick: u64) {
        self.phase = ArticleBladePlinthPhase::Cooling {
            return_in: self.return_ticks,
        };
        self.changed_at = tick;
        self.outside_seen.clear();
    }

    pub fn on_player_leave(&mut self, id: Uuid, tick: u64) {
        self.outside_seen.remove(&id);
        if self.holder() == Some(id) {
            self.start_cooling(tick);
        }
    }

    pub fn on_holder_death(&mut self, id: Uuid, tick: u64) {
        if self.holder() == Some(id) {
            self.start_cooling(tick);
        }
    }

    pub fn on_exhausted(&mut self, tick: u64) {
        self.start_cooling(tick);
    }

    /// Decrement cooldown on active ticks only (pause semantics).
    pub fn tick_active(&mut self, tick: u64) {
        if let ArticleBladePlinthPhase::Cooling { return_in } = &mut self.phase {
            *return_in = return_in.saturating_sub(1);
            if *return_in == 0 {
                self.phase = ArticleBladePlinthPhase::Available;
                self.changed_at = tick;
                self.outside_seen.clear();
            }
        }
    }

    pub fn state(&self, holder_uses: u16) -> ArticleBladeState {
        ArticleBladeState {
            pickup_id: self.pickup_id.clone(),
            phase: match self.phase {
                ArticleBladePlinthPhase::Available => ArticleBladePhase::Available,
                ArticleBladePlinthPhase::Held { .. } => ArticleBladePhase::Held,
                ArticleBladePlinthPhase::Cooling { .. } => ArticleBladePhase::Cooling,
            },
            uses_left: match self.phase {
                ArticleBladePlinthPhase::Held { .. } => holder_uses,
                _ => 0,
            },
            changed_at: self.changed_at,
            holder: self.holder(),
            return_in: self.return_in(),
        }
    }

    pub fn pickup_state(&self) -> PickupState {
        PickupState {
            claim: SupplyClaim::Contested,
            pool: None,
            id: self.pickup_id.clone(),
            kind: "weapon".to_string(),
            weapon: WeaponType::ArticleBlade.name().to_string(),
            amount: None,
            x: self.feet[0],
            y: self.feet[1] + 0.4,
            z: self.feet[2],
            available: self.is_available(),
            dropped: false,
        }
    }
}

#[cfg(test)]
mod tests;
