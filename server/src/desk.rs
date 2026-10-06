//! Local venue desk for a dedicated server.
//!
//! The person at the machine can see who is in the room, ask one of them to
//! step outside, keep that address out, and put one ordinary sentence on the
//! air. The desk is not a player and it is not the on-air Host. Closing the
//! input does not stop the match. Nothing it prints belongs on `GET /status`.

use crate::access;
use std::io::Write;
use std::net::IpAddr;
use std::path::PathBuf;
use tokio::sync::{mpsc, oneshot};
use uuid::Uuid;

/// What one desk line asked the match to do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DeskVerb {
    Who,
    Kick {
        name: String,
    },
    /// Find the one person and the address. The caller writes the ban file
    /// before [`DeskVerb::FinishBan`] removes them.
    PrepareBan {
        query: String,
    },
    FinishBan(BanReady),
    Say {
        text: String,
    },
}

/// A person the desk has already resolved to one address.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BanReady {
    pub client_id: Option<Uuid>,
    pub player_id: Option<Uuid>,
    pub ip: IpAddr,
    pub name: String,
    pub reason: String,
}

/// Answer from the match. A [`DeskOutcome::Close`] still carries the words
/// the operator reads. The socket close is the game loop's job.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DeskOutcome {
    Text(String),
    BanReady(BanReady),
    Close {
        client_id: Uuid,
        banned: bool,
        text: String,
    },
}

impl DeskOutcome {
    pub fn text(&self) -> &str {
        match self {
            DeskOutcome::Text(text) | DeskOutcome::Close { text, .. } => text,
            DeskOutcome::BanReady(_) => "",
        }
    }
}

pub struct DeskCall {
    pub verb: DeskVerb,
    pub reply: oneshot::Sender<DeskOutcome>,
}

#[derive(Debug)]
enum Parsed {
    Blank,
    Help,
    Who,
    Kick { name: String },
    Ban { query: String },
    Say { text: String },
}

#[derive(Debug)]
enum ParseFault {
    Unknown,
    NeedsName,
    NeedsSentence,
    TooLong,
}

/// Read desk lines until the channel closes. A closed channel is the end of
/// the input, not the end of the match.
pub async fn serve<W: Write>(
    mut lines: mpsc::UnboundedReceiver<String>,
    requests: mpsc::UnboundedSender<DeskCall>,
    ban_list: Option<PathBuf>,
    out: &mut W,
) {
    while let Some(line) = lines.recv().await {
        if requests.is_closed() {
            return;
        }
        match parse_line(&line) {
            Ok(Parsed::Blank) => {}
            Ok(Parsed::Help) => write_line(out, HELP),
            Ok(Parsed::Who) => write_line(out, ask(&requests, DeskVerb::Who).await.text()),
            Ok(Parsed::Kick { name }) => {
                write_line(out, ask(&requests, DeskVerb::Kick { name }).await.text());
            }
            Ok(Parsed::Say { text }) => {
                write_line(out, ask(&requests, DeskVerb::Say { text }).await.text());
            }
            Ok(Parsed::Ban { query }) => {
                let Some(path) = ban_list.clone() else {
                    write_line(
                        out,
                        "Name a ban file with --ban-list before the desk can keep someone out.",
                    );
                    continue;
                };
                let ready = match ask(&requests, DeskVerb::PrepareBan { query }).await {
                    DeskOutcome::BanReady(ready) => ready,
                    other => {
                        write_line(out, other.text());
                        continue;
                    }
                };
                let path_for_write = path.clone();
                let ip = ready.ip;
                let reason = ready.reason.clone();
                let wrote = tokio::task::spawn_blocking(move || {
                    access::append_ban(&path_for_write, ip, &reason)
                })
                .await;
                match wrote {
                    Ok(Ok(())) => {
                        write_line(out, ask(&requests, DeskVerb::FinishBan(ready)).await.text());
                    }
                    Ok(Err(error)) => write_line(out, &error),
                    Err(_) => write_line(out, "The ban file could not be written."),
                }
            }
            Err(ParseFault::Unknown) => {
                write_line(out, "The desk knows who, kick, ban, and say.");
            }
            Err(ParseFault::NeedsName) => {
                write_line(out, "Say who. Use the name from who.");
            }
            Err(ParseFault::NeedsSentence) => write_line(out, "Say the sentence."),
            Err(ParseFault::TooLong) => write_line(out, "That line is too long."),
        }
    }
}

const HELP: &str = "\
who
kick <name>
ban <name> [reason]
say <sentence>
Names are what who prints. A ban keeps the address, not the name. \
Closing this input leaves the match running.";

