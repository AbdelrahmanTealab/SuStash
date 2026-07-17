//
//  RediscoverReminder.swift
//  SuStash
//
//  Optional weekly local notification resurfacing the unopened backlog.
//  Off by default; the Settings toggle requests permission on first enable.
//

import Foundation
import UserNotifications

enum RediscoverReminder {
    static let enabledKey = "rediscoverReminderEnabled"
    private static let requestIdentifier = "sustash.rediscover.weekly"

    /// Ask for permission (first enable). Returns whether notifications are allowed.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    /// (Re)schedule the weekly nudge with a fresh unopened count, or clear it
    /// when disabled/empty. Called after every library pipeline pass.
    static func refreshSchedule(enabled: Bool, unopenedCount: Int) {
        let center = UNUserNotificationCenter.current()
        guard enabled, unopenedCount > 0 else {
            center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Your stash misses you"
        content.body = unopenedCount == 1
            ? "1 saved link is still waiting to be opened."
            : "\(unopenedCount) saved links are still waiting. Rediscover a few?"
        content.sound = .default

        // Sunday 10:00 local time, repeating.
        var components = DateComponents()
        components.weekday = 1
        components.hour = 10
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        // Replaces any pending request with the same identifier, so the
        // count stays current without stacking notifications.
        center.add(UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger))
    }
}
