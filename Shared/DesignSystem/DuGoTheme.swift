//
//  DuGoTheme.swift
//  DuGo-iOS
//
//  Created by 김승원 on 19/9/26.
//

import SwiftUI

enum DuGoTheme {
    static let background = Color("DuGoBackground")
    static let surface = Color("DuGoSurface")
    static let surfaceInset = Color("DuGoSurfaceInset")
    static let ink = Color("DuGoInk")
    static let secondary = Color("DuGoSecondary")
    static let accent = Color("DuGoAccent")
    static let button = Color("DuGoButton")
    static let toggle = accent
    static let onAccent = Color("DuGoOnAccent")
    static let complement = Color("DuGoComplement")
    static let border = Color("DuGoBorder")
}

struct DuGoScreenBackground: ViewModifier {
    // MARK: - Body

    func body(content: Content) -> some View {
        content
            .font(DuGoFont.body16Regular.font)
            .background(DuGoTheme.background)
            .tint(DuGoTheme.accent)
    }
}

extension View {

    // MARK: - Methods

    func dugoScreen() -> some View {
        modifier(DuGoScreenBackground())
    }
}
