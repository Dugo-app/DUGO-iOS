//
//  CategoryEntry.swift
//  DuGo-iOS
//
//  Created by 김승원 on 12/10/26.
//

import Foundation
import SwiftData

@Model
final class CategoryEntry {
    // MARK: - Properties

    var name: String = ""
    var sortOrder: Int = 0
    var isDeleted: Bool = false
    var replacementName: String?
    var updatedAt: Date = Date.now

    // MARK: - Computed Properties

    var isRemoved: Bool { replacementName != nil }

    // MARK: - Initializer

    init(
        name: String,
        sortOrder: Int,
        isRemoved: Bool = false,
        replacementName: String? = nil,
        updatedAt: Date = .now
    ) {
        self.name = name
        self.sortOrder = sortOrder
        self.replacementName = isRemoved ? (replacementName ?? WishCategory.other.rawValue) : nil
        self.updatedAt = updatedAt
    }
}
