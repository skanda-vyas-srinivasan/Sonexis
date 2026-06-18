# Sonexis

Real-time audio effects for your entire Mac.

Sonexis captures all system audio, routes it through a visual effect chain you design, and outputs the processed sound to your speakers or headphones. One button handles all the routing automatically.

---

## What It Does

1. You build an effect chain by dragging effects onto a canvas
2. You press the power button
3. Sonexis reroutes your system audio through your effect chain
4. Everything you hear on your Mac now goes through your effects
5. Turn it off and your audio routing returns to normal

No manual audio configuration. No MIDI setup. Just press power.

---

## Effects

18 built-in effects:

| Effect | What it does |
|--------|--------------|
| **Bass Boost** | Adds power to low frequencies |
| **Clarity** | Brings out vocals and instruments |
| **Reverb** | Adds space and depth |
| **Soft Compression** | Evens out loud and quiet parts |
| **Stereo Widening** | Makes the soundstage feel wider |
| **Pitch** | High-quality pitch shifting (±12 semitones) |
| **Simple EQ** | 3-band bass/mid/treble control |
| **10-Band EQ** | Fine control over 10 frequency bands |
| **De-Mud** | Cuts muddy mid-frequency buildup |
| **Delay** | Echoes and rhythmic repeats |
| **Distortion** | Warmth, grit, and harmonics |
| **Tremolo** | Pulsing volume modulation |
| **Chorus** | Thick, lush modulation |
| **Phaser** | Swirling, sweeping movement |
| **Flanger** | Jet-like sweeping effect |
| **Bitcrusher** | Lo-fi digital crunch |
| **Tape Saturation** | Warm analog-style saturation |
| **Resampling** | Pitch/speed shift via resampling |

---

## The Canvas

Build your effect chain visually:

- **Drag and drop** effects from the sidebar onto the canvas
- **Rearrange** by dragging effects to change processing order
- **Manual wiring** (Option+drag) for custom signal routing
- **Dual-mono mode** for independent left/right channel processing
- **Real-time visualization** shows audio flowing through your chain

Right-click any effect to edit parameters or remove it.

---

## Requirements

- macOS 14.4 or later
- BlackHole 2ch for the legacy virtual-device backend
- No virtual audio driver is required when the experimental Process Tap backend is enabled

---

## Install

Download the `.pkg` from [Releases](https://github.com/skanda-vyas-srinivasan/Sonexis/releases), open it, done.

On first launch, Sonexis will prompt you to install BlackHole if it's not already installed.

---

## Build from Source

```bash
git clone https://github.com/skanda-vyas-srinivasan/Sonexis.git
cd Sonexis
open Sonexis.xcodeproj
```

Build with ⌘R.

---

## How It Works

Sonexis has two system-audio backends.

The legacy backend uses BlackHole as a virtual loopback:

```
System Audio → BlackHole → Sonexis (effects) → Your Speakers/Headphones
```

When you press power, Sonexis sets BlackHole as your system output, captures that audio, processes it through your effect chain, and sends it to your real output device. When you turn it off, your original audio routing is restored.

The experimental backend uses macOS Process Taps:

```
System Audio → Core Audio Process Tap → Sonexis effect graph → Current macOS Default Output
```

On the `process-tap-backend` branch, Debug builds use the Process Tap backend by default so it can be tested directly from Xcode. To force the old BlackHole backend in Debug:

```bash
SONEXIS_USE_BLACKHOLE=1
```

Release builds keep the Process Tap backend opt-in:

```bash
SONEXIS_USE_PROCESS_TAP=1
```

Current state:

- No virtual audio driver is required.
- No manual output-device switching is required.
- System audio is captured with `AudioHardwareCreateProcessTap`.
- The original output path is muted while tapped, then processed audio is played through the current macOS default output.
- The captured signal is processed through Sonexis's existing visual effect graph.
- Process Tap playback follows the macOS default output device. The old in-app output picker applies to the BlackHole backend, not this backend yet.
- Manual listening and route-change tests are still required before treating this as production-ready.

Build and run the hidden Process Tap smoke test with:

```bash
Scripts/smoke-process-tap.sh
```

---

## Tech

- Swift / SwiftUI
- AVFoundation / CoreAudio
- Custom DSP (biquad filters, circular buffers, LFOs)
- RubberBand library for high-quality pitch shifting

---

## Acknowledgments

- [RubberBand](https://breakfastquay.com/rubberband/) - Audio time-stretching and pitch-shifting library (GPL-2.0)
- [BlackHole](https://existential.audio/blackhole/) - Virtual audio driver (GPL-3.0)

## License

GPL-3.0
