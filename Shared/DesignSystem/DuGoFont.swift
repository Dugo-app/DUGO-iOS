//
//  DuGoFont.swift
//  DuGo-iOS
//
//  Created by 김승원 on 20/9/26.
//

import SwiftUI
import UIKit

enum DuGoFont {
    case display32SemiBold
    case display24SemiBold
    case title18SemiBold
    case title17Medium
    case title16Medium
    case body16Medium
    case body16Regular
    case body14Medium
    case body14Regular
    case button16Medium
    case button14Medium
    case caption14Regular
    case caption12Medium
    case caption12Regular

    // MARK: - Font Properties

    private var size: CGFloat {
        switch self {
        case .display32SemiBold: 32
        case .display24SemiBold: 24
        case .title18SemiBold: 18
        case .title17Medium: 17
        case .title16Medium, .body16Medium, .body16Regular, .button16Medium: 16
        case .body14Medium, .body14Regular, .button14Medium, .caption14Regular: 14
        case .caption12Medium, .caption12Regular: 12
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .display32SemiBold: 38
        case .display24SemiBold: 30
        case .title18SemiBold: 23
        case .title16Medium: 21
        case .title17Medium: 20
        case .body16Medium, .body16Regular: 19
        case .body14Medium, .body14Regular: 19
        case .button16Medium: 21
        case .button14Medium: 18
        case .caption14Regular: 20
        case .caption12Medium, .caption12Regular: 18
        }
    }

    private var fontName: String {
        switch self {
        case .display32SemiBold, .display24SemiBold, .title18SemiBold:
            "Pretendard-SemiBold"
        case .body16Regular, .body14Regular, .caption14Regular, .caption12Regular:
            "Pretendard-Regular"
        case .title16Medium, .body16Medium, .body14Medium, .button16Medium, .button14Medium,
            .caption12Medium, .title17Medium:
            "Pretendard-Medium"
        }
    }

    private var fallbackWeight: UIFont.Weight {
        switch self {
        case .display32SemiBold, .display24SemiBold, .title18SemiBold:
            .semibold
        case .body16Regular, .body14Regular, .caption14Regular, .caption12Regular:
            .regular
        case .title16Medium, .body16Medium, .body14Medium, .button16Medium, .button14Medium,
            .caption12Medium, .title17Medium:
            .medium
        }
    }

    var uiFont: UIFont {
        UIFont(name: fontName, size: size) ?? .systemFont(ofSize: size, weight: fallbackWeight)
    }

    var font: Font {
        Font(uiFont)
    }
}

// MARK: - DuGoFontModifier

private struct DuGoFontModifier: ViewModifier {
    let style: DuGoFont

    func body(content: Content) -> some View {
        let font = style.uiFont
        let verticalPadding = max(0, (style.lineHeight - font.lineHeight) / 2)

        content
            .font(Font(font))
            .lineSpacing(max(0, style.lineHeight - font.lineHeight))
            .kerning(0)
            .padding(.vertical, verticalPadding)
    }
}

extension View {
    func applyDuGoFont(_ style: DuGoFont) -> some View {
        modifier(DuGoFontModifier(style: style))
    }
}
