import XCTest
@testable import VaaniCore

final class InputGainControlTests: XCTestCase {
    func testNoiseConfidenceDoesNotRaiseGain() {
        var samples = tone(0.015)
        let original = samples
        var control = InputGainControl()
        samples.withUnsafeMutableBufferPointer { _ = control.process($0, speechProbability: 0) }
        XCTAssertEqual(samples, original)
    }
    private func tone(_ amplitude: Double, seconds: Int = 2) -> [Int16] {
        (0..<(16000 * seconds)).map { Int16((sin(Double($0) * 2 * .pi * 200 / 16000) * amplitude * 32767).rounded()) }
    }
    private func rms(_ samples: ArraySlice<Int16>) -> Double {
        sqrt(samples.reduce(0) { $0 + pow(Double($1) / 32768, 2) } / Double(samples.count))
    }
    func testQuietSpeechIsBoostedWithBoundedGain() {
        var samples = tone(0.015)
        let original = rms(samples.suffix(8000))
        var control = InputGainControl()
        samples.withUnsafeMutableBufferPointer { _ = control.process($0) }
        XCTAssertGreaterThan(rms(samples.suffix(8000)), original * 3.8)
        XCTAssertLessThan(rms(samples.suffix(8000)), original * 4.01)
    }
    func testLoudSpeechSettlesAtTarget() {
        var samples = tone(0.8)
        var control = InputGainControl()
        samples.withUnsafeMutableBufferPointer { _ = control.process($0) }
        XCTAssertEqual(rms(samples.suffix(8000)), 0.07943, accuracy: 0.005)
    }
    func testSilenceAndVeryLowNoiseAreNotBoosted() {
        var control = InputGainControl()
        var silence = [Int16](repeating: 0, count: 16000)
        let level = silence.withUnsafeMutableBufferPointer { control.process($0) }
        XCTAssertEqual(level, 0)
        XCTAssertTrue(silence.allSatisfy { $0 == 0 })
        var noise = tone(0.001)
        let original = noise
        noise.withUnsafeMutableBufferPointer { _ = control.process($0) }
        XCTAssertEqual(noise, original)
    }
    func testSuddenFullScaleAfterBoostNeverClips() {
        var control = InputGainControl()
        var quiet = tone(0.015)
        quiet.withUnsafeMutableBufferPointer { _ = control.process($0) }
        var loud: [Int16] = [.max, .min, .max, .min]
        loud.withUnsafeMutableBufferPointer { _ = control.process($0) }
        XCTAssertTrue(loud.allSatisfy { abs(Int($0)) <= 31130 })
        XCTAssertGreaterThan(loud[0], 0)
        XCTAssertLessThan(loud[1], 0)
    }
    func testChunkBoundariesDoNotChangeOutput() {
        var whole = tone(0.02, seconds: 1)
        var split = whole
        var first = InputGainControl(), second = InputGainControl()
        whole.withUnsafeMutableBufferPointer { _ = first.process($0) }
        split.withUnsafeMutableBufferPointer { buffer in
            for start in stride(from: 0, to: buffer.count, by: 137) {
                _ = second.process(UnsafeMutableBufferPointer(rebasing: buffer[start..<min(start + 137, buffer.count)]))
            }
        }
        XCTAssertEqual(whole, split)
        var empty: [Int16] = []
        XCTAssertEqual(empty.withUnsafeMutableBufferPointer { second.process($0) }, 0)
    }
}
