# Audio Shaper

Audio Shaper is a macOS app that processes all system audio in real time. It routes audio through a virtual device, runs it through an effect chain (currently passthrough), and outputs to your speakers with automatic device selection to avoid feedback loops.

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

### 4. Run Audio Shaper

1. Launch the app
2. It should auto-select **BlackHole 2ch** as input and your speakers as output
3. Click **Start Processing**

## Build and run

```bash
cd AudioShaper
open AudioShaper.xcodeproj
```

In Xcode:

1. Select the **AudioShaper** scheme
2. Choose **My Mac**
3. Press **⌘R**

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
AudioShaper/
├── AudioShaperApp.swift        # App entry point
├── ContentView.swift           # Main UI
├── AudioEngine.swift           # Core audio processing engine
├── Models.swift                # Effect/chain data models
├── Info.plist                  # App configuration
└── AudioShaper.entitlements    # Sandbox permissions
```

## Notes

- The app currently runs in passthrough mode; effect blocks are planned.
- Input auto-selects **BlackHole 2ch**, output auto-selects your real speakers to avoid feedback.

## License

Personal project; provided as-is for educational use.
