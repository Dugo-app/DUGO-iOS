//
//  OnboardingView.swift
//  DuGo-iOS
//
//  Created by 김승원 on 4/10/26.
//

import SwiftUI

struct OnboardingContainer<Content: View>: View {
    // MARK: - Properties

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var isFadingOut = false

    private let content: Content

    // MARK: - Initializer

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if isFadingOut || hasCompletedOnboarding {
                content
            }

            if !hasCompletedOnboarding {
                OnboardingView(onComplete: completeOnboarding)
                    .environment(\.colorScheme, .light)
                    .preferredColorScheme(isFadingOut ? nil : .light)
                    .opacity(isFadingOut ? 0 : 1)
                    .allowsHitTesting(!isFadingOut)
            }
        }
    }

    // MARK: - Methods

    private func completeOnboarding() {
        guard !isFadingOut else { return }

        withAnimation(.easeInOut(duration: 0.45)) {
            isFadingOut = true
        }

        Task {
            try? await Task.sleep(for: .milliseconds(450))
            hasCompletedOnboarding = true
        }
    }
}

struct OnboardingView: View {
    // MARK: - Types

    private struct Page: Identifiable {
        let id: Int
        let title: String
        let description: String
        let illustration: Illustration
    }

    private enum Illustration {
        case intro
        case share
        case reminder
        case decision
    }

    // MARK: - Properties

    @State private var selectedPage = 0
    @State private var activePage: Int?

    private let completionTitle: String
    private let onComplete: () -> Void

    private let pages = [
        Page(
            id: 0,
            title: "마음은 담고\n결정은 두고",
            description: "사고 싶은 순간부터\n결정하는 순간까지 함께해요",
            illustration: .intro
        ),
        Page(
            id: 1,
            title: "사고 싶은 순간\n바로 담아두기",
            description: "다른 앱에서 상품 링크를 공유하면\n상품 정보를 간편하게 채워드려요",
            illustration: .share
        ),
        Page(
            id: 2,
            title: "다시 볼 날을\n정해두기",
            description: "마음을 다시 확인할 날을 정하면\n잊지 않도록 알려드려요",
            illustration: .reminder
        ),
        Page(
            id: 3,
            title: "충분히 생각하고\n나답게 결정하기",
            description: "처음 담아둔 이유를 돌아보고\n지금의 마음을 결정해요",
            illustration: .decision
        )
    ]

    // MARK: - Initializer

    init(
        completionTitle: String = "두고 시작하기",
        onComplete: @escaping () -> Void
    ) {
        self.completionTitle = completionTitle
        self.onComplete = onComplete
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedPage) {
                ForEach(pages) { page in
                    pageView(page)
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            pageIndicator

            bottomAction
        }
        .background(DuGoTheme.background)
        .foregroundStyle(DuGoTheme.ink)
        .dugoScreen()
        .task(id: selectedPage) {
            activePage = nil
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled else { return }
            activePage = selectedPage
        }
    }

    // MARK: - Subviews

