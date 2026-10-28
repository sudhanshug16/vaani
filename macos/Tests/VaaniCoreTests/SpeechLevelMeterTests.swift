import XCTest
@testable import VaaniCore

final class SpeechLevelMeterTests: XCTestCase {
    func testBriefSpikeDoesNotSnapMeterToFullScale() {
        var meter = SpeechLevelMeter()
        let spike = meter.update(rms: 1, frames: 160)
        XCTAssertGreaterThan(spike, 0)
        XCTAssertLessThan(spike, 0.13)
        XCTAssertLessThan(meter.update(rms: 0, frames: 160), spike)
    }
    func testMeterConvergesWithoutOvershootAndRecovers() {
        var meter = SpeechLevelMeter()
        var previous: Float = 0
        for _ in 0..<100 {
            let value = meter.update(rms: 0.1, frames: 160)
            XCTAssertGreaterThanOrEqual(value, previous)
            XCTAssertLessThanOrEqual(value, 0.5)
            previous = value
        }
        XCTAssertEqual(previous, 0.5, accuracy: 0.001)
        for _ in 0..<200 { previous = meter.update(rms: 0, frames: 160) }
        XCTAssertLessThan(previous, 0.001)
    }
}
