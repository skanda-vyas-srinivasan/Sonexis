import Foundation

struct DSPConfiguration {
    var processingGain: Float
    var startupRampDuration: TimeInterval
    var shutdownRampDuration: TimeInterval
    var routeChangeRampDuration: TimeInterval

    static let productBaseline = DSPConfiguration(
        processingGain: 1.0,
        startupRampDuration: 0.40,
        shutdownRampDuration: 0.25,
        routeChangeRampDuration: 0.15
    )
}
