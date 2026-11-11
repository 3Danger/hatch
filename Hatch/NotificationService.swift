import Foundation
import UserNotifications
import AppKit

/// Локальные уведомления о завершении долгих команд.
final class NotificationService {
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Показывает уведомление, только если приложение не в фокусе.
    func notifyIfNotFocused(title: String, body: String) {
        guard !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
