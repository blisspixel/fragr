//! Line board for a fragr server. Dial in, read the floor, leave a notice.
//! The process that is serving owns the lines. This program only renders them.

use std::io::{self, Write};
use std::process::ExitCode;

use clap::Parser;
use futures_util::{SinkExt, StreamExt};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio_tungstenite::{connect_async, tungstenite::Message};

use fragr_server::protocol::{BoardPage, ServerMessage, GAMEPLAY_VERSION, GEOMETRY_VERSION};

#[derive(Parser, Debug)]
#[command(name = "fragr-wire", about = "Dial the fragr wire")]
struct Args {
    /// Host that is already serving. The board is that process.
    #[arg(long, default_value = "127.0.0.1:6767")]
    server: String,
    /// Callsign on a notice. The server keeps the name it assigned.
    #[arg(long, default_value = "Wire")]
    name: String,
}

#[derive(Debug, PartialEq, Eq)]
enum Ask {
    List,
    Read(String),
    Post(String),
    Quit,
    Help,
}

fn parse_ask(line: &str) -> Ask {
    let trimmed = line.trim();
    if trimmed.is_empty() || trimmed == "list" {
        return Ask::List;
    }
    if trimmed == "quit" || trimmed == "q" {
        return Ask::Quit;
    }
    if trimmed == "help" || trimmed == "?" {
        return Ask::Help;
    }
    if let Some(board) = trimmed.strip_prefix("read ") {
        return Ask::Read(board.trim().to_string());
    }
    if let Some(text) = trimmed.strip_prefix("post ") {
        return Ask::Post(text.trim().to_string());
    }
    Ask::Help
}

fn render_page(page: &BoardPage) -> String {
    if let Some(code) = &page.code {
        return match code.as_str() {
            "board_closed" => {
                "The floor is the room talking. Speak from a seat, or post a notice.".into()
            }
            "board_rate_limited" => "The wire just took a line. Wait a moment.".into(),
            "board_unknown" => "This server has floor and notices.".into(),
            _ => "That line did not go up.".into(),
        };
    }
    if page.op == fragr_server::protocol::BoardOp::List {
        let mut out = String::from("BOARDS\n");
        for card in &page.boards {
            out.push_str(&format!("  {:<8} {}\n", card.id, card.count));
        }
        return out;
    }
    let title = page.board.as_deref().unwrap_or("wire").to_uppercase();
    let mut out = format!("{title}\n");
    if page.lines.is_empty() {
        out.push_str("  (quiet)\n");
        return out;
    }
    for line in &page.lines {
        out.push_str(&format!(
            "  {:>6}  {}: {}\n",
            line.tick, line.name, line.text
        ));
    }
    out
}

fn render_speak(name: &str, text: &str) -> String {
    format!("floor  {name}: {text}")
}

fn masthead() -> &'static str {
    "\
================================
 UNMETERED WIRE
 the board stays up while this server does
 floor is the room. notices stay until the process ends.
 list, read floor, read notices, post <line>, quit
================================"
}