fn parse_line(line: &str) -> Result<Parsed, ParseFault> {
    let line = line.trim();
    if line.is_empty() {
        return Ok(Parsed::Blank);
    }
    if line.chars().count() > 300 {
        return Err(ParseFault::TooLong);
    }
    let (verb, rest) = line.split_once(char::is_whitespace).unwrap_or((line, ""));
    let rest = rest.trim();
    match verb {
        "help" | "?" if rest.is_empty() => Ok(Parsed::Help),
        "who" | "status" | "list" if rest.is_empty() => Ok(Parsed::Who),
        "kick" if rest.is_empty() => Err(ParseFault::NeedsName),
        "kick" => Ok(Parsed::Kick {
            name: rest.to_string(),
        }),
        "ban" if rest.is_empty() => Err(ParseFault::NeedsName),
        "ban" => Ok(Parsed::Ban {
            query: rest.to_string(),
        }),
        "say" if rest.is_empty() => Err(ParseFault::NeedsSentence),
        "say" => Ok(Parsed::Say {
            text: rest.to_string(),
        }),
        _ => Err(ParseFault::Unknown),
    }
}

async fn ask(requests: &mpsc::UnboundedSender<DeskCall>, verb: DeskVerb) -> DeskOutcome {
    let (reply, answer) = oneshot::channel();
    if requests.send(DeskCall { verb, reply }).is_err() {
        return DeskOutcome::Text("The desk is closed.".into());
    }
    answer
        .await
        .unwrap_or_else(|_| DeskOutcome::Text("The desk is closed.".into()))
}

fn write_line(out: &mut impl Write, line: &str) {
    if line.is_empty() {
        return;
    }
    let _ = writeln!(out, "{line}");
    let _ = out.flush();
}

