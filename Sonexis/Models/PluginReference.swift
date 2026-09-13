import Foundation

enum PluginFormat: String, Codable {
    case au
    case vst3
}

struct PluginReference: Codable, Equatable {
    var format: PluginFormat
    var identifier: String
    var name: String
    var vendor: String
    var componentType: UInt32?
    var componentSubType: UInt32?
    var componentManufacturer: UInt32?
    var hasCustomView: Bool?
    var stateData: Data?

    init(
        format: PluginFormat,
        identifier: String,
        name: String,
        vendor: String,
        componentType: UInt32? = nil,
        componentSubType: UInt32? = nil,
        componentManufacturer: UInt32? = nil,
        hasCustomView: Bool? = nil,
        stateData: Data? = nil
    ) {
        self.format = format
        self.identifier = identifier
        self.name = name
        self.vendor = vendor
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
        self.hasCustomView = hasCustomView
        self.stateData = stateData
    }
}
