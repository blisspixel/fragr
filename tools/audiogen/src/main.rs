//! Command line front end for developer-only audio generation.
//!
//! Argument parsing and the real HTTP transport live here. Everything else is in
//! the library so it is tested without touching the network.

use clap::{Parser, Subcommand};
use fragr_audiogen::casting::{
    DesignParams, LibraryQuery, SaveVoiceParams, DEFAULT_DESIGN_FORMAT, DEFAULT_DESIGN_MODEL,
};
use fragr_audiogen::{
    parse_spec, read_capped, read_dotenv_key, resolve_api_key, review, run_command, score, Command,
    Error, Job, Method, MusicParams, Request, Response, RunOptions, SfxParams, Transport,
    TtsParams, API_KEY_ENV, DEFAULT_BASE_URL, DEFAULT_MUSIC_FORMAT, DEFAULT_MUSIC_MODEL,
    DEFAULT_SFX_FORMAT, DEFAULT_TTS_FORMAT, DEFAULT_TTS_MODEL,
};
use std::io::Read;
use std::path::PathBuf;
use std::time::Duration;
use tracing_subscriber::EnvFilter;

#[derive(Parser, Debug)]
#[command(
    name = "fragr-audiogen",
    version = env!("FRAGR_CLI_VERSION"),
    about = "Developer-only sound effect and music generation for fragr through the ElevenLabs API. Never runs in CI or in the game."
)]
struct Cli {
    /// File containing the API key. Overrides ELEVENLABS_API_KEY. Keep it out of git.
    #[arg(long, global = true)]
    api_key_file: Option<PathBuf>,
    /// Dotenv file consulted when ELEVENLABS_API_KEY is unset (accepts elevenlabs=...).
    #[arg(long, global = true, default_value = ".env")]
    env_file: PathBuf,
    /// API host.
    #[arg(long, global = true, default_value = DEFAULT_BASE_URL)]
    base_url: String,
    /// Output directory. Defaults to client/assets/audio, or the spec's out_dir for batch.
    #[arg(long, global = true)]
    out_dir: Option<PathBuf>,
    /// Replace files that already exist.
    #[arg(long, global = true)]
    overwrite: bool,
    /// Print the requests without calling the API or writing files.
    #[arg(long, global = true)]
    dry_run: bool,
    /// Refuse to start when the estimated credits for the run exceed this number.
    #[arg(long, global = true)]
    max_credits: Option<u64>,
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Generate one sound effect.
    Sfx {
        /// Asset name without extension, for example fire_rail or ui/click.
        #[arg(long)]
        name: String,
        /// What the sound should be. Concrete and physical beats poetic.
        #[arg(long)]
        prompt: String,
        /// Duration in seconds (0.5 to 30). Omit to let the model choose.
        #[arg(long)]
        seconds: Option<f64>,
        /// Prompt influence from 0 to 1. Higher follows the prompt more literally.
        #[arg(long)]
        influence: Option<f64>,
        /// Ask for a seamless loop.
        #[arg(long = "loop")]
        looping: bool,
        /// ElevenLabs output format. pcm_* becomes .wav, mp3_* becomes .mp3.
        #[arg(long, default_value = DEFAULT_SFX_FORMAT)]
        format: String,
    },
    /// Generate one music track.
    Music {
        /// Asset name without extension, for example music/match_01.
        #[arg(long)]
        name: String,
        /// Display title recorded in the manifest.
        #[arg(long)]
        title: Option<String>,
        /// Style, tempo, mood, instrumentation.
        #[arg(long)]
        prompt: String,
        /// Length in milliseconds (3000 to 600000). Omit to let the model choose.
        #[arg(long)]
        length_ms: Option<u32>,
        /// Music model id.
        #[arg(long, default_value = DEFAULT_MUSIC_MODEL)]
        model: String,
        /// No vocals.
        #[arg(long)]
        instrumental: bool,
        /// ElevenLabs output format.
        #[arg(long, default_value = DEFAULT_MUSIC_FORMAT)]
        format: String,
    },
    /// Generate every item in a JSON spec (see tools/audiogen/specs).
    Batch {
        /// Path to the spec file.
        #[arg(long)]
        spec: PathBuf,
        /// Only generate the item with this name.
        #[arg(long)]
        only: Option<String>,
        /// Only generate items whose name starts with this prefix, for example radio/rock/.
        #[arg(long)]
        prefix: Option<String>,
        /// Generate at most this many new files in this run (skipped files do not count).
        #[arg(long)]
        limit: Option<usize>,
    },
    /// Speak one line with a voice (news bulletins, Host lines).
    Tts {
        /// Asset name without extension, for example radio/news/generic-01-count.
        #[arg(long)]
        name: String,
        /// Text to speak. Square-bracket delivery tags such as [sighs] work on eleven_v3.
        #[arg(long)]
        text: String,
        /// ElevenLabs voice id (see the voices command).
        #[arg(long)]
        voice: String,
        /// Speech model id.
        #[arg(long, default_value = DEFAULT_TTS_MODEL)]
        model: String,
        /// Stability from 0 (creative) to 1 (robust).
        #[arg(long)]
        stability: Option<f64>,
        /// ElevenLabs output format.
        #[arg(long, default_value = DEFAULT_TTS_FORMAT)]
        format: String,
        /// Display title recorded in the manifest.
        #[arg(long)]
        title: Option<String>,
    },
    /// Turn a scripts file (see specs/radio-news-scripts.json) into a batch spec with voices cast.
    Scripts {
        /// Path to the scripts file.
        #[arg(long)]
        scripts: PathBuf,
        /// Cast a speaker: --voice host=<id>, --voice caller=<id1>,<id2>. Repeat per speaker.
        #[arg(long = "voice", value_parser = parse_voice_assignment, required = true)]
        voices: Vec<(String, Vec<String>)>,
        /// Stability for every spoken item, 0 (creative) to 1 (robust).
        #[arg(long, default_value_t = 0.5)]
        stability: f64,
        /// Where to write the batch spec.
        #[arg(long)]
        out: PathBuf,
    },
    /// List the account's default voices with ids. ElevenLabs states default voices expire on 2026-12-31.
    Voices,
    /// Search the shared voice library (free). Prints id, owner, labels, notice period and rate.
    Library {
        /// Free-text search over names and descriptions.
        #[arg(long)]
        search: Option<String>,
        #[arg(long)]
        gender: Option<String>,
        #[arg(long)]
        age: Option<String>,
        #[arg(long)]
        accent: Option<String>,
        #[arg(long)]
        language: Option<String>,
        /// Use case filter, for example narrative_story; repeatable.
        #[arg(long = "use-case")]
        use_cases: Vec<String>,
        /// professional, famous or high_quality.
        #[arg(long)]
        category: Option<String>,
        /// Only voices whose owner must give at least this many days notice before removal.
        #[arg(long)]
        min_notice_days: Option<u32>,
        /// Include legacy custom-rate voices, which bill a credit multiplier.
        #[arg(long)]
        include_custom_rates: bool,
        /// created_date, usage_character_count_1y, trending or cloned_by_count.
        #[arg(long)]
        sort: Option<String>,
        #[arg(long, default_value_t = 30)]
        page_size: u32,
        #[arg(long, default_value_t = 0)]
        page: u32,
    },
    /// Design a voice from a description, or remix an existing one, into previews (charges the preview text).
    Design {
        /// Candidate name; previews land at <out-dir>/<name>_<n>.mp3 with <name>.design.json.
        #[arg(long)]
        name: String,
        /// What the voice should sound like.
        #[arg(long)]
        description: String,
        /// Preview text, 100 to 1000 characters. Use a line the voice will actually speak.
        #[arg(long)]
        text: String,
        /// Voice Design model.
        #[arg(long, default_value = DEFAULT_DESIGN_MODEL)]
        model: String,
        /// Remix this voice (one the account owns: designed or cloned) instead of designing from nothing.
        #[arg(long)]
        remix: Option<String>,
        #[arg(long)]
        seed: Option<u64>,
        /// Lower is freer, higher follows the description more literally.
        #[arg(long)]
        guidance_scale: Option<f64>,
        /// -1 (quietest) to 1 (loudest).
        #[arg(long)]
        loudness: Option<f64>,
        /// 0 to 1, eleven_ttv_v3 only.
        #[arg(long)]
        prompt_strength: Option<f64>,
        #[arg(long, default_value = DEFAULT_DESIGN_FORMAT)]
        format: String,
    },
    /// Save one design preview as an account voice (no credits; uses a voice slot).
    SaveVoice {
        /// generated_voice_id from a <name>.design.json record.
        #[arg(long)]
        generated_voice_id: String,
        /// Account voice name.
        #[arg(long)]
        voice_name: String,
        #[arg(long)]
        description: String,
    },
    /// Open the radio music review page: listen, then mark each track keep or reject.
    Review {
        #[command(flatten)]
        paths: ReviewPaths,
        /// Loopback port for the page (0 picks a free one).
        #[arg(long, default_value_t = review::DEFAULT_PORT)]
        port: u16,
        /// Print the URL without opening a browser.
        #[arg(long)]
        no_open: bool,
    },
    /// Copy keepers into client/assets/audio/radio and remove rejected tracks. Dry run unless --apply.
    Promote {
        #[command(flatten)]
        paths: ReviewPaths,
        /// Refuse when a station that loses tracks would end with fewer than this.
        #[arg(long, default_value_t = review::DEFAULT_MIN_TRACKS)]
        min_tracks: usize,
        /// Allow a station to drop below --min-tracks.
        #[arg(long)]
        force: bool,
        /// Write the changes. Without this the plan is only printed.
        #[arg(long)]
        apply: bool,
    },
    /// Show remaining credits for the configured key.
    Quota,
    /// Print the campaign score takes picked in game (A or B per slot), read from
    /// the game's settings file. Spends nothing.
    ScorePicks {
        #[command(flatten)]
        score: ScorePaths,
        /// Also write the picks as JSON to this file.
        #[arg(long)]
        save: Option<PathBuf>,
    },
    /// Delete every shipped score take that was not picked, with its .import file
    /// and manifest entry. Slots without a pick keep both. Dry run unless --apply.
    ScorePrune {
        #[command(flatten)]
        score: ScorePaths,
        /// Delete the files. Without this the plan is only printed.
        #[arg(long)]
        apply: bool,
    },
}

