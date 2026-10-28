import AppKit
import SwiftUI
import XCTest
import VaaniCore
@testable import Vaani

final class FloatingPanelSizingTests: XCTestCase {
    @MainActor func testNativeBoundsFollowStateWithAutomaticHostingSizingDisabled() async throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vaani-panel-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let model = AppModel(store: PreferenceStore(url: url), inventory: {
            ([], ConnectedSetup(fingerprint: "fixture", summary: "Fixture"))
        }, observeDevices: false)
        let panel = DictationPanel(contentRect: NSRect(x: 100, y: 100, width: 54, height: 36),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let initial = expectation(description: "Initial SwiftUI layout reached native window")
        var initialized = false
        let hosting = NSHostingView(rootView: FloatingView(model: model, hide: {}, resize: { size in
            DispatchQueue.main.async {
                panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: true)
                if !initialized { initialized = true; initial.fulfill() }
            }
        }))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.orderFrontRegardless()
        defer { panel.close() }
        let bottom = panel.frame.minY
        await fulfillment(of: [initial], timeout: 3)
        for phase in [AppModel.Phase.connecting, .listening, .finishing, .processing, .idle, .listening, .idle] {
            model.phase = phase
            let expected: CGFloat = phase == .idle ? 54 : 138
            for _ in 0..<100 {
                if abs(panel.frame.width - expected) < 0.5 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertEqual(panel.frame.width, expected, accuracy: 0.5, "Pill clipped in phase \(phase)")
            XCTAssertEqual(hosting.frame.width, expected, accuracy: 0.5)
            XCTAssertEqual(panel.frame.height, 36, accuracy: 0.5)
            XCTAssertEqual(panel.frame.minY, bottom, accuracy: 0.5)
            XCTAssertFalse(panel.isKeyWindow)
            XCTAssertFalse(panel.isMainWindow)
        }
    }
}
