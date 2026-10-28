import Foundation

/// Time-based display envelope, independent of callback size. Audio is untouched.
public struct SpeechLevelMeter {
    private var value: Float = 0
    public init() {}
    public mutating func update(rms: Float, frames: Int) -> Float {
        guard frames > 0, rms.isFinite else { return value }
        let target = min(1, max(0, rms * 5))
        let seconds = Double(frames) / 16000
        let rate = Float(1 - exp(-seconds / (target > value ? 0.080 : 0.250)))
        value += rate * (target - value)
        return value
    }
}
