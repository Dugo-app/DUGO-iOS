//
//  CloudSyncMonitor.swift
//  DuGo-iOS
//
//  Created by 김승원 on 12/10/26.
//

import CloudKit
import Combine
import Foundation

enum CloudSyncConfiguration {
    // MARK: - Properties

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

        var title: String {
            switch self {
            case .checking: "확인 중"
            case .available: "사용 가능"
            case .noAccount: "iCloud 계정 필요"
            case .unavailable: "확인 필요"
            case .notConfigured: "연결되지 않음"
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
            }
        }
    }

    // MARK: - Properties

    @Published private(set) var status: Status
    private let isConfigured: Bool

    // MARK: - Initializer

    init(isConfigured: Bool) {
        self.isConfigured = isConfigured
        status = isConfigured ? .checking : .notConfigured
    }

    // MARK: - Methods

    func refresh() async {
        guard isConfigured, let identifier = CloudSyncConfiguration.containerIdentifier else {
            status = .notConfigured
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
}