    private func pageView(_ page: Page) -> some View {
        let isActive = activePage == page.id

        return VStack(spacing: 0) {
            Spacer(minLength: 48)

            illustration(for: page.illustration, isActive: isActive)
                .frame(maxHeight: 300)

            Spacer(minLength: 44)

            VStack(spacing: 16) {
                Text(page.title)
                    .applyDuGoFont(.display32SemiBold)
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .applyDuGoFont(.body16Regular)
                    .foregroundStyle(DuGoTheme.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 16)
            .animation(.easeOut(duration: 0.45).delay(0.15), value: isActive)

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 28)
    }

    @ViewBuilder
    private func illustration(
        for illustration: Illustration,
        isActive: Bool
    ) -> some View {
        switch illustration {
        case .intro:
            introIllustration(isActive: isActive)
        case .share:
            shareIllustration(isActive: isActive)
        case .reminder:
            reminderIllustration(isActive: isActive)
        case .decision:
            decisionIllustration(isActive: isActive)
        }
    }

    private func introIllustration(isActive: Bool) -> some View {
        ZStack {
            illustrationBackground(color: DuGoTheme.accent, isActive: isActive)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(DuGoTheme.accent.opacity(0.18))
                .frame(width: 225, height: 158)
                .rotationEffect(.degrees(isActive ? 8 : 19))
                .offset(x: isActive ? 9 : 36, y: isActive ? -7 : 28)
                .opacity(isActive ? 1 : 0)
                .animation(.spring(response: 0.72, dampingFraction: 0.72), value: isActive)

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("오늘 담은 마음")
                        .applyDuGoFont(.caption12Medium)
                        .foregroundStyle(DuGoTheme.secondary)

                    Spacer()

                    Circle()
                        .fill(DuGoTheme.accent)
                        .frame(width: 7, height: 7)
                }

                HStack(spacing: 11) {
                    Image(systemName: "bag")
                        .font(.system(size: 27, weight: .regular))
                        .foregroundStyle(DuGoTheme.accent)
                        .frame(width: 54, height: 54)
                        .background(
                            DuGoTheme.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("마음에 남은 상품")
                            .applyDuGoFont(.body14Medium)
                            .foregroundStyle(DuGoTheme.ink)

                        Text("잠시 여기 두어요")
                            .applyDuGoFont(.caption12Regular)
                            .foregroundStyle(DuGoTheme.secondary)
                    }

                    Spacer(minLength: 0)
                }

                Label("나중에 다시 보기", systemImage: "clock")
                    .applyDuGoFont(.caption12Medium)
                    .foregroundStyle(DuGoTheme.accent)
            }
            .padding(16)
            .frame(width: 228)
            .dugoRoundedSurface(cornerRadius: 22)
            .rotationEffect(.degrees(isActive ? -4 : 8))
            .offset(x: isActive ? -5 : -32, y: isActive ? 5 : 35)
            .scaleEffect(isActive ? 1 : 0.82)
            .opacity(isActive ? 1 : 0)
            .animation(.spring(response: 0.72, dampingFraction: 0.68).delay(0.1), value: isActive)

            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))

                Text("마음에 담았어요")
                    .applyDuGoFont(.caption12Medium)
            }
            .foregroundStyle(DuGoTheme.accent)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .dugoRoundedSurface(cornerRadius: 19)
            .rotationEffect(.degrees(isActive ? 5 : -8))
            .offset(x: isActive ? 47 : 78, y: isActive ? 100 : 125)
            .scaleEffect(isActive ? 1 : 0.75)
            .opacity(isActive ? 1 : 0)
            .animation(
                .spring(response: 0.62, dampingFraction: 0.68).delay(0.42),
                value: isActive
            )
        }
        .frame(width: 240, height: 240)
    }

    private func shareIllustration(isActive: Bool) -> some View {
        ZStack {
            illustrationBackground(color: DuGoTheme.accent, isActive: isActive)

            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(DuGoTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(
                        DuGoTheme.accent.opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("상품 링크 공유")
                        .applyDuGoFont(.body14Medium)
                        .foregroundStyle(DuGoTheme.ink)

                    Text("다른 앱에서 보냈어요")
                        .applyDuGoFont(.caption12Regular)
                        .foregroundStyle(DuGoTheme.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: 219, height: 62)
            .dugoRoundedSurface(cornerRadius: 16)
            .rotationEffect(.degrees(isActive ? -7 : -15))
            .offset(x: isActive ? -12 : -45, y: isActive ? -70 : -36)
            .opacity(isActive ? 1 : 0)
            .animation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.06), value: isActive)

            VStack(alignment: .leading, spacing: 13) {
                Text("마음 담기")
                    .applyDuGoFont(.caption12Medium)
                    .foregroundStyle(DuGoTheme.secondary)

                HStack(spacing: 11) {
                    Image(systemName: "bag")
                        .font(.system(size: 25, weight: .regular))
                        .foregroundStyle(DuGoTheme.accent)
                        .frame(width: 54, height: 54)
                        .background(
                            DuGoTheme.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("공유한 상품")
                            .applyDuGoFont(.body14Medium)
                            .foregroundStyle(DuGoTheme.ink)

                        Text("상품 정보를 불러왔어요")
                            .applyDuGoFont(.caption12Regular)
                            .foregroundStyle(DuGoTheme.secondary)
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(16)
            .frame(width: 228)
            .dugoRoundedSurface(cornerRadius: 22)
            .rotationEffect(.degrees(isActive ? 3 : 10))
            .offset(x: isActive ? 4 : 40, y: isActive ? 20 : 57)
            .scaleEffect(isActive ? 1 : 0.82)
            .opacity(isActive ? 1 : 0)
            .animation(.spring(response: 0.72, dampingFraction: 0.7).delay(0.19), value: isActive)

            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))

                Text("링크로 담았어요")
                    .applyDuGoFont(.caption12Medium)
            }
            .foregroundStyle(DuGoTheme.accent)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .dugoRoundedSurface(cornerRadius: 19)
            .rotationEffect(.degrees(isActive ? -4 : 8))
            .offset(x: isActive ? 36 : 75, y: isActive ? 111 : 139)
            .scaleEffect(isActive ? 1 : 0.75)
            .opacity(isActive ? 1 : 0)
            .animation(.spring(response: 0.62, dampingFraction: 0.68).delay(0.48), value: isActive)
        }
        .frame(width: 240, height: 240)
    }

    private func reminderIllustration(isActive: Bool) -> some View {
        ZStack {
            illustrationBackground(color: DuGoTheme.complement, isActive: isActive)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(DuGoTheme.complement.opacity(0.16))
                .frame(width: 219, height: 154)
                .rotationEffect(.degrees(isActive ? 7 : 17))
                .offset(x: isActive ? 10 : 38, y: isActive ? -6 : 24)
                .opacity(isActive ? 1 : 0)
                .animation(.spring(response: 0.72, dampingFraction: 0.72), value: isActive)

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("다시 만나는 날")
                        .applyDuGoFont(.caption12Medium)
                        .foregroundStyle(DuGoTheme.secondary)

                    Spacer()

                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DuGoTheme.complement)
                }

                HStack(spacing: 6) {
                    reminderDateChip("내일", isSelected: false)
                    reminderDateChip("3일 뒤", isSelected: true)
                    reminderDateChip("5일 뒤", isSelected: false)
                }

                HStack(spacing: 7) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DuGoTheme.complement)

                    Text("알림 받기")
                        .applyDuGoFont(.caption12Medium)
                        .foregroundStyle(DuGoTheme.ink)

                    Spacer()

                    Text(ReminderTimePreference.displayText)
                        .applyDuGoFont(.caption12Regular)
                        .foregroundStyle(DuGoTheme.secondary)
                }
            }
            .padding(15)
            .frame(width: 228)
            .dugoRoundedSurface(cornerRadius: 22)
            .rotationEffect(.degrees(isActive ? -3 : 7))
            .offset(x: isActive ? -4 : -34, y: isActive ? 10 : 42)
            .scaleEffect(isActive ? 1 : 0.82)
            .opacity(isActive ? 1 : 0)
            .animation(.spring(response: 0.72, dampingFraction: 0.7).delay(0.1), value: isActive)

            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))

                Text("알림을 설정했어요")
                    .applyDuGoFont(.caption12Medium)
            }
            .foregroundStyle(DuGoTheme.complement)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .dugoRoundedSurface(cornerRadius: 19)
            .rotationEffect(.degrees(isActive ? 5 : -7))
            .offset(x: isActive ? 39 : 76, y: isActive ? 109 : 138)
            .scaleEffect(isActive ? 1 : 0.75)
            .opacity(isActive ? 1 : 0)
            .animation(.spring(response: 0.62, dampingFraction: 0.68).delay(0.46), value: isActive)
        }
        .frame(width: 240, height: 240)
    }

    private func reminderDateChip(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .applyDuGoFont(.caption12Medium)
            .foregroundStyle(isSelected ? DuGoTheme.onAccent : DuGoTheme.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 33)
            .background(
                isSelected ? DuGoTheme.accent : DuGoTheme.surfaceInset,
                in: Capsule()
            )
    }

    private func decisionIllustration(isActive: Bool) -> some View {
        ZStack {
            illustrationBackground(color: DuGoTheme.accent, isActive: isActive)

            VStack(alignment: .leading, spacing: 8) {
                Text("지금의 마음")
                    .applyDuGoFont(.caption12Medium)
                    .foregroundStyle(DuGoTheme.secondary)
                    .padding(.bottom, 2)

                decisionChoice(.purchase, isSelected: true, delay: 0.18, isActive: isActive)
                decisionChoice(.wait, isSelected: false, delay: 0.3, isActive: isActive)
                decisionChoice(.release, isSelected: false, delay: 0.42, isActive: isActive)
            }
            .padding(14)
            .frame(width: 228)
            .dugoRoundedSurface(cornerRadius: 22)
            .rotationEffect(.degrees(isActive ? -2 : 5))
            .offset(y: isActive ? 7 : 38)
            .scaleEffect(isActive ? 1 : 0.84)
            .opacity(isActive ? 1 : 0)
            .animation(.spring(response: 0.72, dampingFraction: 0.72).delay(0.08), value: isActive)

            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DuGoTheme.accent)
                    .frame(width: 3, height: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text("결정 기록")
                        .applyDuGoFont(.caption12Medium)
                        .foregroundStyle(DuGoTheme.secondary)

                    Text("구매하기 · 오늘")
                        .applyDuGoFont(.body14Medium)
                        .foregroundStyle(DuGoTheme.ink)
                }

                Spacer(minLength: 0)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DuGoTheme.accent)
            }
            .padding(.horizontal, 12)
            .frame(width: 179, height: 52)
            .dugoRoundedSurface(cornerRadius: 15)
            .rotationEffect(.degrees(isActive ? 4 : 13))
            .offset(x: isActive ? 37 : 83, y: isActive ? 132 : 159)
            .scaleEffect(isActive ? 1 : 0.72)
            .opacity(isActive ? 1 : 0)
            .animation(.spring(response: 0.64, dampingFraction: 0.7).delay(0.53), value: isActive)
        }
        .frame(width: 240, height: 240)
    }

    private func decisionChoice(
        _ decision: WishDecision,
        isSelected: Bool,
        delay: Double,
        isActive: Bool
    ) -> some View {
        HStack(spacing: 9) {
            DuGoDecisionIcon(decision: decision, size: 19, color: DuGoTheme.accent)

            Text(decision.rawValue)
                .applyDuGoFont(.body14Medium)
                .foregroundStyle(DuGoTheme.ink)

            Spacer(minLength: 0)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DuGoTheme.accent.opacity(isSelected ? 1 : 0.38))
        }
        .padding(.horizontal, 11)
        .frame(height: 40)
        .background(
            isSelected ? DuGoTheme.accent.opacity(0.12) : DuGoTheme.surfaceInset,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .offset(x: isActive ? 0 : -22)
        .opacity(isActive ? 1 : 0)
        .animation(.spring(response: 0.58, dampingFraction: 0.76).delay(delay), value: isActive)
    }

    private func illustrationBackground(
        color: Color,
        isActive: Bool
    ) -> some View {
        Circle()
            .fill(color.opacity(0.12))
            .frame(width: 220, height: 220)
            .scaleEffect(isActive ? 1 : 0.76)
            .opacity(isActive ? 1 : 0)
            .animation(.spring(response: 0.62, dampingFraction: 0.75), value: isActive)
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages) { page in
                Capsule()
                    .fill(
                        page.id == selectedPage
                            ? DuGoTheme.accent
                            : DuGoTheme.secondary.opacity(0.25)
                    )
                    .frame(
                        width: page.id == selectedPage ? 24 : 8,
                        height: 8
                    )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedPage)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var bottomAction: some View {
        if selectedPage == pages.count - 1 {
            DuGoPrimaryButton(title: completionTitle, action: onComplete)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        } else {
            Button {
                selectedPage += 1
            } label: {
                Text("다음")
                    .applyDuGoFont(.button16Medium)
                    .foregroundStyle(DuGoTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }
}