/// Where the score take commands read.
#[derive(clap::Args, Debug, Clone, PartialEq)]
struct ScorePaths {
    /// The game's settings file. Defaults to Godot's user data folder for fragr.
    #[arg(long)]
    settings: Option<PathBuf>,
    /// Score slot list.
    #[arg(long, default_value = score::DEFAULT_SLOTS_FILE)]
    slots: PathBuf,
    /// Shipped takes (<dir>/<slot>/<take>.mp3); its parent holds audiogen-manifest.json.
    #[arg(long, default_value = score::DEFAULT_SCORE_DIR)]
    score_dir: PathBuf,
}

/// Where the review and promote commands read and write.
#[derive(clap::Args, Debug, Clone, PartialEq)]
struct ReviewPaths {
    /// Station list.
    #[arg(long, default_value = review::DEFAULT_STATIONS_FILE)]
    stations: PathBuf,
    /// Shipped station folders; its parent holds audiogen-manifest.json.
    #[arg(long, default_value = review::DEFAULT_RADIO_DIR)]
    radio_dir: PathBuf,
    /// Candidate station folders (<dir>/<station>/*.mp3).
    #[arg(long, default_value = review::DEFAULT_CANDIDATES_DIR)]
    candidates: PathBuf,
    /// Decisions file, written on every mark.
    #[arg(long, default_value = review::DEFAULT_DECISIONS_FILE)]
    decisions: PathBuf,
    /// Keepers wanted per station, shown on the tabs.
    #[arg(long, default_value_t = review::DEFAULT_TARGET)]
    target: usize,
    /// Review the campaign score instead: one tab per level bed or story cue,
    /// with its shipped takes side by side (defaults switch to the score's paths).
    #[arg(long)]
    score: bool,
}

