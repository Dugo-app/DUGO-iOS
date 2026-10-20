//
//  DecisionRecord.swift
//  DuGo-iOS
//
//  Created by 김승원 on 19/9/26.
//

import Foundation
import SwiftData

@Model
final class DecisionRecord {
    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var title: String = ""
    var decisionRaw: String = "더 두기"
    var feeling: String = ""
    var note: String = ""
    var createdAt: Date = Date.now

    init(
        item: WishItem,
        decision: WishDecision,
        feeling: String = "",
        note: String = ""
    ) {
        id = UUID()
        itemID = item.id
        title = item.title
        decisionRaw = decision.rawValue
        self.feeling = feeling
        self.note = note
        createdAt = .now
    }
    var decision: WishDecision { WishDecision(rawValue: decisionRaw) ?? .wait }
}

enum WishDecision: String, CaseIterable, Identifiable {
    case purchase = "구매하기"
    case wait = "더 두기"
    case release = "보내주기"
    case restore = "다시 담기"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .purchase: "bag"
        case .wait: "clock"
        case .release: "hand.palm.facing"
        case .restore: "arrow.down.heart"
        }
    }

    var message: String {
        switch self {
        case .purchase: "충분히 생각하고 선택했어요"
        case .wait: "아직 결정하지 않아도 괜찮아요"
        case .release: "지금의 나에게는 필요하지 않았어요"
        case .restore: "다시 살펴보고 싶은 마음을 담았어요"
        }
    }

    var subMessage: String {
        switch self {
        case .purchase: "구매 기록을 남겼어요!"
        case .wait: "준비가 되면 그때 다시 봐요!"
        case .release: "마음이 바뀌면 언제든 다시 담을 수 있어요!"
        case .restore: "다시 한번 천천히 살펴봐요!"
        }
    }
}
