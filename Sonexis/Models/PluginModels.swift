import Foundation

struct PluginDescriptor: Identifiable, Hashable {
    let id: String
    let format: PluginFormat
    let identifier: String
    let name: String
    let vendor: String
    let componentType: UInt32?
    let componentSubType: UInt32?
    let componentManufacturer: UInt32?
    let hasCustomView: Bool?
    let location: URL?

    init(
        format: PluginFormat,
        identifier: String,
        name: String,
        vendor: String,
        componentType: UInt32? = nil,
        componentSubType: UInt32? = nil,
        componentManufacturer: UInt32? = nil,
        hasCustomView: Bool? = nil,
        location: URL? = nil
    ) {
        self.format = format
        self.identifier = identifier
        self.name = name
        self.vendor = vendor
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
        self.hasCustomView = hasCustomView
        self.location = location
        self.id = "\(format.rawValue)|\(identifier)"
    }

    func toReference(stateData: Data? = nil) -> PluginReference {
        PluginReference(
            format: format,
            identifier: identifier,
            name: name,
            vendor: vendor,
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            hasCustomView: hasCustomView,
            stateData: stateData
        )
    }
}

struct PluginParameter: Identifiable, Hashable {
    let id: String
    let name: String
    var value: Double
    let minValue: Double
    let maxValue: Double
    let unitName: String?
    let groupName: String?
    let isReadOnly: Bool

    init(
        id: String,
        name: String,
        value: Double,
        minValue: Double,
        maxValue: Double,
        unitName: String? = nil,
        groupName: String? = nil,
        isReadOnly: Bool = false
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.unitName = unitName
        self.groupName = groupName
        self.isReadOnly = isReadOnly
    }
}