impl ReviewPaths {
    fn config(self) -> review::ReviewConfig {
        let config = review::ReviewConfig {
            stations_file: self.stations,
            radio_dir: self.radio_dir,
            candidates_dir: self.candidates,
            decisions_file: self.decisions,
            target: self.target,
        };
        if self.score {
            config.for_score()
        } else {
            config
        }
    }
}

/// `speaker=id` or `speaker=id1,id2` for the scripts command.
fn parse_voice_assignment(raw: &str) -> Result<(String, Vec<String>), String> {
    let (speaker, ids) = raw
        .split_once('=')
        .ok_or_else(|| format!("expected speaker=<voice_id>, got '{raw}'"))?;
    let speaker = speaker.trim();
    let ids: Vec<String> = ids
        .split(',')
        .map(str::trim)
        .filter(|id| !id.is_empty())
        .map(str::to_string)
        .collect();
    if speaker.is_empty() || ids.is_empty() {
        return Err(format!("expected speaker=<voice_id>, got '{raw}'"));
    }
    Ok((speaker.to_string(), ids))
}

fn to_command(cmd: Cmd) -> Result<Command, Error> {
    Ok(match cmd {
        Cmd::Sfx {
            name,
            prompt,
            seconds,
            influence,
            looping,
            format,
        } => Command::Generate {
            name,
            job: Job::Sfx(SfxParams {
                prompt,
                seconds,
                influence,
                looping,
                format,
                title: None,
            }),
        },
        Cmd::Music {
            name,
            title,
            prompt,
            length_ms,
            model,
            instrumental,
            format,
        } => Command::Generate {
            name,
            job: Job::Music(MusicParams {
                prompt,
                length_ms,
                model,
                instrumental,
                format,
                title,
            }),
        },
        Cmd::Batch {
            spec,
            only,
            prefix,
            limit,
        } => {
            let text = std::fs::read_to_string(&spec)?;
            Command::Batch {
                spec: parse_spec(&text)?,
                only,
                prefix,
                limit,
            }
        }
        Cmd::Tts {
            name,
            text,
            voice,
            model,
            stability,
            format,
            title,
        } => Command::Generate {
            name,
            job: Job::Tts(TtsParams {
                text,
                voice_id: voice,
                model,
                stability,
                format,
                title,
                lines: Vec::new(),
            }),
        },
        Cmd::Scripts {
            scripts,
            voices,
            stability,
            out,
        } => {
            let scripts_json = std::fs::read_to_string(&scripts)?;
            let mut cast = fragr_audiogen::VoiceCast::new();
            for (speaker, ids) in voices {
                cast.entry(speaker).or_default().extend(ids);
            }
            Command::Scripts {
                scripts_json,
                cast,
                stability,
                out,
            }
        }
        Cmd::Voices => Command::Voices,
        Cmd::Library {
            search,
            gender,
            age,
            accent,
            language,
            use_cases,
            category,
            min_notice_days,
            include_custom_rates,
            sort,
            page_size,
            page,
        } => Command::Library(LibraryQuery {
            search,
            gender,
            age,
            accent,
            language,
            use_cases,
            category,
            min_notice_days,
            include_custom_rates,
            sort,
            page_size,
            page,
        }),
        Cmd::Design {
            name,
            description,
            text,
            model,
            remix,
            seed,
            guidance_scale,
            loudness,
            prompt_strength,
            format,
        } => Command::Design {
            name,
            params: DesignParams {
                description,
                text,
                model,
                remix_voice_id: remix,
                seed,
                guidance_scale,
                loudness,
                prompt_strength,
                format,
            },
        },
        Cmd::SaveVoice {
            generated_voice_id,
            voice_name,
            description,
        } => Command::SaveVoice(SaveVoiceParams {
            generated_voice_id,
            voice_name,
            description,
        }),
        Cmd::Quota => Command::Quota,
        Cmd::Review { .. }
        | Cmd::Promote { .. }
        | Cmd::ScorePicks { .. }
        | Cmd::ScorePrune { .. } => return Err(Error::InvalidArgument(
            "review, promote and the score take commands run locally, not through the generator"
                .into(),
        )),
    })
}

