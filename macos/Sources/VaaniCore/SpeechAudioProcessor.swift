import AVFoundation
import Foundation

/// Recording-local resampling and display meter. Enhancement is experimental and opt-in.
/// Input: normalized mono 48 kHz floats. Output: mono 16 kHz PCM16. Serial use only.
public final class SpeechAudioProcessor {
    public enum Mode { case original, enhanced }
    private let denoiser: SpeechDenoiser?
    private var pending = [Float]()
    private var finished = false
    private let converter: AVAudioConverter
    private let input: AVAudioPCMBuffer
    private let output: AVAudioPCMBuffer
    private var gain = InputGainControl()
    private var meter = SpeechLevelMeter()

    public init(mode: Mode = .original) throws {
        denoiser = mode == .enhanced ? try SpeechDenoiser() : nil
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
        guard !finished else { return }
        if let denoiser {
            try denoiser.process(samples) { try convert($0, emit: emit) }
        } else {
            for sample in samples {
                pending.append(sample.isFinite ? min(1, max(-1, sample)) : 0)
                if pending.count == 480 {
                    try convert(.init(samples: pending, speechProbability: 0), emit: emit)
                    pending.removeAll(keepingCapacity: true)
                }
            }
        }
    }
    public func finish(emit: (Data, Float) -> Void) throws {
        guard !finished else { return }
        finished = true
        if let denoiser {
            try denoiser.finish { try convert($0, emit: emit) }
        } else if !pending.isEmpty {
            pending.append(contentsOf: repeatElement(0, count: 480 - pending.count))
            try convert(.init(samples: pending, speechProbability: 0), emit: emit)
            pending.removeAll()
        }
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
        let rms: Float
        if denoiser != nil {
            rms = gain.process(UnsafeMutableBufferPointer(start: samples, count: length), speechProbability: frame.speechProbability)
        } else {
            // Meter smoothing never changes the PCM sent for transcription.
            let power = UnsafeBufferPointer(start: samples, count: length).reduce(Float(0)) {
                let sample = Float($1) / 32768
                return $0 + sample * sample
            }
            rms = sqrt(power / Float(length))
        }
        emit(Data(bytes: samples, count: length * 2), meter.update(rms: rms, frames: length))
    }
    public enum Failure: Error { case conversionUnavailable }
}
