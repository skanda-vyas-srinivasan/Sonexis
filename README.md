# Laya

Real-time audio effects for your entire Mac.

Laya captures all system audio, routes it through a visual effect chain you design, and outputs the processed sound to your speakers or headphones. One button handles all the routing automatically.

---

## What It Does

1. You build an effect chain by dragging effects onto a canvas
2. You press the power button
3. Laya reroutes your system audio through your effect chain
4. Everything you hear on your Mac now goes through your effects
5. Turn it off and your audio routing returns to normal

No manual audio configuration. No MIDI setup. Just press power.

---

## Effects

19 built-in effects:

| Effect | What it does |
|--------|--------------|
| **Bass Boost** | Adds power to low frequencies |
| **Clarity** | Brings out vocals and instruments |
| **Reverb** | Adds space and depth |
| **Soft Compression** | Evens out loud and quiet parts |
| **Stereo Widening** | Makes the soundstage feel wider |
| **Pitch** | Shift pitch up or down (±12 semitones) |
| **Pitch (Rubber Band)** | High-quality pitch shifting |
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

- macOS 13.0 or later
- BlackHole 2ch (virtual audio driver — installer included in app)

---

## Install

Download the `.pkg` from [Releases](https://github.com/skanda-vyas-srinivasan/Laya/releases), open it, done.

On first launch, Laya will prompt you to install BlackHole if it's not already installed.

---

## Build from Source

```bash
git clone https://github.com/skanda-vyas-srinivasan/Laya.git
cd Laya
open Laya.xcodeproj
```

Build with ⌘R.

---

## How It Works

Laya uses BlackHole as a virtual loopback:

```
System Audio → BlackHole → Laya (effects) → Your Speakers/Headphones
```

When you press power, Laya sets BlackHole as your system output, captures that audio, processes it through your effect chain, and sends it to your real output device. When you turn it off, your original audio routing is restored.

---

## Tech

- Swift / SwiftUI
- AVFoundation / CoreAudio
- Custom DSP (biquad filters, circular buffers, LFOs)
- RubberBand library for high-quality pitch shifting

---

## License

GPL-3.0