struct HttpTransport {
    client: reqwest::blocking::Client,
    base_url: String,
}

impl HttpTransport {
    fn new(base_url: &str) -> Result<Self, Error> {
        // Music generation can take minutes for long tracks; keep the timeout generous.
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(600))
            .build()
            .map_err(|err| Error::Transport(err.to_string()))?;
        Ok(HttpTransport {
            client,
            base_url: base_url.trim_end_matches('/').to_string(),
        })
    }
}

impl Transport for HttpTransport {
    fn send(&self, api_key: &str, request: &Request) -> Result<Response, Error> {
        let url = format!("{}{}", self.base_url, request.path);
        let mut builder = match request.method {
            Method::Get => self.client.get(&url),
            Method::Post => self.client.post(&url),
        };
        builder = builder.header("xi-api-key", api_key).query(&request.query);
        if let Some(body) = &request.body {
            builder = builder.json(body);
        }
        let response = builder
            .send()
            .map_err(|err| Error::Transport(err.to_string()))?;
        let status = response.status().as_u16();
        let media = response
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .is_some_and(|value| value.contains("audio") || value.contains("octet-stream"));
        // Voice Design returns its previews as base64 inside JSON; library pages are large JSON.
        let limit = if media {
            20 * 1024 * 1024
        } else if request.path.starts_with("/v1/text-to-voice") {
            32 * 1024 * 1024
        } else if request.path == "/v1/shared-voices" {
            4 * 1024 * 1024
        } else {
            256 * 1024
        };
        let declared = response.content_length();
        let body = read_capped(&mut response.take(limit as u64 + 1), declared, limit)?;
        Ok(Response { status, body })
    }
}

fn open_browser(url: &str) -> std::io::Result<()> {
    let mut command = if cfg!(target_os = "windows") {
        let mut command = std::process::Command::new("cmd");
        command.args(["/C", "start", ""]);
        command
    } else if cfg!(target_os = "macos") {
        std::process::Command::new("open")
    } else {
        std::process::Command::new("xdg-open")
    };
    command
        .arg(url)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map(drop)
}

fn run_review(
    paths: ReviewPaths,
    port: u16,
    no_open: bool,
    out: &mut dyn std::io::Write,
) -> Result<(), Error> {
    let listener = match std::net::TcpListener::bind(("127.0.0.1", port)) {
        Ok(listener) => listener,
        Err(err) if err.kind() == std::io::ErrorKind::AddrInUse => {
            return Err(Error::InvalidArgument(format!(
                "port {port} is busy (is a review page already running?); pass --port 0 for any free port"
            )))
        }
        Err(err) => return Err(err.into()),
    };
    let port = listener.local_addr()?.port();
    let server = review::ReviewServer::new(paths.config(), port)?;
    let tracks: usize = server
        .catalog
        .stations
        .iter()
        .map(|station| station.tracks.len())
        .sum();
    let url = format!("http://127.0.0.1:{port}/");
    writeln!(
        out,
        "review: {} stations, {tracks} tracks; decisions in {}",
        server.catalog.stations.len(),
        server.config.decisions_file.display()
    )?;
    writeln!(out, "review: open {url} (Ctrl+C to stop)")?;
    out.flush()?;
    if !no_open {
        if let Err(err) = open_browser(&url) {
            writeln!(
                out,
                "review: could not open a browser ({err}); open the URL by hand"
            )?;
        }
    }
    review::serve(listener, server)
}

fn run_promote(
    paths: ReviewPaths,
    min_tracks: usize,
    force: bool,
    apply: bool,
    out: &mut dyn std::io::Write,
) -> Result<(), Error> {
    // A score slot ships two takes and keeps at least one, not a station's twelve.
    let min_tracks = if paths.score && min_tracks == review::DEFAULT_MIN_TRACKS {
        review::SCORE_MIN_TAKES
    } else {
        min_tracks
    };
    let config = paths.config();
    let mut decisions = review::load_decisions(&config.decisions_file)?;
    let catalog = review::scan_catalog(&config, &decisions)?;
    let plan = review::plan_promotion(&config, &catalog, &decisions);
    write!(out, "{}", review::describe_plan(&plan, min_tracks, force))?;
    if !apply {
        writeln!(out, "dry run: nothing written; pass --apply to promote")?;
        return Ok(());
    }
    if let Some(reason) = review::promotion_refusal(&plan, min_tracks, force) {
        return Err(Error::InvalidArgument(format!(
            "promotion refused: {reason}"
        )));
    }
    if plan.stations.iter().all(|station| !station.changes()) {
        return Ok(());
    }
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    review::apply_promotion(&config, &plan, &mut decisions, now)?;
    writeln!(
        out,
        "promoted. Next: import in Godot (tools/godot_check.sh) to create .import files, then check `git status client/assets/audio` and stage with `git add -A client/assets/audio`"
    )?;
    Ok(())
}

