use super::{encounters::EncounterDefinition, identity, invalid, standing, Placement};
use crate::movement::{Arena, Solid, CONTACT_EPSILON};
use crate::navigation::{Navigation, RouteStatus, SEARCH_LIMIT};
use crate::protocol::{VehicleKind, VehicleSeat};
use crate::vehicles::{self, Jeep};
use std::collections::HashSet;
use std::io;
use std::sync::Arc;

fn parked(placement: &Placement) -> Jeep {
    Jeep::new(1, placement.feet, placement.yaw)
}

fn overlaps(a: &Solid, b: &Solid) -> bool {
    a.min_x < b.max_x
        && a.max_x > b.min_x
        && a.min_z < b.max_z
        && a.max_z > b.min_z
        && a.bottom < b.top
        && a.top > b.bottom
}

pub(super) fn validate(
    placements: &[Placement],
    arena: &Arena,
    seen: &mut HashSet<String>,
) -> io::Result<()> {
    let mut hulls = Vec::new();
    for placement in placements {
        identity(&placement.id, seen)?;
        let [x, y, z] = placement.feet;
        if !placement.feet.iter().all(|v| v.is_finite())
            || y < 0.0
            || !placement.yaw.is_finite()
            || !(0.0..std::f32::consts::TAU).contains(&placement.yaw)
            || !vehicles::clear_kind(VehicleKind::Jeep, placement.feet, placement.yaw, arena)
        {
            return Err(invalid(
                "authored jeep requires finite feet, clearance and normalized yaw",
            ));
        }
        let mut hull = vehicles::hull(&parked(placement).state);
        // Check the entire parked footprint, including the exposed gunner,
        // rather than relying on the moving kernel's three-circle envelope.
        hull.top = y + vehicles::CLEARANCE_HEIGHT;
        if hull.min_x < -arena.half
            || hull.max_x > arena.half
            || hull.min_z < -arena.half
            || hull.max_z > arena.half
            || arena.solids.iter().any(|solid| overlaps(&hull, solid))
            || hulls.iter().any(|other| overlaps(&hull, other))
        {
            return Err(invalid(
                "authored jeep footprint or exposed occupant is obstructed",
            ));
        }
        for forward in [-vehicles::HALF_LENGTH, 0.0, vehicles::HALF_LENGTH] {
            for side in [-vehicles::HALF_WIDTH, 0.0, vehicles::HALF_WIDTH] {
                let point = vehicles::local_point([x, y, z], placement.yaw, [forward, 0.0, side]);
                if (arena.support_height(point[0], point[2], y + CONTACT_EPSILON) - y).abs()
                    > CONTACT_EPSILON
                {
                    return Err(invalid(
                        "authored jeep requires support across its footprint",
                    ));
                }
            }
        }
        hulls.push(hull);
    }
    Ok(())
}

pub(super) fn reachable(nav: Option<&Navigation>, start: [f32; 3], to: [f32; 3]) -> io::Result<()> {
    if nav.is_some_and(|nav| nav.route(start, to, SEARCH_LIMIT).status != RouteStatus::Complete) {
        return Err(invalid("parked fleet blocks a required walking route"));
    }
    Ok(())
}

pub(super) fn boarding_navigation(
    placements: &[Placement],
    arena: &Arena,
    start: [f32; 3],
    encounters: &[EncounterDefinition],
) -> io::Result<Option<Arc<Navigation>>> {
    if placements.is_empty() {
        return Ok(None);
    }
    let fleet: Vec<_> = placements.iter().map(parked).collect();
    let hulls: Vec<_> = fleet
        .iter()
        .map(|jeep| vehicles::hull(&jeep.state))
        .collect();
    let mut blocked = arena.clone();
    blocked.solids.extend(hulls.iter().copied());
    // Elevated parked bodies can enter an otherwise clear airborne volume.
    // Check flight bounds and the grounded gun approach in the same world
    // used for the required walking routes, before any actors are admitted.
    for enemy in encounters.iter().flat_map(|group| &group.enemies) {
        if let Some(hover) = &enemy.hover {
            hover
                .validate_for(&blocked, enemy.feet, enemy.kind)
                .map_err(|error| {
                    invalid(&format!(
                        "enemy {} in parked fleet world: {error}",
                        enemy.id
                    ))
                })?;
        }
    }
    let navigation = Navigation::shared(blocked.clone()).map_err(invalid)?;
    for (index, placement) in placements.iter().enumerate() {
        // Use a real standing approach inside the shared two-metre entry
        // radius. Both seats need the same swept-body access as live play.
        for seat in [VehicleSeat::Driver, VehicleSeat::Gunner] {
            let target = vehicles::seat_feet(&fleet[index].state, seat);
            let accessible = [1.75, 1.95].into_iter().any(|radius| {
                (0..16).any(|angle| {
                    let point = vehicles::local_point(
                        placement.feet,
                        placement.yaw + angle as f32 * std::f32::consts::TAU / 16.0,
                        [radius, 0.0, 0.0],
                    );
                    standing(&blocked, point)
                        && navigation.route(start, point, SEARCH_LIMIT).status
                            == RouteStatus::Complete
                        && !arena
                            .solids
                            .iter()
                            .any(|solid| vehicles::body_passage_blocked(point, target, solid))
                        && !hulls.iter().enumerate().any(|(other, hull)| {
                            other != index && vehicles::body_passage_blocked(point, target, hull)
                        })
                })
            });
            if !accessible {
                return Err(invalid(
                    "authored jeep has no reachable swept-body boarding approach",
                ));
            }
        }
    }
    Ok(Some(navigation))
}

