# Desktop release packages

**Status:** in flight, 2026-09-24. Roadmap Phase 2.7, "desktop exports on tags".

## Goal

A player downloads one zip for Windows, Linux or macOS from a GitHub release,
unpacks it, and gets a game that can start the local campaign without a
checkout or a toolchain. Each zip holds the exported Godot client with a
matching `fragr-server` beside the game executable, where
`client/scripts/local_match.gd` already looks for it. The game has its own icon
instead of the Godot mark.

## Non-goals

- Code signing with a paid certificate, Apple notarization, installers, auto
  update, store builds, Linux AppImage or Flatpak, and ARM Windows or ARM Linux
  packages.
- Proving a package boots to a playable match on a clean desktop with a GPU.
  CI runners are headless; that evidence still needs a human on real hardware.
- Changing the wire, the server, or how multiplayer finds a host.

## What changes

- **Icon.** `tools/bake_icon.gd` (GDScript, run through Godot) draws the mark
  from the logo: a magenta ring, a bone inverted triangle and an ember eye,
  using `docs/palette.json`. The 16 px grid is placed by hand because a
  computed one-pixel circle breaks at the diagonals; the 32 px grid is computed.
  Bigger sizes are whole-number nearest-neighbour multiples. The bake writes
  `client/icon.svg` (the project icon, one rect per pixel run, 256 px display
  size), `client/icon.ico` (16, 32, 48, 64, 128 and 256 px PNG entries) and
  `client/icon.icns` (16 to 1024 px PNG entries), and fails unless the SVG
  rasterizes back to the 32 px grid. The Windows and macOS presets use the ICO
  and ICNS with nearest interpolation, and `windows_native_icon` sets the
  running window's icon on Windows.
- **macOS preset.** The universal macOS preset never exported before: Godot
  refuses universal or arm64 without ETC2/ASTC import. The project now enables
  it. No texture uses VRAM compression today, so nothing else is re-encoded.
- **Local server attach fix.** `LocalMatch.for_tree` added itself to the root
  during the boot menu's `_ready`, which Godot rejects when the boot menu is
  the main scene. The owner never entered the tree, so a launched game never
  polled its child: the saved-run preview stayed on "loading" and a campaign
  start never finished. It now attaches on the next frame and reuses the
  pending owner until then. Harness runs did not catch this because they load
  the boot menu after startup.
- **Install check.** `fragr --headless -- --check-install` boots the real main
  scene, resolves `fragr-server` through `LocalMatch`, asks it for a run
  preview, prints `fragr install check: PASS` or a failure line, and exits 0 or
  1. An exported build must find the server in its own directory.
  `client/scripts/test_install_check.gd` covers the pending owner, a missing
  server and a real answer.
