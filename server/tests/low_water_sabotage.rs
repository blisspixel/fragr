//! MapInfo, finite mixed-role admission and a whole match over ordinary sockets.
use fragr_server::navigation::{Navigation, Navigator};
use fragr_server::protocol::{
    Action, ClientMessage, GameEvent, GameMode, Role, SabotageEventKind, SabotageMap,
    SabotagePhase, SabotageReason, ServerMessage, Snapshot, Team, WeaponType,
};
use fragr_server::rules::{RuleSet, SabotageConfig};
use fragr_server::run::{run_server, ServerOptions};
use fragr_server::sim::sabotage::controller;
use fragr_server::sim::{MapKind, MatchConfig};
use futures_util::{stream::SplitSink, SinkExt, StreamExt};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::watch;
use tokio_tungstenite::{connect_async, tungstenite::Message, MaybeTlsStream, WebSocketStream};
use uuid::Uuid;

type Socket = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;
type Writer = SplitSink<Socket, Message>;

async fn read(socket: &mut Socket) -> ServerMessage {
    tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            match socket
                .next()
                .await
                .expect("open socket")
                .expect("wire frame")
            {
                Message::Text(text) => break serde_json::from_str(&text).expect("server contract"),
                Message::Close(_) => panic!("closed before the expected contract"),
                _ => {}
            }
        }
    })
    .await
    .expect("bounded server response")
}

async fn hello(url: &str, role: Role, index: usize, version: u32) -> Socket {
    let (mut socket, _) = connect_async(url).await.unwrap();
    socket
        .send(Message::Text(
            serde_json::to_string(&ClientMessage::Hello {
                role,
                name: format!("Town socket {index:02}"),
                gameplay_version: version,
                geometry_version: 2,
                ticket: None,
                resume: None,
                body: None,
            })
            .unwrap(),
        ))
        .await
        .unwrap();
    socket
}

async fn start() -> (
    String,
    tokio::sync::oneshot::Sender<()>,
    tokio::task::JoinHandle<Result<(), String>>,
) {
    let (stop, shutdown) = tokio::sync::oneshot::channel();
    let (ready, address) = tokio::sync::oneshot::channel();
    let task = tokio::spawn(async move {
        run_server(
            ServerOptions {
                bind: "127.0.0.1:0".into(),
                bots: 0,
                map: MapKind::LowWater,
                seed: 71,
                match_config: Some(MatchConfig {
                    frag_limit: None,
                    time_limit_ticks: None,
                    boss_spawn_ticks: None,
                    compliance_ping_ticks: None,
                    rules: RuleSet::new(GameMode::Sabotage, &[], false).unwrap(),
                    sabotage: SabotageConfig {
                        five_vs_five: true,
                        ..Default::default()
                    },
                    ..Default::default()
                }),
                status_every_s: 0,
                ..Default::default()
            },
            async {
                let _ = shutdown.await;
            },
            Some(ready),
        )
        .await
        .map_err(|e| e.to_string())
    });
    let address = tokio::time::timeout(Duration::from_secs(60), address)
        .await
        .expect("prepared topology")
        .unwrap();
    eprintln!("low_water socket server: ws://{address}");
    (format!("ws://{address}"), stop, task)
}

#[tokio::test]
async fn low_water_rejects_older_contract_before_welcome_or_roster_admission() {
    let (url, stop, server) = start().await;
    let mut old = hello(
        &url,
        Role::Human,
        99,
        fragr_server::protocol::LOW_WATER_SABOTAGE_GAMEPLAY_VERSION - 1,
    )
    .await;
    assert!(
        matches!(read(&mut old).await, ServerMessage::Error { code, .. } if code == "unsupported_gameplay")
    );
    let mut watcher = hello(
        &url,
        Role::Spectator,
        100,
        fragr_server::protocol::GAMEPLAY_VERSION,
    )
    .await;
    assert!(matches!(
        read(&mut watcher).await,
        ServerMessage::Welcome {
            player_id: None,
            ..
        }
    ));
    assert!(matches!(
        read(&mut watcher).await,
        ServerMessage::MapInfo {
            map_id: 8,
            sabotage: Some(_),
            ..
        }
    ));
    loop {
        if let ServerMessage::Snapshot(snapshot) = read(&mut watcher).await {
            assert!(snapshot.players.is_empty());
            break;
        }
    }
    let _ = stop.send(());
    server.await.unwrap().unwrap();
}

fn walk(point: [f32; 3]) -> Action {
    Action {
        forward: true,
        look_at: Some(fragr_server::protocol::LookAt {
            x: Some(point[0]),
            y: Some(point[1]),
            z: Some(point[2]),
            player_id: None,
        }),
        ..Default::default()
    }
}

