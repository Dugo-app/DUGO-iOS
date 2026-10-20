//
//  WishEditorView.swift
//  DuGo-iOS
//
//  Created by 김승원 on 19/9/26.
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct WishEditorView: View {
    // MARK: - Types

    private enum InputField: Hashable {
        case link
        case title
        case price
        case reason
    }

    private enum AutofilledField: Hashable {
        case image, title, price
    }

    private struct PreviewRequest: Equatable {
        let link: String
        let isSaving: Bool
    }

    // MARK: - Properties

    @ObservedObject private var viewModel: HomeViewModel
    let item: WishItem?
    let onCancel: (() -> Void)?
    let onSaved: () -> Void

    @State private var draft: WishDraft
    @State private var previewedLink: String?
    @State private var isLoadingLinkPreview = false
    @State private var linkPreviewMessage: String?
    @FocusState private var focusedField: InputField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSaving = false
    @State private var activePreviewID: UUID?
    @State private var activeImageReloadID: UUID?
    @State private var imageReloadMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var activePhotoSelectionID: UUID?
    @State private var photoSelectionMessage: String?
    @State private var autofilledFields: Set<AutofilledField> = []
    @State private var automaticTitle: String?
    @State private var automaticPrice: String?

    private let linkPreviewService = LinkPreviewService()

    // MARK: - Initializer

    init(
        viewModel: HomeViewModel,
        item: WishItem? = nil,
        onCancel: (() -> Void)? = nil,
        onSaved: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.item = item
        self.onCancel = onCancel
        self.onSaved = onSaved
        _draft = State(initialValue: WishDraft(item: item))
        _previewedLink = State(initialValue: item?.link)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                linkSection

                if showsDetails {
                    VStack(alignment: .leading, spacing: 24) {
                        itemInformationSection

                        if showsAdditionalDetails {
                            VStack(alignment: .leading, spacing: 24) {
                                reasonSection

                                if item == nil || item?.status == .keeping {
                                    reviewDateSection
                                }
                            }
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .move(edge: .bottom).combined(with: .opacity)
                            )
                        }
                    }
                    .transition(
                        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 48)
            .animation(revealAnimation, value: showsDetails)
            .animation(revealAnimation, value: showsAdditionalDetails)
        }
        .navigationTitle(item == nil ? "마음 담기" : "마음 수정")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .dugoScreen()
        .dugoErrorToast(message: $viewModel.errorMessage)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbar { toolbarContent }
        .dismissKeyboardOnBackgroundTap()
        .disabled(viewModel.isWorking || isSaving)
        .interactiveDismissDisabled(viewModel.isWorking || isSaving)
        .onAppear {
            viewModel.errorMessage = nil
            formatPrice()
        }
        .task(id: PreviewRequest(link: trimmedLink, isSaving: isSaving)) {
            guard !isSaving else { return }
            prepareForLinkChange()
            guard hasValidLink else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await loadLinkPreview()
        }
        .task(id: autofilledFields) {
            guard !autofilledFields.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                autofilledFields = []
            }
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            await loadSelectedPhoto(selectedPhoto)
        }
        .onChange(of: focusedField) { previousField, currentField in
            if previousField == .link, currentField != .link {
                presentLinkErrorIfNeeded()
            }

            if previousField == .price, currentField != .price {
                formatPrice()
            } else if currentField == .price {
                preparePriceForEditing()
            }
        }
    }

    // MARK: - Subviews

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("상품 링크", showsRequiredIndicator: true)

            editorCard(verticalSpacing: 6) {
                HStack(alignment: .center, spacing: 4) {
                    TextField("https://…", text: $draft.link)
                        .font(DuGoFont.body16Regular.font)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .link)
                        .frame(minHeight: 48)
                        .onSubmit {
                            presentLinkErrorIfNeeded()
                            focusedField = nil
                        }

                    DuGoPasteButton { link in
                        draft.link = link
                        focusedField = nil
                    }
                }
            }
        }
    }

    private var itemInformationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("상품 정보", showsRequiredIndicator: true)

            Group {
                if isShowingProductLoading {
                    editorCard {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("상품 정보를 불러오는 중이에요")
                                .applyDuGoFont(.body14Regular)
                                .foregroundStyle(DuGoTheme.secondary)
                        }
                    }
                } else {
                    editorCard(verticalSpacing: 0) {
                        VStack(spacing: 0) {
                            linkPreviewContent
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 16)
                                .background { autofillBackground(for: .image) }

                            cardDivider

                            TextField("상품 이름", text: $draft.title)
                                .font(DuGoFont.body16Regular.font)
                                .focused($focusedField, equals: .title)
                                .frame(minHeight: 54)
                                .background { autofillBackground(for: .title) }

                            cardDivider

                            TextField("가격 (원)", text: $draft.price)
                                .font(DuGoFont.body16Regular.font)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .price)
                                .frame(minHeight: 54)
                                .background { autofillBackground(for: .price) }

                            cardDivider

                            HStack {
                                Text("카테고리")
                                    .applyDuGoFont(.body16Regular)
                                    .foregroundStyle(DuGoTheme.ink)

                                Spacer()

                                Picker("카테고리", selection: $draft.category) {
                                    ForEach(viewModel.categories, id: \.self) { category in
                                        Text(category).tag(category)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .tint(DuGoTheme.ink)
                            }
                            .frame(minHeight: 54)
                        }
                    }
                }
            }

            if let message = linkPreviewMessage {
                Text(message)
                    .applyDuGoFont(.caption12Regular)
                    .foregroundStyle(DuGoTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("사고 싶은 이유")

            editorCard {
                TextField("어떤 순간에 필요할까요?", text: $draft.reason, axis: .vertical)
                    .font(DuGoFont.body16Regular.font)
                    .lineLimit(4...7)
                    .focused($focusedField, equals: .reason)
                    .frame(minHeight: 96, alignment: .topLeading)
            }
        }
    }

    private var reviewDateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("다시 만나는 날")

            editorCard {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("다시 볼 날짜 정하기", isOn: $draft.hasReviewDate)
                        .applyDuGoFont(.body16Medium)
                        .tint(DuGoTheme.toggle)

                    if draft.hasReviewDate {
                        cardDivider

                        ReviewDatePicker(reviewDate: $draft.reviewDate)
                            .padding(.horizontal, -16)

                        cardDivider

                        Toggle("알림 받기", isOn: $draft.wantsReminder)
                            .applyDuGoFont(.body16Medium)
                            .tint(DuGoTheme.toggle)
                    }
                }
            }

            if draft.hasReviewDate && draft.wantsReminder {
                Text("선택한 날 \(ReminderTimePreference.displayText)에 알림을 보내드려요")
                    .applyDuGoFont(.caption12Regular)
                    .foregroundStyle(DuGoTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func autofillBackground(for field: AutofilledField) -> some View {
        Rectangle()
            .fill(DuGoTheme.accent.opacity(0.12))
            .opacity(autofilledFields.contains(field) ? 1 : 0)
            .padding(.horizontal, -16)
            .allowsHitTesting(false)
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(DuGoTheme.border.opacity(0.65))
            .frame(height: 1)
            .padding(.horizontal, -16)
    }

    private func sectionTitle(
        _ title: String,
        showsRequiredIndicator: Bool = false
    ) -> some View {
        Text(title)
            .applyDuGoFont(.title18SemiBold)
            .foregroundStyle(DuGoTheme.ink)
            .overlay(alignment: .topTrailing) {
                if showsRequiredIndicator {
                    Circle()
                        .fill(DuGoTheme.accent)
                        .frame(width: 6, height: 6)
                        .offset(x: 8, y: -2)
                }
            }
    }

    private func editorCard<Content: View>(
        verticalSpacing: CGFloat = 16,
        horizontalSpacing: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.vertical, verticalSpacing)
            .padding(.horizontal, horizontalSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dugoRoundedSurface(clipsContent: true)
    }

    private var linkPreviewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let data = draft.imageData, let image = UIImage(data: data) {
                HStack(spacing: 14) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            if isReloadingImage || isLoadingSelectedPhoto {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.35))
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                        .transition(.opacity)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedPhoto == nil ? "대표 사진을 가져왔어요" : "대표 사진을 추가했어요")
                            .applyDuGoFont(.body14Medium)
                        if selectedPhoto == nil {
                            Button(action: reloadImage) {
                                Text("다시 불러오기")
                                    .applyDuGoFont(.caption12Regular)
                                    .foregroundStyle(DuGoTheme.secondary)
                                    .underline()
                            }
                            .buttonStyle(.plain)
                        } else {
                            galleryPicker("사진 바꾸기")
                        }
                    }
                }
            } else if isLoadingSelectedPhoto {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("사진을 추가하는 중이에요")
                        .applyDuGoFont(.body14Regular)
                        .foregroundStyle(DuGoTheme.secondary)
                }
                .frame(minHeight: 72)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("대표 사진을 찾지 못했어요")
                        .applyDuGoFont(.body14Regular)
                        .foregroundStyle(DuGoTheme.secondary)
                    galleryPicker("갤러리에서 직접 추가")
                }
            }

            if let imageReloadMessage {
                Text(imageReloadMessage)
                    .applyDuGoFont(.caption12Regular)
                    .foregroundStyle(DuGoTheme.secondary)
            }
            if let photoSelectionMessage {
                Text(photoSelectionMessage)
                    .applyDuGoFont(.caption12Regular)
                    .foregroundStyle(.red)
            }
        }
        .disabled(isReloadingImage)
    }

    private func galleryPicker(_ title: String) -> some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Text(title)
                .applyDuGoFont(.caption12Regular)
                .foregroundStyle(DuGoTheme.secondary)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let onCancel {
            ToolbarItem(placement: .topBarLeading) {
                Button("취소", action: onCancel)
                .tint(.duGoInk)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isSaving = true
                Task {
                    defer { isSaving = false }
                    focusedField = nil
                    if await viewModel.save(draft, editing: item) {
                        draft = WishDraft()
                        onSaved()
                    }
                }
            } label: {
                Text("저장")
                    .opacity(viewModel.isWorking || isSaving ? 0 : 1)
                    .overlay {
                        if viewModel.isWorking || isSaving {
                            ProgressView()
                        }
                    }
            }
            .tint(.duGoAccent)
            .fontWeight(.semibold)
            .disabled(
                viewModel.isWorking || isSaving || !hasValidLink
            )
        }
    }

    // MARK: - Methods

    private var trimmedLink: String {
        draft.link.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasValidLink: Bool {
        draft.validURL != nil
    }

    private var hasInvalidLink: Bool {
        !trimmedLink.isEmpty && !hasValidLink
    }

    private func presentLinkErrorIfNeeded() {
        guard hasInvalidLink else { return }
        viewModel.errorMessage = DraftError.invalidLink.errorDescription
    }

    private var showsDetails: Bool { hasValidLink }

    private var showsAdditionalDetails: Bool {
        previewedLink == trimmedLink
    }

    private var isShowingProductLoading: Bool {
        isLoadingLinkPreview
            || (hasValidLink && previewedLink != trimmedLink && linkPreviewMessage == nil)
    }

    private var isReloadingImage: Bool { activeImageReloadID != nil }
    private var isLoadingSelectedPhoto: Bool { activePhotoSelectionID != nil }

    private var revealAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.28)
    }

    private func prepareForLinkChange() {
        guard trimmedLink != previewedLink else { return }
        activePreviewID = nil
        activeImageReloadID = nil
        imageReloadMessage = nil
        activePhotoSelectionID = nil
        selectedPhoto = nil
        photoSelectionMessage = nil
        isLoadingLinkPreview = false
        linkPreviewMessage = nil
        draft.imageData = nil
        if draft.title == automaticTitle {
            draft.title = ""
        }
        if draft.price == automaticPrice {
            draft.price = ""
        }
        automaticTitle = nil
        automaticPrice = nil
        previewedLink = nil
        autofilledFields = []
    }

    private func preparePriceForEditing() {
        draft.preparePriceForEditing()
    }

    private func formatPrice() {
        draft.formatPrice()
    }

    private func loadLinkPreview() async {
        let link = trimmedLink
        guard hasValidLink, link != previewedLink else { return }

        let requestID = UUID()
        activePreviewID = requestID
        isLoadingLinkPreview = true
        linkPreviewMessage = nil
        defer {
            if activePreviewID == requestID {
                isLoadingLinkPreview = false
            }
        }

        do {
            let preview = try await linkPreviewService.fetch(from: link)
            try Task.checkCancellation()
            guard trimmedLink == link, !isSaving else { return }

            if draft.imageData == nil, let imageData = preview.imageData {
                withAnimation(revealAnimation) {
                    if draft.fillImageIfMissing(imageData) {
                        autofilledFields.insert(.image)
                    }
                }
            }

            if !reduceMotion {
                try await Task.sleep(for: .milliseconds(150))
            }
            try Task.checkCancellation()
            guard trimmedLink == link, !isSaving else { return }

            if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                preview.title != nil
            {
                withAnimation(revealAnimation) {
                    if draft.fillTitleIfEmpty(preview.title) {
                        automaticTitle = draft.title
                        autofilledFields.insert(.title)
                    }
                }
            }

            if !reduceMotion {
                try await Task.sleep(for: .milliseconds(150))
            }
            try Task.checkCancellation()
            guard trimmedLink == link, !isSaving else { return }

            if draft.price.isEmpty, focusedField != .price, let price = preview.price {
                withAnimation(revealAnimation) {
                    if draft.fillPriceIfEmpty(price) {
                        automaticPrice = draft.price
                        autofilledFields.insert(.price)
                    }
                }
            }
            previewedLink = link
            linkPreviewMessage =
                preview.price == nil
                ? "가져온 정보만 채웠어요 가격은 직접 적어도 괜찮아요"
                : "상품 정보를 채웠어요 가격이 맞는지 확인해주세요"
            if preview.imageData == nil && preview.title == nil && preview.price == nil {
                linkPreviewMessage = "상품 정보를 찾지 못했어요 링크만 저장해도 괜찮아요"
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, trimmedLink == link, !isSaving else { return }
            linkPreviewMessage = "상품 정보를 가져오지 못했어요 링크만 저장해도 괜찮아요"
        }
    }

    private func reloadImage() {
        guard hasValidLink, !isReloadingImage else { return }

        let link = trimmedLink
        let requestID = UUID()
        activeImageReloadID = requestID
        imageReloadMessage = nil

        Task {
            defer {
                if activeImageReloadID == requestID {
                    activeImageReloadID = nil
                }
            }

            do {
                let preview = try await linkPreviewService.fetch(from: link)
                guard activeImageReloadID == requestID,
                    trimmedLink == link,
                    !isSaving
                else { return }

                if let imageData = preview.imageData {
                    withAnimation(revealAnimation) {
                        draft.imageData = imageData
                        autofilledFields.insert(.image)
                    }
                } else {
                    imageReloadMessage = "대표 사진을 찾지 못했어요"
                }
            } catch {
                guard activeImageReloadID == requestID,
                    trimmedLink == link,
                    !isSaving
                else { return }
                imageReloadMessage = "대표 사진을 다시 불러오지 못했어요"
            }
        }
    }

    private func loadSelectedPhoto(_ photo: PhotosPickerItem) async {
        let link = trimmedLink
        let requestID = UUID()
        activePhotoSelectionID = requestID
        photoSelectionMessage = nil
        defer {
            if activePhotoSelectionID == requestID {
                activePhotoSelectionID = nil
            }
        }

        do {
            guard let data = try await photo.loadTransferable(type: Data.self),
                let image = UIImage(data: data),
                let imageData = linkPreviewService.resizedJPEGData(from: image)
            else {
                if activePhotoSelectionID == requestID {
                    photoSelectionMessage = "사진을 불러오지 못했어요 다시 선택해주세요"
                    selectedPhoto = nil
                }
                return
            }
            try Task.checkCancellation()
            guard activePhotoSelectionID == requestID,
                selectedPhoto == photo,
                trimmedLink == link,
                !isSaving
            else { return }

            withAnimation(revealAnimation) {
                draft.imageData = imageData
                autofilledFields.insert(.image)
            }
        } catch is CancellationError {
        } catch {
            guard activePhotoSelectionID == requestID, trimmedLink == link else { return }
            photoSelectionMessage = "사진을 불러오지 못했어요 다시 선택해주세요"
            selectedPhoto = nil
        }
    }
}