- **Release workflow.** `.github/workflows/release.yml` runs on `v*` tags,
  manual dispatch, and pull requests that touch packaging files.
  - `server`: `fragr-server --release --locked` on ubuntu-22.04 (glibc 2.35
    floor), windows-2025, and macos-26 (aarch64 and x86_64 joined with `lipo`,
    x86_64 targeting macOS 10.13).
  - `client`: Godot 4.7.2-stable for Linux plus the official
    `Godot_v4.7.2-stable_export_templates.tpz`, both checked against the
    release's `SHA512-SUMS.txt`. Only `linux_release.x86_64`,
    `windows_release_x86_64.exe`, `windows_release_x86_64_console.exe`,
    `macos.zip` and `version.txt` are kept and cached. On a tag the preset
    versions are stamped from the tag. All three presets export with a clean log.
  - `package`: per platform on its own runner, place the server beside the
    game (inside `Contents/MacOS` for the app), add license files (fragr,
    both font OFLs, Godot's `LICENSE.txt` and `COPYRIGHT.txt`), zip, then
    unpack the zip into a fresh directory and smoke it: `fragr-server --help`,
    a 200 tick `--bench`, and the exported game's `--check-install` with an
    empty `FRAGR_RUN_DIR`. Windows also saves the executable's icon as evidence.
  - `publish` (tags only): attach the zips and `SHA256SUMS.txt` to the tag's
    release, creating a draft release if none exists yet.
- **macOS signing.** The app is ad-hoc signed after the server is placed inside
  it, because Apple Silicon will not run unsigned code and adding a file breaks
  the export's seal. It is not notarized, so Gatekeeper blocks the first open;
  the README gives the steps.

Action majors checked 2026-09-24 against each repository's releases:
`actions/checkout@v7`, `actions/upload-artifact@v7`,
`actions/download-artifact@v8`, `actions/cache@v6`, `Swatinem/rust-cache@v2`,
`dtolnay/rust-toolchain@stable`. Runner labels checked the same day against
`actions/runner-images`. Godot asset and template file names checked against
the 4.7.2-stable release and a local extraction of the template archive
(`version.txt` reads `4.7.2.stable`). Official templates are built with
`disable_path_overrides`, so `--script` is ignored in an exported game; that is
why the smoke uses a user argument handled by the boot menu.

## Verification

- `tools/godot_check.sh` and `tools/test_godot_check.sh` on Windows with Godot
  4.7.2-stable.
- Local exports on Windows of all three presets. The Windows executable,
  with `fragr-server.exe` copied beside it, passed `--check-install`, and
  without the server it failed with exit 1. The main scene run from the editor
  binary failed the same check before the attach fix (preview timed out) and
  passed after it.
- Icon previews under `.agents/icon/` (16, 32, 256 px, and the icon pulled out
  of the exported `fragr.exe`), inspected by eye.
- `actionlint` on both workflows.
- The release workflow on the pull request: results recorded below.

## Spend

$0. Local tools, public repository Actions minutes, and GitHub release storage.
No paid service is called.

## Success criteria

- A tag produces three zips and a checksum file on its release without manual
  steps.
- Each zip unpacks and its bundled server answers the exported game's install
  check on a hosted runner of that platform.
- The executable, the running window, and the macOS app use the fragr icon.
- The README says how to download, unpack and open each package, including
  the macOS Gatekeeper step, and what the packages do not yet prove.

## Open

- A clean-machine boot to Solo Scrap or the campaign on real Windows, Linux and
  macOS hardware (the 1.0 bar line) has not been recorded.
- Rust crate license notices for `fragr-server` are not bundled yet; the
  package carries fragr, font and Godot notices only.
- Windows SmartScreen will warn on the unsigned executable.

## Results

Local, 2026-09-24, Windows 11, Godot 4.7.2-stable: `tools/godot_check.sh`
PASS (including `test_install_check`), `tools/test_godot_check.sh` PASS,
`actionlint` clean. All three presets exported. The Windows executable with
`fragr-server.exe` beside it passed `--check-install`, and exited 1 without it.

Release workflow on [#233](https://github.com/blisspixel/fragr/pull/233),
[run 36015674280](https://github.com/blisspixel/fragr/actions/runs/36015674280),
all jobs green, `publish` skipped as intended for a pull request:

| Package | Zip | Server | Unpacked smoke on |
|---|---|---|---|
| windows-x86_64 | 621 MB | built on windows-2025 | windows-2025: `--help`, bench, install check PASS |
| linux-x86_64 | 611 MB | built on ubuntu-22.04 | ubuntu-24.04: `--help`, bench, install check PASS |
| macos-universal | 645 MB | `lipo`: x86_64 and arm64 | macos-26 (arm64): `codesign --verify --deep --strict` valid, `--help`, bench, install check PASS |

Each install check line named the server inside the unpacked package
directory (`Contents/MacOS/fragr-server` for the app) and reported `missing`
for the empty run directory. The icon pulled from the Linux-exported
`fragr.exe` on the Windows runner is the fragr mark. No tag or release was
created.
