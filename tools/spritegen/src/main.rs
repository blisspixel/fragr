//! Command line front end for sprite generation.
//!
//! The default is to price a run and generate nothing. Spending requires typing
//! a cap, and the cap is checked against the whole priced run before the first
//! image is requested.

use std::io::Read as IoRead;
use std::io::Write as IoWrite;
use std::path::PathBuf;
use std::time::Duration;

use clap::{Parser, Subcommand};
use fragr_spritegen::reduce::{nearest_upscale, parse_hex, reduce_file, Palette, Reduction};
use fragr_spritegen::{
    check_budget, estimate, parse_spec, read_dotenv_credential, Error, Frame, Method, Request,
    Response, Spec, Transport,
};
use tracing_subscriber::EnvFilter;

#[derive(Parser, Debug)]
#[command(
    name = "fragr-spritegen",
    about = "Developer-only sprite generation for fragr through the Higgsfield API"
)]
struct Cli {
    /// Dotenv file holding `higgsfield=<id>:<secret>`. Keep it out of git.
    #[arg(long, global = true, default_value = ".env")]
    env_file: PathBuf,

    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Attach a dashboard-verified request ID to an uncertain local reservation.
    Recover {
        #[arg(long)]
        out: PathBuf,
        #[arg(long)]
        frame_id: String,
        #[arg(long)]
        request_id: String,
    },
    /// Price a spec and generate nothing.
    Price {
        #[arg(long)]
        spec: PathBuf,
        /// Only frames whose id contains this.
        #[arg(long)]
        only: Option<String>,
    },
    /// Generate. Refuses without a cap, and refuses if the priced run exceeds it.
    Gen {
        #[arg(long)]
        spec: PathBuf,
        #[arg(long)]
        only: Option<String>,
        /// Dollar ceiling for this run. Required, and itself capped.
        #[arg(long)]
        max_spend_usd: Option<f64>,
        /// Print the prompt for each frame before sending it.
        #[arg(long)]
        show_prompts: bool,
    },
    /// Print the assembled prompt for each frame. Costs nothing, sends nothing.
    Prompts {
        #[arg(long)]
        spec: PathBuf,
        #[arg(long)]
        only: Option<String>,
    },
    /// Turn generated pictures into sprites. Local, free, no network.
    Reduce {
        /// Input PNG, or a directory of them.
        #[arg(long)]
        input: PathBuf,
        /// Where the sprites go.
        #[arg(long)]
        out: PathBuf,
        /// Target height in pixels.
        #[arg(long, default_value_t = 128)]
        height: u32,
        /// Palette JSON to quantise to. Omit to keep the generated colours.
        #[arg(long)]
        palette: Option<PathBuf>,
        /// Do not trim to the alpha bounding box first.
        #[arg(long)]
        no_trim: bool,
        /// Keep soft edges instead of forcing alpha fully on or off.
        #[arg(long)]
        soft_alpha: bool,
        /// Exact flat background RGB hex to remove from image edges before trim.
        #[arg(long, value_parser = parse_hex)]
        matte: Option<[u8; 3]>,
        /// Also write a nearest-neighbour upscale by this factor, for looking at.
        #[arg(long)]
        preview_scale: Option<u32>,
    },
}

/// The real network.
struct HttpTransport {
    client: reqwest::blocking::Client,
}

impl HttpTransport {
    fn new() -> Result<Self, Error> {
        reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(120))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map(|client| HttpTransport { client })
            .map_err(|e| Error::Transport(e.to_string()))
    }
}

impl Transport for HttpTransport {
    fn send(&self, credential: &str, request: &Request) -> Result<Response, Error> {
        fragr_spritegen::validate_api_url(&request.url)?;
        let mut builder = match request.method {
            Method::Get => self.client.get(&request.url),
            Method::Post => self.client.post(&request.url),
        }
        .header("Authorization", format!("Key {credential}"));
        if let Some(body) = &request.body {
            builder = builder
                .header("Content-Type", "application/json")
                .body(body.clone());
        }
        let response = builder
            .send()
            .map_err(|e| Error::Transport(e.to_string()))?;
        let status = response.status().as_u16();
        let bytes = read_bounded(response, 4 * 1024 * 1024)?;
        let body = String::from_utf8(bytes).map_err(|e| Error::Transport(e.to_string()))?;
        Ok(Response { status, body })
    }

