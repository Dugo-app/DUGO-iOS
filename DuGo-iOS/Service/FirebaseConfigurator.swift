//
//  FirebaseConfigurator.swift
//  DuGo-iOS
//
//  Created by 김승원 on 8/10/26.
//

import FirebaseCore
import Foundation
import OSLog

enum FirebaseConfigurator {
    // MARK: - Properties

    private static let logger = Logger(
        subsystem: "app.seungwon.dugo",
        category: "firebase"
    )

    private(set) static var isConfigured = false

    // MARK: - Methods

    static func configure() {
        if FirebaseApp.app() != nil {
            isConfigured = true
            return
        }

        let configuration = AppEnvironment.firebase
        guard configuration.bundleID == Bundle.main.bundleIdentifier else {
            logger.error("Firebase configuration bundle ID does not match the app")
            return
        }

        let options = FirebaseOptions(
            googleAppID: configuration.googleAppID,
            gcmSenderID: configuration.gcmSenderID
        )
        options.apiKey = configuration.apiKey
        options.projectID = configuration.projectID
        options.bundleID = configuration.bundleID
        options.storageBucket = configuration.storageBucket

        FirebaseApp.configure(options: options)
        isConfigured = true
    }
}
