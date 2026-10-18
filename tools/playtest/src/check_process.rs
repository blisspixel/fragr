//! Developer check deadline. File output deliberately avoids inherited-pipe EOF.
use clap::Parser;
use std::ffi::OsString;
use std::fs::File;
use std::path::PathBuf;
use std::process::{Child, Command, ExitCode, ExitStatus, Stdio};
use std::time::{Duration, Instant};

#[derive(Parser)]
#[command(about = "Run one developer check with a deadline and retained output")]
struct Args {
    #[arg(long, default_value_t = 180_000, value_parser = clap::value_parser!(u64).range(1..))]
    timeout_ms: u64,
    #[arg(long)]
    output: PathBuf,
    #[arg(required = true, trailing_var_arg = true, allow_hyphen_values = true)]
    command: Vec<OsString>,
}

fn wait_until(child: &mut Child, deadline: Instant) -> std::io::Result<Option<ExitStatus>> {
    loop {
        if let Some(status) = child.try_wait()? {
            return Ok(Some(status));
        }
        if Instant::now() >= deadline {
            return Ok(None);
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[cfg(windows)]
fn stop_tree(pid: u32) -> std::io::Result<()> {
    let mut killer = Command::new("taskkill.exe")
        .args(["/T", "/F", "/PID", &pid.to_string()])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    let status = wait_until(&mut killer, Instant::now() + Duration::from_secs(5))?;
    if !status.is_some_and(|status| status.success()) {
        let _ = killer.kill();
        let _ = wait_until(&mut killer, Instant::now() + Duration::from_secs(1));
        return Err(std::io::Error::other(
            "owned descendant-tree cleanup failed",
        ));
    }
    Ok(())
}

fn stop(child: &mut Child) -> std::io::Result<()> {
    // The retained Child handle identifies this process. Never discover or kill
    // unrelated processes by executable name. The Windows console launcher can
    // own both the engine and the engine's local server.
    #[cfg(windows)]
    if let Err(error) = stop_tree(child.id()) {
        // Best effort direct-child cleanup does not establish tree cleanup.
        let _ = child.kill();
        let _ = wait_until(child, Instant::now() + Duration::from_secs(2));
        return Err(error);
    }
    #[cfg(not(windows))]
    child.kill()?;
    if wait_until(child, Instant::now() + Duration::from_secs(2))?.is_none() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::TimedOut,
            "owned check did not exit after termination",
        ));
    }
    Ok(())
}

fn run(args: Args) -> std::io::Result<u8> {
    let output = File::create(&args.output)?;
    let mut child = Command::new(&args.command[0])
        .args(&args.command[1..])
        .stdin(Stdio::inherit())
        .stdout(Stdio::from(output.try_clone()?))
        .stderr(Stdio::from(output))
        .spawn()?;
    let started = Instant::now();
    loop {
        if let Some(status) = child.try_wait()? {
            if status.success() {
                return Ok(0);
            }
            eprintln!(
                "Check exited with {status}; output: {}",
                args.output.display()
            );
            return Ok(status
                .code()
                .and_then(|code| u8::try_from(code).ok())
                .unwrap_or(1));
        }
        if started.elapsed() >= Duration::from_millis(args.timeout_ms) {
            eprintln!(
                "CHECK TIMEOUT after {} ms; output: {}",
                args.timeout_ms,
                args.output.display()
            );
            stop(&mut child)?;
            return Ok(124);
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn main() -> ExitCode {
    match run(Args::parse()) {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            eprintln!("Check process failed: {error}");
            ExitCode::FAILURE
        }
    }
}
