import SwiftUI
import AppKit

/// A transparent overlay that adds macOS right-click behavior to a dashboard
/// row: it **selects** the row first (so you see what you're acting on) and,
/// when `showsCloseSession` is true, pops a "Close Session" menu.
///
/// SwiftUI's own `.contextMenu` can't select-on-open, hence this small AppKit
/// shim. `hitTest` claims **only** right-mouse events (inspecting the current
/// event); every other event — left click, double-click, hover — returns `nil`
/// and falls through to the SwiftUI row beneath, so existing gestures are
/// untouched.
struct RowRightClick: NSViewRepresentable {
    var showsCloseSession: Bool
    var onSelect: () -> Void
    var onCloseSession: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CatcherView else { return }
        configure(view)
    }

    private func configure(_ view: CatcherView) {
        view.showsCloseSession = showsCloseSession
        view.onSelect = onSelect
        view.onCloseSession = onCloseSession
    }

    final class CatcherView: NSView {
        var showsCloseSession = false
        var onSelect: (() -> Void)?
        var onCloseSession: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return self
            default:
                return nil // let left-click / double-click / hover reach SwiftUI
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            onSelect?()
            guard showsCloseSession else { return }
            let menu = NSMenu()
            let item = NSMenuItem(title: "Close Session", action: #selector(closeSession), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc private func closeSession() { onCloseSession?() }
    }
}
