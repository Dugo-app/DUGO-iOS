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

    // MARK: - Initializer

    init(
        name: String,
        sortOrder: Int,
        isDeleted: Bool = false,
        replacementName: String? = nil,
        updatedAt: Date = .now
    ) {
        self.name = name
        self.sortOrder = sortOrder
        self.isDeleted = isDeleted
        self.replacementName = replacementName
        self.updatedAt = updatedAt
    }
}