fn action(id: Uuid, snapshot: &Snapshot, layout: &SabotageMap) -> Action {
    let state = snapshot.sabotage.as_ref().unwrap();
    let Some(charge) = state.charge.as_ref() else {
        return Action::default();
    };
    if state.phase == SabotagePhase::Live && charge.carrier == Some(id) {
        return controller::objective_action(id, snapshot, layout).unwrap();
    }
    if state.phase != SabotagePhase::Planted {
        return Action::default();
    }
    let me = snapshot.players.iter().find(|p| p.id == id).unwrap();
    if me.team == Some(Team::Coalition) {
        // The planting carrier leaves the charge for a real retake; the other
        // four attackers stay at muster, so the fixture isolates held Use.
        if me.z < 25.0 && (me.x - charge.position[0]).abs() < 5.0 {
            return walk([charge.position[0], 3.0, 26.0]);
        }
        return Action::default();
    }
    // Four defensive wins establish the actual half. After the side swap,
    // the original defenders plant and detonate to finish their fifth win.
    if state.round <= 4 {
        let withdrawal_complete = snapshot
            .players
            .iter()
            .filter(|p| p.team == Some(Team::Coalition))
            .all(|p| (p.x - charge.position[0]).hypot(p.z - charge.position[2]) > 4.0);
        if withdrawal_complete
            && snapshot
                .players
                .iter()
                .filter(|p| p.team == Some(Team::Union))
                .min_by(|a, b| {
                    (a.x - charge.position[0])
                        .hypot(a.z - charge.position[2])
                        .total_cmp(&(b.x - charge.position[0]).hypot(b.z - charge.position[2]))
                        .then_with(|| a.name.cmp(&b.name))
                })
                .is_some_and(|p| p.id == id)
        {
            return controller::objective_action(id, snapshot, layout).unwrap();
        }
    }
    Action::default()
}

