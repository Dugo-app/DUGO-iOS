//
//  AppVersionMonitor.swift
//  DuGo-iOS
//
//  Created by 김승원 on 4/10/26.
//

import Combine
import FirebaseRemoteConfig
import Foundation
import OSLog

@MainActor
final class AppVersionMonitor: ObservableObject {
    // MARK: - Types

    private enum UpdateLevel {
        case none
        case optional
        case required
    }

    private struct AppVersion: Comparable {
        let components: [Int]
        let rawValue: String

        init?(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
            guard !parts.isEmpty else { return nil }

            var components: [Int] = []
            for part in parts {
                guard
                    !part.isEmpty,
                    part.utf8.allSatisfy({ (48...57).contains($0) }),
                    let number = Int(part)
                else {
                    return nil
                }
                components.append(number)
            }

            while components.count > 1 && components.last == 0 {
                components.removeLast()
            }

            self.components = components
            rawValue = trimmed
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            for index in 0..<max(lhs.components.count, rhs.components.count) {
                let left = index < lhs.components.count ? lhs.components[index] : 0
                let right = index < rhs.components.count ? rhs.components[index] : 0
                if left != right { return left < right }
            }
            return false
        }
    }

    private struct UpdatePolicy {
        let minimumVersion: AppVersion
        let latestVersion: AppVersion
        let appStoreURL: URL?
        let requiredMessage: String
        let optionalMessage: String
    }

    private struct LookupResponse: Decodable {
        let results: [StoreApp]
    }

    private struct StoreApp: Decodable {
        let bundleId: String
        let trackViewUrl: URL
    }

    private enum RemoteKey {
        static let minimumVersion = "minimum_supported_version"
        static let latestVersion = "latest_version"
        static let appStoreURL = "app_store_url"
        static let requiredMessage = "force_update_message"
        static let optionalMessage = "optional_update_message"

        static let updateKeys: Set<String> = [
            minimumVersion,
            latestVersion,
            appStoreURL,
            requiredMessage,
            optionalMessage
        ]
    }

    private enum CacheKey {
        static let storeURL = "dugo.latestVerifiedStoreURL"
        static let dismissedOptionalVersion = "dugo.dismissedOptionalUpdateVersion"
    }

    private enum DefaultValue {
        static let minimumVersion = "1.0.0"
        static let latestVersion = "1.0.0"
        static let requiredMessage = "두고를 계속 사용하려면 최신 버전으로 업데이트해 주세요"
        static let optionalMessage = "새로운 버전의 두고를 사용할 수 있어요"
    }

    // MARK: - Properties

    @Published private var updateLevel: UpdateLevel = .none
    @Published var isAlertPresented = false

    private(set) var appStoreURL: URL?
    private(set) var alertMessage = ""
    private var latestVersion: String?
    private var isChecking = false
    private var configListener: ConfigUpdateListenerRegistration?

    private let logger = Logger(subsystem: "app.seungwon.dugo", category: "updates")

    var isUpdateRequired: Bool {
        updateLevel == .required
    }

    var isUpdateAvailable: Bool {
        updateLevel != .none
    }

    var alertTitle: String {
        isUpdateRequired ? "업데이트가 필요해요" : "새로운 버전이 있어요"
    }

    // MARK: - Initializer

    init() {
        guard
            let urlString = UserDefaults.standard.string(forKey: CacheKey.storeURL),
            let url = URL(string: urlString),
            Self.isAppStoreURL(url)
        else {
            return
        }

        appStoreURL = url
    }

    // MARK: - Methods

    @discardableResult
    func checkForUpdate(
        ignoringDismissedVersion: Bool = false,
        forceRefresh: Bool = false
    ) async -> Bool {
        guard !isChecking else { return false }
        guard let installedVersion = Self.installedVersion else { return false }

        isChecking = true
        defer { isChecking = false }

        guard let policy = await fetchRemotePolicy(forceRefresh: forceRefresh) else { return false }

        if let remoteURL = policy.appStoreURL {
            cacheStoreURL(remoteURL)
        } else {
            await refreshStoreURL()
        }

        apply(
            policy,
            to: installedVersion,
            ignoringDismissedVersion: ignoringDismissedVersion
        )
        return true
    }

    func startListeningForUpdates() {
        guard FirebaseConfigurator.isConfigured, configListener == nil else { return }

        let remoteConfig = configuredRemoteConfig()
        configListener = remoteConfig.addOnConfigUpdateListener { [weak self] update, error in
            let errorMessage = error?.localizedDescription
            let hasPolicyChange = update?.updatedKeys.isDisjoint(with: RemoteKey.updateKeys) == false

            Task { @MainActor [weak self] in
                guard let self else { return }

                if let errorMessage {
                    self.logger.error("Remote Config listener failed: \(errorMessage)")
                    return
                }

                guard hasPolicyChange else { return }
                await self.activateRealtimePolicy()
            }
        }
    }

    func stopListeningForUpdates() {
        configListener?.remove()
        configListener = nil
    }

    func presentAlertIfNeeded() {
        guard updateLevel != .none else { return }
        isAlertPresented = true
    }

    func dismissOptionalUpdate() {
        guard updateLevel == .optional else { return }

        if let latestVersion {
            UserDefaults.standard.set(
                latestVersion,
                forKey: CacheKey.dismissedOptionalVersion
            )
        }

        updateLevel = .none
        isAlertPresented = false
    }

    // MARK: - Private Methods

