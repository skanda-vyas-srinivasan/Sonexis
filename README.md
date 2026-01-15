# Laya

Laya is a macOS app that processes all system audio in real time. It listens to a virtual device (BlackHole), runs audio through an effect chain, then outputs to your speakers with automatic device selection to avoid feedback loops.

## What’s working now

- Real-time processing of all system audio
- Beginner mode drag-and-drop effect chain with live signal flow
- Preset save/apply (stored locally in Application Support)
- Output device picker to choose speakers/headphones
- Effects: Bass Boost, Pitch Effect (brightness/clarity boost), Clarity, De-Mud, Simple EQ, Soft Compression, Reverb, Stereo Widening, Delay, Distortion, Tremolo

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later
- BlackHole 2ch virtual audio device

## Setup (first time)

### 1. Install BlackHole

1. Download BlackHole 2ch: https://github.com/ExistentialAudio/BlackHole/releases
2. Install the package
3. Open **Audio MIDI Setup** (Applications > Utilities > Audio MIDI Setup)

### 2. Create a Multi-Output Device

1. In Audio MIDI Setup, click **+** (bottom left)
2. Select **Create Multi-Output Device**
3. Check both:
   - **BlackHole 2ch**
   - **Built-in Output** (or your headphones)
4. Optionally rename it to "Multi-Output Device"

### 3. Route system audio

1. Open **System Settings** > **Sound**
2. In **Output**, select **Multi-Output Device**

### 4. Run Laya

1. Launch the app
2. It should auto-select **BlackHole 2ch** as input and your speakers as output
3. Click **Start Processing**

## Build and run

```bash
cd Laya
open Laya.xcodeproj
```

In Xcode:

1. Select the **Laya** scheme (target name)
2. Choose **My Mac**
3. Press **⌘R**

## Using the app

- **Presets tab**: Save the current chain and reapply it later.
- **Beginner tab**: Drag effects from the palette into the chain, reorder them, and toggle settings per block.
- **Advanced tab**: Placeholder for the future node graph.

Preset files are stored at:

```
~/Library/Application Support/Laya/presets.json
```

## Troubleshooting

- **"No such module 'Observation'"**
  - Ensure the deployment target is macOS 13.0+
  - Ensure Swift language version is 5.0+

- **Microphone permission denied**
  - Grant access in **System Settings** > **Privacy & Security** > **Microphone**
  - Confirm `NSMicrophoneUsageDescription` exists in `Info.plist`

- **No audio / no processing**
  - Verify BlackHole is installed and visible in Audio MIDI Setup
  - Confirm Multi-Output includes both BlackHole and your speakers
  - Restart the app after changing audio devices

## Project layout

```
Laya/
├── LayaApp.swift               # App entry point
├── ContentView.swift           # Main UI
├── AudioEngine.swift           # Core audio processing engine
├── Models.swift                # Effect/chain data models
├── PresetManager.swift         # Preset persistence
├── Info.plist                  # App configuration
└── AudioShaper.entitlements    # Sandbox permissions
```

## License

Personal project; provided as-is for educational use.
