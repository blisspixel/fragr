# Graphics and auto settings

How fragr picks its graphics for your computer, what each setting costs and
how to change any of it. Everything here runs on your machine; nothing is
sent anywhere. The developer contract (how tiers are defined and measured, the
hardware matrix) is in [BENCHMARK.md](BENCHMARK.md#tiers-and-auto-settings).

## Auto settings in one paragraph

The first time fragr opens a window, a card says **Tuning graphics for this
computer**, about 90 seconds, with **Start now** and **Skip**. It starts by
itself after eight seconds. It plays a short local fight with ten bots on
Larak Lot, tries a few settings while that fight replays, and keeps the best
look that still holds your target frame rate in the slowest moments. Then it
shows one card that says what it chose and why. **Skip** (or Esc) uses a guess
from a small list of known graphics chips and says it was not measured. Run it
again any time from **Benchmark > Auto settings**. It never runs again by
itself; when your graphics hardware, driver, renderer or display changes, or a
new version of fragr draws differently, the main menu says so and offers
**Tune graphics again**.

## What the tuner does

1. **Reads this computer**: graphics adapter, vendor, driver and its version,
   graphics API, renderer, operating system, display server, the current
   screen's size and refresh rate, processor and memory. A Steam Deck, Apple
   silicon and the Compatibility renderer are recognised here.
2. **Guesses a start** from a small hardware list. Unknown hardware starts at
   Medium. The guess only picks where to begin; the measurement decides.
3. **Records a fight**: 20 seconds of ten bots. The local server keeps running
   while every candidate is measured, as it does in solo play, so the
   processor's share of a real match is in every frame. (The plain benchmark
   stops the server and measures drawing alone.)
4. **Warms up** each candidate until no shader has compiled for a second (at
   most six seconds), so a one-off compile is never scored.
5. **Measures** eight seconds per candidate with V-Sync and the frame cap off.
   A candidate passes when its **1% low** (the average of the slowest 1% of
   frames, as frames per second) is at least your target plus 10 percent and
   no frame took 50 ms or more. The 10 percent covers busier venues than the
   benchmark scene, heat and the noise of a short window.
6. **Searches the quality tiers** up from the guess while they pass and down
   while they fail. If the graphics chip finishes a frame with lots of time to
   spare, it tries two tiers up at once.
7. **Finds the bottleneck**. If the slowest frames spent little of their time
   on the graphics chip, the processor (or the display path) is the limit; the
   tuner stops lowering graphics, because that would not help, and says so.
8. **Searches 3D resolution** within the tier it found. With world pixels off,
   a computer that holds Ultra tries 125 and 150 percent (supersampling). With
   world pixels on, nothing changes there: see below.
9. **The floor**. If even Potato falls short: with world pixels off it tries
   83, 67 and 50 percent 3D resolution, then a 720-line render where that is
   fewer lines; with world pixels on it measures the next coarser pixel size
   and only suggests it. If nothing holds and the processor is not the limit,
   it offers the **Compatibility renderer** (see Old or weak graphics chips).
10. **Confirms** the choice with a 12-second window. Two windows more than 10
    percent apart are labelled variable and the lower one counts. On a laptop
    on battery or integrated graphics, a choice whose lower figure no longer
    passes drops one tier; anywhere, a choice that falls below the target
    itself drops one tier.
11. **Saves and explains** the choice, its figures, the fingerprint, the date
    and the build's rendering-cost revision, then shows the card.

A figure within 5 percent of the line gets one more window (at most two per
run). The whole run takes about 90 seconds, a little more on a weak machine.

The result card reads like this:

> Auto settings: High, Fine pixels, 60 fps target.
> Measured 1% low 84 fps (Medium 112, Ultra 51).
> Limited by the graphics chip. Ultra would drop below 60 in busy fights.
> Radeon 780M Graphics, Forward+ vulkan, 1920 x 1080, 120 Hz. Tuned 2026-11-01.

Below it, every candidate it tried with its 1% low and whether it held the
line, the frame-time timeline, and **Details**. Crackpot's benchmark
certificate sings once here too, as after a benchmark. **Copy summary** puts
the card and the figures on the clipboard for a bug report. The JSON and CSV
are saved as `autotune-*.json` and `.csv` beside the benchmark results.

## Your target

60 frames a second by default. Settings > Graphics > **Target frame rate**
offers 60, 90, 120, 144 and **Display refresh** (whatever the current screen
reports). The tuner measures uncapped, so a 144 target on a 60 Hz panel is
allowed (it lowers latency) but you will only see 60 new frames a second.

