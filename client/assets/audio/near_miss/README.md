# Incoming pass-by candidates

Three short, original offline accents for resolved shots passing close to the
local view. These are development mix candidates, with listening acceptance
still open. They are separate from body impacts and do not represent measured
ballistics or a vacuum sound treatment.

Rebuild from the repository root with Godot 4.7.2-stable:

```text
godot --headless --path client --script ../tools/bake_near_miss_audio.gd
```

The bake uses fixed seeded noise between two one-pole low-pass responses,
a 4 ms attack and tapered release. Pellet, rifle and Rail have separate band
limits, seeds and lengths (105, 145 and 190 ms). Rail also has a quiet descending
tone. Output is mono signed 16-bit PCM at 48 kHz, with lossless imports. The
presenter reduces gain by 8 dB on Effects and bounds both radius and cadence.
The build does not contact a service, and runtime does not synthesize audio.

`test_incoming_combat_feedback.gd` checks the imported format, one-shot lengths,
non-silent energy, peak and DC limits, silent/tapered endpoints, distinct source
data, local ownership and bounded spatial voices. These establish file and
presentation contracts. Headphone and speaker quality require listening.
