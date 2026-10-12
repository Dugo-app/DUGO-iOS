//
//  ReviewView.swift
//  DuGo-iOS
//
//  Created by 김승원 on 19/9/26.
//

import SwiftData
import SwiftUI

struct ReviewView: View {
    // MARK: - Properties

    let item: WishItem
    @ObservedObject private var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var note = ""
    @State private var decision: WishDecision?
    @State private var showsSelectionFooter = false
    @State private var isNoteExpanded = false
    @State private var nextDate =
        Calendar.current.date(
            byAdding: .day,
            value: 3,
            to: Calendar.current.startOfDay(for: .now)
        ) ?? .now
    @State private var wantsReminder = false
    @State private var completed: WishDecision?
    @State private var undoToken: HomeViewModel.DecisionUndoToken?
    @State private var showsWaitSheet = false
    @State private var showsPurchaseConfirmation = false
    @State private var showsReleaseConfirmation = false
    @State private var isWaitingForPurchaseReturn = false
    @State private var didLeaveForPurchase = false
    @State private var pendingCompletion: WishDecision?

    private let decisions: [WishDecision] = [.purchase, .wait, .release]

    // MARK: - Initializer

    init(
        item: WishItem,
        viewModel: HomeViewModel,
        completed: WishDecision? = nil
    ) {
        self.item = item
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _completed = State(initialValue: completed)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let completed {
                completionView(completed)
            } else {
                reviewContent
            }
        }
        .navigationTitle(completed == nil ? "내 마음 다시 보기" : "선택을 남겼어요")
        .navigationBarTitleDisplayMode(.inline)
        .dismissKeyboardOnBackgroundTap()
        .dugoScreen()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarVisibility(.visible, for: .navigationBar)
        .interactiveDismissDisabled(viewModel.isWorking)
        .onAppear { viewModel.errorMessage = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, isWaitingForPurchaseReturn {
                didLeaveForPurchase = true
            } else if phase == .active, isWaitingForPurchaseReturn, didLeaveForPurchase {
                isWaitingForPurchaseReturn = false
                didLeaveForPurchase = false
                showsPurchaseConfirmation = true
            }
        }
        .sheet(
            isPresented: $showsPurchaseConfirmation,
            onDismiss: showPendingCompletion
        ) {
            purchaseConfirmationSheet
        }
        .sheet(
            isPresented: $showsWaitSheet,
            onDismiss: showPendingCompletion
        ) {
            waitDateSheet
        }
        .sheet(
            isPresented: $showsReleaseConfirmation,
            onDismiss: showPendingCompletion
        ) {
            releaseConfirmationSheet
        }
    }

    // MARK: - Subviews

    private var reviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                productCard

                initialReasonSection

                decisionSection

                noteSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(viewModel.isWorking)
        .dugoErrorToast(message: $viewModel.errorMessage)
        .safeAreaInset(edge: .bottom) {
            if showsSelectionFooter {
                selectionFooter
                    .transition(.move(edge: .bottom))
            }
        }
    }

    private var productCard: some View {
        HStack(alignment: .top, spacing: 14) {
            FillWishImage(item: item, size: 100)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 3) {
                    Image(systemName: "clock")
                        .applyDuGoFont(.caption12Medium)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.reviewDueDescription)
                        .applyDuGoFont(.caption12Medium)
                }
                .foregroundStyle(DuGoTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, -2)

                Text(item.title)
                    .applyDuGoFont(.title17Medium)
                    .foregroundStyle(DuGoTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if let price = item.price {
                    Text(price.dugoFormattedPrice)
                        .applyDuGoFont(.body14Medium)
                        .foregroundStyle(DuGoTheme.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(DuGoTheme.surface)
                .dugoShadow(.subtle)
        }
        .dugoRoundedBorder()
    }

    private var initialReasonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("처음 담았던 마음")

            Text(
                item.initialReason.isEmpty
                    ? "처음에는 이유를 남기지 않았어요"
                    : item.initialReason
            )
            .applyDuGoFont(.body16Regular)
            .foregroundStyle(item.initialReason.isEmpty ? DuGoTheme.secondary : DuGoTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dugoRoundedSurface()
        }
    }

    private var decisionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                sectionTitle("지금 이 마음을 어떻게 할까요?")

                Text("어떤 선택이어도 괜찮아요")
                    .applyDuGoFont(.body14Regular)
                    .foregroundStyle(DuGoTheme.secondary)
            }

            VStack(spacing: 10) {
                ForEach(decisions) { value in
                    decisionCard(value)
                }
            }
        }
    }

    private func decisionCard(_ value: WishDecision) -> some View {
        let isSelected = decision == value

        return Button {
            let shouldRevealFooter = decision == nil
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                decision = value
            }

            if shouldRevealFooter {
                withAnimation(.easeOut(duration: 0.25)) {
                    showsSelectionFooter = true
                }
            }
        } label: {
            HStack(spacing: 14) {
                DuGoDecisionIcon(
                    decision: value,
                    size: 24,
                    color: DuGoTheme.ink
                )
                .frame(width: 42, height: 42)
                .background(DuGoTheme.surfaceInset, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(value.rawValue)
                        .applyDuGoFont(.title16Medium)
                        .foregroundStyle(DuGoTheme.ink)

                    Text(decisionDescription(for: value))
                        .applyDuGoFont(.caption12Regular)
                        .foregroundStyle(DuGoTheme.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isSelected ? DuGoTheme.ink : DuGoTheme.secondary)
                    .animation(nil, value: isSelected)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dugoRoundedSurface()
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var noteSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isNoteExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .medium))

                    Text("생각 한 줄 남기기")
                        .applyDuGoFont(.body16Medium)

                    Text("선택")
                        .applyDuGoFont(.caption12Regular)
                        .foregroundStyle(DuGoTheme.secondary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DuGoTheme.secondary)
                        .rotationEffect(.degrees(isNoteExpanded ? 180 : 0))
                }
                .foregroundStyle(DuGoTheme.ink)
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isNoteExpanded {
                Rectangle()
                    .fill(DuGoTheme.border.opacity(0.65))
                    .frame(height: 1)

                TextField(
                    "지금 이 상품을 보면 드는 생각을 적어보세요",
                    text: $note,
                    axis: .vertical
                )
                .font(DuGoFont.body16Regular.font)
                .lineLimit(3...6)
                .frame(minHeight: 96, alignment: .topLeading)
                .padding(16)
                .transition(.opacity)
            }
        }
        .dugoRoundedSurface(clipsContent: true)
    }

    private var purchaseConfirmationSheet: some View {
        DuGoActionSheet(
            height: .medium,
            heading: "상품을 살펴보셨나요?",
            message: "구매하기로 마음을 정했다면 선택을 남겨주세요\n아직 고민 중이어도 괜찮아요",
            primaryTitle: "구매하기로 했어요",
            isLoading: viewModel.isWorking,
            secondaryTitle: "조금 더 생각할래요"
        ) {
            saveSelection(.purchase)
        } secondaryAction: {
            decision = .wait
            showsPurchaseConfirmation = false
        } closeAction: {
            showsPurchaseConfirmation = false
        }
        .dugoErrorToast(message: $viewModel.errorMessage)
    }

    private var waitDateSheet: some View {
        DuGoSheet(
            height: .large,
            isWorking: viewModel.isWorking,
            scrollsContent: true,
            closeAction: { showsWaitSheet = false }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Text("언제 다시 만나볼까요?")
                    .applyDuGoFont(.display24SemiBold)
                    .foregroundStyle(DuGoTheme.ink)

                Text("조금 더 생각할 시간을 정해두고,\n그날 다시 마음을 살펴봐요")
                    .applyDuGoFont(.body16Regular)
                    .foregroundStyle(DuGoTheme.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    ReviewDatePicker(reviewDate: $nextDate)
                        .padding(.horizontal, -16)

                    Rectangle()
                        .fill(DuGoTheme.border.opacity(0.65))
                        .frame(height: 1)
                        .padding(.horizontal, -16)

                    Toggle("알림 받기", isOn: $wantsReminder)
                        .applyDuGoFont(.body16Medium)
                        .tint(DuGoTheme.toggle)
                }
                .padding(16)
                .dugoRoundedSurface()

                if wantsReminder {
                    Text("선택한 날 오후 1시에 알림을 보내드려요")
                        .applyDuGoFont(.caption12Regular)
                        .foregroundStyle(DuGoTheme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } footer: {
            DuGoSheetActions(
                primaryTitle: "이 날짜로 더 두기",
                isLoading: viewModel.isWorking,
                secondaryTitle: "날짜 정하지 않고 더 두기"
            ) {
                saveSelection(.wait)
            } secondaryAction: {
                saveSelection(.wait, schedulesNextReview: false)
            }
        }
        .dugoErrorToast(message: $viewModel.errorMessage)
    }

    private var releaseConfirmationSheet: some View {
        DuGoActionSheet(
            height: .medium,
            heading: "이 마음을 보내줄까요?",
            message: "지금은 필요하지 않다고 느꼈다면 보내줘도 괜찮아요\n마음이 바뀌면 언제든 다시 담을 수 있어요",
            primaryTitle: "마음 보내주기",
            isLoading: viewModel.isWorking,
            secondaryTitle: "조금 더 생각할래요"
        ) {
            saveSelection(.release)
        } secondaryAction: {
            decision = .wait
            showsReleaseConfirmation = false
        } closeAction: {
            showsReleaseConfirmation = false
        }
        .dugoErrorToast(message: $viewModel.errorMessage)
    }

    private var selectionFooter: some View {
        DuGoPrimaryButton(
            title: continueButtonTitle,
            isLoading: viewModel.isWorking,
            action: continueSelection
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func completionView(_ completed: WishDecision) -> some View {
        VStack(spacing: 0) {
            DuGoDecisionCelebrationIcon(decision: completed)
                .padding(.top, 80)

            Text(completed.message)
                .applyDuGoFont(.display24SemiBold)
                .foregroundStyle(DuGoTheme.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 30)

            Text(completed.subMessage)
                .applyDuGoFont(.body14Regular)
                .foregroundStyle(DuGoTheme.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            Spacer()

            DuGoSheetActions(
                primaryTitle: "완료",
                isLoading: viewModel.isWorking,
                secondaryTitle: undoToken == nil ? nil : "선택 되돌리기"
            ) {
                dismiss()
            } secondaryAction: {
                undoSelection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 48)
        .padding(.bottom, 8)
        .dugoErrorToast(message: $viewModel.errorMessage)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .applyDuGoFont(.title18SemiBold)
            .foregroundStyle(DuGoTheme.ink)
    }

    // MARK: - Methods

    private var continueButtonTitle: String {
        switch decision {
        case .purchase: "상품 구매하러 가기"
        case .wait: "다시 볼 날 정하기"
        case .release: "마음 보내주기"
        case .restore, nil: "이 선택으로 계속하기"
        }
    }

    private func continueSelection() {
        guard let decision, !viewModel.isWorking else { return }
        viewModel.errorMessage = nil

        switch decision {
        case .purchase:
            openProductLink()
        case .wait:
            showsWaitSheet = true
        case .release:
            showsReleaseConfirmation = true
        case .restore:
            break
        }
    }

    private func openProductLink() {
        guard let url = URL(string: item.link),
            let scheme = url.scheme?.lowercased(),
            ["https", "http"].contains(scheme),
            url.host != nil
        else {
            viewModel.errorMessage = "상품 링크를 열 수 없어요 저장된 링크를 확인해주세요"
            return
        }

        didLeaveForPurchase = false
        isWaitingForPurchaseReturn = true
        openURL(url) { accepted in
            if !accepted {
                isWaitingForPurchaseReturn = false
                didLeaveForPurchase = false
                viewModel.errorMessage = "상품 링크를 열지 못했어요 다시 시도해주세요"
            }
        }
    }

    private func decisionDescription(for decision: WishDecision) -> String {
        switch decision {
        case .purchase:
            "지금도 필요하고, 살 이유가 분명해요"
        case .wait:
            "조금 더 시간을 두고 생각해볼래요"
        case .release:
            "지금은 보내줘도 괜찮아요"
        case .restore:
            decision.message
        }
    }

    private func saveSelection(
        _ decision: WishDecision,
        schedulesNextReview: Bool = true
    ) {
        let scheduledDate = decision == .wait && schedulesNextReview ? nextDate : nil

        Task {
            if let undoToken = await viewModel.decide(
                item,
                decision: decision,
                feeling: "",
                note: note,
                nextDate: scheduledDate,
                notify: scheduledDate != nil && wantsReminder
            ) {
                self.undoToken = undoToken
                pendingCompletion = decision
                showsPurchaseConfirmation = false
                showsWaitSheet = false
                showsReleaseConfirmation = false
            }
        }
    }

    private func undoSelection() {
        guard let undoToken else { return }

        Task {
            if await viewModel.undoDecision(undoToken) {
                self.undoToken = nil
                pendingCompletion = nil
                completed = nil
                decision = nil
                showsSelectionFooter = false
            }
        }
    }

    private func showPendingCompletion() {
        guard let pendingCompletion else { return }
        self.pendingCompletion = nil

        DispatchQueue.main.async {
            completed = pendingCompletion
        }
    }
}
