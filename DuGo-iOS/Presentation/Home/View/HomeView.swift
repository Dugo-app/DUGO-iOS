//
//  HomeView.swift
//  DuGo-iOS
//
//  Created by 김승원 on 19/9/26.
//

import SwiftData
import SwiftUI

struct HomeView: View {
    // MARK: - Properties

    @ObservedObject private var viewModel: HomeViewModel
    private let reminders: ReminderManager
    private let cloudSyncConfigured: Bool
    private let onAddTapped: () -> Void
    private let scrollToTopRequest: Int
    @State private var openingMessage: String

    // MARK: - Initializer

    init(
        viewModel: HomeViewModel,
        reminders: ReminderManager,
        cloudSyncConfigured: Bool,
        onAddTapped: @escaping () -> Void,
        scrollToTopRequest: Int = 0
    ) {
        self.viewModel = viewModel
        self.reminders = reminders
        self.cloudSyncConfigured = cloudSyncConfigured
        self.onAddTapped = onAddTapped
        self.scrollToTopRequest = scrollToTopRequest
        _openingMessage = State(initialValue: DuGoGreeting.randomOpeningMessage)
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    introduction

                    if let message = viewModel.reminderNotice {
                        ReminderNoticeView(text: message)
                            .padding(16)
                            .background(DuGoTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }

                    if !viewModel.reviewItems.isEmpty {
                        reviewSection
                    }

                    collection
                }
                .id("home-scroll-top")
                .frame(maxWidth: 620)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                viewModel.resetFilters()
                await viewModel.refresh()
            }
            .onChange(of: scrollToTopRequest) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("home-scroll-top", anchor: .top)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnBackgroundTap()
        .dugoScreen()
        .dugoErrorToast(message: $viewModel.errorMessage)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            DuGoLogoImage(width: 30, height: 30)
                .foregroundStyle(DuGoTheme.accent)
                .padding(.leading, 4)

            Spacer()

            NavigationLink {
                SettingsView(
                    viewModel: viewModel,
                    reminders: reminders,
                    cloudSyncConfigured: cloudSyncConfigured
                )
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DuGoTheme.ink)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("설정")
        }
        .foregroundStyle(DuGoTheme.ink)
    }

    private var introduction: some View {
        Text(openingMessage)
            .applyDuGoFont(.display32SemiBold)
            .tracking(-1.4)
            .foregroundStyle(DuGoTheme.ink)
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("다시 살펴볼 마음")
                .applyDuGoFont(.body14Regular)
                .foregroundStyle(DuGoTheme.secondary)

            ReviewCarouselView(items: viewModel.reviewItems, viewModel: viewModel)
        }
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("담아 둔 마음")
                    .applyDuGoFont(.body14Regular)
                    .foregroundStyle(DuGoTheme.secondary)

                Text("\(viewModel.keptItems.count)")
                    .applyDuGoFont(.body14Medium)
                    .foregroundStyle(DuGoTheme.accent)

                Spacer()
            }

            searchField

            categories

            if viewModel.keptItems.isEmpty {
                emptyCollection(
                    title: "마음을 담아보세요",
                    message: "사고 싶은 물건의 링크만 있어도 괜찮아요",
                    buttonTitle: "마음 담기"
                ) {
                    onAddTapped()
                }
            } else if viewModel.filteredItems.isEmpty {
                emptyCollection(
                    title: "찾는 마음이 없어요",
                    message: "다른 검색어나 카테고리로 살펴보세요",
                    buttonTitle: "전체 보기"
                ) {
                    viewModel.resetFilters()
                }
            } else {
                DuGoMasonryLayout(
                    columns: 2,
                    horizontalSpacing: 12,
                    verticalSpacing: 16
                ) {
                    ForEach(viewModel.filteredItems) { item in
                        NavigationLink {
                            WishDetailView(item: item, viewModel: viewModel)
                        } label: {
                            WishCardView(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(DuGoTheme.secondary)
            TextField("어떤 물건을 담아두었나요?", text: $viewModel.searchText)
                .font(DuGoFont.body14Regular.font)
                .foregroundStyle(DuGoTheme.ink)
                .autocorrectionDisabled()
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DuGoTheme.secondary)
                        .frame(minWidth: 32, minHeight: 44)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background {
            Capsule()
                .fill(DuGoTheme.surface)
                .dugoShadow(.subtle)
        }
    }

    private var categories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton(nil)
                ForEach(viewModel.categories, id: \.self) { category in
                    categoryButton(category)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.horizontal, -24)
        .scrollClipDisabled()
    }

    private func categoryButton(_ category: String?) -> some View {
        let selected = viewModel.selectedCategory == category
        return DuGoCategoryChip(
            category: category,
            isSelected: selected
        ) {
            viewModel.selectedCategory = category
        }
    }

    private func emptyCollection(
        title: String,
        message: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .applyDuGoFont(.title18SemiBold)
                .foregroundStyle(DuGoTheme.ink)
                .frame(maxWidth: .infinity)

            Text(message)
                .applyDuGoFont(.caption12Regular)
                .foregroundStyle(DuGoTheme.secondary)
                .multilineTextAlignment(.center)

            DuGoPrimaryButton(title: buttonTitle, action: action)
                .frame(maxWidth: 180)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}
