import AppKit
import SwiftUI

/// Clicking the overlay must never take keyboard focus from the destination.
final class DictationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        // Hosting-view intrinsic sizing can also resize the native window.
        // Keep the bottom edge anchored for that path as well as our callback.
        if isVisible, frame.size != rect.size { rect.origin = frame.origin }
        if let bounds = (screen ?? NSScreen.main)?.visibleFrame {
            rect.origin.x = min(max(rect.minX, bounds.minX), max(bounds.minX, bounds.maxX - rect.width))
            rect.origin.y = min(max(rect.minY, bounds.minY), max(bounds.minY, bounds.maxY - rect.height))
        }
        super.setFrame(rect, display: flag)
    }
}

private struct PanelSize: PreferenceKey {
    static var defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct PanelDragRegion: NSViewRepresentable {
    var click: () -> Void
    func makeNSView(context: Context) -> DragView { DragView(click: click) }
    func updateNSView(_ view: DragView, context: Context) { view.click = click }
    final class DragView: NSView {
        var click: () -> Void
        private var dragStart: NSPoint?
        private var windowStart: NSPoint?
        private var moved = false
        init(click: @escaping () -> Void) {
            self.click = click; super.init(frame: .zero)
            setAccessibilityElement(true); setAccessibilityRole(.button)
            setAccessibilityLabel("Dictate or finish dictation")
            setAccessibilityHelp("Drag to move the panel")
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override var mouseDownCanMoveWindow: Bool { false }
        override func accessibilityPerformPress() -> Bool { click(); return true }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            dragStart = window.convertPoint(toScreen: event.locationInWindow)
            windowStart = window.frame.origin; moved = false
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window, let dragStart, let windowStart else { return }
            let point = window.convertPoint(toScreen: event.locationInWindow)
            let delta = NSPoint(x: point.x - dragStart.x, y: point.y - dragStart.y)
            guard moved || abs(delta.x) > 3 || abs(delta.y) > 3 else { return }
            moved = true
            var rect = window.frame
            rect.origin = NSPoint(x: windowStart.x + delta.x, y: windowStart.y + delta.y)
            window.setFrame(rect, display: true)
        }
        override func mouseUp(with event: NSEvent) {
            let shouldClick = dragStart != nil && !moved
            dragStart = nil; windowStart = nil
            if shouldClick { click() }
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}

struct FloatingView: View {
    @ObservedObject var model: AppModel
    var hide: () -> Void
    var resize: (CGSize) -> Void
    @State private var hovered = false
    private let surface = Color(red: 0.10, green: 0.105, blue: 0.11)

    var body: some View {
        pill
        .background(surface.opacity(0.98), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
        .fixedSize()
        .preferredColorScheme(.dark)
        .background(GeometryReader { proxy in Color.clear.preference(key: PanelSize.self, value: proxy.size) })
        .onPreferenceChange(PanelSize.self, perform: resize)
        .onHover { hovered = $0 }
        .help(model.error ?? model.statusNotice ?? "Drag to move · tap to dictate")
    }

    private var face: some View {
        HStack(spacing: 7) {
            if model.active {
                if model.phase == .listening {
                    ForEach(0..<5) { index in
                        Capsule().fill(.white).frame(width: 3,
                            height: 4 + CGFloat(model.level) * CGFloat([10, 18, 24, 18, 10][index]))
                    }
                } else { ProgressView().controlSize(.small).tint(.white) }
            } else if model.error != nil {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            } else {
                Capsule().fill(.white).frame(width: 6, height: 3)
                Capsule().fill(.white).frame(width: 6, height: 3)
            }
        }.frame(width: model.active ? 52 : 24, height: 26)
    }
    private var pill: some View {
        HStack(spacing: 12) {
            face.overlay(PanelDragRegion {
                if model.error != nil && !model.active { model.showErrorDetails?() }
                else if !model.isPasting { model.toggleFromPanel() }
            })
                .help(model.error.map { "\($0) · Click for details" } ?? "Drag to move · click to dictate or finish")
                .accessibilityLabel(model.error != nil && !model.active ? "Show dictation error details" : "Move dictation panel")
            if model.active || hovered || model.isPasting {
                if model.isPasting { ProgressView().controlSize(.small) }
                else {
                    Button(action: model.toggleFromPanel) {
                        Image(systemName: model.phase == .listening ? "stop.fill" : "mic.fill")
                    }.help(model.phase == .listening ? "Finish dictation" : "Dictate")
                        .accessibilityLabel(model.phase == .listening ? "Finish dictation" : "Dictate")
                        .disabled(model.active && model.phase != .listening)
                }
                Button(action: hide) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .help("Dismiss · Escape").accessibilityLabel("Dismiss dictation panel")
            }
        }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.9)).padding(.horizontal, 15).padding(.vertical, 5)
    }
}
