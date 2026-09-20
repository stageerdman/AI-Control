import Foundation
import AppKit
import UserNotifications

/// Turns the store's `awaitingInputURLs` into macOS **notifications** and a
/// **Dock badge** (PROJECT.md §11). Fires exactly one notification per genuine
/// working→awaiting transition, withdraws it when the session leaves awaiting,
/// and stays quiet when the user is already looking at that project (Phase 5 UX
/// pass). Clicking a notification asks the app to open that project.
@MainActor
final class SessionAlerts: NSObject, ObservableObject {
    /// Set by the notification delegate when the user clicks a notification; the
    /// dashboard observes this and opens the project, then clears it.
    @Published var pendingOpenURL: URL?

    private var previousAwaiting: Set<URL> = []
    private var authorized = false
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    /// Requests notification permission once (no-op if already asked). Safe to
    /// call on launch.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in self?.authorized = granted }
        }
    }

    /// Reconciles alerts with the current awaiting set. `foreground` is the
    /// project currently shown full-window (if any); `appActive` is whether the
    /// app is frontmost. `name(for:)` resolves a project's display name.
    func update(
        awaiting: Set<URL>,
        foreground: URL?,
        appActive: Bool,
        name: (URL) -> String
    ) {
        // Dock badge: how many projects need a reply. A project the user is
        // actively viewing doesn't count while the app is frontmost — the badge
        // is a "come back" signal and they're already there.
        let hidden: Set<URL> = (appActive && foreground != nil) ? [foreground!] : []
        let badgeCount = awaiting.subtracting(hidden).count
        NSApp.dockTile.badgeLabel = badgeCount > 0 ? "\(badgeCount)" : nil

        // New transitions into awaiting → notify, unless the user is looking at
        // that very project.
        for url in awaiting.subtracting(previousAwaiting) {
            let viewingThis = appActive && url == foreground
            if !viewingThis { postNotification(for: url, name: name(url)) }
        }

        // Left awaiting (replied, resumed, or closed) → withdraw its notification.
        let noLonger = previousAwaiting.subtracting(awaiting)
        if !noLonger.isEmpty {
            let ids = noLonger.map(\.absoluteString)
            center.removeDeliveredNotifications(withIdentifiers: ids)
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }

        previousAwaiting = awaiting
    }

    private func postNotification(for url: URL, name: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = "Claude is waiting for your reply."
        content.interruptionLevel = .active // informative, not an alarm
        // Identifier == project URL, so repeated working↔awaiting toggles replace
        // rather than stack, and we can withdraw it precisely.
        let request = UNNotificationRequest(identifier: url.absoluteString, content: content, trigger: nil)
        center.add(request)
    }
}

extension SessionAlerts: UNUserNotificationCenterDelegate {
    /// Clicking a notification opens that project.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        Task { @MainActor in
            if let url = URL(string: id) { self.pendingOpenURL = url }
        }
        completionHandler()
    }
}
