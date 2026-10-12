//
//  AppEnvironment.swift
//  DuGo-iOS
//
//  Created by 김승원 on 12/10/26.
//

import Foundation

enum AppEnvironment {
    // MARK: - Properties

    static let shareHelpURL = configuredURL(forKey: "DuGoShareHelpURL")
    static let privacyPolicyURL = configuredURL(forKey: "DuGoPrivacyPolicyURL")

    // MARK: - Private Methods

    private static func configuredURL(forKey key: String) -> URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: value),
              url.scheme == "https",
              url.host != nil
        else {
            preconditionFailure("Missing or invalid app URL configuration: \(key)")
        }
        return url
    }
}