    fn download(&self, url: &str) -> Result<Vec<u8>, Error> {
        fragr_spritegen::validate_download_url(url)?;
        let response = self
            .client
            .get(url)
            .send()
            .map_err(|e| Error::Transport(e.to_string()))?;
        if !response.status().is_success() {
            return Err(Error::Api {
                status: response.status().as_u16(),
                body: format!("downloading {url}"),
            });
        }
        read_bounded(response, 32 * 1024 * 1024)
    }
}

fn read_bounded(reader: impl IoRead, limit: u32) -> Result<Vec<u8>, Error> {
    let mut bytes = Vec::new();
    reader
        .take(u64::from(limit) + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| Error::Transport(e.to_string()))?;
    if bytes.len() > limit as usize {
        return Err(Error::Transport(format!("response exceeds {limit} bytes")));
    }
    Ok(bytes)
}

fn select<'a>(spec: &'a Spec, only: &Option<String>) -> Vec<&'a Frame> {
    match only {
        Some(pattern) => spec
            .frames
            .iter()
            .filter(|f| f.id.contains(pattern.as_str()))
            .collect(),
        None => spec.frames.iter().collect(),
    }
}

fn load(path: &PathBuf) -> Result<Spec, Error> {
    let text = std::fs::read_to_string(path)
        .map_err(|e| Error::Io(format!("could not read {}: {e}", path.display())))?;
    parse_spec(&text)
}

/// Price every selected frame and print the table.
fn price_run(
    transport: &dyn Transport,
    credential: &str,
    spec: &Spec,
    frames: &[&Frame],
    out: &mut dyn IoWrite,
) -> Result<f64, Error> {
    let mut total = 0.0;
    for frame in frames {
        let usd = estimate(transport, credential, &spec.model, frame)?;
        total += usd;
        writeln!(out, "  {:<28} ${usd:.4}", frame.id).map_err(|e| Error::Io(e.to_string()))?;
    }
    Ok(total)
}

