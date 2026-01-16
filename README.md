# Laya

Real-time audio effects for macOS system sound.

Laya captures all audio playing on your Mac, runs it through a customizable effect chain, and outputs to your speakers or headphones. Just press power and it handles all the routing automatically.

## Features

- **19 audio effects** — Bass Boost, Clarity, Reverb, Compression, Stereo Widening, Pitch Shift, Rubber Band Pitch, Simple EQ, 10-Band EQ, De-Mud, Delay, Distortion, Tremolo, Chorus, Phaser, Flanger, Bitcrusher, Tape Saturation, Resampling
- **Drag-and-drop canvas** — Build your effect chain visually
- **Dual-mono mode** — Separate effect chains for left and right channels
- **Manual wiring** — Option+drag for custom signal routing
- **Presets** — Save and load your effect chains
- **Live signal flow** — See audio flowing through your chain in real time

## Requirements

- macOS 13.0 or later

## Getting Started

1. Open Laya
2. Follow the onboarding to install BlackHole (if needed)
3. Build your effect chain
4. Press power

When you turn it on, Laya automatically switches your system audio routing. When you turn it off, everything goes back to normal.

## Building from Source

```bash
git clone https://github.com/skanda-vyas-srinivasan/Laya.git
cd Laya
open Laya.xcodeproj
```

Build and run with ⌘R.

## License

MIT
