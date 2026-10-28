import Foundation
import CRNNoise
import CryptoKit

/// A recording's RNNoise state and 10 ms input framing. Serial capture queue only.
public final class SpeechDenoiser {
    public struct Frame {
        /// Normalized mono 48 kHz floats, ready for downsampling.
        public let samples: [Float]
        public let speechProbability: Float
    }
    private let model: OpaquePointer
    private let state: OpaquePointer
    private let weights: NSData
    private var pending = [Float](repeating: 0, count: 480)
    private var count = 0
    private var receivedAudio = false
    private var finished = false

    public convenience init() throws {
        let url: URL?
        if Bundle.main.bundleURL.pathExtension == "app" {
            let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("Vaani_VaaniCore.bundle")
            url = bundleURL.flatMap { Bundle(url: $0) }?.url(forResource: "rnnoise-model", withExtension: "bin")
        } else {
            url = Bundle.module.url(forResource: "rnnoise-model", withExtension: "bin")
        }
        guard let url else { throw Failure.modelUnavailable }
        try self.init(modelURL: url)
    }
    init(modelURL: URL) throws {
        // Validate before handing bytes to the upstream C parser. Retain the
        // stable NSData storage until after both state and model are destroyed.
        let weights = try NSData(contentsOf: modelURL, options: .mappedIfSafe)
        guard SHA256.hash(data: weights as Data).map({ String(format: "%02x", $0) }).joined()
                == "35da861b090c25df53ba7f258b1ea55b1ea36d0c9063d9495bc145ada945c90e",
              let model = rnnoise_model_from_buffer(weights.bytes, Int32(weights.length)) else {
            throw Failure.modelUnavailable
        }
        guard rnnoise_get_frame_size() == 480, let state = rnnoise_create(model) else {
            rnnoise_model_free(model)
            throw Failure.modelUnavailable
        }
        self.model = model; self.state = state; self.weights = weights
    }
    deinit { rnnoise_destroy(state); rnnoise_model_free(model) }

    public func process(_ samples: UnsafeBufferPointer<Float>, emit: (Frame) throws -> Void) rethrows {
        guard !finished else { return }
        for sample in samples {
            receivedAudio = true
            pending[count] = sample.isFinite ? min(1, max(-1, sample)) * 32768 : 0
            count += 1
            if count == 480 { count = 0; try emit(denoise()) }
        }
    }
    /// Pads the final partial frame and drains v0.2's two-frame (20 ms) delay:
    /// one delayed spectrum plus the analysis/synthesis overlap.
    /// Called once on explicit Finish; cancellation discards pending audio.
    public func finish(emit: (Frame) throws -> Void) rethrows {
        guard !finished else { return }
        finished = true
        guard receivedAudio else { return }
        if count > 0 {
            for index in count..<480 { pending[index] = 0 }
            count = 0; try emit(denoise())
        }
        pending = [Float](repeating: 0, count: 480)
        for _ in 0..<2 { try emit(denoise()) }
    }
    private func denoise() -> Frame {
        var output = [Float](repeating: 0, count: 480)
        let probability = pending.withUnsafeBufferPointer { input in
            output.withUnsafeMutableBufferPointer { rnnoise_process_frame(state, $0.baseAddress, input.baseAddress) }
        }
        for index in output.indices { output[index] = output[index].isFinite ? output[index] / 32768 : 0 }
        return Frame(samples: output, speechProbability: min(1, max(0, probability)))
    }
    public enum Failure: Error { case modelUnavailable }
}
