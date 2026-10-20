//
//  CloudKitSchemaInitializer.swift
//  DuGo-iOS
//
//  Created by 김승원 on 12/10/26.
//

#if DEBUG
import CoreData
import Foundation
import SwiftData

enum CloudKitSchemaInitializer {
    // MARK: - Properties

    private static let schemaVersion = 1

    // MARK: - Methods

    static func initializeIfNeeded(
        storeURL: URL,
        containerIdentifier: String
    ) throws {
        let marker = "cloudKitDevelopmentSchema.v\(schemaVersion).\(containerIdentifier)"
        guard !UserDefaults.standard.bool(forKey: marker) else { return }

        try autoreleasepool {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(
                for: [WishItem.self, DecisionRecord.self, CategoryEntry.self]
            ) else {
                throw SchemaInitializationError.modelUnavailable
            }

            let description = NSPersistentStoreDescription(url: storeURL)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: containerIdentifier
            )
            description.shouldAddStoreAsynchronously = false

            let container = NSPersistentCloudKitContainer(
                name: "DoGo",
                managedObjectModel: model
            )
            container.persistentStoreDescriptions = [description]

            var loadError: Error?
            container.loadPersistentStores { _, error in
                loadError = error
            }
            if let loadError { throw loadError }

            do {
                try container.initializeCloudKitSchema()
                if let store = container.persistentStoreCoordinator.persistentStores.first {
                    try container.persistentStoreCoordinator.remove(store)
                }
            } catch {
                if let store = container.persistentStoreCoordinator.persistentStores.first {
                    try? container.persistentStoreCoordinator.remove(store)
                }
                throw error
            }
        }

        UserDefaults.standard.set(true, forKey: marker)
    }
}

private enum SchemaInitializationError: Error {
    case modelUnavailable
}
#endif
