//
//  AppEnvironment.swift
//  DuGo-iOS
//
//  Created by 김승원 on 12/10/26.
//

import Foundation

enum AppEnvironment {
    // MARK: - Properties

    static let shareHelpURL = configuredURL(configuration.shareHelpURL)
    static let privacyPolicyURL = configuredURL(configuration.privacyPolicyURL)

    static var firebase: FirebaseConfiguration {
#if DUGO_DEV
        configuration.firebase.development
#else
        configuration.firebase.release
#endif
    }

    private static let configuration: Configuration = {
        guard
            let url = Bundle.main.url(forResource: "AppConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let configuration = try? PropertyListDecoder().decode(Configuration.self, from: data)
        else {
            preconditionFailure("Missing or invalid AppConfig.plist")
        }

        return configuration
    }()

    // MARK: - Private Methods

    private static func configuredURL(_ value: String) -> URL {
        guard let url = URL(string: value),
              url.scheme == "https",
              url.host != nil
        else {
            preconditionFailure("Missing or invalid app URL in AppConfig.plist")
        }
        return url
    }

    private struct Configuration: Decodable {
        let shareHelpURL: String
        let privacyPolicyURL: String
        let firebase: FirebaseEnvironments
    }

    private struct FirebaseEnvironments: Decodable {
        let development: FirebaseConfiguration
        let release: FirebaseConfiguration
    }

    struct FirebaseConfiguration: Decodable {
        let apiKey: String
        let gcmSenderID: String
        let googleAppID: String
        let projectID: String
        let bundleID: String
        let storageBucket: String
    }
}
