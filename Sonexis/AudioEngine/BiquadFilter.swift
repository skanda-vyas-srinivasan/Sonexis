import Accelerate
import Foundation

// MARK: - Bass Boost Biquad

struct BiquadState {
    var x1: Float = 0
    var x2: Float = 0
    var y1: Float = 0
    var y2: Float = 0
}

struct AllPassState {
    var x1: Float = 0
    var y1: Float = 0
}

struct BiquadCoefficients {
    var b0: Float = 1
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0

    static func lowShelf(sampleRate: Double, frequency: Double, gainDb: Double, q: Double) -> BiquadCoefficients {
        let a = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let alpha = sinw0 / (2.0 * q)
        let sqrtA = sqrt(a)

        let b0 =    a * ((a + 1.0) - (a - 1.0) * cosw0 + 2.0 * sqrtA * alpha)
        let b1 =  2.0 * a * ((a - 1.0) - (a + 1.0) * cosw0)
        let b2 =    a * ((a + 1.0) - (a - 1.0) * cosw0 - 2.0 * sqrtA * alpha)
        let a0 =        (a + 1.0) + (a - 1.0) * cosw0 + 2.0 * sqrtA * alpha
        let a1 =   -2.0 * ((a - 1.0) + (a + 1.0) * cosw0)
        let a2 =        (a + 1.0) + (a - 1.0) * cosw0 - 2.0 * sqrtA * alpha

        return BiquadCoefficients(
            b0: Float(b0 / a0),
            b1: Float(b1 / a0),
            b2: Float(b2 / a0),
            a1: Float(a1 / a0),
            a2: Float(a2 / a0)
        )
    }

    static func highShelf(sampleRate: Double, frequency: Double, gainDb: Double, q: Double) -> BiquadCoefficients {
        let a = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let alpha = sinw0 / (2.0 * q)
        let sqrtA = sqrt(a)

        let b0 =    a * ((a + 1.0) + (a - 1.0) * cosw0 + 2.0 * sqrtA * alpha)
        let b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cosw0)
        let b2 =    a * ((a + 1.0) + (a - 1.0) * cosw0 - 2.0 * sqrtA * alpha)
        let a0 =        (a + 1.0) - (a - 1.0) * cosw0 + 2.0 * sqrtA * alpha
        let a1 =    2.0 * ((a - 1.0) - (a + 1.0) * cosw0)
        let a2 =        (a + 1.0) - (a - 1.0) * cosw0 - 2.0 * sqrtA * alpha

        return BiquadCoefficients(
            b0: Float(b0 / a0),
            b1: Float(b1 / a0),
            b2: Float(b2 / a0),
            a1: Float(a1 / a0),
            a2: Float(a2 / a0)
        )
    }

    static func peakingEQ(sampleRate: Double, frequency: Double, gainDb: Double, q: Double) -> BiquadCoefficients {
        let a = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let alpha = sinw0 / (2.0 * q)

        let b0 =  1.0 + alpha * a
        let b1 = -2.0 * cosw0
        let b2 =  1.0 - alpha * a
        let a0 =  1.0 + alpha / a
        let a1 = -2.0 * cosw0
        let a2 =  1.0 - alpha / a

        return BiquadCoefficients(
            b0: Float(b0 / a0),
            b1: Float(b1 / a0),
            b2: Float(b2 / a0),
            a1: Float(a1 / a0),
            a2: Float(a2 / a0)
        )
    }

    func process(x: Float, state: inout BiquadState) -> Float {
        let y = b0 * x + b1 * state.x1 + b2 * state.x2 - a1 * state.y1 - a2 * state.y2
        state.x2 = state.x1
        state.x1 = x
        state.y2 = state.y1
        state.y1 = y
        return y
    }

    /// Process entire buffer using vDSP_biquad (vectorized, ~3x faster)
    /// - Parameters:
    ///   - input: Input samples for one channel
    ///   - output: Output buffer (will be overwritten)
    ///   - delay: vDSP delay state, must have 4 elements, persists between calls
    func processBuffer(_ input: [Float], output: inout [Float], delay: inout [Float], frameLength: Int? = nil) {
        let sampleCount = min(frameLength ?? input.count, input.count)
        guard sampleCount > 0 else { return }

        // vDSP_biquad expects the normalized RBJ coefficient convention used here.
        let coefficients: [Double] = [Double(b0), Double(b1), Double(b2), Double(a1), Double(a2)]

        guard let setup = vDSP_biquad_CreateSetup(coefficients, 1) else { return }
        defer { vDSP_biquad_DestroySetup(setup) }

        // Ensure output buffer is sized correctly
        if output.count < sampleCount {
            output = [Float](repeating: 0, count: sampleCount)
        }

        // Ensure delay buffer is sized correctly (4 elements for single section)
        if delay.count < 4 {
            delay = [Float](repeating: 0, count: 4)
        }

        vDSP_biquad(setup, &delay, input, 1, &output, 1, vDSP_Length(sampleCount))
    }
}
