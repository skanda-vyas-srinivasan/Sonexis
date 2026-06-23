# Sonexis

Real-time audio effects for your entire Mac.

Sonexis captures system audio with macOS Process Taps, runs it through a visual effect chain you design, and outputs the processed sound to your current speakers or headphones.

---

## What It Does

1. You build an effect chain by dragging effects onto a canvas
2. You press the power button
3. Sonexis captures your system audio through a Process Tap
4. Everything you hear on your Mac now goes through your effects
5. Turn it off and normal system audio resumes

No virtual audio driver. No manual output-device switching. Just press power.

---

## Effects

20 built-in effects:

| Effect | What it does |
|--------|--------------|
| **Night Drive** | Dark, wide, bass-forward color for late-night listening |
| **Chrome Punch** | Adds impact, attack, and tight low-end body |
| **Midnight Glow** | Smooths harsh edges with warm, gentle loudness |
| **Afterglow** | Adds air, stereo shimmer, and a short spacious tail |
| **Bass Boost** | Adds power to low frequencies |
| **Clarity** | Brings out vocals and instruments |
| **Reverb** | Adds space and depth |
| **Stereo Widening** | Makes the soundstage feel wider |
| **Enhancer** | Adds clarity, warmth, and punch in one step |
| **Pitch (Rubber Band)** | High-quality pitch shifting (±12 semitones) |
| **Simple EQ** | 3-band bass/mid/treble control |
| **Delay** | Echoes and rhythmic repeats |
| **Amp** | Preamp drive and output gain |
| **Tremolo** | Pulsing volume modulation |
| **Auto Pan** | Constant-power left/right movement |
| **Chorus** | Thick, lush modulation |
| **Phaser** | Swirling, sweeping movement |
| **Flanger** | Jet-like sweeping effect |
| **Bitcrusher** | Lo-fi digital crunch |
| **Tape Saturation** | Warm analog-style saturation |

Older retired effect IDs remain decodable so existing presets do not crash, but they are not exposed as active built-in blocks.

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
- Audio capture permission
- No virtual audio driver required

---

## Install

Download the `.pkg` from [Releases](https://github.com/skanda-vyas-srinivasan/Sonexis/releases), open it, done.

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

Sonexis uses macOS Process Taps:

```
System Audio → Core Audio Process Tap → Sonexis effect graph → Current macOS Default Output
```

Current state:

- No virtual audio driver is required.
- No manual output-device switching is required.
- System audio is captured with `AudioHardwareCreateProcessTap`.
- The original output path is muted while tapped, then processed audio is played through the current macOS default output.
- The captured signal is processed through Sonexis's existing visual effect graph.
- Process Tap playback follows the macOS default output device.
- Route changes rebuild the Process Tap pipeline.
- Manual stress testing is still required before treating this as production-ready.

Build and run the developer Process Tap smoke test with:

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

## License

GPL-3.0