If V-Sync is off and your display is faster than the target, the card suggests
a frame cap equal to the target on the Display page, which keeps the pace even.
With a variable refresh (FreeSync, G-Sync) display, cap a little under the
refresh (about `r - r*r/3600`: 138 at 144 Hz) and leave V-Sync on in the
driver.

## Tiers

Five tiers, Settings > Graphics > **Quality**. Low, Medium and High are exactly
the Performance, Balanced and High presets of earlier builds.

| Tier | What you see | Renderer |
|---|---|---|
| Potato | No edge smoothing, small hard-edged shadows, light fixtures cast no shadows and fade out from 24 m, a quarter of the marks and effects | either |
| Low | No edge smoothing, small shadow maps, light fixtures cast no shadows, half the marks and effects | either |
| Medium | 2x edge smoothing (MSAA), normal shadows, light fixtures cast shadows, light contact shading (SSAO), lamp glow | either |
| High | 4x MSAA, large shadow maps, stronger contact shading | either |
| Ultra | High plus soft shadow edges, high-quality contact shading, bounce light (SSIL), lamp shadows carried further, marks that last longer | Forward+ only; draws as High on Compatibility |

Every tier keeps the same room: the same ambient light, fog colour and density,
faction colours, signs and silhouettes. A tier adds or removes depth (shadows,
contact shading, bounce light), never the look of the place. Volumetric fog and
screen-space reflections are wired into Ultra for venues that opt in; none does
yet, because each needs its own look pass before it ships.

What each costs on the reference machine is in the measured table in
[BENCHMARK.md](BENCHMARK.md#tier-costs); costs on your machine are what the
tuner measures.

## Each option

| Option | What it changes | Cost | Renderer |
|---|---|---|---|
| Quality | The tier above | the largest single cost | Ultra needs Forward+ |
| Auto settings | On: the tuner and the in-match adjustments may move any option you have not set by hand | none | both |
| Target frame rate | The 1% low auto settings hold | none | both |
| 3D resolution | The 3D scene renders at 50 to 150 percent of the output; menus and the HUD stay sharp. Only with world pixels off | roughly with the pixel count | both; above 100 is supersampling |
| Upscaling | How a lower 3D resolution is scaled up: Standard, FSR 1 or FSR 2 | FSR 2 replaces MSAA | FSR needs Forward+ |
| World pixels | The pixel look: see below | Fine costs less than native | both |
| Dither | An ordered dither in value steps; every hue is kept | tiny | both |
| In-match adjustments | The safety valve, below | none | both |
| Resolution (Display) | Window size when windowed; 3D render height in fullscreen | with the pixel count | both |
| Frame cap, V-Sync (Display) | Pacing; the tuner turns both off while measuring and restores them | none | Compatibility has only plain V-Sync |

## World pixels and dither

World pixels are part of fragr's look, not a performance knob. The 3D world is
drawn on a coarse grid and scaled up by a whole number with nearest filtering,
so every world pixel is the same size and the HUD stays native. **Fine** aims
at 540 world lines: 2x at 1080p, native at 720p and on the Steam Deck's 800p,
3x (480 lines) at 1440p and 4x (540 lines) at 4K. **Medium** aims at 360 lines,
**Chunky** at 270. The tuner never changes your world pixels or the dither,
never splits the grid with a fractional 3D resolution, and never changes the
grid mid-match. If a coarser grid would hold your target where nothing else
does, the card says so and leaves the choice to you.

## Your choices stick

Change any graphics option by hand and save, and that option is **pinned**:
the Graphics page says **Custom: auto settings work around your choices** and
names them. The tuner and the in-match adjustments only move options you have
not pinned. Choosing a tier by hand pins the tier; the tuner then only tunes
3D resolution, if you have not pinned that too. **Reset to auto** clears every
pin and puts the last tune's choice back. Turning **Auto settings** off leaves
everything exactly as you set it. Settings stay on this computer.

A settings file from a build before tiers stored the old three-preset index;
it is not converted. Its quality goes back to auto settings and the Graphics
page says so once.

## In-match adjustments

Real fights can be heavier than the benchmark scene, and laptops slow down
when hot. While you play, fragr scores the frame rate in 30-second windows.
After three windows in a row below your target it lowers one costly effect,
only at a safe moment (your death, a respawn, a checkpoint or the end of a
round), never mid-fight, and says so in one line in the feed, for example
"Graphics lowered: contact shading lowered to hold 60." It lowers in this
order, least visible first: volumetric fog, bounce light, reflections, contact
shading, light-fixture shadow distance, the marks and effects budget, edge
smoothing. It never touches world pixels, the output resolution, the renderer
or anything you pinned, and never raises anything back mid-match. Each step
lasts until you quit or tune again. Turn it off with **In-match adjustments**
on the Graphics page; it is also off whenever you pinned the tier.

After fifteen minutes of play on a tune where most windows fell short, the
main menu offers to tune again.

## Laptops, battery, monitors and high refresh

- **Battery.** On Linux (including the Steam Deck) fragr reads whether you are
  plugged in; a tune on battery says so and suggests tuning again on power.
  Windows and macOS do not tell a game, so the card does not mention it there.
- **Heat.** A 90-second tune on a cool laptop can overestimate. The 10 percent
  headroom, the confirm window and the in-match adjustments cover short drift.
- **Several monitors.** A tune remembers the screen it ran on. Move the window
  to another display and the Graphics page and Benchmark page say **Tuned for
  another display**; tune again there if you want.
- **Hybrid laptops** (Intel plus NVIDIA or AMD): the card names the adapter it
  measured. If that is the integrated chip, set fragr to the discrete GPU in
  the driver's control panel or in Windows Graphics settings, or start with
  `--gpu-index 1`.

## Steam Deck

fragr runs natively on SteamOS through Vulkan; Proton is not needed.

- **Default: 40 fps at 40 Hz.** In the Quick Access menu, set Refresh Rate to
  40 Hz. Every frame is new, motion is steady, and battery life is close to
  30 fps. The tuner aims at 40 with headroom (a 1% low of 44 or more) on the
  Deck's settings, caps at 40 and turns V-Sync on. Ultra is never chosen.
- **60 fps** is chosen on AC power when the Deck measured a 1% low of 66 or
  more, or whenever you pick 60 as the target. On battery the default stays 40.
- **60 Hz panel.** If the panel is at 60 Hz and 60 does not hold, fragr caps
  at 40 and the card says: "Set Refresh Rate to 40 Hz in the Quick Access menu
  for steady motion." 40 fps on a 60 Hz panel judders.
- **Deck OLED at 90 Hz**: 45 fps, an even half of the refresh.
- The Quick Access frame limiter and TDP limit override the game. Tune with
  them off, or the card measures what they allow.
- **World pixels on the Deck.** Fine renders natively at 800p; Medium renders
  640x400. Both are art choices; the tuner leaves them to you.

Not yet verified on a real Deck: how the game recognises it (the adapter name
and the `SteamDeck` variable), whether the engine reports the 40 Hz mode as
40, how the Quick Access limiter combines with the game's cap, and suspend in
the middle of a match. The Deck targets above are design targets until a Deck
row appears in the hardware matrix.

## Old or weak graphics chips

fragr's default renderer is **Forward+** (Vulkan on Windows and Linux, Metal on
Apple silicon). Graphics chips without Vulkan 1.0, Direct3D 12 or Metal 3 get
the **Compatibility** renderer (OpenGL 3.3) automatically when Forward+ cannot
start. Compatibility draws every fragr shader, the pixel look and SSAO, but has
no FSR, no Ultra (no bounce light, volumetric fog or reflections), no light
fixture shadows in fragr (a stability choice), plainer glow, and only on or off
V-Sync.

