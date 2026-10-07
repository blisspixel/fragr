//! Authored stock goes through real supply claims, never an equipment gift.
use crate::maps::AuthoredMap;
use crate::protocol::{Action, Role, SupplyClaim};
use crate::session::GameSession;
use crate::sim::PLAYER_FLOOR_Y;
use serde_json::json;
use uuid::Uuid;

fn document(claim: SupplyClaim) -> serde_json::Value {
    json!({"version":1,"map_id":1114,"name":"Remote supply fixture","half_extent":12,
        "ground":"concrete","equipment":"discovery","solids":[],
        "spawns":[{"id":"entry","feet":[0,0,0],"yaw":0}],
        "landmarks":[{"id":"return","feet":[-4,0,0]}],
        "supplies":[{"id":"armory_remotes","feet":[0,0,0],"claim":claim,
            "grant":{"kind":"remote_mine","amount":4}}],
        "encounters":[{"id":"later_guard","regions":[{"min":[8,0,8],"max":[10,2,10]}],
            "enemies":[{"id":"guard","kind":"clerk","feet":[9,0,9],"yaw":0}]}]})
}
fn session(claim: SupplyClaim) -> GameSession {
    let map = AuthoredMap::read(serde_json::to_vec(&document(claim)).unwrap().as_slice()).unwrap();
    GameSession::with_authored_map(map)
}
fn add(session: &mut GameSession, id: Uuid, x: f32) {
    session.state.add_player(id, "Walker".into(), Role::Human);
    let body = session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == id)
        .unwrap();
    body.x = x;
    body.z = 0.0;
    body.y = PLAYER_FLOOR_Y;
}
fn stock(session: &GameSession, id: Uuid) -> u16 {
    session
        .state
        .players
        .iter()
        .find(|p| p.id == id)
        .unwrap()
        .inventory
        .remote_mines()
}

#[test]
fn remote_supply_strict_amount_and_kind_boundary_reserves_contract_not_sniper() {
    let doc = document(SupplyClaim::Personal);
    let map = AuthoredMap::read(serde_json::to_vec(&doc).unwrap().as_slice()).unwrap();
    let runtime = GameSession::with_authored_map(map).state.map;
    assert!(runtime.requires_m11_contract());
    assert!(!runtime.requires_sniper_contract());
    assert!(!runtime.has_custody_devices());
    for bad in [
        json!(0),
        json!(7),
        json!(-1),
        json!(1.5),
        json!("4"),
        json!(null),
    ] {
        let mut invalid = doc.clone();
        invalid["supplies"][0]["grant"]["amount"] = bad.clone();
        assert!(
            AuthoredMap::read(serde_json::to_vec(&invalid).unwrap().as_slice()).is_err(),
            "bad actual grant: {bad}"
        );
    }
    let mut invalid = doc.clone();
    invalid["supplies"][0]["grant"]["trigger"] = json!(true);
    assert!(AuthoredMap::read(serde_json::to_vec(&invalid).unwrap().as_slice()).is_err());
    invalid = doc;
    invalid["equipment"] = json!("full_arsenal");
    assert!(AuthoredMap::read(serde_json::to_vec(&invalid).unwrap().as_slice()).is_err());
}

#[test]
fn remote_supply_personal_claims_cap_real_gain_and_preserve_other_gadgets() {
    let mut session = session(SupplyClaim::Personal);
    let a = Uuid::from_u128(11140);
    let b = Uuid::from_u128(11141);
    add(&mut session, a, 0.0);
    add(&mut session, b, 0.0);
    session
        .state
        .players
        .iter_mut()
        .find(|p| p.id == a)
        .unwrap()
        .inventory
        .grant_remote_mines(5);
    session.tick_messages(0.05);
    assert_eq!(stock(&session, a), 6);
    assert_eq!(stock(&session, b), 4);
    assert!(session.state.pickups[0].available);
    let pad = &session.state.snapshot().pickups[0];
    assert_eq!(pad.kind, "remote_mine");
    assert_eq!(pad.amount, Some(4));
    for id in [a, b] {
        let body = session
            .state
            .players
            .iter_mut()
            .find(|p| p.id == id)
            .unwrap();
        assert_eq!(body.inventory.grenades(), 0);
        assert_eq!(body.inventory.mines(), 0);
        assert!(body.inventory.claimed("armory_remotes"));
        assert!(body.inventory.try_place_remote_mine());
    }
    session.tick_messages(0.05);
    assert_eq!(stock(&session, a), 5);
    assert_eq!(stock(&session, b), 3);
    assert_eq!(session.state.pickups[0].respawn_timer, None);
}

#[test]
fn remote_supply_contested_stock_has_one_actual_claim_no_campaign_respawn() {
    let mut session = session(SupplyClaim::Contested);
    let a = Uuid::from_u128(11142);
    let b = Uuid::from_u128(11143);
    add(&mut session, a, 0.0);
    add(&mut session, b, 0.0);
    session.tick_messages(0.05);
    assert_eq!(stock(&session, a) + stock(&session, b), 4);
    assert!(!session.state.pickups[0].available);
    assert_eq!(session.state.pickups[0].respawn_timer, None);
    for _ in 0..220 {
        session.tick_messages(0.05);
    }
    assert!(!session.state.pickups[0].available);
    assert_eq!(stock(&session, a) + stock(&session, b), 4);
}

#[test]
fn remote_supply_full_stock_waits_then_claims_after_actual_spend() {
    let mut session = session(SupplyClaim::Personal);
    let id = Uuid::from_u128(11144);
    add(&mut session, id, 0.0);
    session.state.players[0].inventory.grant_remote_mines(6);
    session.tick_messages(0.05);
    assert!(!session.state.players[0].inventory.claimed("armory_remotes"));
    session.state.set_action(
        id,
        Action {
            place_remote_mine: true,
            ..Action::default()
        },
    );
    session.tick_messages(0.05);
    assert_eq!(session.state.snapshot().remote_mines.len(), 1);
    assert_eq!(
        stock(&session, id),
        5,
        "pickup claims precede ordinary device placement"
    );
    assert!(!session.state.players[0].inventory.claimed("armory_remotes"));
    session.state.set_action(id, Action::default());
    session.tick_messages(0.05);
    assert_eq!(
        stock(&session, id),
        6,
        "actual placement spent one and useful capped supply granted one"
    );
    assert!(session.state.players[0].inventory.claimed("armory_remotes"));
}
