import AppKit
import AVFoundation

final class ToneAppDelegate: NSObject, NSApplicationDelegate {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var phase = 0.0
    private var isPlaying = false
    private var button: NSButton!

    private var frequency: Double {
        Bundle.main.object(forInfoDictionaryKey: "ToneFrequency") as? Double ?? 440
    }

    private var amplitude: Double {
        Bundle.main.object(forInfoDictionaryKey: "ToneAmplitude") as? Double ?? 0.00005
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Test Tone"

        let label = NSTextField(labelWithString: "\(Int(frequency)) Hz")
        label.font = .monospacedDigitSystemFont(ofSize: 22, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: 40, y: 82, width: 220, height: 32)

        button = NSButton(title: "Play", target: self, action: #selector(toggle))
        button.bezelStyle = .rounded
        button.frame = NSRect(x: 95, y: 30, width: 110, height: 34)
        button.setAccessibilityLabel("Play test tone")

        let content = NSView(frame: window.contentView!.bounds)
        content.addSubview(label)
        content.addSubview(button)
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggle() {
        if isPlaying {
            engine.stop()
            source = nil
            isPlaying = false
            button.title = "Play"
            button.setAccessibilityLabel("Play test tone")
            return
        }

        let output = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = output.sampleRate
        let frequency = self.frequency
        let amplitude = self.amplitude
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let phaseStep = 2 * Double.pi * frequency / sampleRate
            for frame in 0..<Int(frameCount) {
                let sample = Float(sin(self.phase) * amplitude)
                self.phase += phaseStep
                if self.phase >= 2 * Double.pi { self.phase -= 2 * Double.pi }
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: output)
        do {
            try engine.start()
            isPlaying = true
            button.title = "Stop"
            button.setAccessibilityLabel("Stop test tone")
        } catch {
            button.title = "Audio failed"
        }
    }
}

let application = NSApplication.shared
let delegate = ToneAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
