//! `cargo run -p fragr-licenses -- --target <triple> --out THIRD_PARTY_LICENSES.txt`
//! lists the crates fragr-server links for those targets with their license
//! texts, and fails when any crate cannot be resolved against deny.toml.

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::process::{Command, ExitCode};

use clap::Parser;
use fragr_licenses::{distributed_crates, parse_allowlist, render, Crate};

#[derive(Parser)]
#[command(about = "Write third-party license notices for a packaged fragr-server")]
struct Args {
    /// Workspace package whose linked dependencies are listed.
    #[arg(long, default_value = "fragr-server")]
    package: String,
    /// Target triple to resolve for; repeat to union several (a universal macOS build).
    #[arg(long, required = true)]
    target: Vec<String>,
    /// cargo-deny policy whose license allowlist every crate must satisfy.
    #[arg(long, default_value = "deny.toml")]
    deny: PathBuf,
    /// Output file.
    #[arg(long)]
    out: PathBuf,
}

fn metadata(target: &str) -> Result<serde_json::Value, String> {
    let cargo = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
    let output = Command::new(cargo)
        .args([
            "metadata",
            "--locked",
            "--format-version",
            "1",
            "--filter-platform",
            target,
        ])
        .output()
        .map_err(|error| format!("cannot run cargo metadata: {error}"))?;
    if !output.status.success() {
        return Err(format!(
            "cargo metadata failed for {target}: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    serde_json::from_slice(&output.stdout).map_err(|error| format!("cargo metadata JSON: {error}"))
}

fn run(args: &Args) -> Result<usize, Vec<String>> {
    let deny = std::fs::read_to_string(&args.deny)
        .map_err(|error| vec![format!("cannot read {}: {error}", args.deny.display())])?;
    let allow = parse_allowlist(&deny)
        .map_err(|error| vec![format!("{}: {error}", args.deny.display())])?;
    let mut crates: BTreeMap<(String, String), Crate> = BTreeMap::new();
    for target in &args.target {
        let metadata = metadata(target).map_err(|error| vec![error])?;
        for krate in distributed_crates(&metadata, &args.package).map_err(|error| vec![error])? {
            crates.insert((krate.name.clone(), krate.version.clone()), krate);
        }
    }
    let list: Vec<Crate> = crates.into_values().collect();
    let doc = render(&list, &allow)?;
    std::fs::write(&args.out, doc)
        .map_err(|error| vec![format!("cannot write {}: {error}", args.out.display())])?;
    Ok(list.len())
}

fn main() -> ExitCode {
    let args = Args::parse();
    match run(&args) {
        Ok(count) => {
            println!(
                "fragr-licenses: {count} crates for {} written to {}",
                args.target.join(", "),
                args.out.display()
            );
            ExitCode::SUCCESS
        }
        Err(problems) => {
            for problem in problems {
                eprintln!("fragr-licenses: {problem}");
            }
            ExitCode::FAILURE
        }
    }
}
