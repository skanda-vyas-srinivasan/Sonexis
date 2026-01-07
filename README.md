# Audio Shaper

A real-time audio processing app for macOS that lets you apply creative effects to all system audio. Play Spotify, YouTube, or any app and hear it transformed through customizable effect chains.

## Features

- **Real-time Processing**: Process all system audio with minimal latency
- **Effect Blocks**: Bass boost, clarity enhancement, reverb, compression, and more
- **Three Modes**:
  - Preset Mode: Simple one-click presets (coming soon)
  - Beginner Block Mode: Drag-and-drop effect blocks (coming soon)
  - Advanced Mode: Full node-graph editing (coming soon)
- **Safety Built-in**: Automatic gain compensation and master limiter prevent distortion

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later
- BlackHole virtual audio device

## Setup Instructions

### 1. Install BlackHole

BlackHole is a free, open-source virtual audio device that acts as a "cable" to route audio into the app.

1. Download BlackHole 2ch from: https://github.com/ExistentialAudio/BlackHole/releases
2. Install the package
3. Open **Audio MIDI Setup** (Applications > Utilities > Audio MIDI Setup)

### 2. Create Multi-Output Device

1. In Audio MIDI Setup, click the **+** button at the bottom left
2. Select **Create Multi-Output Device**
3. Check **BOTH**:
   - ✅ **BlackHole 2ch** - checked
   - ✅ **Your speakers (Built-in Output or headphones)** - checked
4. Rename it to "Multi-Output Device" (optional but helpful)

### 3. Set System Output

1. Open **System Settings** > **Sound**
2. In the **Output** tab, select **Multi-Output Device**

Now system audio goes to both BlackHole (where app reads it) and speakers (where you hear it)!

### 4. Configure Audio Shaper

1. Open Audio Shaper
2. The app should detect BlackHole as the input source automatically
3. Click **Start Processing**
4. Play some music and verify you hear it (passthrough mode for now)

## Building the Project

### Open in Xcode

```bash
cd AudioShaper
open AudioShaper.xcodeproj
```

### Build and Run

1. Select the **AudioShaper** scheme
2. Choose **My Mac** as the destination
3. Press **⌘R** to build and run

### Troubleshooting Build Issues

**Error: "No such module 'Observation'"**
- Make sure deployment target is set to macOS 13.0 or later
- Check that Swift language version is 5.0 or later

**Error: "Microphone permission denied"**
- Grant microphone access in System Settings > Privacy & Security > Microphone
- Check that Info.plist includes `NSMicrophoneUsageDescription`

**Audio not flowing**
- Verify BlackHole is installed: Look for it in Audio MIDI Setup
- Verify Multi-Output Device is selected as system output
- Check that Multi-Output includes both BlackHole and your speakers
- Restart the app after changing audio devices

## Project Structure

```
AudioShaper/
├── AudioShaperApp.swift        # App entry point
├── ContentView.swift            # Main UI
├── AudioEngine.swift            # Core Audio processing engine
├── Models.swift                 # Data models (effects, chains, presets)
├── Info.plist                   # App configuration
└── AudioShaper.entitlements     # Sandbox permissions
```

## Current Status (Phase 1 - Complete!)

✅ **Completed**:
- Project setup with Xcode
- Basic audio engine with passthrough
- **Intelligent device selection** (BlackHole → App → Real Speakers)
- SwiftUI interface with start/stop toggle
- Device info display (shows which devices are in use)
- Data models for effects and chains
- Microphone permissions configured
- Automatic BlackHole detection
- Prevents feedback loops and audio doubling

🚧 **Coming Next (Phase 2)**:
- Single effect implementation (bass boost with slider)
- Real-time parameter controls
- Multi-effect chain building
- Safety limiter

## How It Works

### Audio Flow

```
System Audio (Spotify, YouTube, etc.)
    ↓
Multi-Output Device (only BlackHole checked)
    ↓
BlackHole 2ch (virtual cable)
    ↓
Audio Shaper Input (automatically selects BlackHole)
    ↓
Effect Processing (passthrough for now)
    ↓
Safety Limiter (coming soon)
    ↓
Audio Shaper Output (automatically selects real speakers)
    ↓
Speakers/Headphones
```

**Key insight:** The app intelligently selects:
- **Input**: BlackHole 2ch (reads system audio)
- **Output**: Your actual speakers (NOT the Multi-Output Device)

This prevents feedback loops and audio doubling.

### Core Audio Architecture

The app uses **AVAudioEngine** from Core Audio:
- `engine.inputNode` captures audio from BlackHole
- Effects are `AVAudioUnit` nodes (EQ, reverb, etc.)
- Nodes connect in a graph: Input → Effect → Effect → Limiter → Output
- `engine.outputNode` sends processed audio to speakers

### Safety Systems

1. **Format Consistency**: All nodes use 44.1kHz, stereo, Float32 format
2. **Automatic Gain Compensation**: Prevents volume spikes when adding effects
3. **Master Limiter**: Hard ceiling at -0.3dBFS prevents distortion
4. **Configuration Change Handling**: Gracefully handles device switching

## Development Roadmap

**Phase 1**: ✅ Basic passthrough (current)
**Phase 2**: Single effect implementation
**Phase 3**: Multi-effect chains
**Phase 4**: Preset system
**Phase 5**: Beginner block mode UI
**Phase 6**: Save/load system
**Phase 7**: Advanced mode (parallel routing)
**Phase 8**: Polish and optimization

## License

This is a personal project. Code is provided as-is for educational purposes.

## Credits

- Built with Swift and SwiftUI
- Uses Apple's Core Audio framework (AVAudioEngine)
- BlackHole virtual audio device by Existential Audio
