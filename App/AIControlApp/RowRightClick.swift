import SwiftUI
import AppKit

/// A transparent overlay that adds macOS right-click behavior to a dashboard
/// row: it **selects** the row first (so you see what you're acting on) and,
/// for a running session, pops a menu with **Stop** (graceful wrap-up routine,
/// PROJECT.md §7/§9.7) and **Force Close** (immediate kill).
///
/// SwiftUI's own `.contextMenu` can't select-on-open, hence this small AppKit
/// shim. `hitTest` claims **only** right-mouse events (inspecting the current
/// event); every other event — left click, double-click, hover — returns `nil`
/// and falls through to the SwiftUI row beneath, so existing gestures are
/// untouched.
struct RowRightClick: NSViewRepresentable {
    /// Whether this row currently has a running session (menu is only shown then).
    var isRunning: Bool
    /// Whether a graceful Stop routine is already in flight (disables "Stop").
    var isStopping: Bool
    var onSelect: () -> Void
    var onStop: () -> Void
    var onForceClose: () -> Void

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
        view.isRunning = isRunning
        view.isStopping = isStopping
        view.onSelect = onSelect
        view.onStop = onStop
        view.onForceClose = onForceClose
    }

    final class CatcherView: NSView {
        var isRunning = false
        var isStopping = false
        var onSelect: (() -> Void)?
        var onStop: (() -> Void)?
        var onForceClose: (() -> Void)?

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
            guard isRunning else { return }
            let menu = NSMenu()

            let stop = NSMenuItem(title: "Stop", action: #selector(stopSession), keyEquivalent: "")
            stop.target = self
            stop.isEnabled = !isStopping
            stop.toolTip = "Ask Claude to wrap up (save, commit, push), then exit"
            menu.addItem(stop)

            let force = NSMenuItem(title: "Force Close", action: #selector(forceClose), keyEquivalent: "")
            force.target = self
            force.toolTip = "Kill the session immediately without wrapping up"
            menu.addItem(force)

            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc private func stopSession() { onStop?() }
        @objc private func forceClose() { onForceClose?() }
    }
}