fn run(cli: Cli) -> Result<(), Error> {
    let out_stream = &mut std::io::stdout();

    match &cli.command {
        Cmd::Recover {
            out,
            frame_id,
            request_id,
        } => {
            let mut ledger = fragr_spritegen::ledger::Ledger::open(out)?;
            ledger.recover(frame_id, request_id)?;
            writeln!(
                out_stream,
                "request attached locally; rerun gen to poll and download, without resubmitting"
            )
            .map_err(|e| Error::Io(e.to_string()))
        }
        Cmd::Prompts { spec, only } => {
            let spec = load(spec)?;
            for frame in select(&spec, only) {
                writeln!(out_stream, "--- {} ---\n{}\n", frame.id, frame.prompt())
                    .map_err(|e| Error::Io(e.to_string()))?;
            }
            Ok(())
        }

        Cmd::Reduce {
            input,
            out,
            height,
            palette,
            no_trim,
            soft_alpha,
            matte,
            preview_scale,
        } => {
            let palette = match palette {
                Some(path) => {
                    let text = std::fs::read_to_string(path).map_err(|e| {
                        Error::Io(format!("could not read {}: {e}", path.display()))
                    })?;
                    Some(Palette::from_json(&text)?)
                }
                None => None,
            };
            let settings = Reduction {
                height: *height,
                trim: !no_trim,
                palette,
                harden_alpha: !soft_alpha,
                matte: *matte,
            };

            let inputs: Vec<PathBuf> = if input.is_dir() {
                let mut found: Vec<PathBuf> = std::fs::read_dir(input)
                    .map_err(|e| Error::Io(e.to_string()))?
                    .filter_map(Result::ok)
                    .map(|entry| entry.path())
                    .filter(|path| {
                        path.extension().and_then(|e| e.to_str()).is_some_and(|e| {
                            matches!(
                                e.to_ascii_lowercase().as_str(),
                                "png" | "jpg" | "jpeg" | "webp"
                            )
                        })
                    })
                    .collect();
                found.sort();
                found
            } else {
                vec![input.clone()]
            };

            if inputs.is_empty() {
                return Err(Error::Io(format!("no images in {}", input.display())));
            }

            for path in &inputs {
                let stem = path
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("sprite");
                let target = out.join(format!("{stem}.png"));
                let (w, h) = reduce_file(path, &target, &settings)?;
                writeln!(out_stream, "  {stem:<28} {w}x{h}")
                    .map_err(|e| Error::Io(e.to_string()))?;

                if let Some(factor) = preview_scale {
                    let reduced = image::open(&target)
                        .map_err(|e| Error::Io(e.to_string()))?
                        .to_rgba8();
                    let preview = nearest_upscale(&reduced, *factor);
                    let preview_path = out.join(format!("{stem}_preview.png"));
                    preview
                        .save(&preview_path)
                        .map_err(|e| Error::Io(e.to_string()))?;
                }
            }
            Ok(())
        }

        Cmd::Price { spec, only } => {
            let credential = read_dotenv_credential(&cli.env_file)?;
            let spec = load(spec)?;
            let frames = select(&spec, only);
            let transport = HttpTransport::new()?;
            writeln!(out_stream, "model {}", spec.model).map_err(|e| Error::Io(e.to_string()))?;
            let total = price_run(&transport, &credential, &spec, &frames, out_stream)?;
            writeln!(
                out_stream,
                "\n{} frames, ${total:.4}. Nothing was generated.",
                frames.len()
            )
            .map_err(|e| Error::Io(e.to_string()))?;
            Ok(())
        }

        Cmd::Gen {
            spec,
            only,
            max_spend_usd,
            show_prompts,
        } => {
            check_budget(0.0, *max_spend_usd)?;
            let credential = read_dotenv_credential(&cli.env_file)?;
            let spec = load(spec)?;
            let selected = select(&spec, only);
            let transport = HttpTransport::new()?;
            fragr_spritegen::generation::generate(
                &transport,
                &credential,
                &spec,
                &selected,
                fragr_spritegen::generation::Options {
                    max_spend_usd: *max_spend_usd,
                    show_prompts: *show_prompts,
                },
                out_stream,
                &mut |delay| std::thread::sleep(delay),
            )
        }
    }
}

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    if let Err(err) = run(Cli::parse()) {
        eprintln!("fragr-spritegen: {err}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    #[test]
    fn response_limits_reject_oversize_and_propagate_read_failures() {
        assert_eq!(read_bounded(&[1, 2][..], 2).unwrap(), vec![1, 2]);
        assert!(read_bounded(&[1, 2, 3][..], 2).is_err());
        struct Broken;
        impl IoRead for Broken {
            fn read(&mut self, _: &mut [u8]) -> std::io::Result<usize> {
                Err(std::io::Error::other("interrupted download"))
            }
        }
        assert!(read_bounded(Broken, 2)
            .unwrap_err()
            .to_string()
            .contains("interrupted download"));
    }

    #[test]
    fn real_http_client_does_not_follow_redirects() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            let mut request = [0; 4096];
            assert!(stream.read(&mut request).unwrap() > 0);
            stream.write_all(b"HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:1/never\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").unwrap();
        });
        let transport = HttpTransport::new().unwrap();
        let response = transport
            .client
            .get(format!("http://{address}/redirect"))
            .send()
            .unwrap();
        assert_eq!(response.status().as_u16(), 302);
        server.join().unwrap();
        assert!(transport
            .send(
                "unused",
                &Request {
                    method: Method::Get,
                    url: format!("http://{address}/"),
                    body: None
                }
            )
            .is_err());
        assert!(transport.download("file:///local").is_err());
    }

    #[test]
    fn missing_cap_is_refused_before_loading_a_key_or_spec() {
        let cli = Cli::parse_from([
            "fragr-spritegen",
            "--env-file",
            "missing-env",
            "gen",
            "--spec",
            "missing-spec",
        ]);
        assert!(matches!(run(cli), Err(Error::Budget(_))));
    }

    #[test]
    fn recovery_command_needs_no_key_and_updates_only_a_reservation() {
        let dir = std::env::temp_dir().join(format!("fragr-recover-cli-{}", std::process::id()));
        std::fs::create_dir(&dir).unwrap();
        let mut ledger = fragr_spritegen::ledger::Ledger::open(&dir).unwrap();
        let spec = parse_spec(
            r#"{"model":"m","out_dir":"o","frames":[{"id":"tack","subject":"pistol"}]}"#,
        )
        .unwrap();
        ledger
            .record(
                "tack",
                fragr_spritegen::ledger::Event::Reserved {
                    identity: fragr_spritegen::ledger::Identity::new(&spec.model, &spec.frames[0]),
                    estimated_usd: 0.02,
                },
            )
            .unwrap();
        drop(ledger);
        let args = [
            "fragr-spritegen",
            "--env-file",
            "missing-env",
            "recover",
            "--out",
            dir.to_str().unwrap(),
            "--frame-id",
            "tack",
            "--request-id",
            "r1",
        ];
        run(Cli::parse_from(args)).unwrap();
        assert!(run(Cli::parse_from(args)).is_err());
        let ledger = fragr_spritegen::ledger::Ledger::open(&dir).unwrap();
        assert!(matches!(
            ledger.job("tack").unwrap().stage,
            fragr_spritegen::ledger::Stage::Submitted { .. }
        ));
        drop(ledger);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn gen_parses_a_cap() {
        let cli = Cli::parse_from([
            "fragr-spritegen",
            "gen",
            "--spec",
            "s.json",
            "--max-spend-usd",
            "0.50",
        ]);
        match cli.command {
            Cmd::Gen { max_spend_usd, .. } => assert_eq!(max_spend_usd, Some(0.50)),
            other => panic!("expected gen, got {other:?}"),
        }
    }

    #[test]
    fn reduce_requires_an_exact_valid_matte_colour() {
        let args = [
            "fragr-spritegen",
            "reduce",
            "--input",
            "sprite.png",
            "--out",
            "out",
            "--matte",
        ];
        for bad in ["", "bone", "fff", "gg0000"] {
            assert!(Cli::try_parse_from(args.into_iter().chain([bad])).is_err());
        }
        let cli = Cli::try_parse_from(args.into_iter().chain(["e8e2d6"])).unwrap();
        match cli.command {
            Cmd::Reduce { matte, .. } => assert_eq!(matte, Some([232, 226, 214])),
            other => panic!("expected reduce, got {other:?}"),
        }
    }

    #[test]
    fn gen_without_a_cap_parses_but_is_refused_later() {
        let cli = Cli::parse_from(["fragr-spritegen", "gen", "--spec", "s.json"]);
        match cli.command {
            Cmd::Gen { max_spend_usd, .. } => {
                assert_eq!(max_spend_usd, None);
                assert!(check_budget(0.01, max_spend_usd).is_err());
            }
            other => panic!("expected gen, got {other:?}"),
        }
    }

    #[test]
    fn prompts_needs_no_credential_and_no_network() {
        let dir = std::env::temp_dir().join("fragr-spritegen-main-prompts");
        std::fs::create_dir_all(&dir).unwrap();
        let spec = dir.join("spec.json");
        std::fs::write(
            &spec,
            r#"{"model":"m","out_dir":"o","frames":[{"id":"tack","subject":"a pistol"}]}"#,
        )
        .unwrap();

        let cli = Cli::parse_from([
            "fragr-spritegen",
            "prompts",
            "--spec",
            spec.to_str().unwrap(),
        ]);
        // No .env exists in the temp directory, so this passing proves the
        // prompt path never reaches for a credential.
        run(cli).unwrap();
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn only_filters_by_substring() {
        let spec = parse_spec(
            r#"{"model":"m","out_dir":"o","frames":[
                 {"id":"tack_side","subject":"x"},
                 {"id":"rail_side","subject":"y"},
                 {"id":"rail_front","subject":"z"}]}"#,
        )
        .unwrap();
        let picked: Vec<&str> = select(&spec, &Some("rail".to_string()))
            .iter()
            .map(|f| f.id.as_str())
            .collect();
        assert_eq!(picked, vec!["rail_side", "rail_front"]);
        assert_eq!(select(&spec, &None).len(), 3);
    }
}