#[tokio::main]
async fn main() -> ExitCode {
    let args = Args::parse();
    let url = if args.server.starts_with("ws://") || args.server.starts_with("wss://") {
        args.server.clone()
    } else {
        format!("ws://{}", args.server)
    };
    let socket = match connect_async(&url).await {
        Ok((socket, _)) => socket,
        Err(error) => {
            eprintln!("The wire did not answer {url}: {error}");
            return ExitCode::from(1);
        }
    };
    let (mut write, mut read) = socket.split();
    let hello = serde_json::json!({
        "type": "hello",
        "role": "spectator",
        "name": args.name,
        "geometry_version": GEOMETRY_VERSION,
        "gameplay_version": GAMEPLAY_VERSION,
    });
    if write.send(Message::Text(hello.to_string())).await.is_err() {
        eprintln!("The hello did not leave this machine.");
        return ExitCode::from(1);
    }
    match next_message(&mut read).await {
        Some(ServerMessage::Welcome { .. }) => {}
        Some(ServerMessage::Error { message, .. }) => {
            eprintln!("{message}");
            return ExitCode::from(1);
        }
        _ => {
            eprintln!("This host did not answer.");
            return ExitCode::from(1);
        }
    }
    println!("{}", masthead());
    let _ = writeln!(io::stdout());
    if send_ask(&mut write, &Ask::List).await.is_err() {
        eprintln!("The list did not leave this machine.");
        return ExitCode::from(1);
    }
    let stdin = BufReader::new(tokio::io::stdin());
    let mut lines = stdin.lines();
    print_prompt();
    loop {
        tokio::select! {
            incoming = next_message(&mut read) => {
                match incoming {
                    Some(ServerMessage::Board(page)) => {
                        println!("\r{}", render_page(&page));
                        print_prompt();
                    }
                    Some(ServerMessage::Event(fragr_server::protocol::GameEvent::Speak { player, text, .. })) => {
                        println!("\r{}", render_speak(&player, &text));
                        print_prompt();
                    }
                    Some(ServerMessage::Event(fragr_server::protocol::GameEvent::VenueNotice { text })) => {
                        println!("\r{text}");
                        print_prompt();
                    }
                    Some(ServerMessage::Error { message, .. }) => {
                        println!("\r{message}");
                        print_prompt();
                    }
                    None => {
                        println!("\rThe wire dropped.");
                        return ExitCode::from(1);
                    }
                    _ => {}
                }
            }
            typed = lines.next_line() => {
                let Ok(Some(typed)) = typed else {
                    return ExitCode::SUCCESS;
                };
                match parse_ask(&typed) {
                    Ask::Quit => return ExitCode::SUCCESS,
                    Ask::Help => {
                        println!("{}", masthead());
                        print_prompt();
                    }
                    ask => {
                        if send_ask(&mut write, &ask).await.is_err() {
                            println!("That line did not leave this machine.");
                            return ExitCode::from(1);
                        }
                    }
                }
            }
        }
    }
}

fn print_prompt() {
    print!("wire> ");
    let _ = io::stdout().flush();
}

async fn send_ask(write: &mut (impl SinkExt<Message> + Unpin), ask: &Ask) -> Result<(), ()> {
    let body = match ask {
        Ask::List => serde_json::json!({"type": "board", "op": "list"}),
        Ask::Read(board) => serde_json::json!({"type": "board", "op": "read", "board": board}),
        Ask::Post(text) => {
            serde_json::json!({"type": "board", "op": "post", "board": "notices", "text": text})
        }
        Ask::Quit | Ask::Help => return Ok(()),
    };
    write
        .send(Message::Text(body.to_string()))
        .await
        .map_err(|_| ())
}

async fn next_message(
    read: &mut (impl StreamExt<Item = Result<Message, tokio_tungstenite::tungstenite::Error>> + Unpin),
) -> Option<ServerMessage> {
    loop {
        match read.next().await? {
            Ok(Message::Text(text)) => {
                if let Ok(message) = serde_json::from_str::<ServerMessage>(&text) {
                    return Some(message);
                }
            }
            Ok(Message::Close(_)) | Err(_) => return None,
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fragr_server::protocol::BoardLine;

    #[test]
    fn commands_are_the_board_and_a_blank_line_lists_again() {
        assert_eq!(parse_ask(""), Ask::List);
        assert_eq!(parse_ask("list"), Ask::List);
        assert_eq!(parse_ask("read floor"), Ask::Read("floor".into()));
        assert_eq!(parse_ask("post still here"), Ask::Post("still here".into()));
        assert_eq!(parse_ask("quit"), Ask::Quit);
        assert_eq!(parse_ask("nope"), Ask::Help);
    }

    #[test]
    fn a_page_names_the_line_and_a_closed_floor_says_why() {
        let posted = BoardPage {
            op: fragr_server::protocol::BoardOp::Post,
            board: Some("notices".into()),
            boards: Vec::new(),
            lines: vec![BoardLine {
                tick: 4,
                name: "Wire".into(),
                text: "still here".into(),
            }],
            code: None,
        };
        assert!(render_page(&posted).contains("Wire: still here"));
        let closed = BoardPage {
            op: fragr_server::protocol::BoardOp::Post,
            board: Some("floor".into()),
            boards: Vec::new(),
            lines: Vec::new(),
            code: Some("board_closed".into()),
        };
        assert!(render_page(&closed).contains("post a notice"));
        assert_eq!(
            render_speak("Meat Proxy", "nice scrap"),
            "floor  Meat Proxy: nice scrap"
        );
    }
}
