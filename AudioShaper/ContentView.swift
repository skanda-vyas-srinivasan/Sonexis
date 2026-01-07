import SwiftUI

struct ContentView: View {
    @State private var audioEngine = AudioEngine()

    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 8) {
                Text("Audio Shaper")
                    .font(.system(size: 32, weight: .bold))

                Text("Real-time Audio Processing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            Spacer()

            // Status indicator
            VStack(spacing: 12) {
                Image(systemName: audioEngine.isRunning ? "waveform.circle.fill" : "waveform.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(audioEngine.isRunning ? .green : .secondary)

                Text(audioEngine.isRunning ? "Processing" : "Inactive")
                    .font(.headline)
                    .foregroundStyle(audioEngine.isRunning ? .primary : .secondary)
            }

            // Error message if any
            if let error = audioEngine.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // Control button
            Toggle(isOn: Binding(
                get: { audioEngine.isRunning },
                set: { enabled in
                    if enabled {
                        audioEngine.start()
                    } else {
                        audioEngine.stop()
                    }
                }
            )) {
                Text(audioEngine.isRunning ? "Stop Processing" : "Start Processing")
                    .frame(maxWidth: .infinity)
            }
            .toggleStyle(.button)
            .controlSize(.large)
            .tint(audioEngine.isRunning ? .red : .green)
            .padding(.horizontal, 40)

            // Device info
            if audioEngine.isRunning {
                VStack(spacing: 8) {
                    HStack {
                        Text("Input:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(audioEngine.inputDeviceName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Output:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(audioEngine.outputDeviceName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .padding()
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 40)
            }

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("Setup Instructions:")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("1. Install BlackHole 2ch")
                Text("2. Audio MIDI Setup → Create Multi-Output Device")
                Text("3. Multi-Output → Check BlackHole + Speakers")
                Text("4. System Settings → Sound → Output → Multi-Output")
                Text("5. Click 'Start Processing' above")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .frame(width: 500, height: 600)
        .background(.background)
    }
}

#Preview {
    ContentView()
}
