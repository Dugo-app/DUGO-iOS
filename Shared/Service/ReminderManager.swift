//
//  ReminderManager.swift
//  DuGo-iOS
//
//  Created by 김승원 on 19/9/26.
//

import Combine
import Foundation
import UserNotifications

struct WishReminder {
    // MARK: - Properties

    let itemID: UUID
    let title: String
    let date: Date
}

enum ReminderTimePreference {
    // MARK: - Properties

    private static let key = "reviewReminderMinuteOfDay"
    private static let defaultMinuteOfDay = 13 * 60

    static var minuteOfDay: Int {
        let defaults = UserDefaults(suiteName: SharedLinkInbox.groupIdentifier) ?? .standard
        guard defaults.object(forKey: key) != nil else { return defaultMinuteOfDay }
        return min(max(defaults.integer(forKey: key), 0), 23 * 60 + 59)
    }

    static var date: Date {
        let selectedMinutes = minuteOfDay
        return Calendar.current.date(
            bySettingHour: selectedMinutes / 60,
            minute: selectedMinutes % 60,
            second: 0,
            of: .now
        ) ?? .now
    }

    static var displayText: String {
        let selectedMinutes = minuteOfDay
        let hour = selectedMinutes / 60
        let minute = selectedMinutes % 60
        let period = hour < 12 ? "오전" : "오후"
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return minute == 0 ? "\(period) \(hour12)시" : "\(period) \(hour12)시 \(minute)분"
    }

    // MARK: - Methods

    static func save(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 13) * 60 + (components.minute ?? 0)
        let defaults = UserDefaults(suiteName: SharedLinkInbox.groupIdentifier) ?? .standard
        defaults.set(minutes, forKey: key)
    }
}

