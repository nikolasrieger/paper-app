import Foundation
import Observation
import UserNotifications

/// Daily "paper of the day" notification. Schedules the next two weeks individually,
/// because each day has a different paper.
@Observable
final class Reminders {
    var enabled: Bool { didSet { save() } }
    var time: Date { didSet { save() } }
    private(set) var denied = false

    private let defaults = UserDefaults.standard

    init() {
        enabled = defaults.bool(forKey: "reminderEnabled")
        let minutes = defaults.object(forKey: "reminderMinutes") as? Int ?? 8 * 60
        time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    private func save() {
        defaults.set(enabled, forKey: "reminderEnabled")
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        defaults.set((c.hour ?? 8) * 60 + (c.minute ?? 0), forKey: "reminderMinutes")
    }

    /// Asks for permission when needed, then replaces all pending reminders.
    @MainActor
    func reschedule(using store: LibraryStore) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled, !store.papers.isEmpty else { return }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        denied = !granted
        guard granted else { return }

        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: time)
        for offset in 0..<14 {
            guard let day = cal.date(byAdding: .day, value: offset, to: .now),
                  let fire = cal.date(bySettingHour: hm.hour ?? 8, minute: hm.minute ?? 0, second: 0, of: day),
                  fire > .now,
                  let paper = store.paperOfTheDay(on: day) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Paper of the day: \(paper.shortTitle)"
            content.body = paper.hook
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "daily-\(offset)", content: content, trigger: trigger))
        }
    }
}