private struct DuGoPasteButton: View {
    // MARK: - Properties

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasLinkInPasteboard = false
    @State private var availabilityRequestID: UUID?
    @State private var showsPasteFailure = false

    let onPaste: (String) -> Void

    // MARK: - Body

    var body: some View {
        Button(action: pasteLink) {
            Text("붙여넣기")
                .applyDuGoFont(.button14Medium)
                .foregroundStyle(DuGoTheme.background)
                .frame(width: 90, height: 34)
                .background(
                    DuGoTheme.toggle,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!hasLinkInPasteboard)
        .opacity(isEnabled && hasLinkInPasteboard ? 1 : 0.45)
        .task(id: scenePhase) {
            availabilityRequestID = nil
            hasLinkInPasteboard = false
            guard scenePhase == .active else { return }
            await updatePasteAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) {
            _ in
            Task { await updatePasteAvailability() }
        }
        .onDisappear {
            availabilityRequestID = nil
        }
        .alert("붙여넣지 못했어요", isPresented: $showsPasteFailure) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("복사한 링크를 읽지 못했어요 붙여넣기 권한을 확인하거나 링크 입력칸에 직접 붙여넣어 주세요")
        }
    }

    // MARK: - Methods

    private func pasteLink() {
        guard isEnabled, hasLinkInPasteboard else { return }
        let pasteboard = UIPasteboard.general
        let value = (pasteboard.string ?? pasteboard.url?.absoluteString)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value, !value.isEmpty else {
            showsPasteFailure = true
            Task { await updatePasteAvailability() }
            return
        }
        onPaste(value)
    }

    private func updatePasteAvailability() async {
        guard scenePhase == .active else { return }
        let requestID = UUID()
        availabilityRequestID = requestID
        hasLinkInPasteboard = false
        let changeCount = UIPasteboard.general.changeCount
        let webURLPattern: PartialKeyPath<UIPasteboard.DetectedValues> = \.probableWebURL

        do {
            let detectedPatterns = try await UIPasteboard.general.detectedPatterns(
                for: [webURLPattern]
            )
            guard !Task.isCancelled,
                availabilityRequestID == requestID,
                scenePhase == .active,
                UIPasteboard.general.changeCount == changeCount
            else { return }
            hasLinkInPasteboard = detectedPatterns.contains(webURLPattern)
        } catch {
            guard availabilityRequestID == requestID else { return }
            hasLinkInPasteboard = false
        }
    }
}