@MainActor
final class ReminderManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    // MARK: - Properties

    @Published var openedItemID: UUID?
    @Published var shouldOpenReviewList = false
    private(set) var scheduledIDs: Set<UUID> = []
    private(set) var notice: String?
    private var queue: Task<Void, Never>?
    private var center: UNUserNotificationCenter { .current() }
    private let notificationIdentifierPrefix = "dugo.review."
    private let groupedNotificationIdentifierPrefix = "dugo.review.group."

    // MARK: - Methods

    func start() { center.delegate = self }

    func requestPermissionIfNeeded() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func synchronize(_ reminders: [WishReminder]) async {
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            await self.performSync(reminders)
        }
        queue = task
        await task.value
    }

    func synchronizeAdditional(_ reminders: [WishReminder]) async {
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            await self.performAdditionalSync(reminders)
        }
        queue = task
        await task.value
    }

    // MARK: - Private Methods

    private func performSync(_ reminders: [WishReminder]) async {
        let settings = await center.notificationSettings()
        let authorized = [.authorized, .provisional, .ephemeral].contains(
            settings.authorizationStatus
        )
        let groups = groupedReminders(from: reminders)
        let future = groups.filter { $0.date > .now }
        let selected = authorized ? Array(future.prefix(60)) : []
        let allowed = Set(selected.map(\.identifier))
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter {
                $0.hasPrefix(notificationIdentifierPrefix) && !allowed.contains($0)
            }
        )
        let active = Set(groups.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(
            withIdentifiers: delivered.compactMap { notification in
                let request = notification.request
                guard request.identifier.hasPrefix(notificationIdentifierPrefix) else {
                    return nil
                }
                guard active.contains(request.identifier),
                    let group = groups.first(where: { $0.identifier == request.identifier }),
                    reminderIDs(from: request.content) == Set(group.reminders.map(\.itemID))
                else {
                    return request.identifier
                }
                return nil
            }
        )
        notice = nil
        if !authorized && !future.isEmpty {
            notice = "알림 권한이 꺼져 있어요"
        } else if future.count > 60 {
            notice = "가까운 일정 60개까지 알림을 예약했어요 앱을 열 때 다음 일정을 갱신해요"
        }
        for group in selected {
            let existing = pending.first { $0.identifier == group.identifier }
            if !(await schedule(group, replacing: existing)) {
                notice = "알림을 예약하지 못했어요"
            }
        }
        await updateScheduledIDs()
    }

    private func performAdditionalSync(_ additions: [WishReminder]) async {
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            notice = "알림 권한이 꺼져 있어요"
            return
        }

        let pending = await center.pendingNotificationRequests()
        let groups = groupedReminders(from: additions).filter { $0.date > .now }
        var scheduledGroupCount = pending.filter {
            $0.identifier.hasPrefix(notificationIdentifierPrefix)
        }.count
        notice = nil

        for group in groups {
            let existing = pending.first { $0.identifier == group.identifier }
            if existing == nil, scheduledGroupCount >= 60 {
                notice = "가까운 일정 60개까지 알림을 예약했어요 앱을 열 때 다음 일정을 갱신해요"
                continue
            }

            var combined = existing.map { reminders(from: $0, on: group.date) } ?? []
            let addedIDs = Set(group.reminders.map(\.itemID))
            combined.removeAll { addedIDs.contains($0.itemID) }
            combined.append(contentsOf: group.reminders)

            let updatedGroup = ReminderGroup(
                date: group.date,
                identifier: group.identifier,
                reminders: combined
            )
            if !(await schedule(updatedGroup, replacing: existing)) {
                notice = "알림을 예약하지 못했어요"
            } else if existing == nil {
                scheduledGroupCount += 1
            }
        }
        await updateScheduledIDs()
    }

    private func schedule(
        _ group: ReminderGroup,
        replacing existing: UNNotificationRequest?
    ) async -> Bool {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: group.date
        )
        let content = notificationContent(for: group)
        let expectedTitles = group.reminders.map { notificationTitle(from: $0.title) }
        if let existing,
            let trigger = existing.trigger as? UNCalendarNotificationTrigger,
            trigger.dateComponents == components,
            existing.content.title == content.title,
            existing.content.body == content.body,
            reminderIDs(from: existing.content) == Set(group.reminders.map(\.itemID)),
            existing.content.userInfo["wishTitles"] as? [String] == expectedTitles
        {
            return true
        }

        let request = UNNotificationRequest(
            identifier: group.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    private func updateScheduledIDs() async {
        let actual = await center.pendingNotificationRequests()
        scheduledIDs = Set(
            actual
                .filter { $0.identifier.hasPrefix(notificationIdentifierPrefix) }
                .flatMap { reminderIDs(from: $0.content) }
        )
    }

    private func groupedReminders(from reminders: [WishReminder]) -> [ReminderGroup] {
        Dictionary(grouping: reminders) { notificationDate(for: $0.date) }
            .map { date, reminders in
                ReminderGroup(
                    date: date,
                    identifier: notificationIdentifier(for: date),
                    reminders: reminders
                )
            }
            .sorted { $0.date < $1.date }
    }

    private func notificationContent(for group: ReminderGroup) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let representativeTitle = notificationTitle(
            from: group.reminders.first?.title ?? "담아둔 상품"
        )
        let additionalCount = group.reminders.count - 1

        if additionalCount == 0 {
            content.title = "다시 볼 마음이 있어요"
            content.body = "“\(representativeTitle)”을 다시 살펴볼 시간이에요"
            content.userInfo = [
                "wishID": group.reminders[0].itemID.uuidString,
                "wishTitles": group.reminders.map { notificationTitle(from: $0.title) },
            ]
        } else {
            content.title = "오늘 다시 볼 마음이 \(group.reminders.count)개 있어요"
            content.body = "\(representativeTitle) 외 \(additionalCount)개를 천천히 살펴보세요"
            content.userInfo = [
                "wishIDs": group.reminders.map { $0.itemID.uuidString },
                "wishTitles": group.reminders.map { notificationTitle(from: $0.title) },
            ]
        }
        return content
    }

    private func notificationTitle(from rawTitle: String) -> String {
        let normalizedTitle = rawTitle
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let title = normalizedTitle.isEmpty ? "담아둔 상품" : normalizedTitle
        let maximumLength = 20

        guard title.count > maximumLength else { return title }
        return String(title.prefix(maximumLength)) + "…"
    }

    private func reminderIDs(from content: UNNotificationContent) -> Set<UUID> {
        if let values = content.userInfo["wishIDs"] as? [String] {
            return Set(values.compactMap(UUID.init(uuidString:)))
        }
        if let value = content.userInfo["wishID"] as? String,
            let id = UUID(uuidString: value)
        {
            return [id]
        }
        return []
    }

    private func reminders(from request: UNNotificationRequest, on date: Date) -> [WishReminder] {
        let userInfo = request.content.userInfo
        let identifiers = (userInfo["wishIDs"] as? [String])
            ?? (userInfo["wishID"] as? String).map { [$0] }
            ?? []
        let titles = userInfo["wishTitles"] as? [String] ?? []
        let fallbackTitle = legacyTitle(from: request.content.body)

        return identifiers.enumerated().compactMap { index, identifier in
            guard let id = UUID(uuidString: identifier) else { return nil }
            let title = titles.indices.contains(index) ? titles[index] : fallbackTitle
            return WishReminder(itemID: id, title: title, date: date)
        }
    }

    private func legacyTitle(from body: String) -> String {
        if let start = body.firstIndex(of: "“"),
            let end = body[start...].firstIndex(of: "”")
        {
            return String(body[body.index(after: start)..<end])
        }
        return body.components(separatedBy: " 외 ").first ?? "담아둔 상품"
    }

    private func notificationIdentifier(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return groupedNotificationIdentifierPrefix
            + "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func notificationDate(for reviewDate: Date) -> Date {
        let minuteOfDay = ReminderTimePreference.minuteOfDay
        return Calendar.current.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: reviewDate
        ) ?? reviewDate
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let values = userInfo["wishIDs"] as? [String], values.count > 1 {
            await MainActor.run { self.shouldOpenReviewList = true }
            return
        }
        guard let text = userInfo["wishID"] as? String,
            let id = UUID(uuidString: text)
        else { return }
        await MainActor.run { self.openedItemID = id }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

private struct ReminderGroup {
    let date: Date
    let identifier: String
    let reminders: [WishReminder]
}
