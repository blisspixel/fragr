# Default mix and startup artwork

Status: implemented in #201, 2026-09-20. Spend: $0.

Gunfire overpowers the radio at default settings. Effects start at full gain,
while the music preference and playing-state attenuation compound. The engine
boot splash also still uses the old ON AIR artwork before any test scene loads.

Lower the default effects preference to 0.5 and bring playing radio from -12 to
-8 dB. Keep music at 0.7, preserve explicitly saved preferences, and retain
temporary announcement ducking. These are mix changes through `settings.gd` and
`radio.gd`, not new sounds or changes to authoritative combat. Check the actual
bus levels, saved preferences, reset behavior and existing radio state table.
Measure a representative shot/music mix; do not infer listening approval from
decoding or gain arithmetic alone.

Rebuild `client/assets/ui/boot_splash.png` from the approved
`docs/fragr-logo-refined.png`, with no invented branding or scene delay. Keep the
complete composition at smaller window sizes and nearest filtering. Verify the
installed engine's splash settings against current primary documentation, inspect
the rendered startup and refresh the published tour. No protocol, dependency,
generation spend or gameplay changes.

Acceptance: the default mix gives music more room, existing choices survive a
load/save, the old splash no longer appears, client verification passes, and
inspected captures and remaining listening limitations are recorded here.

## Implemented evidence

Fresh effects now use 0.5 gain, music remains 0.7, and playing radio uses -8 dB.
This changes the effects/music gain relationship by about 10 dB in favor of
music. Settings tests prove actual bus values, preservation of both custom and
previous full-volume preferences, and reset behavior. Radio tests preserve the
announcement duck and station-specific exemptions.

Source measurements with FFmpeg 9.0.1, first 15 seconds or whole shorter clip:

| Asset | Mean dBFS | Peak dBFS |
|---|---:|---:|
| Generic shot | -25.7 | -10.6 |
| Flechette | -21.4 | -1.0 |
| Scatter | -15.1 | 0.0 |
| Rail | -7.2 | 0.0 |
| LOCK IN, Frag for Frag Amen | -14.2 | -0.1 |

These are source-level measurements, not perceived loudness or an approved final
mix. Effects still differ substantially; the separate effects-refresh plan owns
cadence, identity and listening review. No sound files were replaced.

The splash bake preserves all 1672 by 941 approved source pixels. Godot 4.7.2's
installed property list confirms `stretch_mode=1` means Keep; the old `fullsize`
setting resolved to disabled stretching. The current
[project settings reference](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-application-boot-splash-stretch-mode)
also documents PNG, aspect-fit and nearest filtering. The bake and import pass;
the source has been visually inspected. An early desktop capture did not capture
the game and was discarded; it supplies no rendered startup evidence.

All 30 client harnesses pass (`.agents/stats-audio-godot-final.log`). The refreshed
23-state tour passes and its contact sheet, service record, settings and shot
sequence were inspected (`.agents/qa/stats-audio-release-20260920/`). It verifies
scene presentation after startup, not the fleeting engine splash itself. The
approved splash pixels and effective engine setting were verified separately.