#[cfg(test)]
mod tests {
    use super::super::tests::{decode, small};
    use serde_json::json;

    fn fixture() -> serde_json::Value {
        let mut doc = small();
        doc["vehicles"] = json!([{"id":"motorpool","feet":[0,0,0],"yaw":0}]);
        doc
    }

    fn elevated_hover() -> serde_json::Value {
        let mut doc = fixture();
        doc["solids"] = json!([
            {"id":"raised_floor","min":[-8,0,-8],"max":[8,2,8],"surface":"concrete"}
        ]);
        doc["spawns"][0]["feet"] = json!([0, 2, -4]);
        doc["landmarks"][0]["feet"] = json!([0, 2, 4]);
        doc["vehicles"][0]["feet"] = json!([0, 2, 0]);
        doc["equipment"] = json!("discovery");
        doc["encounters"] = json!([{
            "id":"hover_guard",
            "regions":[{"min":[-8,2,-8],"max":[8,4,8]}],
            "enemies":[{
                "id":"notary","kind":"notary","feet":[0,3,0],"yaw":0,
                "hover":{
                    "volume":{"min":[-0.5,2.5,-0.5],"max":[0.5,4,0.5]},
                    "band":[2.5,4],"patrol":[[-0.25,3,-0.25],[0.25,3,0.25]],
                    "approach":[0,2,-4]
                }
            }]
        }]);
        doc
    }

    #[test]
    fn rejects_elevated_jeep_hull_inside_an_otherwise_clear_notary_hover() {
        let mut doc = elevated_hover();
        let fleet = doc["vehicles"].take();
        doc["vehicles"] = json!([]);
        assert!(decode(&doc).is_ok(), "the static hover world is clear");
        doc["vehicles"] = fleet;
        let error = decode(&doc).unwrap_err().to_string();
        assert!(error.contains("parked fleet"), "{error}");
        assert!(error.contains("hover volume clips"), "{error}");
    }

    #[test]
    fn elevated_jeep_allows_a_notary_hover_above_its_actual_hull() {
        let mut doc = elevated_hover();
        let enemy = &mut doc["encounters"][0]["enemies"][0];
        let hull_top = 2.0 + crate::vehicles::BODY_TOP;
        enemy["feet"] = json!([0, 3.5, 0]);
        enemy["hover"]["volume"]["min"][1] = json!(hull_top);
        enemy["hover"]["volume"]["max"][1] = json!(4.5);
        enemy["hover"]["band"] = json!([hull_top, 4.5]);
        enemy["hover"]["patrol"] = json!([[-0.25, 3.5, -0.25], [0.25, 3.5, 0.25]]);
        decode(&doc).expect("exact hull-top clearance is legal");
    }

    #[test]
    fn assessor_parked_fleet_uses_its_wider_body_than_the_notary_control() {
        let mut doc = elevated_hover();
        doc["vehicles"][0]["feet"] = json!([3.2, 2, 0]);
        let enemy = &mut doc["encounters"][0]["enemies"][0];
        enemy["feet"] = json!([0, 3.5, 0]);
        enemy["hover"]["volume"]["min"][1] = json!(3);
        enemy["hover"]["band"] = json!([3, 4]);
        enemy["hover"]["patrol"] = json!([[-0.25, 3.5, -0.25], [0.25, 3.5, 0.25]]);
        decode(&doc).expect("the narrower Notary misses the parked hull beside its volume");
        doc["encounters"][0]["enemies"][0]["kind"] = json!("assessor");
        let fleet = doc["vehicles"].take();
        doc["vehicles"] = json!([]);
        decode(&doc).expect("the Assessor's static flight world is clear");
        doc["vehicles"] = fleet;
        let error = decode(&doc).unwrap_err().to_string();
        assert!(error.contains("parked fleet"), "{error}");
        assert!(error.contains("hover volume clips"), "{error}");
    }

