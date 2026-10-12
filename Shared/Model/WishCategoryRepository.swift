//
//  WishCategoryRepository.swift
//  DuGo-iOS
//
//  Created by 김승원 on 1/10/26.
//

import Foundation

enum WishCategory: String, CaseIterable {
    case digital = "디지털"
    case fashion = "패션"
    case living = "생활"
    case hobby = "취미"
    case other = "미분류"
}

struct WishCategoryRepository {
    static let appGroupIdentifier = SharedLinkInbox.groupIdentifier
    static let storageKey = "wishCategories.v1"
    static let defaultCategories = WishCategory.allCases.map(\.rawValue)

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)) {
        self.defaults = defaults ?? .standard
    }

    func load() -> [String] {
        guard let saved = defaults.stringArray(forKey: Self.storageKey) else {
            return Self.defaultCategories
        }

        let categories = Self.normalized(saved)
        return categories.isEmpty ? [WishCategory.other.rawValue] : categories
    }

    func save(_ categories: [String]) {
        defaults.set(Self.normalized(categories), forKey: Self.storageKey)
    }

    private static func normalized(_ categories: [String]) -> [String] {
        var seen = Set<String>()
        var result = categories.compactMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 5, seen.insert(trimmed).inserted else {
                return nil
            }
            return trimmed
        }

        let uncategorized = WishCategory.other.rawValue
        result.removeAll { $0 == uncategorized }
        result.append(uncategorized)
        return result
    }
}

enum WishCategoryManagementError: LocalizedError {
    case empty
    case tooLong
    case duplicate
    case limitReached
    case protected
    case missing
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .empty:
            "카테고리 이름을 입력해주세요"
        case .tooLong:
            "카테고리는 최대 5글자까지 입력할 수 있어요"
        case .duplicate:
            "이미 같은 이름의 카테고리가 있어요"
        case .limitReached:
            "카테고리는 최대 10개까지 만들 수 있어요"
        case .protected:
            "미분류 카테고리는 수정하거나 삭제할 수 없어요"
        case .missing:
            "카테고리를 찾지 못했어요 다시 시도해주세요"
        case .saveFailed:
            "카테고리 변경을 저장하지 못했어요"
        }
    }
}
