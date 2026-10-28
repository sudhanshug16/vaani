import XCTest
@testable import VaaniCore

final class SetupLabelTests: XCTestCase {
    func testConnectedNamesAreStableAndReadable() {
        XCTAssertEqual(SetupLabel.make(displays: ["DELL U2723QE", "Built-in Retina Display"], peripherals: ["USB Hub", "USB Mic"]),
            "Built-in Retina Display + DELL U2723QE + USB Hub + USB Mic")
        XCTAssertEqual(SetupLabel.make(displays: ["B", "A"], peripherals: ["Hub", "Mic"]),
            SetupLabel.make(displays: ["A", "B"], peripherals: ["Mic", "Hub"]))
    }
    func testDuplicateDeviceNamesAreCounted() {
        XCTAssertEqual(SetupLabel.make(displays: ["Studio Display", "Studio Display"], peripherals: ["Hub", "Hub"]),
            "Studio Display × 2 + Hub × 2")
    }
    func testEmptyNamesAreTrimmedAndFallbackIsReadable() {
        XCTAssertEqual(SetupLabel.make(displays: ["  "], peripherals: ["\n"]), "This Mac")
        XCTAssertEqual(SetupLabel.make(displays: ["  Display  "], peripherals: ["", " Mic\n"]), "Display + Mic")
    }
}
