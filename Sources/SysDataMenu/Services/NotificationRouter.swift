import UserNotifications

/// Sends a tap on one of the app's notifications to the place that explains
/// it. For now that is the growth notification, which opens the history view
/// at the category it named instead of leaving the person to find it.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let growthCategoryKey = "growthCategory"
    private static let shared = NotificationRouter()

    /// Called once at launch. A process with no application bundle, such as
    /// the command-line modes, has no notification center to attach to.
    @MainActor
    static func install() {
        guard LowSpaceAlert.isAvailable else { return }
        UNUserNotificationCenter.current().delegate = shared
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let raw = response.notification.request.content.userInfo[Self.growthCategoryKey] as? String
        Task { @MainActor in
            defer { completionHandler() }
            guard let raw, let category = StorageCategory(rawValue: raw) else { return }
            MainWindow.shared.show()
            MainWindow.shared.model?.growthFocus = category
        }
    }
}
