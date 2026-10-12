//
//  WishItem.swift
//  DuGo-iOS
//
//  Created by 김승원 on 19/9/26.
//

import Foundation
import SwiftData

@Model
final class WishItem {
    var id: UUID = UUID()
    var title: String = ""
    var link: String = ""
    var categoryRaw: String = "미분류"
    var price: Int?
    var reason: String = ""
    var initialReason: String = ""
    var createdAt: Date = Date.now
    var reviewAt: Date?
    var wantsReminder: Bool = false
    var statusRaw: String = "keeping"
    @Attribute(.externalStorage) var imageData: Data?

    init(
        title: String,
        link: String,
        category: WishCategory = .other,
        price: Int? = nil,
        reason: String = "",
        reviewAt: Date? = nil,
        wantsReminder: Bool = false,
        imageData: Data? = nil
    ) {
        id = UUID()
        self.title = title
        self.link = link
        categoryRaw = category.rawValue
        self.price = price
        self.reason = reason
        initialReason = reason
        createdAt = .now
        self.reviewAt = reviewAt
        self.wantsReminder = wantsReminder
        statusRaw = WishStatus.keeping.rawValue
        self.imageData = imageData
    }

    var category: WishCategory { WishCategory(rawValue: categoryRaw) ?? .other }
    var status: WishStatus { WishStatus(rawValue: statusRaw) ?? .keeping }
    var daysStored: Int {
        let calendar = Calendar.current
        return max(
            0,
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: createdAt),
                to: calendar.startOfDay(for: .now)
            ).day ?? 0
        )
    }
    var storedDescription: String { daysStored == 0 ? "오늘 담았어요" : "\(daysStored)일째 담아두는 중" }

    var reviewDueDescription: String {
        guard let reviewAt else { return "오늘 다시 보기" }

        let calendar = Calendar.current
        let daysPast = max(
            0,
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: reviewAt),
                to: calendar.startOfDay(for: .now)
            ).day ?? 0
        )

        return daysPast == 0 ? "오늘 다시 보기" : "\(daysPast)일 지났어요"
    }
}

enum WishStatus: String {
    case keeping, purchased, released
    var title: String {
        switch self {
        case .keeping: "담아두는 중"
        case .purchased: "구매하기로 했어요"
        case .released: "보내준 마음"
        }
    }
}

extension WishDraft {
    init(item: WishItem?) {
        self.init()
        guard let item else { return }

        link = item.link
        title = item.title
        category = item.categoryRaw
        price = item.price.map(String.init) ?? ""
        reason = item.reason
        imageData = item.imageData
        hasReviewDate = item.reviewAt != nil
        reviewDate = item.reviewAt ?? reviewDate
        wantsReminder = item.wantsReminder
    }
}
