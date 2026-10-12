//
//  ContentView.swift
//  DuGo-iOS
//
//  Created by 김승원 on 19/9/26.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    // MARK: - Types

    enum AppTab {
        case home
        case add
        case records
    }

    // MARK: - Properties

    @StateObject private var viewModel: HomeViewModel
    @ObservedObject private var reminders: ReminderManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: AppTab = .home
    @State private var tabActionHandler = DuGoTabActionHandler(actionTabIndex: 1)
    @State private var notificationItem: WishItem?
    @State private var isPresentingEditor = false
    @State private var homeScrollToTopRequest = 0
    @State private var recordsScrollToTopRequest = 0

    // MARK: - Initializer

    init(context: ModelContext, reminders: ReminderManager) {
        _viewModel = StateObject(
            wrappedValue: HomeViewModel(context: context, reminders: reminders)
        )
        self.reminders = reminders
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            tabContent
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .tint(DuGoTheme.accent)
        .task {
            await viewModel.refresh()
            openNotification()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.refresh() }
            }
        }
        .onChange(of: reminders.openedItemID) { _, _ in
            openNotification()
        }
        .onChange(of: reminders.shouldOpenReviewList) { _, shouldOpen in
            guard shouldOpen else { return }
            openReviewList()
        }
        .sheet(isPresented: $isPresentingEditor) {
            NavigationStack {
                WishEditorView(viewModel: viewModel, onCancel: { isPresentingEditor = false }) {
                    isPresentingEditor = false
                    selectedTab = .home
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $notificationItem) { item in
            NavigationStack {
                if item.status == .keeping {
                    ReviewView(item: item, viewModel: viewModel)
                } else {
                    WishDetailView(item: item, viewModel: viewModel)
                }
            }
        }
    }

    // MARK: - Subviews

    private var tabContent: some View {
        TabView(selection: tabSelection) {
            Tab("홈", image: "homeIcon", value: AppTab.home) {
                HomeView(
                    viewModel: viewModel,
                    reminders: reminders,
                    onAddTapped: presentEditor,
                    scrollToTopRequest: homeScrollToTopRequest
                )
                .background {
                    tabActionInstaller
                }
            }

            Tab("담기", systemImage: "plus.circle.fill", value: AppTab.add) {
                Color.clear
            }

            Tab("기록", image: "recordIcon", value: AppTab.records) {
                RecordsView(
                    viewModel: viewModel,
                    scrollToTopRequest: recordsScrollToTopRequest
                )
                .background {
                    tabActionInstaller
                }
            }
        }
    }

    private var tabActionInstaller: some View {
        DuGoTabActionInstaller(
            handler: tabActionHandler,
            onAction: presentEditor,
            onReselect: handleTabReselection
        )
    }

    // MARK: - Computed Properties

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                if tab == .add {
                    presentEditor()
                } else {
                    selectedTab = tab
                }
            }
        )
    }

    // MARK: - Methods

    private func presentEditor() {
        guard !isPresentingEditor else { return }
        isPresentingEditor = true
    }

    private func handleTabReselection(_ index: Int) {
        switch index {
        case 0:
            homeScrollToTopRequest += 1
        case 2:
            recordsScrollToTopRequest += 1
        default:
            break
        }
    }

    private func openNotification() {
        if reminders.shouldOpenReviewList {
            openReviewList()
            return
        }
        guard let id = reminders.openedItemID else { return }

        selectedTab = .home
        notificationItem = viewModel.item(id: id)
        reminders.openedItemID = nil
    }

    private func openReviewList() {
        selectedTab = .home
        notificationItem = nil
        reminders.shouldOpenReviewList = false
    }
}
