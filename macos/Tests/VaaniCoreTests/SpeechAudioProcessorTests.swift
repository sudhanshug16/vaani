import AVFoundation
import XCTest
@testable import VaaniCore

final class SpeechAudioProcessorTests: XCTestCase {
    private func noise(count: Int) -> [Float] {
        var state: UInt32 = 12345
        return (0..<count).map { _ in
            state = 1664525 &* state &+ 1013904223
            return (Float(state >> 8) / Float(1 << 24) * 2 - 1) * 0.025
        }
    }
    private func run(_ input: [Float], chunk: Int = 480) throws -> ([Int16], [Float]) {
        let processor = try SpeechAudioProcessor()
        var output = [Int16](), levels = [Float]()
        let collect: (Data, Float) -> Void = { data, level in
            output.append(contentsOf: data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) })
            levels.append(level)
        }
        try input.withUnsafeBufferPointer { buffer in
            for start in stride(from: 0, to: buffer.count, by: chunk) {
                try processor.process(UnsafeBufferPointer(rebasing: buffer[start..<min(start + chunk, buffer.count)]), emit: collect)
            }
        }
        try processor.finish(emit: collect)
        let count = output.count
        try processor.finish(emit: collect)
        try input.withUnsafeBufferPointer { try processor.process($0, emit: collect) }
        XCTAssertEqual(output.count, count, "Finished audio must not be emitted twice")
        return (output, levels)
    }
    func testStationaryNoiseIsSuppressedThroughProductionPipeline() throws {
        let input = noise(count: 96000)
        let (output, levels) = try run(input)
        let before = sqrt(input.suffix(48000).reduce(0.0) { $0 + Double($1 * $1) } / 48000)
        let after = sqrt(output.suffix(16000).reduce(0.0) { $0 + pow(Double($1) / 32768, 2) } / 16000)
        let reduction = 20 * log10(before / max(after, 1e-10))
        print("RNNoise stationary-noise reduction: \(reduction) dB")
        XCTAssertGreaterThan(reduction, 6)
        XCTAssertTrue(levels.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }
    func testArbitraryChunksAndNewRecordingProduceSamePCM() throws {
        let input = noise(count: 4801)
        let whole = try run(input, chunk: input.count)
        let split = try run(input, chunk: 137)
        XCTAssertEqual(whole.0, split.0)
        XCTAssertEqual(whole.1, split.1)
        // 11 padded frames plus two frames draining the denoiser delay/overlap.
        XCTAssertEqual(whole.0.count, 13 * 160)
    }
    func testPartialAndSilentRecordingTail() throws {
        XCTAssertTrue(try run([]).0.isEmpty)
        let (output, levels) = try run([0])
        XCTAssertEqual(output.count, 480)
        XCTAssertTrue(output.allSatisfy { $0 == 0 })
        XCTAssertTrue(levels.allSatisfy { $0 == 0 })
    }
    func testFullScaleAndNonfiniteInputRemainBounded() throws {
        let input: [Float] = [.infinity, -.infinity, .nan] + (0..<4800).map { $0 % 2 == 0 ? 1 : -1 }
        let (output, levels) = try run(input)
        XCTAssertTrue(output.allSatisfy { abs(Int($0)) <= 31130 })
        XCTAssertTrue(levels.allSatisfy(\.isFinite))
    }
    func testMissingOrCorruptModelThrowsBeforeCParsing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try SpeechDenoiser(modelURL: url))
        try Data("invalid model".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try SpeechDenoiser(modelURL: url))
    }
    func testOptionalLocalSyntheticSpeechFixture() throws {
        guard let path = ProcessInfo.processInfo.environment["VAANI_SYNTHETIC_SPEECH"] else {
            throw XCTSkip("Opt-in local synthesized speech fixture")
        }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        XCTAssertEqual(file.processingFormat.sampleRate, 48000)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let speech = Array(UnsafeBufferPointer(start: try XCTUnwrap(buffer.floatChannelData?[0]), count: Int(buffer.frameLength)))
        let padding = [Float](repeating: 0, count: 48000)
        let clean = padding + speech + padding
        let background = noise(count: clean.count)
        let mixed = zip(clean, background).map(+)
        let (output, _) = try run(mixed)
        let sourceEnergy = speech.reduce(0.0) { $0 + Double($1 * $1) } / Double(speech.count)
        let speechOutput = output.dropFirst(16320).prefix(speech.count / 3)
        let speechEnergy = speechOutput.reduce(0.0) { $0 + pow(Double($1) / 32768, 2) } / Double(speechOutput.count)
        XCTAssertGreaterThan(speechEnergy, sourceEnergy * 0.1, "Denoiser must retain synthetic speech")
        let outputURL = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("processed.wav")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false))
        let result = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(output.count)))
        result.frameLength = AVAudioFrameCount(output.count)
        output.withUnsafeBufferPointer { result.int16ChannelData![0].update(from: $0.baseAddress!, count: output.count) }
        try AVAudioFile(forWriting: outputURL, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: false).write(from: result)
        print("Synthetic speech output: \(outputURL.path), speech RMS \(sqrt(speechEnergy))")
    }
}