/// Longest roster name that is the whole query or a prefix followed by a space.
/// Ban carries a reason after the name. Kick does not: the rest of a kick
/// line is the name, because names have spaces.
pub fn split_ban_query<'a>(query: &'a str, names: &'a [String]) -> Option<(&'a str, &'a str)> {
    let mut best: Option<&str> = None;
    for name in names {
        let exact = query == name.as_str();
        let prefixed = query.starts_with(name.as_str())
            && query[name.len()..]
                .chars()
                .next()
                .is_some_and(char::is_whitespace);
        if (exact || prefixed) && best.is_none_or(|previous| name.len() > previous.len()) {
            best = Some(name.as_str());
        }
    }
    let name = best?;
    Some((name, query[name.len()..].trim()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::Ipv4Addr;
    use std::sync::{Arc, Mutex};

    #[test]
    fn lines_parse_as_an_operator_would_type_them() {
        assert!(matches!(parse_line("  "), Ok(Parsed::Blank)));
        assert!(matches!(parse_line("who"), Ok(Parsed::Who)));
        assert!(matches!(parse_line("status"), Ok(Parsed::Who)));
        assert!(matches!(parse_line("list"), Ok(Parsed::Who)));
        assert!(matches!(parse_line("help"), Ok(Parsed::Help)));
        match parse_line("kick Dead Air Dan").unwrap() {
            Parsed::Kick { name } => assert_eq!(name, "Dead Air Dan"),
            other => panic!("kick: {other:?}"),
        }
        match parse_line("say doors at the bell").unwrap() {
            Parsed::Say { text } => assert_eq!(text, "doors at the bell"),
            other => panic!("say: {other:?}"),
        }
        match parse_line("ban Patch camping the rail").unwrap() {
            Parsed::Ban { query } => assert_eq!(query, "Patch camping the rail"),
            other => panic!("ban: {other:?}"),
        }
        assert!(matches!(parse_line("kick"), Err(ParseFault::NeedsName)));
        assert!(matches!(parse_line("say"), Err(ParseFault::NeedsSentence)));
        assert!(matches!(parse_line("fly"), Err(ParseFault::Unknown)));
        assert!(matches!(
            parse_line(&"x".repeat(301)),
            Err(ParseFault::TooLong)
        ));
    }

    #[test]
    fn a_ban_takes_the_longest_name_and_leaves_the_reason() {
        let names = vec![
            "Ann".into(),
            "Anne".into(),
            "Dead Air Dan".into(),
            "Patch".into(),
            "Patch #2".into(),
        ];
        assert_eq!(
            split_ban_query("Anne camping", &names),
            Some(("Anne", "camping"))
        );
        assert_eq!(
            split_ban_query("Dead Air Dan", &names),
            Some(("Dead Air Dan", ""))
        );
        assert_eq!(
            split_ban_query("Patch #2 the rail", &names),
            Some(("Patch #2", "the rail"))
        );
        assert_eq!(split_ban_query("Nobody", &names), None);
        assert_eq!(split_ban_query("An", &names), None);
    }

    #[tokio::test]
    async fn the_desk_prints_answers_and_returns_when_input_ends() {
        let (line_tx, line_rx) = mpsc::unbounded_channel();
        let (call_tx, mut call_rx) = mpsc::unbounded_channel::<DeskCall>();
        let seen = Arc::new(Mutex::new(Vec::new()));
        let record = Arc::clone(&seen);
        let answers = tokio::spawn(async move {
            while let Some(call) = call_rx.recv().await {
                let text = match &call.verb {
                    DeskVerb::Who => "Patch  human  2  203.0.113.7".into(),
                    DeskVerb::Kick { name } => format!("{name} is off the floor."),
                    other => format!("unexpected {other:?}"),
                };
                record.lock().unwrap().push(text.clone());
                let _ = call.reply.send(DeskOutcome::Text(text));
            }
        });
        let mut output = Vec::new();
        line_tx.send("who".into()).unwrap();
        line_tx.send("kick Patch".into()).unwrap();
        line_tx.send("".into()).unwrap();
        line_tx.send("dance".into()).unwrap();
        drop(line_tx);
        serve(line_rx, call_tx, None, &mut output).await;
        answers.await.unwrap();
        let text = String::from_utf8(output).unwrap();
        assert!(text.contains("Patch  human  2  203.0.113.7"), "{text}");
        assert!(text.contains("Patch is off the floor."), "{text}");
        assert!(
            text.contains("The desk knows who, kick, ban, and say."),
            "{text}"
        );
        assert_eq!(seen.lock().unwrap().len(), 2);
    }

    #[tokio::test]
    async fn ban_writes_the_file_before_it_removes_anyone() {
        let dir = std::env::temp_dir().join(format!(
            "fragr-desk-{}-{}",
            std::process::id(),
            Uuid::new_v4()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("bans.txt");
        std::fs::write(&path, "# tonight\n").unwrap();
        let (line_tx, line_rx) = mpsc::unbounded_channel();
        let (call_tx, mut call_rx) = mpsc::unbounded_channel::<DeskCall>();
        let finished = Arc::new(Mutex::new(false));
        let flag = Arc::clone(&finished);
        let file_at_finish = Arc::new(Mutex::new(String::new()));
        let snapshot = Arc::clone(&file_at_finish);
        let listed = path.clone();
        let answers = tokio::spawn(async move {
            while let Some(call) = call_rx.recv().await {
                match call.verb {
                    DeskVerb::PrepareBan { query } => {
                        assert_eq!(query, "Patch camping");
                        let _ = call.reply.send(DeskOutcome::BanReady(BanReady {
                            client_id: Some(Uuid::nil()),
                            player_id: Some(Uuid::nil()),
                            ip: IpAddr::V4(Ipv4Addr::new(203, 0, 113, 7)),
                            name: "Patch".into(),
                            reason: "camping".into(),
                        }));
                    }
                    DeskVerb::FinishBan(_) => {
                        *snapshot.lock().unwrap() = std::fs::read_to_string(&listed).unwrap();
                        *flag.lock().unwrap() = true;
                        let _ = call.reply.send(DeskOutcome::Text(
                            "203.0.113.7 stays out. Patch is off the floor.".into(),
                        ));
                    }
                    other => panic!("unexpected {other:?}"),
                }
            }
        });
        let mut output = Vec::new();
        line_tx.send("ban Patch camping".into()).unwrap();
        drop(line_tx);
        serve(line_rx, call_tx, Some(path.clone()), &mut output).await;
        answers.await.unwrap();
        assert!(*finished.lock().unwrap(), "finish runs after the write");
        let written = file_at_finish.lock().unwrap().clone();
        assert!(written.starts_with("# tonight\n"), "{written}");
        assert!(
            written.contains("203.0.113.7 reason=camping\n"),
            "{written}"
        );
        let text = String::from_utf8(output).unwrap();
        assert!(text.contains("Patch is off the floor."), "{text}");
    }

    #[tokio::test]
    async fn a_ban_without_a_file_does_not_ask_the_match() {
        let (line_tx, line_rx) = mpsc::unbounded_channel();
        let (call_tx, mut call_rx) = mpsc::unbounded_channel::<DeskCall>();
        let answers = tokio::spawn(async move {
            if let Some(call) = call_rx.recv().await {
                panic!("no file means no match call: {:?}", call.verb);
            }
        });
        let mut output = Vec::new();
        line_tx.send("ban Patch".into()).unwrap();
        drop(line_tx);
        serve(line_rx, call_tx, None, &mut output).await;
        answers.await.unwrap();
        let text = String::from_utf8(output).unwrap();
        assert!(text.contains("--ban-list"), "{text}");
    }
}
