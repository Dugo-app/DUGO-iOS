//
//  CloudSyncMonitor.swift
//  DuGo-iOS
//
//  Created by 김승원 on 12/10/26.
//

import CloudKit
import Combine
import CoreData
import Foundation

enum CloudSyncConfiguration {
    // MARK: - Properties

    static var isPausedForSafety: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    static var containerIdentifier: String? {
        guard let identifier = Bundle.main.object(
            forInfoDictionaryKey: "DuGoCloudKitContainerIdentifier"
        ) as? String,
            identifier.hasPrefix("iCloud.")
        else { return nil }
        return identifier
    }
}

@MainActor
final class CloudSyncMonitor: ObservableObject {
    // MARK: - Types

    enum Status {
        case checking
        case available
        case noAccount
        case unavailable
        case notConfigured
        case paused

        var title: String {
            switch self {
            case .checking: "확인 중"
            case .available: "사용 가능"
            case .noAccount: "iCloud 계정 필요"
            case .unavailable: "확인 필요"
            case .notConfigured: "연결되지 않음"
            case .paused: "동기화 일시 중지"
            }
        }

        var description: String {
            switch self {
            case .checking, .available:
                "같은 Apple 계정의 기기에서 기록을 자동으로 동기화해요"
            case .noAccount:
                "기기의 설정에서 iCloud에 로그인하면 동기화할 수 있어요"
            case .unavailable:
                "iCloud 상태를 확인하지 못했어요 잠시 후 다시 확인해 주세요"
            case .notConfigured:
                "기록은 이 기기에 저장돼요 iCloud 연결을 확인해 주세요"
            case .paused:
                "기록 보호를 위해 iCloud 동기화를 잠시 중지했어요 기록은 이 기기에 저장돼요"
            }
        }
    }

    // MARK: - Properties

    @Published private(set) var status: Status
    @Published private(set) var lastSyncAt: Date?
    private let isConfigured: Bool
    private static let lastSyncKey = "lastSuccessfulCloudSyncAt"

    var statusLabel: String {
        guard case .available = status else { return status.title }
        guard let lastSyncAt else { return "기록 없음" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter.string(from: lastSyncAt)
    }

    // MARK: - Initializer

    init(isConfigured: Bool) {
        self.isConfigured = isConfigured
        status = isConfigured ? .checking : Self.inactiveStatus
        lastSyncAt = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    // MARK: - Methods

    func refresh() async {
        lastSyncAt = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
        guard isConfigured, let identifier = CloudSyncConfiguration.containerIdentifier else {
            status = Self.inactiveStatus
            return
        }

        let accountStatus = await withCheckedContinuation { continuation in
            CKContainer(identifier: identifier).accountStatus { accountStatus, error in
                continuation.resume(
                    returning: error == nil ? accountStatus : .couldNotDetermine
                )
            }
        }

        switch accountStatus {
        case .available:
            status = .available
        case .noAccount:
            status = .noAccount
        case .couldNotDetermine, .restricted, .temporarilyUnavailable:
            status = .unavailable
        @unknown default:
            status = .unavailable
        }
    }

    private static var inactiveStatus: Status {
        CloudSyncConfiguration.isPausedForSafety ? .paused : .notConfigured
    }

    func record(_ event: NSPersistentCloudKitContainer.Event) {
        guard let date = Self.recordSuccessfulSync(event) else { return }
        if date > (lastSyncAt ?? .distantPast) {
            lastSyncAt = date
        }
    }

    @discardableResult
    static func recordSuccessfulSync(_ event: NSPersistentCloudKitContainer.Event) -> Date? {
        guard event.type == .import || event.type == .export,
            event.succeeded,
            let endDate = event.endDate
        else { return nil }

        let previous = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
        if endDate > (previous ?? .distantPast) {
            UserDefaults.standard.set(endDate, forKey: lastSyncKey)
        }
        return endDate
    }
}
