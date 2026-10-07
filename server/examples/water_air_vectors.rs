use fragr_server::movement::{Arena, Solid};
use fragr_server::protocol::{VehicleKind, WaterRegion};
use fragr_server::vehicles::{vehicle_step_kind, VehicleInput, VehicleMotion};

fn main() {
    let arena = Arena {
        half: 220.0,
        solids: Vec::new(),
    };
    let water = vec![WaterRegion {
        min: [-100.0, -100.0],
        max: [100.0, 100.0],
        level: 2.2,
        depth: 2.2,
    }];
    let initial = VehicleMotion {
        position: [0.0, 0.0, 0.0],
        yaw: 0.0,
        speed: 0.0,
        vy: 0.0,
    };
    let boat = VehicleMotion {
        position: [0.0, 2.2, 0.0],
        ..initial
    };
    let forward = VehicleInput {
        forward: true,
        ..Default::default()
    };
    let climb = VehicleInput {
        forward: true,
        brake: true,
        ..Default::default()
    };
    let mut wall = arena.clone();
    wall.solids.push(Solid {
        min_x: 4.0,
        max_x: 4.01,
        min_z: -20.0,
        max_z: 20.0,
        bottom: 0.0,
        top: 6.0,
    });
    let cases = vec![
        (
            "boat_accelerate",
            VehicleKind::Boat,
            boat,
            forward,
            80,
            arena.clone(),
            water.clone(),
        ),
        (
            "boat_reverse",
            VehicleKind::Boat,
            boat,
            VehicleInput {
                back: true,
                ..Default::default()
            },
            60,
            arena.clone(),
            water.clone(),
        ),
        (
            "boat_turn",
            VehicleKind::Boat,
            boat,
            VehicleInput {
                right: true,
                ..forward
            },
            100,
            arena.clone(),
            water.clone(),
        ),
        (
            "boat_shore",
            VehicleKind::Boat,
            VehicleMotion {
                position: [96.0, 2.2, 0.0],
                speed: 14.0,
                ..initial
            },
            forward,
            12,
            arena.clone(),
            water.clone(),
        ),
        (
            "boat_dock",
            VehicleKind::Boat,
            VehicleMotion {
                speed: 14.0,
                ..boat
            },
            forward,
            10,
            wall,
            water.clone(),
        ),
        (
            "plane_takeoff",
            VehicleKind::LightAircraft,
            initial,
            climb,
            100,
            arena.clone(),
            Vec::new(),
        ),
        (
            "plane_turn",
            VehicleKind::LightAircraft,
            VehicleMotion {
                position: [0.0, 12.0, 0.0],
                speed: 24.0,
                ..initial
            },
            VehicleInput {
                left: true,
                ..forward
            },
            80,
            arena.clone(),
            Vec::new(),
        ),
        (
            "plane_descend",
            VehicleKind::LightAircraft,
            VehicleMotion {
                position: [0.0, 20.0, 0.0],
                speed: 24.0,
                ..initial
            },
            VehicleInput {
                descend: true,
                ..forward
            },
            50,
            arena.clone(),
            Vec::new(),
        ),
        (
            "plane_ceiling",
            VehicleKind::LightAircraft,
            VehicleMotion {
                position: [0.0, 59.0, 0.0],
                speed: 24.0,
                vy: 6.0,
                ..initial
            },
            climb,
            20,
            arena.clone(),
            Vec::new(),
        ),
        (
            "plane_stall",
            VehicleKind::LightAircraft,
            VehicleMotion {
                position: [0.0, 8.0, 0.0],
                ..initial
            },
            VehicleInput::default(),
            40,
            arena.clone(),
            Vec::new(),
        ),
        (
            "plane_water",
            VehicleKind::LightAircraft,
            VehicleMotion {
                position: [0.0, 3.0, 0.0],
                vy: -4.0,
                ..initial
            },
            VehicleInput::default(),
            12,
            arena,
            water,
        ),
    ];
    let vectors:Vec<_>=cases.into_iter().map(|(name,kind,start,input,steps,arena,water)|{
        let mut expected=start;
        for _ in 0..steps {expected=vehicle_step_kind(kind,expected,input,0.05,&arena,&water);}
        serde_json::json!({"name":name,"kind":kind,"initial":start,"input":input,"steps":steps,"dt":0.05,"arena":arena,"water_regions":water,"expected":expected})
    }).collect();
    println!(
        "{}",
        serde_json::to_string_pretty(&serde_json::json!({"version":1,"vectors":vectors})).unwrap()
    );
}
