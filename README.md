# Sonexis

<p align="center">
  <img src="Branding/sonexis-mark.png" width="128" alt="Sonexis logo">
</p>

<p align="center">
  <strong>Shape your system audio.</strong>
</p>

Sonexis is a native macOS audio processor that captures system sound and applies effects in real time without requiring a virtual audio device.

Build visual effect chains with EQ, compression, reverb, modulation, pitch, saturation, and third-party Audio Unit plug-ins. Create independent chains for individual apps, use a default chain for everything else, save reusable presets, control processing from the menu bar, and record the processed output.

## Requirements

- macOS 14.4 or later
- Apple Silicon or Intel Mac
- Xcode 16 or later with the macOS 14.4 SDK or later
- Screen & System Audio Recording permission when running the app

## Build

Clone the repository and open `Sonexis.xcodeproj` in Xcode, or build from the command line:

```sh
git clone https://github.com/skanda-vyas-srinivasan/Sonexis.git
cd Sonexis
xcodebuild \
  -project Sonexis.xcodeproj \
  -scheme Sonexis \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The Rubber Band Library source needed for pitch shifting is vendored under `External/rubberband`; there are no submodules to initialize.

To run the app from Xcode, select the **Sonexis** scheme and the **My Mac** destination. macOS will request audio-capture permission on first use.

## Test

Most regression harnesses link against the current Debug app build, so build first. Then run the complete offline suite:

```sh
Scripts/test-all.sh
```

Individual checks live in `Scripts/test-*.sh`. Tests use temporary data and synthetic audio; they should not alter your Sonexis presets or workspace. Live-device, sleep/wake, signing, notarization, and installer acceptance remain manual checks.

## Repository map

```text
Sonexis/
├── Sonexis/                 App source
│   ├── AudioEngine/         Graph rendering, effects, plug-ins, and recording
│   ├── CanvasView/          Visual chain editor
│   ├── ContentView/         Screens, workspace chrome, and tutorials
│   ├── Models/              Persisted and runtime data models
│   ├── ProcessTapEngine/    Core Audio capture and output pipeline
│   └── SharedUI/            Shared presentation components
├── Tests/                   Standalone regression harnesses
├── Scripts/                 Build, test, audit, and packaging commands
├── docs/                    Architecture, roadmap, and release records
├── External/rubberband/     Vendored GPL pitch-shifting dependency
└── Sonexis.xcodeproj/       Xcode project
```

See [Architecture](docs/ARCHITECTURE.md) for the runtime data flow and guidance on where changes belong.

## Contributing

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), especially the real-time audio rules and verification expectations. For substantial behavior or UX changes, open an issue before investing in an implementation.

- Use the bug template for reproducible defects.
- Keep pull requests focused and explain user-visible behavior.
- Add regression coverage for fixes and DSP changes.
- Never allocate, block, log, or perform file/UI work on the audio callback.

Please also read the [Code of Conduct](CODE_OF_CONDUCT.md) and [Security Policy](SECURITY.md).

## Project status

Sonexis is actively maintained. The current source targets version 2.1.0. Release audit documents under `docs/` are retained as engineering history; they are not a substitute for current issue reports or test results.

## License

Sonexis is free software licensed under the [GNU General Public License, version 2 or later](LICENSE). The repository includes third-party code with its own notices under `External/`.

[Website](https://sonexis.ink)
