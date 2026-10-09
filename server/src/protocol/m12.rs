//! Terms of Cooperation habitat facts, owned by the authoritative mission.
use super::{
    CampaignDifficulty, MapPresentation, MissionObjective, MissionObjectiveAction, MissionPhase,
    Region3, UseTarget,
};
use crate::movement::Solid;
use serde::{Deserialize, Serialize};

pub const M12_PUMP_MAX_HP: u16 = 100;
pub const M12_OBJECTIVE_IDS: [&str; 6] = [
    "market_secured",
    "arc_found",
    "greenhouse_secured",
    "shelter_route_secured",
    "aid_force_arrived",
    "coalition_commitment",
];

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M12PumpGeometry {
    pub id: String,
    pub solids: [usize; 3],
    pub health: u16,
}
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M12AidVehicle {
    pub feet: [f32; 3],
    pub yaw: f32,
}
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M12MapGeometry {
    pub objectives: Vec<MissionObjective>,
    pub shelter_release: UseTarget,
    pub worker_release: UseTarget,
    pub commitment: UseTarget,
    pub departure: UseTarget,
    pub boarding: Region3,
    pub shelter_door: usize,
    pub shelter_open: bool,
    pub shelter_people: Vec<[f32; 3]>,
    pub workers: Vec<[f32; 3]>,
    pub pumps: [M12PumpGeometry; 2],
    pub aid_vehicles: [M12AidVehicle; 2],
}
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M12ChallengeState {
    pub shelter_opened: bool,
    pub workers_released: bool,
    pub pump_health: [u16; 2],
    pub assessor_wreck_union_kills: u8,
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub first_pump_damage_at: Option<u64>,
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub shelter_route_secured_at: Option<u64>,
}
impl Default for M12ChallengeState {
    fn default() -> Self {
        Self {
            shelter_opened: false,
            workers_released: false,
            pump_health: [M12_PUMP_MAX_HP; 2],
            assessor_wreck_union_kills: 0,
            first_pump_damage_at: None,
            shelter_route_secured_at: None,
        }
    }
}
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct M12ObjectiveState {
    pub completed: Vec<String>,
    #[serde(
        default,
        deserialize_with = "super::m11::present",
        skip_serializing_if = "Option::is_none"
    )]
    pub current: Option<MissionObjective>,
    pub challenges: M12ChallengeState,
    /// Actual server vehicle identities, empty until the depot arrival.
    pub aid_vehicle_ids: Vec<u32>,
}
fn point(p: [f32; 3], half: f32) -> bool {
    p.iter().all(|v| v.is_finite())
        && p[0].abs() <= half
        && p[2].abs() <= half
        && (0.0..=512.0).contains(&p[1])
}
impl M12MapGeometry {
    pub fn validate(
        &self,
        half: f32,
        solids: &[Solid],
        presentation: Option<&MapPresentation>,
    ) -> Result<(), &'static str> {
        let present = presentation.ok_or("M12 presentation missing")?;
        if !half.is_finite()
            || !(2.0..=crate::movement::MAX_HALF_EXTENT).contains(&half)
            || self.objectives.len() != 6
            || self
                .objectives
                .iter()
                .zip(M12_OBJECTIVE_IDS)
                .enumerate()
                .any(|(i, (o, id))| {
                    o.id != id
                        || match &o.action {
                            MissionObjectiveAction::Arrival { region, feet } => {
                                i == 5
                                    || !region.valid(half)
                                    || !point(*feet, half)
                                    || !region.contains(*feet)
                            }
                            MissionObjectiveAction::Use { target } => {
                                i != 5 || target != &self.commitment
                            }
                            _ => true,
                        }
                })
            || !self.boarding.valid(half)
            || !self.boarding.contains(self.departure.approach)
            || self.shelter_door >= solids.len()
            || self.shelter_people.len() != 3
            || self.workers.len() != 3
            || self
                .shelter_people
                .iter()
                .chain(&self.workers)
                .any(|p| !point(*p, half))
            || [&self.shelter_people, &self.workers]
                .into_iter()
                .any(|people| {
                    people.iter().enumerate().any(|(index, feet)| {
                        people[..index].iter().any(|old| {
                            (feet[0] - old[0]).hypot(feet[2] - old[2])
                                < crate::movement::RADIUS * 2.0
                        })
                    })
                })
            || self
                .pumps
                .iter()
                .zip(["west", "east"])
                .enumerate()
                .any(|(i, (p, id))| {
                    p.id != id
                        || p.health != M12_PUMP_MAX_HP
                        || p.solids.iter().enumerate().any(|(n, s)| {
                            *s >= solids.len()
                                || *s == self.shelter_door
                                || p.solids[..n].contains(s)
                                || self.pumps[..i].iter().any(|old| old.solids.contains(s))
                        })
                })
            || self.aid_vehicles.iter().any(|v| {
                !point(v.feet, half)
                    || !v.yaw.is_finite()
                    || !(0.0..std::f32::consts::TAU).contains(&v.yaw)
            })
        {
            return Err("invalid M12 habitat geometry");
        }
        let targets = [
            &self.shelter_release,
            &self.worker_release,
            &self.commitment,
            &self.departure,
        ];
        if targets.iter().enumerate().any(|(i, t)| {
            !point(t.approach, half)
                || t.point(present, solids).is_none()
                || targets[..i]
                    .iter()
                    .any(|old| old.decoration == t.decoration)
        }) {
            return Err("invalid M12 physical controls");
        }
        Ok(())
    }
}
impl M12ChallengeState {
    pub fn validate(&self, tick: u64) -> Result<(), &'static str> {
        let exact = (1u64 << 53) - 1;
        if tick > exact
            || self.pump_health.iter().any(|hp| *hp > M12_PUMP_MAX_HP)
            || self.assessor_wreck_union_kills > 3
            || self.first_pump_damage_at.is_some_and(|at| at > tick)
            || self.shelter_route_secured_at.is_some_and(|at| at > tick)
            || self.first_pump_damage_at.is_some()
                != self.pump_health.iter().any(|hp| *hp < M12_PUMP_MAX_HP)
            || self.shelter_opened && self.shelter_route_secured_at.is_none()
        {
            return Err("invalid M12 resolved challenge receipts");
        }
        Ok(())
    }
    pub fn pumps_intact_at_route_secure(&self) -> bool {
        self.shelter_route_secured_at.is_some_and(|secured| {
            self.first_pump_damage_at
                .is_none_or(|damage| damage > secured)
        })
    }
    /// Optional brief results never gate the required departure.
    pub fn brief_completed(&self, difficulty: CampaignDifficulty) -> bool {
        self.shelter_route_secured_at.is_some()
            && (difficulty == CampaignDifficulty::Assisted || self.assessor_wreck_union_kills > 0)
            && (difficulty != CampaignDifficulty::Severe || self.pumps_intact_at_route_secure())
    }
}
impl M12ObjectiveState {
    pub fn validate(&self, phase: MissionPhase, tick: u64) -> Result<(), &'static str> {
        self.challenges.validate(tick)?;
        let n = self.completed.len();
        let order = |i| {
            M12_OBJECTIVE_IDS
                .get(i)
                .copied()
                .unwrap_or("party_departed")
        };
        if !matches!(
            phase,
            MissionPhase::Briefing | MissionPhase::InProgress | MissionPhase::Departed
        ) || n > 7
            || self
                .completed
                .iter()
                .enumerate()
                .any(|(i, s)| s != order(i))
            || (phase == MissionPhase::Departed) != (n == 7)
            || self.current.is_some() != (n <= 6)
            || phase == MissionPhase::Briefing
                && (n != 0 || self.challenges != M12ChallengeState::default())
            || self.challenges.shelter_route_secured_at.is_some() != (n >= 4)
            || self.challenges.workers_released && n < 3
            || (if n >= 5 {
                self.aid_vehicle_ids.len() != 2
            } else {
                !self.aid_vehicle_ids.is_empty()
            })
            || self
                .aid_vehicle_ids
                .iter()
                .enumerate()
                .any(|(i, id)| *id == 0 || self.aid_vehicle_ids[..i].contains(id))
        {
            return Err("invalid M12 ordered progression");
        }
        if let Some(o) = &self.current {
            if o.id != order(n)
                || match &o.action {
                    MissionObjectiveAction::Arrival { region, feet } => {
                        n >= 5
                            || !region.valid(512.0)
                            || !point(*feet, 512.0)
                            || !region.contains(*feet)
                    }
                    MissionObjectiveAction::Use { target } => {
                        n < 5
                            || !point(target.approach, 512.0)
                            || target.decoration >= super::MAX_MAP_DECORATIONS
                    }
                    _ => true,
                }
            {
                return Err("invalid M12 current objective");
            }
        }
        Ok(())
    }
}
