//
//  DuGo_iOSApp.swift
//  DuGo-iOS
//
//  Created by 김승원 on 19/9/26.
//

import CoreData
import OSLog
import SwiftData
import SwiftUI

@main
struct DuGo_iOSApp: App {

    // MARK: - Properties

    @StateObject private var reminders: ReminderManager
    private let container: ModelContainer?
    private let cloudSyncConfigured: Bool

    // MARK: - Initializer

    init() {
        FirebaseConfigurator.configure()

        let manager = ReminderManager()
        manager.start()
        _reminders = StateObject(wrappedValue: manager)
        let schema = Schema([WishItem.self, DecisionRecord.self, CategoryEntry.self])
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let storeURL = appSupport.appendingPathComponent("DoGo.store")
        let logger = Logger(subsystem: "app.seungwon.dugo", category: "storage")
        var resolvedContainer: ModelContainer?
        var isCloudConfigured = false

        do {
            try LegacyStoreBackup.createIfNeeded(for: storeURL)
        } catch {
            logger.error("Existing storage backup failed: \(error.localizedDescription)")
            container = nil
            cloudSyncConfigured = false
            return
        }

        #if DEBUG
        if let identifier = CloudSyncConfiguration.containerIdentifier {
            do {
                do {
                    try CloudKitSchemaInitializer.initializeIfNeeded(
                        storeURL: storeURL,
                        containerIdentifier: identifier
                    )
                } catch {
                    logger.error("CloudKit schema initialization failed: \(error.localizedDescription)")
                }

                let configuration = ModelConfiguration(
                    "DoGo",
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: .private(identifier)
                )
                resolvedContainer = try ModelContainer(
                    for: schema,
                    configurations: configuration
                )
                isCloudConfigured = true
            } catch {
                logger.error("Cloud storage initialization failed: \(error.localizedDescription)")
            }
        }
        #endif

        if resolvedContainer == nil {
            do {
                let configuration = ModelConfiguration(
                    "DoGo",
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: .none
                )
                resolvedContainer = try ModelContainer(
                    for: schema,
                    configurations: configuration
                )
            } catch {
                logger.error("Local storage initialization failed: \(error.localizedDescription)")
            }
        }

        container = resolvedContainer
        cloudSyncConfigured = isCloudConfigured
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ForceUpdateGate {
                SplashContainer {
                    OnboardingContainer {
                        if let container {
                            ContentView(
                                context: container.mainContext,
                                reminders: reminders,
                                cloudSyncConfigured: cloudSyncConfigured
                            )
                                .modelContainer(container)
                        } else {
                            ContentUnavailableView(
                                "보관함을 열지 못했어요",
                                systemImage: "externaldrive.badge.exclamationmark",
                                description: Text("앱을 다시 실행해주세요 문제가 계속되면 저장 공간을 확인해주세요")
                            )
                        }
                    }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSPersistentCloudKitContainer.eventChangedNotification
                )
            ) { notification in
                guard let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event else { return }
                CloudSyncMonitor.recordSuccessfulSync(event)
            }
        }
    }
}

private enum LegacyStoreBackup {
    // MARK: - Methods

    static func createIfNeeded(for storeURL: URL) throws {
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directory.path) else { return }

        let backupURL = directory.appendingPathComponent("DoGoPreCloudBackup", isDirectory: true)
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }

        let storeName = storeURL.lastPathComponent
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { url in
            let name = url.lastPathComponent
            return name == storeName
                || name.hasPrefix(storeName + "-")
                || name.hasPrefix(storeName + "_")
                || name.hasPrefix("." + storeName + "_")
        }
        guard !files.isEmpty else { return }

        let stagingURL = directory.appendingPathComponent(
            "DoGoPreCloudBackup-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: stagingURL) }

        for file in files {
            try fileManager.copyItem(
                at: file,
                to: stagingURL.appendingPathComponent(file.lastPathComponent)
            )
        }
        try fileManager.moveItem(at: stagingURL, to: backupURL)
    }
}
