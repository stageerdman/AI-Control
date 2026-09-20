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

    /// Projects that should currently show an in-app attention banner / glow:
    /// awaiting input, not dismissed for this episode, and not the one the user
    /// is already viewing. Newest-awaiting first. Drives the red banner + glow.
    @Published private(set) var attentionURLs: [URL] = []

    /// Display names for the attention URLs, resolved at compute time (the view
    /// only has URLs; names live in the dashboard model).
    private(set) var names: [URL: String] = [:]

    /// Per-episode dismissals: an X'd project stays out of the banner until it
    /// next re-enters awaiting.
    private var dismissed: Set<URL> = []

    // Last inputs, kept so `dismiss(_:)` can recompute without new data.
    private var lastAwaiting: Set<URL> = []
    private var lastForeground: URL?
    private var lastAppActive = false

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

        // Left awaiting (replied, resumed, or closed) → withdraw its notification
        // and clear any dismissal so a fresh awaiting episode banners again.
        let noLonger = previousAwaiting.subtracting(awaiting)
        if !noLonger.isEmpty {
            let ids = noLonger.map(\.absoluteString)
            center.removeDeliveredNotifications(withIdentifiers: ids)
            center.removePendingNotificationRequests(withIdentifiers: ids)
            dismissed.subtract(noLonger)
        }

        previousAwaiting = awaiting
        lastAwaiting = awaiting
        lastForeground = foreground
        lastAppActive = appActive
        recomputeAttention(name: name)
    }

    /// Dismisses the banner for one project (won't banner again until it
    /// re-enters awaiting). The row **glow** is driven separately (by the raw
    /// awaiting set), so it persists — banner = dismissible interrupt, glow =
    /// ambient reminder (UX pass).
    func dismiss(_ url: URL) {
        dismissed.insert(url)
        recomputeAttention(name: { names[$0] ?? "Project" })
    }

    /// The consolidated banner's X: dismisses every currently-shown project, so
    /// the banner disappears until any of them next re-enters awaiting.
    func dismissAll() {
        dismissed.formUnion(attentionURLs)
        recomputeAttention(name: { names[$0] ?? "Project" })
    }

    private func recomputeAttention(name: (URL) -> String) {
        let hiddenForeground: Set<URL> = lastAppActive && lastForeground != nil ? [lastForeground!] : []
        let visible = lastAwaiting.subtracting(dismissed).subtracting(hiddenForeground)

        // Newest-awaiting first: stable order derived from awaiting membership
        // isn't time-stamped here, so sort by name as a deterministic tiebreak;
        // the store already surfaces most-recent via the pinned ordering.
        let sorted = visible.sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }

        var resolvedNames: [URL: String] = [:]
        for url in lastAwaiting { resolvedNames[url] = name(url) }
        names = resolvedNames
        attentionURLs = sorted
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
