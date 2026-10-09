# Capture window dimensions

Status: **implemented locally**, 2026-10-08. Spend: $0. Bounded capture controls
pass on the corrected helper. The later
[composition](presentation-stairs-composition-20261008.md) records the separately
reassessed official render and original-image review. [The receipt](capture-window-size-20261008.json) binds
actual images, source identities, process retirement and rejected attempts.

The second official tour requested 1280 by 720 but captured 2256 by 1363 in
four consecutive states: Rail impact, Scatter pellets, return to spectator and
spectator chase. Its strict size gate correctly failed. The original window
event is unknown. QaTour restored dimensions only for optional frame benchmarks,
which the standard tour does not request.

The capture tool now checks and restores dimensions before a shot strip, frozen
still or frame sample. After correction, two distinct draws must produce raw
images at the requested size. Settlement is bounded by two seconds or 32 draws.
Window mode, focus and visibility stay under desktop control. Minimized capture
reuses the existing [non-presenting draw pump](capture-draw-liveness-20261008.md).
The final raw PNG check remains strict; a resize during a shot strip fails
without repairing its sampled evidence.

An actual diagnosis rejected a preliminary metadata-based guard: with a
1920 by 1080 logical canvas, the raw image was 1280 by 720 while texture metadata
reported 854 by 480. At 960 by 540, metadata reported 480 by 270. The accepted
guard therefore checks the rendered Image. Both failed preliminary controls
remain retained.

| Actual control | Result |
| --- | --- |
| Normal, resized, minimized and paused captures | 16 assertions pass; unaltered HUD/world originals; minimized mode preserved |
| Minimized timed strip | 12 samples retained with actual timestamps; capture liveness only |
| Incompatible window minimum | Expected refusal within 32 draws, one expected error retained |
| Resize before Rail trigger | All 32 canonical states pass; 1280 by 720 stills; actual finite shot and expiry checks preserved |
| Resize after two Rail samples | Expected failure on frames 2-11; all 12 timestamps retained; later still recovery does not pass the attempt |

The complete private tour returned zero with clean logs. Its actual Rail shot
reduced the magazine from four rounds to three. The separate 15-state negative returned
one with exactly ten expected size errors. The normal strip sheet and first
full-size shot are retained; there is no full-size PNG for every strip frame.
All owned renderers and native processes retired.

These controls bind helper `04ac1289` and the existing package server `5c1f7984`.
They did not rebuild native code, import the project, publish screenshots or
change combat. They establish neither final art, frame rates, other-hardware
behavior. The later composition owns the official render's separate acceptance.
