import AppKit
import Foundation

protocol PluginInstance: AnyObject {
    var reference: PluginReference { get }
    var isReady: Bool { get }
    var displayName: String { get }
    var vendorName: String { get }

    func ensureFormat(sampleRate: Double, channelCount: Int)
    func process(buffer: inout [[Float]], frameLength: Int, sampleRate: Double, channelCount: Int)
    func editorView() -> NSView?
    func parameters() -> [PluginParameter]
    func setParameter(id: String, value: Double)
    func stateData() -> Data?
    func loadState(_ data: Data)
}

final class VST3PluginInstance: PluginInstance {
    let reference: PluginReference
    var isReady: Bool = false

    init(reference: PluginReference) {
        self.reference = reference
    }

    var displayName: String { reference.displayName }
    var vendorName: String { reference.vendor }

    func ensureFormat(sampleRate: Double, channelCount: Int) {
        // VST3 hosting requires the Steinberg SDK and is not wired yet.
    }

    func process(buffer: inout [[Float]], frameLength: Int, sampleRate: Double, channelCount: Int) {
        // No-op: VST3 hosting not configured.
    }

    func editorView() -> NSView? {
        nil
    }

    func parameters() -> [PluginParameter] {
        []
    }

    func setParameter(id: String, value: Double) {
        // No-op.
    }

    func stateData() -> Data? {
        nil
    }

    func loadState(_ data: Data) {
        // No-op.
    }
}
