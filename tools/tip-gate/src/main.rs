//! Refuse empty hangar jammer tip stills. The historical Soft Prison capture
//! missed the dish and still produced plausible PNGs, with an orange share of
//! about 0.01, so `tools/capture_tip_screenshots.sh` checks each named still
//! for a minimum footprint of the dish's orange.
//!
//! Usage: `gate-tip-jammer-orange OUT_DIR`. Exit 0 passes, 1 fails a still or
//! misses one, 2 is a usage error.

use std::path::Path;
use std::process::ExitCode;

/// Named stills and the orange share each must reach.
const FLOORS: [(&str, f64); 3] = [
    ("20_jammer_dish_follow_16x9.png", 0.05),
    ("22_jammer_dish_overview_16x9.png", 0.03),
    ("23_jammer_dish_seize_label_16x9.png", 0.05),
];

/// Whether one pixel reads as the dish's orange.
fn is_orange([r, g, b]: [u8; 3]) -> bool {
    r > 140 && g > 40 && g < 200 && b < 120 && r > g && u16::from(r) > u16::from(b) + 30
}

/// Orange pixels and pixels sampled, on every second row and column from the
/// top left. Alpha is discarded rather than composited.
fn orange_count(image: &image::RgbImage) -> (u64, u64) {
    let (width, height) = image.dimensions();
    let mut orange = 0;
    let mut sampled = 0;
    for y in (0..height).step_by(2) {
        for x in (0..width).step_by(2) {
            sampled += 1;
            if is_orange(image.get_pixel(x, y).0) {
                orange += 1;
            }
        }
    }
    (orange, sampled)
}

fn orange_ratio(image: &image::RgbImage) -> f64 {
    match orange_count(image) {
        (_, 0) => 0.0,
        (orange, sampled) => orange as f64 / sampled as f64,
    }
}

/// Verdict lines, printed as they happen when `echo` is set so stdout and
/// stderr interleave in the order the checks ran, and kept for tests.
#[derive(Debug, Default)]
struct Sink {
    echo: bool,
    out: Vec<String>,
    err: Vec<String>,
}

impl Sink {
    fn out(&mut self, line: String) {
        if self.echo {
            println!("{line}");
        }
        self.out.push(line);
    }

    fn err(&mut self, line: String) {
        if self.echo {
            eprintln!("{line}");
        }
        self.err.push(line);
    }
}

/// Check every named still under `out`, recording one verdict line each.
/// Returns whether all of them exist, decode, and reach their floor.
fn gate(out: &Path, sink: &mut Sink) -> bool {
    let mut passed = true;
    for (name, floor) in FLOORS {
        let path = out.join(name);
        if !path.is_file() {
            sink.err(format!("tip_capture gate: missing {}", path.display()));
            passed = false;
            continue;
        }
        let image = match image::open(&path) {
            Ok(image) => image.to_rgb8(),
            Err(error) => {
                sink.err(format!(
                    "tip_capture gate: cannot read {}: {error}",
                    path.display()
                ));
                passed = false;
                continue;
            }
        };
        let ratio = orange_ratio(&image);
        sink.out(format!(
            "tip_capture gate: {name} orange={ratio:.4} floor={floor:.4}"
        ));
        if ratio < floor {
            sink.err(format!(
                "tip_capture gate: FAIL {name} empty hangar / no dish"
            ));
            passed = false;
        }
    }
    if passed {
        sink.out("tip_capture gate: PASS jammer orange footprint".to_string());
    }
    passed
}

