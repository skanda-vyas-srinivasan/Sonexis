import Foundation

// MARK: - Preset

struct Preset: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let chain: EffectChain
    let exposedParameters: [ExposedParameter]

    struct ExposedParameter: Codable {
        let name: String // User-facing name like "Intensity"
        let min: Float
        let max: Float
        let defaultValue: Float
        let mappings: [ParameterMapping]
    }

    struct ParameterMapping: Codable {
        let blockId: UUID
        let parameterName: String
        let minValue: Float
        let maxValue: Float

        func mapValue(_ normalizedValue: Float) -> Float {
            // Maps input value to minValue-maxValue range
            let t = (normalizedValue - 0) / (100 - 0) // Normalize to 0-1
            return minValue + t * (maxValue - minValue)
        }
    }
}