    private func fetchRemotePolicy(forceRefresh: Bool) async -> UpdatePolicy? {
        guard FirebaseConfigurator.isConfigured else {
            logger.notice("Firebase is not configured; update policy check skipped")
            return nil
        }

        let remoteConfig = configuredRemoteConfig()

        do {
            if forceRefresh {
                let status = try await remoteConfig.fetch(withExpirationDuration: 0)
                guard status == .success else {
                    logger.error("Remote Config manual fetch did not succeed")
                    return nil
                }
                try await remoteConfig.activate()
            } else {
                try await remoteConfig.fetchAndActivate()
            }
        } catch {
            logger.error("Remote Config fetch failed: \(error.localizedDescription)")
            if forceRefresh { return nil }
        }

        return policy(from: remoteConfig)
    }

    private func configuredRemoteConfig() -> RemoteConfig {
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()

#if DEBUG
        settings.minimumFetchInterval = 0
#else
        settings.minimumFetchInterval = 3_600
#endif

        remoteConfig.configSettings = settings
        remoteConfig.setDefaults([
            RemoteKey.minimumVersion: DefaultValue.minimumVersion as NSObject,
            RemoteKey.latestVersion: DefaultValue.latestVersion as NSObject,
            RemoteKey.appStoreURL: "" as NSObject,
            RemoteKey.requiredMessage: DefaultValue.requiredMessage as NSObject,
            RemoteKey.optionalMessage: DefaultValue.optionalMessage as NSObject
        ])

        return remoteConfig
    }

    private func policy(from remoteConfig: RemoteConfig) -> UpdatePolicy? {
        let minimumString = remoteConfig[RemoteKey.minimumVersion].stringValue
        let latestString = remoteConfig[RemoteKey.latestVersion].stringValue

        guard let minimumVersion = AppVersion(minimumString) else {
            logger.error("Invalid minimum supported version: \(minimumString)")
            return nil
        }

        guard let configuredLatestVersion = AppVersion(latestString) else {
            logger.error("Invalid latest version: \(latestString)")
            return nil
        }

        let latestVersion = max(minimumVersion, configuredLatestVersion)
        let urlString = remoteConfig[RemoteKey.appStoreURL].stringValue
        let configuredURL = URL(string: urlString).flatMap { url in
            Self.isAppStoreURL(url) ? url : nil
        }
        let requiredMessage = message(
            remoteConfig[RemoteKey.requiredMessage].stringValue,
            fallback: DefaultValue.requiredMessage
        )
        let optionalMessage = message(
            remoteConfig[RemoteKey.optionalMessage].stringValue,
            fallback: DefaultValue.optionalMessage
        )

        return UpdatePolicy(
            minimumVersion: minimumVersion,
            latestVersion: latestVersion,
            appStoreURL: configuredURL,
            requiredMessage: requiredMessage,
            optionalMessage: optionalMessage
        )
    }

    private func activateRealtimePolicy() async {
        let remoteConfig = RemoteConfig.remoteConfig()

        do {
            try await remoteConfig.activate()
        } catch {
            logger.error("Remote Config activation failed: \(error.localizedDescription)")
            return
        }

        guard
            let installedVersion = Self.installedVersion,
            let policy = policy(from: remoteConfig)
        else {
            return
        }

        if let remoteURL = policy.appStoreURL {
            cacheStoreURL(remoteURL)
        } else {
            await refreshStoreURL()
        }

        apply(policy, to: installedVersion, ignoringDismissedVersion: false)
    }

    private func message(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func refreshStoreURL() async {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        do {
            let storeApp = try await fetchStoreApp(bundleID: bundleID)
            guard Self.isAppStoreURL(storeApp.trackViewUrl) else { return }
            cacheStoreURL(storeApp.trackViewUrl)
        } catch {
            logger.error("App Store lookup failed: \(error.localizedDescription)")
        }
    }

    private func apply(
        _ policy: UpdatePolicy,
        to installedVersion: AppVersion,
        ignoringDismissedVersion: Bool
    ) {
        latestVersion = policy.latestVersion.rawValue

        if installedVersion < policy.minimumVersion {
            guard appStoreURL != nil else {
                logger.error("Required update skipped because the App Store URL is unavailable")
                return
            }

            updateLevel = .required
            alertMessage = policy.requiredMessage
            isAlertPresented = true
            return
        }

        let dismissedVersion = UserDefaults.standard.string(
            forKey: CacheKey.dismissedOptionalVersion
        )

        if
            installedVersion < policy.latestVersion,
            (
                ignoringDismissedVersion ||
                dismissedVersion != policy.latestVersion.rawValue
            ),
            appStoreURL != nil
        {
            updateLevel = .optional
            alertMessage = policy.optionalMessage
            isAlertPresented = true
            return
        }

        updateLevel = .none
        isAlertPresented = false
    }

    private func cacheStoreURL(_ url: URL) {
        guard Self.isAppStoreURL(url) else { return }

        appStoreURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: CacheKey.storeURL)
    }

    private func fetchStoreApp(bundleID: String) async throws -> StoreApp {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: "kr"),
            URLQueryItem(name: "entity", value: "software")
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        let lookup = try JSONDecoder().decode(LookupResponse.self, from: data)
        guard let storeApp = lookup.results.first(where: { $0.bundleId == bundleID }) else {
            throw URLError(.resourceUnavailable)
        }
        return storeApp
    }

    private static var installedVersion: AppVersion? {
        guard
            let string = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        else {
            return nil
        }

        return AppVersion(string)
    }

    private static func isAppStoreURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "apps.apple.com"
    }
}
