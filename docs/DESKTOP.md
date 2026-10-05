# Desktop packages

[Back to the README](../README.md) | [Release history](../CHANGELOG.md)

Tagged releases attach three archives and `SHA256SUMS.txt` on the
[releases page](https://github.com/blisspixel/fragr/releases):
`fragr-<tag>-windows-x86_64.zip`, `fragr-<tag>-linux-x86_64.zip`, and
`fragr-<tag>-macos-universal.zip`. Keep the extracted game and bundled
`fragr-server` together. Each package includes licenses for fragr, Godot,
fonts and linked Rust crates. The radio library makes the packages large.

| Platform | Start | First-open note |
|---|---|---|
| Windows | `fragr.exe` | The executable is unsigned; Windows may ask you to choose **More info > Run anyway**. |
| Linux x86_64 | `./fragr.x86_64` | Requires glibc 2.35 or newer. |
| macOS, Apple Silicon or Intel | Open `fragr.app` | The app is ad-hoc signed but not notarized. Use **Open Anyway** in System Settings, Privacy and Security after the first blocked open. |

On macOS you can also remove the downloaded-file quarantine flag from an
archive you trust with `xattr -dr com.apple.quarantine fragr.app`.

Single Player launches the bundled campaign server. Builds containing the
desktop Host controls offer **Multiplayer > Host** for Team Deathmatch or
5v5 Sabotage using the same bundled executable. The menu keeps the match
alive while you watch, leave a fighter seat or return to the menu. Use
**Stop server** to end it; closing the app also ends its owned match.
Older releases connect to a separately started server. Multiplayer Join and
arena practice can still use a dedicated server, usually on port 6767.
See [hosting](HOSTING.md) for LAN invitations and dedicated commands.

## Check an installation

The packaged client accepts `fragr.exe --headless -- --check-install` on
Windows, `./fragr.x86_64 --headless -- --check-install` on Linux, or
`fragr.app/Contents/MacOS/fragr --headless -- --check-install` on macOS.
It checks exported resources, finds the bundled server, reads its campaign run
preview and starts TDM then 5v5 Sabotage through the actual desktop Host path.
Each preset must supply strict readiness and a matching validated spectator map
and snapshot, then retire its owned native process after Stop. It prints PASS
or FAIL. The package workflow runs it after unpacking each archive. It is a headless check;
it does not establish a playable boot on every clean desktop. The
[release plan](plans/desktop-release.md) records the remaining platform
evidence.

The app was previously named `fragr Client`, which also named its Godot
settings folder. On the first launch under the current name, the game copies
old `settings.cfg` and service records only when the new folder has neither.

## Build an export from source

Install Godot 4.7.2-stable with matching export templates. From the
repository root:

```bash
cargo build -p fragr-server --release --locked
mkdir -p builds/windows builds/macos builds/linux
godot --headless --path client --export-release "Windows Desktop" ../builds/windows/fragr.exe
godot --headless --path client --export-release "macOS" ../builds/macos/fragr.zip
godot --headless --path client --export-release "Linux/X11" ../builds/linux/fragr.x86_64
```

These presets export the client only. Put the matching `fragr-server`
executable beside the Windows or Linux game. A macOS app looks for the server
inside `Contents/MacOS` and needs signing again after it is changed. A source
checkout also searches `target/release` and `target/debug`. The tag packaging
workflow assembles and smokes these parts together.

The game icon is baked from `tools/bake_icon.gd`:

```bash
godot --headless --path client --script ../tools/bake_icon.gd
```

The authoritative package process is
[`.github/workflows/release.yml`](../.github/workflows/release.yml). The
[playing guide](PLAYING.md) covers controls, campaign saves and settings.