fn run(args: &[String], sink: &mut Sink) -> u8 {
    let [out] = args else {
        sink.err("usage: gate-tip-jammer-orange OUT_DIR".to_string());
        return 2;
    };
    if gate(Path::new(out), sink) {
        0
    } else {
        1
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = run(
        &args,
        &mut Sink {
            echo: true,
            ..Sink::default()
        },
    );
    ExitCode::from(code)
}

#[cfg(test)]
mod tests {
    use super::*;

    const ORANGE: [u8; 3] = [230, 120, 30];

    #[test]
    fn the_orange_test_matches_its_boundaries() {
        assert!(is_orange(ORANGE));
        assert!(is_orange([141, 41, 0]));
        for edge in [
            [140, 100, 50],
            [200, 40, 50],
            [200, 200, 50],
            [200, 100, 120],
        ] {
            assert!(!is_orange(edge), "{edge:?} sits on an excluded edge");
        }
        assert!(
            !is_orange([160, 60, 130]),
            "blue at or above 120 is excluded"
        );
        assert!(
            !is_orange([141, 60, 111]),
            "red must lead blue by more than 30"
        );
        assert!(!is_orange([150, 150, 20]), "red must lead green");
        assert!(!is_orange([0, 0, 0]));
    }

    #[test]
    fn only_even_rows_and_columns_are_sampled() {
        let mut image = image::RgbImage::new(3, 3);
        for (x, y) in [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)] {
            image.put_pixel(x, y, image::Rgb(ORANGE));
        }
        assert_eq!(orange_count(&image), (0, 4));
        image.put_pixel(2, 2, image::Rgb(ORANGE));
        assert_eq!(orange_count(&image), (1, 4));
        assert_eq!(orange_ratio(&image), 0.25);
        assert_eq!(orange_ratio(&image::RgbImage::new(0, 0)), 0.0);
    }

    fn scratch(label: &str) -> std::path::PathBuf {
        let dir =
            std::env::temp_dir().join(format!("fragr-tip-gate-{label}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// A 10 by 10 still whose top `rows` rows are orange, stored as RGBA like
    /// the captured PNGs, with transparent orange so alpha must be ignored.
    fn write_still(dir: &Path, name: &str, rows: u32) {
        let image = image::RgbaImage::from_fn(10, 10, |_, y| {
            if y < rows {
                image::Rgba([ORANGE[0], ORANGE[1], ORANGE[2], 0])
            } else {
                image::Rgba([20, 20, 20, 255])
            }
        });
        image.save(dir.join(name)).unwrap();
    }

    #[test]
    fn dish_stills_pass_and_an_empty_hangar_fails() {
        let dir = scratch("verdicts");
        for (name, _) in FLOORS {
            write_still(&dir, name, 2);
        }
        let mut sink = Sink::default();
        assert_eq!(run(&[dir.display().to_string()], &mut sink), 0);
        let (out, err) = (sink.out, sink.err);
        assert!(err.is_empty(), "{err:?}");
        assert_eq!(
            out[0],
            "tip_capture gate: 20_jammer_dish_follow_16x9.png orange=0.2000 floor=0.0500"
        );
        assert_eq!(out[3], "tip_capture gate: PASS jammer orange footprint");

        write_still(&dir, FLOORS[1].0, 0);
        let mut sink = Sink::default();
        assert_eq!(run(&[dir.display().to_string()], &mut sink), 1);
        let (out, err) = (sink.out, sink.err);
        assert_eq!(
            err,
            ["tip_capture gate: FAIL 22_jammer_dish_overview_16x9.png empty hangar / no dish"]
        );
        assert!(!out.iter().any(|line| line.contains("PASS")));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn missing_or_unreadable_stills_fail_and_bad_usage_is_refused() {
        let dir = scratch("missing");
        write_still(&dir, FLOORS[0].0, 2);
        std::fs::write(dir.join(FLOORS[1].0), b"not a png").unwrap();
        let mut sink = Sink::default();
        assert_eq!(run(&[dir.display().to_string()], &mut sink), 1);
        let (out, err) = (sink.out, sink.err);
        assert!(err[0].starts_with("tip_capture gate: cannot read "));
        assert!(err[1].starts_with("tip_capture gate: missing "));
        assert_eq!(out.len(), 1, "only the readable still gets a verdict");
        std::fs::remove_dir_all(dir).unwrap();

        for args in [vec![], vec!["a".to_string(), "b".to_string()]] {
            // Echoing prints as it records; the kept lines are the same.
            let mut sink = Sink {
                echo: true,
                ..Sink::default()
            };
            assert_eq!(run(&args, &mut sink), 2);
            assert!(sink.out.is_empty());
            assert_eq!(sink.err, ["usage: gate-tip-jammer-orange OUT_DIR"]);
        }
    }
}
