use fragr_server::movement::{Arena, Solid};
use fragr_server::vehicles::{vehicle_step, VehicleInput, VehicleMotion};

fn main() {
    let flat = Arena {
        half: 100.0,
        solids: Vec::new(),
    };
    let wall = Arena {
        half: 20.0,
        solids: vec![Solid {
            min_x: 3.0,
            max_x: 3.02,
            min_z: -10.0,
            max_z: 10.0,
            bottom: 0.0,
            top: 4.0,
        }],
    };
    let initial = VehicleMotion {
        position: [0.0, 0.0, 0.0],
        yaw: 0.0,
        speed: 0.0,
        vy: 0.0,
    };
    let cases = [
        (
            "accelerate",
            initial,
            VehicleInput {
                forward: true,
                ..Default::default()
            },
            40,
            flat.clone(),
        ),
        (
            "reverse",
            initial,
            VehicleInput {
                back: true,
                ..Default::default()
            },
            40,
            flat.clone(),
        ),
        (
            "turn_right",
            initial,
            VehicleInput {
                forward: true,
                right: true,
                ..Default::default()
            },
            60,
            flat.clone(),
        ),
        (
            "reverse_left",
            initial,
            VehicleInput {
                back: true,
                left: true,
                ..Default::default()
            },
            60,
            flat.clone(),
        ),
        (
            "handbrake",
            VehicleMotion {
                speed: 16.0,
                ..initial
            },
            VehicleInput {
                brake: true,
                ..Default::default()
            },
            20,
            flat.clone(),
        ),
        (
            "thin_wall",
            VehicleMotion {
                speed: 16.0,
                ..initial
            },
            VehicleInput {
                forward: true,
                ..Default::default()
            },
            10,
            wall,
        ),
        (
            "fall",
            VehicleMotion {
                position: [0.0, 3.0, 0.0],
                speed: 8.0,
                ..initial
            },
            VehicleInput::default(),
            30,
            flat,
        ),
    ];
    let vectors:Vec<_>=cases.into_iter().map(|(name,start,input,steps,arena)|{
        let mut expected=start;
        for _ in 0..steps {expected=vehicle_step(expected,input,0.05,&arena);}
        serde_json::json!({"name":name,"initial":start,"input":input,"steps":steps,"dt":0.05,"arena":arena,"expected":expected})
    }).collect();
    println!(
        "{}",
        serde_json::to_string_pretty(&serde_json::json!({"version":1,"vectors":vectors})).unwrap()
    );
}
