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

    var displayName: String {
        PluginDisplayName.userFacingName(
            rawName: name,
            vendor: vendor,
            componentManufacturer: componentManufacturer
        )
    }
}

extension PluginReference {
    var displayName: String {
        PluginDisplayName.userFacingName(
            rawName: name,
            vendor: vendor,
            componentManufacturer: componentManufacturer
        )
    }
}

enum PluginDisplayName {
    private static let appleManufacturer: UInt32 = 0x6170_706C

    static func userFacingName(rawName: String, vendor: String, componentManufacturer: UInt32?) -> String {
        guard isAppleAudioUnit(vendor: vendor, componentManufacturer: componentManufacturer) else {
            return rawName
        }

        let normalized = normalizedAppleName(rawName)
        let baseName = readableAppleName(from: normalized)
        return baseName.localizedCaseInsensitiveContains("(Apple)") ? baseName : "\(baseName) (Apple)"
    }

    private static func isAppleAudioUnit(vendor: String, componentManufacturer: UInt32?) -> Bool {
        componentManufacturer == appleManufacturer || vendor.localizedCaseInsensitiveContains("Apple")
    }

    private static func normalizedAppleName(_ rawName: String) -> String {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suffix = name.split(separator: ":").last {
            name = String(suffix).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for prefix in ["Apple ", "Apple: ", "com.apple.", "Audio Unit: "] {
            if name.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
                name.removeFirst(prefix.count)
                name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return name.replacingOccurrences(of: " ", with: "")
    }

    private static func readableAppleName(from normalized: String) -> String {
        var name = normalized
        if name.hasPrefix("AU"), name.count > 2 {
            name.removeFirst(2)
        }
        if name == "NewPitch" {
            return "Pitch"
        }
        if name == "NewTimePitch" {
            return "Time Pitch"
        }
        if name == "NBandEQ" {
            return "N-Band EQ"
        }
        name = name.replacingOccurrences(
            of: #"(?<=[a-z0-9])(?=[A-Z])"#,
            with: " ",
            options: .regularExpression
        )
        name = name.replacingOccurrences(of: "E Q", with: "EQ")
        name = name.replacingOccurrences(of: "A A C", with: "AAC")
        name = name.replacingOccurrences(of: "D L S", with: "DLS")
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Audio Effect" : trimmed
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
