import Foundation
import UserNotifications
import SteadyCore

/// Local reminders only: scheduled on this phone, no server involved.
/// Permission is asked for only when the person turns reminders on.
enum ReminderService {
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }

    /// Replaces all Steady Strength reminders with the given slots (an empty list switches them off).
    static func schedule(_ slots: [ReminderSlot]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Reminders.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        for slot in slots {
            let content = UNMutableNotificationContent()
            content.title = slot.title
            content.body = slot.body
            content.sound = .default
            var parts = DateComponents()
            parts.weekday = slot.weekday; parts.hour = slot.hour; parts.minute = slot.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: slot.id, content: content, trigger: trigger))
        }
    }
}
