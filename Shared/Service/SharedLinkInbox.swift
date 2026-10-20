//
//  SharedLinkInbox.swift
//  DuGo-iOS
//
//  Created by 김승원 on 1/10/26.
//

import Foundation

struct PendingSharedWish: Codable {
    // MARK: - Properties

    let id: UUID
    let createdAt: Date
    let link: String
    let title: String
    let categoryRaw: String
    let price: Int?
    let reason: String
    let reviewAt: Date?
    let wantsReminder: Bool?
    let imageData: Data?
}

enum SharedLinkInbox {
    // MARK: - Properties

    static let groupIdentifier: String = {
        guard
            let identifier = Bundle.main.object(
                forInfoDictionaryKey: "DuGoAppGroupIdentifier"
            ) as? String,
            !identifier.isEmpty
        else {
            return "group.app.seungwon.dugo"
        }

        return identifier
    }()

    // MARK: - Types

    enum InboxError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "공유 보관함을 열 수 없어요 두고의 App Group 설정을 확인해주세요"
        }
    }

    // MARK: - Methods

    static func enqueue(_ wish: PendingSharedWish) throws {
        let directory = try inboxDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(wish)
        try data.write(
            to: directory.appendingPathComponent("\(wish.id.uuidString).json"),
            options: .atomic
        )
    }

    static func pending() -> [PendingSharedWish] {
        guard let directory = try? inboxDirectory(),
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else { return [] }

        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode(PendingSharedWish.self, from: data)
        }
    }

    static func remove(id: UUID) throws {
        let file = try inboxDirectory().appendingPathComponent("\(id.uuidString).json")
        try FileManager.default.removeItem(at: file)
    }

    // MARK: - Private Methods

    private static func inboxDirectory() throws -> URL {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupIdentifier
            )
        else { throw InboxError.unavailable }
        return container.appendingPathComponent("PendingWishes", isDirectory: true)
    }
}