fn score_rows(paths: &ScorePaths) -> Result<(PathBuf, Vec<score::PickRow>), Error> {
    let settings = match &paths.settings {
        Some(path) => path.clone(),
        None => score::default_settings_path().ok_or_else(|| {
            Error::InvalidArgument(
                "cannot find the game's user data folder; pass --settings <settings.cfg>".into(),
            )
        })?,
    };
    let text = std::fs::read_to_string(&settings).map_err(|err| {
        Error::InvalidArgument(format!(
            "cannot read {} ({err}); play a campaign level once or pass --settings",
            settings.display()
        ))
    })?;
    let takes = score::parse_takes(&text)?;
    let slots = score::load_slots(&paths.slots)?;
    Ok((
        settings,
        score::collect_picks(&slots, &takes, &paths.score_dir),
    ))
}

fn run_score_picks(
    paths: ScorePaths,
    save: Option<PathBuf>,
    out: &mut dyn std::io::Write,
) -> Result<(), Error> {
    let (settings, rows) = score_rows(&paths)?;
    writeln!(out, "score picks from {}", settings.display())?;
    write!(out, "{}", score::describe_picks(&rows))?;
    if let Some(path) = save {
        let json = serde_json::json!({ "settings": settings.display().to_string(), "slots": rows });
        let text =
            serde_json::to_string_pretty(&json).map_err(|err| Error::Spec(err.to_string()))?;
        if let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, format!("{text}\n"))?;
        writeln!(out, "saved {}", path.display())?;
    }
    Ok(())
}

fn run_score_prune(
    paths: ScorePaths,
    apply: bool,
    out: &mut dyn std::io::Write,
) -> Result<(), Error> {
    let (settings, rows) = score_rows(&paths)?;
    writeln!(out, "score picks from {}", settings.display())?;
    let plan = score::plan_prune(&rows, &paths.score_dir);
    write!(out, "{}", score::describe_prune(&plan))?;
    if !apply {
        writeln!(out, "dry run: nothing deleted; pass --apply to prune")?;
        return Ok(());
    }
    if plan.removals.is_empty() {
        return Ok(());
    }
    score::apply_prune(&plan, &paths.score_dir)?;
    writeln!(
        out,
        "pruned {} take(s). Next: run tools/godot_check.sh, check `git status client/assets/audio` and stage with `git add -A client/assets/audio`",
        plan.removals.len()
    )?;
    Ok(())
}

