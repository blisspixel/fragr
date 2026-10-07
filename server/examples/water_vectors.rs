use fragr_server::movement::{water, Arena, MoveInput, MoveState, Solid, BODY_HEIGHT, DUCK_HEIGHT};
use fragr_server::protocol::WaterRegion;

fn main() {
    let flat = Arena {
        half: 20.0,
        solids: Vec::new(),
    };
    let shore = Arena {
        half: 20.0,
        solids: vec![Solid::from_center_top(5.0, 0.0, 1.0, 5.0, 1.8)],
    };
    let water = vec![WaterRegion {
        min: [-20.0, -20.0],
        max: [20.0, 20.0],
        level: 2.2,
        depth: 2.2,
    }];
    let initial = MoveState {
        x: 0.0,
        y: 0.0,
        z: 0.0,
        vx: 0.0,
        vz: 0.0,
        vy: 0.0,
        yaw: 0.0,
    };
    let forward = MoveInput {
        forward: true,
        ..Default::default()
    };
    let cases = vec![
        (
            "seabed_to_surface",
            initial,
            MoveInput::default(),
            1,
            BODY_HEIGHT,
            flat.clone(),
            water.clone(),
        ),
        (
            "surface_swim",
            MoveState { y: 1.3, ..initial },
            forward,
            20,
            BODY_HEIGHT,
            flat.clone(),
            water.clone(),
        ),
        (
            "fall_to_surface",
            MoveState { y: 5.0, ..initial },
            MoveInput::default(),
            35,
            BODY_HEIGHT,
            flat.clone(),
            water.clone(),
        ),
        (
            "shore_step",
            initial,
            forward,
            25,
            BODY_HEIGHT,
            shore,
            water.clone(),
        ),
        (
            "duck_swim",
            MoveState { y: 1.3, ..initial },
            forward,
            20,
            DUCK_HEIGHT,
            flat.clone(),
            water,
        ),
        (
            "dry_jump",
            initial,
            MoveInput {
                jump: true,
                ..forward
            },
            12,
            BODY_HEIGHT,
            flat,
            Vec::new(),
        ),
    ];
    let vectors:Vec<_>=cases.into_iter().map(|(name,start,input,steps,height,arena,water)|{
        let mut expected=start;
        for _ in 0..steps {expected=water::live_step(expected,&input,5.0,0.05,&arena,height,&water);}
        serde_json::json!({"name":name,"initial":start,"input":input,"steps":steps,"speed":5.0,"dt":0.05,"body_height":height,"arena":arena,"water_regions":water,"expected":expected})
    }).collect();
    println!(
        "{}",
        serde_json::to_string_pretty(&serde_json::json!({"version":1,"vectors":vectors})).unwrap()
    );
}
