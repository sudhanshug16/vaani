import Foundation

/// Per-recording, streaming gain control for mono 16 kHz PCM16.
/// Does not alter device gain or retain audio. Call on the serial capture queue.
public struct InputGainControl {
    private var power = 0.0
    private var gain = 1.0
    private var limiter = 1.0
    private var speechHold = 0
    private let powerRate = 1 - exp(-1.0 / (16000 * 0.050))
    private let boostRate = 1 - exp(-1.0 / (16000 * 0.200))
    private let reduceRate = 1 - exp(-1.0 / (16000 * 0.005))
    private let releaseRate = 1 - exp(-1.0 / (16000 * 0.100))

    public init() {}

    /// Mutates only the supplied frames and returns their normalized RMS level.
    @discardableResult
    public mutating func process(_ samples: UnsafeMutableBufferPointer<Int16>, speechProbability: Float = 1) -> Float {
        guard !samples.isEmpty else { return 0 }
        // RNNoise speech confidence prevents gain from chasing residual noise.
        // Hold through brief consonants/pauses instead of modulating every frame.
        var outputPower = 0.0
        for index in samples.indices {
            if speechProbability >= 0.6 { speechHold = 4800 }
            let input = Double(samples[index]) / 32768
            power += powerRate * (input * input - power)
            let rms = sqrt(max(0, power))
            // Target -22 dBFS RMS, capped at +12 dB. Below -50 dBFS,
            // return toward unity rather than chasing silence/background hiss.
            let desired = rms >= 0.0031623 && speechHold > 0 ? min(4, 0.0794328 / rms) : 1
            // Returning from speech to unity must also be gradual.
            let rate = desired < gain && speechHold > 0 ? reduceRate : boostRate
            gain += rate * (desired - gain)
            speechHold = max(0, speechHold - 1)
            let amplified = input * gain
            // Immediate peak protection with gradual recovery. This also handles
            // a loud sound arriving while quiet speech has raised the gain.
            let ceilingGain = abs(amplified) > 0.95 ? 0.95 / abs(amplified) : 1
            if ceilingGain < limiter { limiter = ceilingGain }
            else { limiter += releaseRate * (ceilingGain - limiter) }
            let output = min(0.95, max(-0.95, amplified * limiter))
            samples[index] = Int16((output * 32768).rounded())
            outputPower += output * output
        }
        return Float(sqrt(outputPower / Double(samples.count)))
    }
}