fn run(cli: Cli, out: &mut dyn std::io::Write) -> Result<(), Error> {
    match cli.command {
        Cmd::Review {
            paths,
            port,
            no_open,
        } => return run_review(paths, port, no_open, out),
        Cmd::Promote {
            paths,
            min_tracks,
            force,
            apply,
        } => return run_promote(paths, min_tracks, force, apply && !cli.dry_run, out),
        Cmd::ScorePicks { score, save } => return run_score_picks(score, save, out),
        Cmd::ScorePrune { score, apply } => {
            return run_score_prune(score, apply && !cli.dry_run, out)
        }
        _ => {}
    }
    // Dry runs never need a key. Quota always does.
    // Dry runs and the scripts converter never touch the network. Quota and voices always do.
    let needs_key = (!cli.dry_run && !matches!(cli.command, Cmd::Scripts { .. }))
        || matches!(cli.command, Cmd::Quota | Cmd::Voices | Cmd::Library { .. });
    let api_key = if needs_key {
        let from_env = match std::env::var(API_KEY_ENV) {
            Ok(value) => Some(value),
            Err(_) => read_dotenv_key(&cli.env_file)?,
        };
        resolve_api_key(from_env, cli.api_key_file.as_deref())?
    } else {
        String::new()
    };
    let command = to_command(cli.command)?;
    let options = RunOptions {
        out_dir: cli.out_dir,
        overwrite: cli.overwrite,
        dry_run: cli.dry_run,
        max_credits: cli.max_credits,
    };
    let transport = HttpTransport::new(&cli.base_url)?;
    run_command(
        &command,
        &options,
        &transport,
        &api_key,
        out,
        &mut |delay| std::thread::sleep(delay),
    )
}

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .with_writer(std::io::stderr)
        .init();
    let cli = Cli::parse();
    let mut stdout = std::io::stdout();
    if let Err(err) = run(cli, &mut stdout) {
        eprintln!("error: {err}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_sfx_arguments() {
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "--out-dir",
            "out",
            "--overwrite",
            "sfx",
            "--name",
            "fire_rail",
            "--prompt",
            "rail shot",
            "--seconds",
            "0.8",
            "--influence",
            "0.6",
            "--loop",
        ])
        .unwrap();
        assert_eq!(cli.out_dir, Some(PathBuf::from("out")));
        assert!(cli.overwrite);
        assert!(!cli.dry_run);
        match to_command(cli.command).unwrap() {
            Command::Generate {
                name,
                job: Job::Sfx(params),
            } => {
                assert_eq!(name, "fire_rail");
                assert_eq!(params.prompt, "rail shot");
                assert_eq!(params.seconds, Some(0.8));
                assert_eq!(params.influence, Some(0.6));
                assert!(params.looping);
                assert_eq!(params.format, DEFAULT_SFX_FORMAT);
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn parses_music_arguments() {
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "music",
            "--name",
            "music/match_01",
            "--prompt",
            "industrial arena loop",
            "--length-ms",
            "45000",
            "--instrumental",
        ])
        .unwrap();
        match to_command(cli.command).unwrap() {
            Command::Generate {
                name,
                job: Job::Music(params),
            } => {
                assert_eq!(name, "music/match_01");
                assert_eq!(params.length_ms, Some(45_000));
                assert_eq!(params.model, DEFAULT_MUSIC_MODEL);
                assert_eq!(params.format, DEFAULT_MUSIC_FORMAT);
                assert!(params.instrumental);
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn parses_batch_and_quota() {
        let dir = std::env::temp_dir().join("fragr-audiogen-main-batch");
        std::fs::create_dir_all(&dir).unwrap();
        let spec = dir.join("spec.json");
        std::fs::write(
            &spec,
            r#"{"items": [{"kind": "sfx", "name": "a", "prompt": "p"}]}"#,
        )
        .unwrap();
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "batch",
            "--spec",
            spec.to_str().unwrap(),
            "--only",
            "a",
        ])
        .unwrap();
        match to_command(cli.command).unwrap() {
            Command::Batch { spec, only, .. } => {
                assert_eq!(spec.items.len(), 1);
                assert_eq!(only.as_deref(), Some("a"));
            }
            other => panic!("unexpected {other:?}"),
        }
        let missing =
            Cli::try_parse_from(["fragr-audiogen", "batch", "--spec", "does-not-exist.json"])
                .unwrap();
        assert!(matches!(to_command(missing.command), Err(Error::Io(_))));
        let quota = Cli::try_parse_from(["fragr-audiogen", "quota"]).unwrap();
        assert_eq!(to_command(quota.command).unwrap(), Command::Quota);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn parses_tts_and_voices() {
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "tts",
            "--name",
            "radio/news/generic-01-count",
            "--text",
            "[sighs] Good evening.",
            "--voice",
            "JBFqnCBsd6RMkjVDRZzb",
            "--stability",
            "0.4",
            "--title",
            "Count",
        ])
        .unwrap();
        match to_command(cli.command).unwrap() {
            Command::Generate {
                name,
                job: Job::Tts(params),
            } => {
                assert_eq!(name, "radio/news/generic-01-count");
                assert_eq!(params.voice_id, "JBFqnCBsd6RMkjVDRZzb");
                assert_eq!(params.model, DEFAULT_TTS_MODEL);
                assert_eq!(params.format, DEFAULT_TTS_FORMAT);
                assert_eq!(params.stability, Some(0.4));
                assert_eq!(params.title.as_deref(), Some("Count"));
            }
            other => panic!("unexpected {other:?}"),
        }
        let voices = Cli::try_parse_from(["fragr-audiogen", "voices"]).unwrap();
        assert_eq!(to_command(voices.command).unwrap(), Command::Voices);
    }

    #[test]
    fn parses_library_design_and_save_voice() {
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "library",
            "--search",
            "narrator",
            "--use-case",
            "narrative_story",
            "--min-notice-days",
            "365",
        ])
        .unwrap();
        match to_command(cli.command).unwrap() {
            Command::Library(query) => {
                assert_eq!(query.search.as_deref(), Some("narrator"));
                assert_eq!(query.use_cases, vec!["narrative_story".to_string()]);
                assert_eq!(query.min_notice_days, Some(365));
                assert_eq!(query.page_size, 30);
                assert!(!query.include_custom_rates);
            }
            other => panic!("unexpected {other:?}"),
        }
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "--out-dir",
            "/tmp/x",
            "design",
            "--name",
            "narrator/a",
            "--description",
            "warm narrator",
            "--text",
            "line",
            "--remix",
            "abc123",
            "--seed",
            "4",
        ])
        .unwrap();
        match to_command(cli.command).unwrap() {
            Command::Design { name, params } => {
                assert_eq!(name, "narrator/a");
                assert_eq!(params.model, DEFAULT_DESIGN_MODEL);
                assert_eq!(params.remix_voice_id.as_deref(), Some("abc123"));
                assert_eq!(params.seed, Some(4));
                assert_eq!(params.format, DEFAULT_DESIGN_FORMAT);
            }
            other => panic!("unexpected {other:?}"),
        }
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "save-voice",
            "--generated-voice-id",
            "gen1",
            "--voice-name",
            "narrator",
            "--description",
            "warm",
        ])
        .unwrap();
        assert!(matches!(
            to_command(cli.command).unwrap(),
            Command::SaveVoice(params) if params.generated_voice_id == "gen1"
        ));
    }

    #[test]
    fn parses_scripts_command() {
        let dir = std::env::temp_dir().join("fragr-audiogen-main-scripts");
        std::fs::create_dir_all(&dir).unwrap();
        let scripts = dir.join("scripts.json");
        std::fs::write(
            &scripts,
            r#"{"items": [{"name": "radio/news/generic-01-a", "class": "generic", "speaker": "host", "title": "A", "text": "Hello."}]}"#,
        )
        .unwrap();
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "scripts",
            "--scripts",
            scripts.to_str().unwrap(),
            "--voice",
            "host=h1",
            "--voice",
            "caller=c1,c2",
            "--voice",
            "caller=c3",
            "--stability",
            "0.4",
            "--out",
            dir.join("out.json").to_str().unwrap(),
        ])
        .unwrap();
        match to_command(cli.command).unwrap() {
            Command::Scripts {
                cast, stability, ..
            } => {
                assert_eq!(cast["host"], vec!["h1".to_string()]);
                assert_eq!(
                    cast["caller"],
                    vec!["c1".to_string(), "c2".into(), "c3".into()]
                );
                assert_eq!(stability, 0.4);
            }
            other => panic!("unexpected {other:?}"),
        }
        assert!(parse_voice_assignment("host").is_err());
        assert!(parse_voice_assignment("=id").is_err());
        assert!(parse_voice_assignment("host=").is_err());
        assert_eq!(
            parse_voice_assignment(" tina = a , b ").unwrap(),
            ("tina".to_string(), vec!["a".to_string(), "b".to_string()])
        );
        // The converter needs no key: a missing key file must not stop it.
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "--api-key-file",
            "definitely-missing.key",
            "scripts",
            "--scripts",
            scripts.to_str().unwrap(),
            "--voice",
            "host=h1",
            "--out",
            dir.join("out2.json").to_str().unwrap(),
        ])
        .unwrap();
        let mut out = Vec::new();
        run(cli, &mut out).unwrap();
        assert!(String::from_utf8(out).unwrap().contains("with 1 items"));
        assert!(dir.join("out2.json").exists());
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn parses_review_and_promote() {
        let cli =
            Cli::try_parse_from(["fragr-audiogen", "review", "--port", "0", "--no-open"]).unwrap();
        match cli.command {
            Cmd::Review {
                paths,
                port,
                no_open,
            } => {
                assert_eq!(port, 0);
                assert!(no_open);
                assert_eq!(paths.config(), review::ReviewConfig::default());
            }
            other => panic!("unexpected {other:?}"),
        }
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "promote",
            "--min-tracks",
            "5",
            "--force",
            "--decisions",
            "d.json",
        ])
        .unwrap();
        match cli.command {
            Cmd::Promote {
                paths,
                min_tracks,
                force,
                apply,
            } => {
                assert_eq!(min_tracks, 5);
                assert!(force);
                assert!(!apply);
                assert_eq!(paths.decisions, PathBuf::from("d.json"));
                let command = Cmd::Promote {
                    paths,
                    min_tracks,
                    force,
                    apply,
                };
                assert!(to_command(command).is_err());
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn promote_dry_run_and_apply_need_no_key() {
        let dir = std::env::temp_dir().join(format!(
            "fragr-audiogen-main-promote-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("audio/radio/rock")).unwrap();
        std::fs::create_dir_all(dir.join("cand/radio/rock")).unwrap();
        std::fs::write(
            dir.join("audio/radio/stations.json"),
            r#"{"stations": [{"id": "rock"}]}"#,
        )
        .unwrap();
        std::fs::write(dir.join("audio/radio/rock/01-a.mp3"), b"a").unwrap();
        std::fs::write(
            dir.join("decisions.json"),
            r#"{"version": 1, "decisions": {"shipped/rock/01-a.mp3": {"decision": "reject", "at_unix": 1}}}"#,
        )
        .unwrap();
        let args = |extra: &[&str]| {
            let mut args = vec![
                "fragr-audiogen".to_string(),
                "--api-key-file".into(),
                "definitely-missing.key".into(),
            ];
            args.extend(extra.iter().map(|s| s.to_string()));
            args.extend([
                "promote".into(),
                "--stations".into(),
                dir.join("audio/radio/stations.json").display().to_string(),
                "--radio-dir".into(),
                dir.join("audio/radio").display().to_string(),
                "--candidates".into(),
                dir.join("cand/radio").display().to_string(),
                "--decisions".into(),
                dir.join("decisions.json").display().to_string(),
            ]);
            args
        };
        let mut out = Vec::new();
        run(Cli::try_parse_from(args(&[])).unwrap(), &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(
            text.contains("rock: 1 -> 0 tracks (+0 -1) REFUSED"),
            "{text}"
        );
        assert!(text.contains("dry run"));
        // The global --dry-run wins over --apply.
        let mut with_apply = args(&["--dry-run"]);
        with_apply.push("--apply".into());
        run(Cli::try_parse_from(with_apply).unwrap(), &mut Vec::new()).unwrap();
        let mut apply = args(&[]);
        apply.push("--apply".into());
        let err = run(Cli::try_parse_from(apply.clone()).unwrap(), &mut Vec::new()).unwrap_err();
        assert!(err.to_string().contains("refused"), "{err}");
        assert!(dir.join("audio/radio/rock/01-a.mp3").exists());
        apply.push("--force".into());
        let mut out = Vec::new();
        run(Cli::try_parse_from(apply.clone()).unwrap(), &mut out).unwrap();
        assert!(String::from_utf8(out).unwrap().contains("promoted"));
        assert!(!dir.join("audio/radio/rock/01-a.mp3").exists());
        // Nothing left to do on a second pass.
        run(Cli::try_parse_from(apply).unwrap(), &mut Vec::new()).unwrap();
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn review_reports_a_bad_layout() {
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "review",
            "--port",
            "0",
            "--no-open",
            "--stations",
            "definitely-missing-stations.json",
        ])
        .unwrap();
        let err = run(cli, &mut Vec::new()).unwrap_err();
        assert!(
            err.to_string().contains("definitely-missing-stations.json"),
            "{err}"
        );
        // A second review on a busy port says so instead of a bare io error.
        let busy = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = busy.local_addr().unwrap().port().to_string();
        let cli = Cli::try_parse_from(["fragr-audiogen", "review", "--port", &port, "--no-open"])
            .unwrap();
        let err = run(cli, &mut Vec::new()).unwrap_err();
        assert!(err.to_string().contains("--port 0"), "{err}");
    }

    #[test]
    fn rejects_missing_required_arguments() {
        assert!(Cli::try_parse_from(["fragr-audiogen", "sfx", "--name", "x"]).is_err());
        assert!(Cli::try_parse_from(["fragr-audiogen"]).is_err());
    }

    #[test]
    fn http_transport_trims_base_url() {
        let transport = HttpTransport::new("https://example.test/").unwrap();
        assert_eq!(transport.base_url, "https://example.test");
    }

    #[test]
    fn dry_run_needs_no_key_and_writes_nothing() {
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "--dry-run",
            "--api-key-file",
            "definitely-missing.key",
            "--out-dir",
            "unused-dir",
            "sfx",
            "--name",
            "hit",
            "--prompt",
            "thud",
        ])
        .unwrap();
        let mut out = Vec::new();
        run(cli, &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.starts_with("dry-run hit -> "));
        assert!(!PathBuf::from("unused-dir").exists());
    }

    #[test]
    fn live_run_reads_a_dotenv_file() {
        let dir = std::env::temp_dir().join("fragr-audiogen-main-dotenv");
        std::fs::create_dir_all(&dir).unwrap();
        let env_file = dir.join(".env");
        std::fs::write(&env_file, "elevenlabs=sk_test_only\n").unwrap();
        // An unreachable host proves the key resolved and the request was attempted.
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "--env-file",
            env_file.to_str().unwrap(),
            "--base-url",
            "http://127.0.0.1:9",
            "quota",
        ])
        .unwrap();
        let err = run(cli, &mut Vec::new()).unwrap_err();
        assert!(matches!(err, Error::Transport(_)), "unexpected {err}");
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn live_run_requires_a_readable_key() {
        let cli = Cli::try_parse_from([
            "fragr-audiogen",
            "--api-key-file",
            "definitely-missing.key",
            "quota",
        ])
        .unwrap();
        let err = run(cli, &mut Vec::new()).unwrap_err();
        assert!(matches!(err, Error::Io(_)));
    }

    #[test]
    fn score_commands_read_settings_and_prune_without_a_key() {
        let dir =
            std::env::temp_dir().join(format!("fragr-audiogen-main-score-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let score = dir.join("audio/score");
        for slot in ["l01", "l02"] {
            std::fs::create_dir_all(score.join(slot)).unwrap();
            for take in ["a", "b"] {
                std::fs::write(score.join(format!("{slot}/{take}.mp3")), b"x").unwrap();
            }
        }
        std::fs::write(
            score.join("slots.json"),
            r#"{"slots": [{"id": "l01", "kind": "bed", "name": "Level 1"}, {"id": "l02", "kind": "bed"}]}"#,
        )
        .unwrap();
        let settings = dir.join("settings.cfg");
        std::fs::write(
            &settings,
            "[score]\n\nenabled=true\ntakes={\n\"l01\": \"b\"\n}\n",
        )
        .unwrap();
        let args = |command: &str, extra: &[&str]| {
            let mut args: Vec<String> = vec![
                "fragr-audiogen".into(),
                "--api-key-file".into(),
                "definitely-missing.key".into(),
                command.into(),
                "--settings".into(),
                settings.display().to_string(),
                "--slots".into(),
                score.join("slots.json").display().to_string(),
                "--score-dir".into(),
                score.display().to_string(),
            ];
            args.extend(extra.iter().map(|s| s.to_string()));
            args
        };
        let saved = dir.join("picks/picks.json");
        let mut out = Vec::new();
        run(
            Cli::try_parse_from(args("score-picks", &["--save", saved.to_str().unwrap()])).unwrap(),
            &mut out,
        )
        .unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(
            text.contains("l01       pick B  ships A+B  Level 1"),
            "{text}"
        );
        assert!(text.contains("1 of 2 slots picked"), "{text}");
        let json: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&saved).unwrap()).unwrap();
        assert_eq!(json["slots"][0]["pick"], "b");
        let mut out = Vec::new();
        run(
            Cli::try_parse_from(args("score-prune", &[])).unwrap(),
            &mut out,
        )
        .unwrap();
        assert!(String::from_utf8(out).unwrap().contains("dry run"));
        assert!(score.join("l01/a.mp3").exists());
        let mut out = Vec::new();
        run(
            Cli::try_parse_from(args("score-prune", &["--apply"])).unwrap(),
            &mut out,
        )
        .unwrap();
        assert!(String::from_utf8(out).unwrap().contains("pruned 1 take"));
        assert!(!score.join("l01/a.mp3").exists() && score.join("l01/b.mp3").exists());
        assert!(score.join("l02/a.mp3").exists() && score.join("l02/b.mp3").exists());
        let missing = vec![
            "fragr-audiogen".to_string(),
            "score-picks".into(),
            "--settings".into(),
            dir.join("nope.cfg").display().to_string(),
        ];
        let err = run(Cli::try_parse_from(missing).unwrap(), &mut Vec::new()).unwrap_err();
        assert!(err.to_string().contains("--settings"), "{err}");
        let cli =
            Cli::try_parse_from(["fragr-audiogen", "review", "--score", "--no-open"]).unwrap();
        match cli.command {
            Cmd::Review { paths, .. } => assert_eq!(paths.config(), review::ReviewConfig::score()),
            other => panic!("unexpected {other:?}"),
        }
        let command = Cmd::ScorePicks {
            score: ScorePaths {
                settings: None,
                slots: PathBuf::from("s"),
                score_dir: PathBuf::from("d"),
            },
            save: None,
        };
        assert!(to_command(command).is_err());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