    #[test]
    fn authored_fleet_is_explicit_and_uses_the_shared_jeep() {
        let map = decode(&fixture()).unwrap();
        let runtime = crate::maps::RuntimeMap::Authored(map);
        assert!(runtime.has_authored_vehicles());
        assert_eq!(
            runtime.vehicle_spawns(),
            vec![(crate::protocol::VehicleKind::Jeep, [0.0; 3], 0.0)]
        );
        let mut doc = small();
        doc["map_id"] = json!(1014);
        assert!(crate::maps::RuntimeMap::Authored(decode(&doc).unwrap())
            .vehicle_spawns()
            .is_empty());
        assert_eq!(
            crate::maps::RuntimeMap::BuiltIn(crate::sim::MapKind::HoldfastAtoll)
                .vehicle_spawns()
                .len(),
            6
        );
    }

    #[test]
    fn rejects_unsupported_unknown_duplicate_and_unbounded_placements() {
        for (field, bad) in [
            ("yaw", json!(-0.1)),
            ("yaw", json!(7)),
            ("feet", json!([0, 0.1, 0])),
            ("feet", json!([7, 0, 0])),
            ("feet", json!([0, -1, 0])),
            ("id", json!("entry")),
            ("kind", json!("boat")),
        ] {
            let mut doc = fixture();
            doc["vehicles"][0][field] = bad;
            assert!(decode(&doc).is_err(), "{field}");
        }
        let mut doc = fixture();
        doc["vehicles"] = json!(vec![
            doc["vehicles"][0].clone();
            crate::protocol::MAX_VEHICLES + 1
        ]);
        assert!(decode(&doc).unwrap_err().to_string().contains("bounded"));
    }

    #[test]
    fn rejects_parked_fleet_overlap_and_low_gunner_roof() {
        let mut doc = fixture();
        doc["vehicles"]
            .as_array_mut()
            .unwrap()
            .push(json!({"id":"second","feet":[2,0,0],"yaw":1.57}));
        assert!(decode(&doc).unwrap_err().to_string().contains("obstructed"));
        let mut doc = fixture();
        doc["solids"][0]["min"][1] = json!(2.7);
        assert!(decode(&doc).is_err());
        doc["solids"][0]["min"][1] = json!(2.75);
        assert!(decode(&doc).is_ok(), "exact roof contact is legal");
    }

    #[test]
    fn rejects_partial_support_and_inaccessible_boarding() {
        let mut doc = fixture();
        doc["solids"] = json!([]);
        doc["solids"].as_array_mut().unwrap().push(
            json!({"id":"narrow_pedestal","min":[-1,0,-1],"max":[1,1,1],"surface":"concrete"}),
        );
        doc["vehicles"][0]["feet"] = json!([0, 1, 0]);
        assert!(decode(&doc).unwrap_err().to_string().contains("support"));
        let mut doc = fixture();
        for (id, min, max) in [
            ("front", [2.0, 0.0, -2.0], [2.2, 1.5, 2.0]),
            ("back", [-2.2, 0.0, -2.0], [-2.0, 1.5, 2.0]),
            ("left", [-2.0, 0.0, -1.1], [2.0, 1.5, -1.0]),
            ("right", [-2.0, 0.0, 1.0], [2.0, 1.5, 1.1]),
        ] {
            doc["solids"]
                .as_array_mut()
                .unwrap()
                .push(json!({"id":id,"min":min,"max":max,"surface":"concrete"}));
        }
        assert!(decode(&doc).unwrap_err().to_string().contains("boarding"));
    }

    #[test]
    fn rejects_required_landmark_hidden_under_a_parked_hull() {
        let mut doc = fixture();
        doc["landmarks"][0]["feet"] = json!([0, 0, 0]);
        assert!(decode(&doc)
            .unwrap_err()
            .to_string()
            .contains("walking route"));
    }

    #[test]
    fn rejects_staged_mission_fleets_before_preparing_unchecked_worlds() {
        let mut doc: serde_json::Value =
            serde_json::from_str(include_str!("../../../maps/m01-recall-notice.json")).unwrap();
        doc["vehicles"] = json!([{"id":"jeep","feet":[0,0,0],"yaw":0}]);
        assert!(decode(&doc)
            .unwrap_err()
            .to_string()
            .contains("static development world"));
        doc["vehicles"] = json!([]);
        assert!(
            decode(&doc).is_ok(),
            "an empty optional field changes no mission world"
        );
    }
}