When even Potato falls short and the graphics chip is the limit, the result
card offers **Try Compatibility**. The game restarts in Compatibility, tunes
again and keeps Compatibility only if it measured faster than Forward+ did;
otherwise the next start goes back to Forward+ and the card says so. The choice
lives in `renderer_override.cfg` in fragr's user folder (Linux
`~/.local/share/godot/app_userdata/fragr/`, Windows
`%APPDATA%\Godot\app_userdata\fragr\`, macOS
`~/Library/Application Support/Godot/app_userdata/fragr/`). If the game will
not start after a renderer change, delete that file, or start it with
`--rendering-method forward_plus` (or `gl_compatibility`). `--rendering-driver`
picks the API (`vulkan`, `d3d12`, `opengl3`) and `--gpu-index` the adapter.

## Driver tips

- **Control panel overrides** (forced FXAA, sharpening, image scaling, forced
  anisotropic filtering) change the pixel look and are not seen by the game.
  Leave them at "application controlled".
- **Linux**: native Wayland paces frames more evenly than X11 (XWayland) on the
  machines measured so far. Mesa RADV (AMD) and ANV (Intel) are the expected
  Vulkan drivers.
- **macOS on Intel**: Vulkan through MoltenVK; GPU timings there are less
  reliable, so the bottleneck line may say less.

## Reporting a result

Run **Benchmark > Auto settings**, then **Copy summary**, and paste it into a
GitHub issue with your graphics adapter, driver and operating system. The
summary already names the adapter, renderer, driver and settings. Results are
only compared with others whose compatibility keys match (same build, display
server, renderer, adapter, output size and settings).
