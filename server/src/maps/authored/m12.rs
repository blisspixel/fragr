//! Connected habitat authoring. Both shelter worlds and aid hull routes are prepared before readiness.
use super::{
    encounters::EncounterDefinition, identity, invalid, standing, vehicle_placements, Placement,
};
use crate::movement::{Arena, EYE_HEIGHT};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{
    EnemyKind, M12AidVehicle, M12MapGeometry, M12PumpGeometry, MapDecoration, MapDecorationKind,
    MapPresentation, MissionObjective, MissionObjectiveAction, Region3, UseTarget,
    M12_OBJECTIVE_IDS, M12_PUMP_MAX_HP, USE_DISTANCE,
};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::Arc,
};

pub(crate) const GROUPS: [&str; 4] = [
    "market_defense",
    "maintenance_defense",
    "greenhouse_defense",
    "court_defense",
];
pub(crate) const OBJECTIVE_GROUPS: [usize; 6] = [0, 1, 2, 3, 3, 3];
pub(crate) const AID_SUPPLY_IDS: [&str; 3] = ["aid_medical", "aid_cells", "aid_armor"];
pub(super) fn validate_supplies(supplies: &[crate::sim::ArenaPickup]) -> io::Result<()> {
    use crate::{
        protocol::{AmmoPool, SupplyClaim, WeaponType},
        sim::PickupKind,
    };
    let required = [
        (AID_SUPPLY_IDS[0], PickupKind::Health, 40),
        (
            AID_SUPPLY_IDS[1],
            PickupKind::Ammo {
                pool: AmmoPool::Cells,
                rounds: 24,
            },
            0,
        ),
        (AID_SUPPLY_IDS[2], PickupKind::Armor, 50),
    ];
    if required.iter().any(|(id, kind, amount)| {
        supplies.iter().find(|p| p.id == *id).is_none_or(|p| {
            p.kind != *kind || p.amount != *amount || p.claim != SupplyClaim::Contested || p.secret
        })
    }) || !supplies
        .iter()
        .any(|p| p.kind == PickupKind::Weapon(WeaponType::Arc) && p.claim == SupplyClaim::Personal)
    {
        return Err(invalid(
            "M12 requires the actual Arc find and three finite aid stocks",
        ));
    }
    Ok(())
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Definition {
    objectives: Vec<Objective>,
    shelter_release: PanelTarget,
    worker_release: PanelTarget,
    commitment: PanelTarget,
    departure: PanelTarget,
    boarding: Region3,
    shelter_door: String,
    shelter_people: Vec<[f32; 3]>,
    workers: Vec<[f32; 3]>,
    aid_vehicles: Vec<Placement>,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Objective {
    id: String,
    #[serde(default)]
    arrival: Option<Region3>,
    #[serde(default)]
    approach: Option<[f32; 3]>,
    requires_encounter: String,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct PanelTarget {
    panel: MapDecoration<String>,
    approach: [f32; 3],
}
#[derive(Debug, Clone)]
pub(crate) struct Prepared {
    pub(crate) geometry: M12MapGeometry,
    pub(crate) navigation: Arc<Navigation>,
    pub(crate) opened: Arena,
    pub(crate) opened_navigation: Arc<Navigation>,
}
impl Definition {
    pub(super) fn prepare(
        self,
        arena: &Arena,
        ids: &HashMap<String, usize>,
        definitions: &[EncounterDefinition],
        presentation: &mut MapPresentation,
        start: [f32; 3],
        seen: &mut HashSet<String>,
    ) -> io::Result<Prepared> {
        use EnemyKind::*;
        let roles: [&[EnemyKind]; 4] = [
            &[Clerk, Clerk, Sweeper, Sweeper],
            &[HeavySweeper, Clerk],
            &[Clerk, Clerk, Clerk, Assessor],
            &[Clerk, Clerk, Sweeper, Sweeper, Enforcer, Notary, Notary],
        ];
        if definitions.len() != 4
            || definitions.iter().enumerate().any(|(i, g)| {
                g.id != GROUPS[i]
                    || g.after.as_deref() != i.checked_sub(1).map(|n| GROUPS[n])
                    || g.enemies.len() != roles[i].len()
                    || roles[i].iter().any(|kind| {
                        g.enemies.iter().filter(|e| e.kind == *kind).count()
                            != roles[i].iter().filter(|k| **k == *kind).count()
                    })
            })
            || definitions[1]
                .enemies
                .iter()
                .find(|e| e.kind == HeavySweeper)
                .is_none_or(|e| e.armor != Some(100))
            || definitions[2]
                .enemies
                .iter()
                .find(|e| e.kind == Assessor)
                .is_none_or(|e| e.id != "greenhouse_assessor")
            || self.objectives.len() != 6
            || self.aid_vehicles.len() != 2
        {
            return Err(invalid("M12 requires its four exact ordered encounters, armored Arc lesson and two aid jeeps"));
        }
        let door = *ids
            .get(&self.shelter_door)
            .ok_or_else(|| invalid("M12 shelter door missing"))?;
        let d = arena.solids[door];
        if d.max_x - d.min_x > 0.5 || d.max_z - d.min_z < 2.0 || d.top - d.bottom < 2.5 {
            return Err(invalid("M12 shelter door must close a full body opening"));
        }
        let mut opened = arena.clone();
        opened.solids[door].bottom = d.top + 1.2;
        opened.solids[door].top = d.top + 1.2 + (d.top - d.bottom);
        vehicle_placements::validate(&self.aid_vehicles, arena, seen)?;
        // Same identities in the second world, checked without rewriting the uniqueness set.
        vehicle_placements::validate(&self.aid_vehicles, &opened, &mut HashSet::new())?;
        let navigation =
            vehicle_placements::boarding_navigation(&self.aid_vehicles, arena, start, definitions)?
                .ok_or_else(|| invalid("M12 aid routing missing"))?;
        let opened_navigation = vehicle_placements::boarding_navigation(
            &self.aid_vehicles,
            &opened,
            start,
            definitions,
        )?
        .ok_or_else(|| invalid("M12 open shelter aid routing missing"))?;
        let reachable = |world: &Arena, nav: &Navigation, feet| {
            standing(world, feet)
                && nav.route(start, feet, SEARCH_LIMIT).status == RouteStatus::Complete
        };
        let panel = |definition: PanelTarget,
                     presentation: &mut MapPresentation|
         -> io::Result<UseTarget> {
            if definition.panel.kind != MapDecorationKind::Terminal
                || !reachable(arena, &navigation, definition.approach)
            {
                return Err(invalid("M12 requires a reachable registered terminal"));
            }
            let host = *ids
                .get(&definition.panel.solid)
                .ok_or_else(|| invalid("M12 control host missing"))?;
            let target = UseTarget {
                decoration: presentation.decorations.len(),
                approach: definition.approach,
            };
            presentation
                .decorations
                .push(definition.panel.with_solid(host));
            let point = target
                .point(presentation, &arena.solids)
                .ok_or_else(|| invalid("M12 physical panel missing"))?;
            let eye = [
                target.approach[0],
                target.approach[1] + EYE_HEIGHT,
                target.approach[2],
            ];
            if (0..3)
                .map(|i| (point[i] - eye[i]).powi(2))
                .sum::<f32>()
                .sqrt()
                > USE_DISTANCE
                || !crate::combat::line_of_sight(eye, point, &arena.solids)
            {
                return Err(invalid("M12 control needs an ordinary supported use lane"));
            }
            Ok(target)
        };
        let shelter_release = panel(self.shelter_release, presentation)?;
        let worker_release = panel(self.worker_release, presentation)?;
        let commitment = panel(self.commitment, presentation)?;
        let departure = panel(self.departure, presentation)?;
        let mut objectives = Vec::new();
        for (i, o) in self.objectives.into_iter().enumerate() {
            identity(&o.id, seen)?;
            if o.id != M12_OBJECTIVE_IDS[i] || o.requires_encounter != GROUPS[OBJECTIVE_GROUPS[i]] {
                return Err(invalid("M12 objective order/group binding changed"));
            }
            let action = if i == 5 {
                if o.arrival.is_some() || o.approach.is_some() {
                    return Err(invalid("M12 commitment requires physical Use"));
                }
                MissionObjectiveAction::Use {
                    target: commitment.clone(),
                }
            } else {
                let region = o.arrival.ok_or_else(|| invalid("M12 arrival missing"))?;
                let feet = o
                    .approach
                    .ok_or_else(|| invalid("M12 arrival approach missing"))?;
                if !region.valid(arena.half)
                    || !region.contains(feet)
                    || !reachable(arena, &navigation, feet)
                {
                    return Err(invalid("M12 arrival unreachable"));
                }
                MissionObjectiveAction::Arrival { region, feet }
            };
            objectives.push(MissionObjective { id: o.id, action });
        }
        if self.shelter_people.len() != 3
            || self.workers.len() != 3
            || self.shelter_people.iter().any(|feet| {
                !reachable(&opened, &opened_navigation, *feet)
                    || navigation.route(start, *feet, SEARCH_LIMIT).status == RouteStatus::Complete
            })
            || self
                .workers
                .iter()
                .any(|feet| !reachable(arena, &navigation, *feet))
        {
            return Err(invalid("M12 shelter must actually hold three people behind its door and workers need reachable utility routes"));
        }
        let pump = |id: &str, names: [&str; 3]| -> io::Result<M12PumpGeometry> {
            let mut indices = [0; 3];
            for (i, name) in names.into_iter().enumerate() {
                indices[i] = *ids
                    .get(name)
                    .ok_or_else(|| invalid("M12 pump host missing"))?;
            }
            Ok(M12PumpGeometry {
                id: id.into(),
                solids: indices,
                health: M12_PUMP_MAX_HP,
            })
        };
        let geometry = M12MapGeometry {
            objectives,
            shelter_release,
            worker_release,
            commitment,
            departure,
            boarding: self.boarding,
            shelter_door: door,
            shelter_open: false,
            shelter_people: self.shelter_people,
            workers: self.workers,
            pumps: [
                pump("west", ["pump_tower_0", "pump_cap_0", "pump_ground_feed_0"])?,
                pump("east", ["pump_tower_2", "pump_cap_2", "pump_ground_feed_2"])?,
            ],
            aid_vehicles: std::array::from_fn(|i| M12AidVehicle {
                feet: self.aid_vehicles[i].feet,
                yaw: self.aid_vehicles[i].yaw,
            }),
        };
        geometry
            .validate(arena.half, &arena.solids, Some(presentation))
            .map_err(invalid)?;
        let mut open_geometry = geometry.clone();
        open_geometry.shelter_open = true;
        open_geometry
            .validate(arena.half, &opened.solids, Some(presentation))
            .map_err(invalid)?;
        crate::protocol::validate_decorations(&presentation.decorations, &opened.solids)
            .map_err(invalid)?;
        super::encounters::validate(
            definitions,
            crate::protocol::EquipmentPolicy::Discovery,
            &opened,
            &mut HashSet::new(),
        )?;
        Ok(Prepared {
            geometry,
            navigation,
            opened,
            opened_navigation,
        })
    }
}