#[tokio::test]
#[ignore = "bounded live-clock five-round socket match, run explicitly for venue acceptance"]
async fn low_water_ten_mixed_sockets_plant_defuse_swap_and_finish_normal_finite_match() {
    let (url, stop, server) = start().await;
    let (latest, mut snapshots) = watch::channel::<Option<Snapshot>>(None);
    let events = Arc::new(Mutex::new(Vec::new()));
    let mut clients: Vec<(Uuid, Writer, Navigator)> = vec![];
    let mut readers = vec![];
    let mut world: Option<Navigation> = None;
    let mut layout: Option<SabotageMap> = None;
    for index in 0usize..10 {
        let role = if index.is_multiple_of(2) {
            Role::Human
        } else {
            Role::Agent
        };
        let mut socket = hello(&url, role, index, fragr_server::protocol::GAMEPLAY_VERSION).await;
        let id = match read(&mut socket).await {
            ServerMessage::Welcome {
                player_id: Some(id),
                role: accepted,
                ..
            } => {
                assert_eq!(accepted, role);
                id
            }
            other => panic!("unexpected welcome {other:?}"),
        };
        match read(&mut socket).await {
            ServerMessage::MapInfo {
                map_id,
                map_name,
                half_extent,
                solids,
                presentation,
                mission,
                sabotage,
                ..
            } => {
                assert_eq!((map_id, map_name.as_str()), (8, "Low Water"));
                assert_eq!(solids, MapKind::LowWater.solids());
                assert!(mission.is_none());
                assert!(presentation.is_some());
                let received = sabotage.unwrap();
                received.validate().unwrap();
                assert_eq!(received.callout_at(-22.0, 18.0), Some("clinic_steps"));
                assert_eq!(received.callout_at(22.0, 18.0), Some("tram_stop"));
                if world.is_none() {
                    world = Some(
                        Navigation::new(fragr_server::movement::Arena {
                            half: half_extent,
                            solids,
                        })
                        .unwrap(),
                    );
                    layout = Some(received);
                } else {
                    assert_eq!(layout.as_ref().unwrap(), &received);
                }
            }
            other => panic!("MapInfo must precede broadcast: {other:?}"),
        }
        loop {
            if let ServerMessage::Loadout(loadout) = read(&mut socket).await {
                assert_eq!(loadout.selected, WeaponType::Tack);
                assert_eq!(loadout.weapons, [WeaponType::Fists, WeaponType::Tack]);
                assert_eq!(loadout.ammo[0].rounds, 50);
                if role == Role::Human {
                    assert_eq!(
                        loadout
                            .loaded
                            .iter()
                            .find(|m| m.weapon == WeaponType::Tack)
                            .unwrap()
                            .rounds,
                        12
                    );
                }
                break;
            }
        }
        let (writer, mut reader) = socket.split();
        let publish = latest.clone();
        let recorded = Arc::clone(&events);
        readers.push(tokio::spawn(async move {
            while let Some(frame) = reader.next().await {
                if let Message::Text(text) = frame.expect("ordinary reader remains connected") {
                    match serde_json::from_str::<ServerMessage>(&text).unwrap() {
                        ServerMessage::Snapshot(snapshot) if index == 0 => {
                            publish.send_replace(Some(snapshot));
                        }
                        ServerMessage::Event(event) if index == 0 => {
                            let mut retained = recorded.lock().unwrap();
                            assert!(retained.len() < 512);
                            retained.push(event);
                        }
                        ServerMessage::Error { code, message } => {
                            panic!("live client error {code}: {message}")
                        }
                        _ => {}
                    }
                }
            }
        }));
        clients.push((id, writer, Navigator::default()));
    }
    let world = world.unwrap();
    let layout = layout.unwrap();
    let mut last_round = 0;
    let completed = tokio::time::timeout(Duration::from_secs(360), async {
        loop {
            snapshots
                .changed()
                .await
                .expect("first socket continues observing");
            let snapshot = snapshots.borrow_and_update().clone().unwrap();
            if snapshot.players.len() != 10 {
                continue;
            }
            assert_eq!(
                snapshot
                    .players
                    .iter()
                    .filter(|p| p.team == Some(Team::Union))
                    .count(),
                5
            );
            assert_eq!(
                snapshot
                    .players
                    .iter()
                    .filter(|p| p.team == Some(Team::Coalition))
                    .count(),
                5
            );
            assert!(snapshot.players.iter().all(|p| p.hp > 0));
            let Some(state) = snapshot.sabotage.as_ref() else {
                continue;
            };
            if state.round != last_round {
                eprintln!(
                    "low_water socket round{} tick{} half{} score{:?}",
                    state.round, snapshot.tick, state.half, state.score
                );
                last_round = state.round;
                for (_, _, navigator) in &mut clients {
                    navigator.clear();
                }
            }
            if events.lock().unwrap().iter().any(
                |e| matches!(e,GameEvent::RoundEnd {sabotage:Some(result),..} if result.match_over),
            ) {
                break snapshot.tick;
            }
            for (id, writer, navigator) in &mut clients {
                let requested = action(*id, &snapshot, &layout);
                let mut input = navigator.steer_snapshot(&world, *id, &snapshot, requested);
                // Shared-room humans supply camera facing. Convert any remaining
                // world-point intent to that same ordinary absolute yaw input.
                if let Some(aim) = input.look_at.take() {
                    let me = snapshot.players.iter().find(|p| p.id == *id).unwrap();
                    input.yaw = Some((aim.z.unwrap() - me.z).atan2(aim.x.unwrap() - me.x));
                    input.pitch = Some(0.0);
                }
                assert!(
                    !input.jump && !input.fire,
                    "this socket fixture isolates ordinary walking and held Use"
                );
                writer
                    .send(Message::Text(
                        serde_json::to_string(&ClientMessage::Action(input)).unwrap(),
                    ))
                    .await
                    .unwrap();
            }
        }
    })
    .await
    .expect("normal clocks finish this whole five-round match within six minutes");
    {
        let retained = events.lock().unwrap();
        let count = |kind| {
            retained
                .iter()
                .filter(|e| matches!(e,GameEvent::Sabotage {kind:actual,..} if *actual==kind))
                .count()
        };
        assert_eq!(count(SabotageEventKind::Planted), 5);
        assert_eq!(count(SabotageEventKind::Defused), 4);
        assert_eq!(count(SabotageEventKind::Detonated), 1);
        assert_eq!(count(SabotageEventKind::SidesSwapped), 1);
        let rounds: Vec<_> = retained
            .iter()
            .filter_map(|e| match e {
                GameEvent::RoundEnd {
                    sabotage: Some(result),
                    ..
                } => Some(result),
                _ => None,
            })
            .collect();
        assert_eq!(rounds.len(), 5);
        assert_eq!(rounds.last().unwrap().reason, SabotageReason::Detonation);
        assert!(rounds.last().unwrap().match_over);
        assert_eq!(rounds.last().unwrap().match_winner, Some(Team::Coalition));
        assert_eq!(rounds.last().unwrap().score.coalition, 5);
        assert!(retained
            .iter()
            .filter_map(|e| match e {
                GameEvent::Sabotage {
                    kind: SabotageEventKind::Planted,
                    site,
                    ..
                } => *site,
                _ => None,
            })
            .any(|site| site == fragr_server::protocol::SiteId::B));
        eprintln!("low_water socket normal finite10 whole match: tick{completed}, 5plants,4defuses,1detonation,1swap,0deaths,score{:?}",rounds.last().unwrap().score);
    }
    let _ = stop.send(());
    server.await.unwrap().unwrap();
    for reader in readers {
        reader.abort();
    }
}
