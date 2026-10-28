import AVFoundation
import Foundation

/// Recording-local noise suppression, resampling, speech-aware gain and meter.
/// Input: normalized mono 48 kHz floats. Output: mono 16 kHz PCM16. Serial use only.
public final class SpeechAudioProcessor {
    private let denoiser: SpeechDenoiser
    private let converter: AVAudioConverter
    private let input: AVAudioPCMBuffer
    private let output: AVAudioPCMBuffer
    private var gain = InputGainControl()
    private var meter = SpeechLevelMeter()

    public init() throws {
        denoiser = try SpeechDenoiser()
        guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false),
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 480),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 176) else {
            throw Failure.conversionUnavailable
        }
        self.converter = converter; self.input = input; self.output = output
        converter.primeMethod = .none
    }
    public func process(_ samples: UnsafeBufferPointer<Float>, emit: (Data, Float) -> Void) throws {
        try denoiser.process(samples) { try convert($0, emit: emit) }
    }
    public func finish(emit: (Data, Float) -> Void) throws {
        try denoiser.finish { try convert($0, emit: emit) }
    }
    private func convert(_ frame: SpeechDenoiser.Frame, emit: (Data, Float) -> Void) throws {
        guard let destination = input.floatChannelData?[0] else { throw Failure.conversionUnavailable }
        frame.samples.withUnsafeBufferPointer { destination.update(from: $0.baseAddress!, count: 480) }
        input.frameLength = 480; output.frameLength = 0
        var supplied = false; var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return self.input
        }
        if let error { throw error }
        guard let samples = output.int16ChannelData?[0], output.frameLength > 0 else { throw Failure.conversionUnavailable }
        let length = Int(output.frameLength)
        let rms = gain.process(UnsafeMutableBufferPointer(start: samples, count: length), speechProbability: frame.speechProbability)
        emit(Data(bytes: samples, count: length * 2), meter.update(rms: rms, frames: length))
    }
    public enum Failure: Error { case conversionUnavailable }
}
