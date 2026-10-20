//
//  ShareComposerView.swift
//  ShareExtension
//
//  Created by 김승원 on 1/10/26.
//

import Combine
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class ShareComposerModel: ObservableObject {
    // MARK: - Properties

    @Published var draft = WishDraft()
    @Published var isReadingLink = false
    @Published var isLoadingPreview = false
    @Published var previewedLink: String?
    @Published var highlightedFields: Set<AutofilledField> = []
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let previewService = LinkPreviewService()
    private var sharedContentLink: String?
    private var sharedContentTitle: String?
    private var sharedContentPrice: Int?
    private var sharedContentImageData: Data?
    private var automaticTitle: String?
    private var automaticPrice: String?

    // MARK: - Computed Properties

    var link: String {
        get { draft.link }
        set { draft.link = newValue }
    }
    var title: String {
        get { draft.title }
        set { draft.title = newValue }
    }
    var price: String {
        get { draft.price }
        set { draft.price = newValue }
    }
    var reason: String {
        get { draft.reason }
        set { draft.reason = newValue }
    }
    var category: String {
        get { draft.category }
        set { draft.category = newValue }
    }
    var hasReviewDate: Bool {
        get { draft.hasReviewDate }
        set { draft.hasReviewDate = newValue }
    }
    var reviewDate: Date {
        get { draft.reviewDate }
        set { draft.reviewDate = newValue }
    }
    var wantsReminder: Bool {
        get { draft.wantsReminder }
        set { draft.wantsReminder = newValue }
    }
    var imageData: Data? {
        get { draft.imageData }
        set { draft.imageData = newValue }
    }
    var validURL: URL? { draft.validURL }

    private var sharedAutofilledFields: Set<AutofilledField> {
        var fields: Set<AutofilledField> = []

        if sharedContentImageData != nil {
            fields.insert(.image)
        }

        if let sharedContentTitle,
            !sharedContentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            fields.insert(.title)
        }

        if sharedContentPrice != nil {
            fields.insert(.price)
        }

        return fields
    }

    // MARK: - Types

    enum AutofilledField: Hashable {
        case image, title, price
    }

    // MARK: - Methods

    func preparePreview() {
        let usesSharedContent = link == sharedContentLink

        isLoadingPreview = false
        previewedLink = nil
        highlightedFields = []
        imageData = usesSharedContent ? sharedContentImageData : nil
        if title == automaticTitle || title.isEmpty {
            title = usesSharedContent ? sharedContentTitle ?? "" : ""
            automaticTitle = title.isEmpty ? nil : title
        }
        if price == automaticPrice || price.isEmpty {
            price = usesSharedContent ? sharedContentPrice.map(String.init) ?? "" : ""
            formatPrice()
            automaticPrice = price.isEmpty ? nil : price
        }
    }

    func applySharedContent(
        url: URL,
        title: String?,
        price: Int?,
        imageData: Data?
    ) {
        sharedContentLink = url.absoluteString
        sharedContentTitle = title
        sharedContentPrice = price
        sharedContentImageData = imageData
        link = url.absoluteString
    }

    func loadPreview(animate: Bool, isEditingPrice: Bool = false) async {
        guard validURL != nil else { return }
        let requestedLink = link
        var newlyAutofilledFields: Set<AutofilledField> = []
        isLoadingPreview = true

        do {
            let preview = try await previewService.fetch(from: requestedLink)
            guard !Task.isCancelled, link == requestedLink else { return }
            if imageData == nil, let image = preview.imageData {
                withAnimation(animate ? .easeInOut(duration: 0.28) : nil) {
                    if draft.fillImageIfMissing(image) {
                        newlyAutofilledFields.insert(.image)
                    }
                }
            }
            if animate {
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard !Task.isCancelled, link == requestedLink else { return }

            if title.isEmpty, let previewTitle = preview.title {
                withAnimation(animate ? .easeInOut(duration: 0.28) : nil) {
                    if draft.fillTitleIfEmpty(previewTitle) {
                        automaticTitle = draft.title
                        newlyAutofilledFields.insert(.title)
                    }
                }
            }
            if animate {
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard !Task.isCancelled, link == requestedLink else { return }

            if price.isEmpty, !isEditingPrice, let amount = preview.price {
                withAnimation(animate ? .easeInOut(duration: 0.28) : nil) {
                    if draft.fillPriceIfEmpty(amount) {
                        automaticPrice = draft.price
                        newlyAutofilledFields.insert(.price)
                    }
                }
            }
        } catch {
        }
        guard !Task.isCancelled, link == requestedLink else { return }
        if requestedLink == sharedContentLink {
            newlyAutofilledFields.formUnion(sharedAutofilledFields)
        }

        withAnimation(animate ? .easeInOut(duration: 0.28) : nil) {
            isLoadingPreview = false
            previewedLink = requestedLink
            highlightedFields = newlyAutofilledFields
        }
    }

    func save() async throws -> String? {
        let values = try draft.validated()
        let wish = PendingSharedWish(
            id: UUID(),
            createdAt: .now,
            link: values.link.absoluteString,
            title: values.title,
            categoryRaw: category,
            price: values.price,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            reviewAt: hasReviewDate ? reviewDate : nil,
            wantsReminder: hasReviewDate && wantsReminder,
            imageData: imageData
        )
        try SharedLinkInbox.enqueue(wish)
        guard wish.wantsReminder == true else { return nil }

        let pendingReminders = SharedLinkInbox.pending().compactMap { pending -> WishReminder? in
            guard pending.wantsReminder == true, let date = pending.reviewAt else { return nil }
            return WishReminder(itemID: pending.id, title: pending.title, date: date)
        }
        if !pendingReminders.isEmpty {
            let reminders = ReminderManager()
            await reminders.requestPermissionIfNeeded()
            await reminders.synchronizeAdditional(pendingReminders)
            return reminders.notice
        }
        return nil
    }

    func preparePriceForEditing() {
        draft.preparePriceForEditing()
    }

    func formatPrice() {
        draft.formatPrice()
    }
}

struct ShareComposerView: View {
    // MARK: - Types

    private enum InputField: Hashable {
        case link
        case title
        case price
        case reason
    }

    // MARK: - Properties

    @ObservedObject var model: ShareComposerModel
    let onCancel: () -> Void
    let onSaved: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: InputField?
    @State private var visibleErrorMessage: String?
    @State private var saveNotice: String?
    @State private var errorDismissTask: Task<Void, Never>?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isLoadingSelectedPhoto = false
    @State private var photoSelectionMessage: String?
    private let linkPreviewService = LinkPreviewService()
    private let reviewDayOptions = [1, 3, 5, 7, 10]

    // MARK: - Computed Properties

    private var categories: [String] {
        WishCategoryRepository().load()
    }

    private var cardShadowColor: Color {
        .black.opacity(colorScheme == .dark ? 0.12 : 0.04)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("상품 링크", optional: false) {
                        TextField("https://…", text: $model.link)
                            .font(DuGoFont.body16Regular.font)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .link)
                            .frame(minHeight: 48)
                            .onSubmit {
                                presentInvalidLinkErrorIfNeeded()
                                focusedField = nil
                            }
                    }

                    if model.isReadingLink {
                        editorCard {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("공유한 링크를 읽고 있어요")
                                    .font(DuGoFont.body14Regular.font)
                                    .foregroundStyle(DuGoTheme.secondary)
                            }
                        }
                    }

                    if showsDetails {
                        section("상품 정보", optional: false) {
                            if isShowingProductLoading {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("상품 정보를 불러오는 중이에요")
                                        .font(DuGoFont.body14Regular.font)
                                        .foregroundStyle(DuGoTheme.secondary)
                                }
                                .frame(minHeight: 54)
                            } else {
                                VStack(spacing: 0) {
                                    productImage
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 16)
                                        .background { autofillBackground(for: .image) }

                                    cardDivider

                                    TextField("상품 이름", text: $model.title)
                                        .font(DuGoFont.body16Regular.font)
                                        .focused($focusedField, equals: .title)
                                        .frame(minHeight: 54)
                                        .background { autofillBackground(for: .title) }

                                    cardDivider

                                    TextField("가격 (원)", text: $model.price)
                                        .font(DuGoFont.body16Regular.font)
                                        .keyboardType(.numberPad)
                                        .focused($focusedField, equals: .price)
                                        .frame(minHeight: 54)
                                        .background { autofillBackground(for: .price) }

                                    cardDivider

                                    HStack {
                                        Text("카테고리")
                                            .font(DuGoFont.body16Regular.font)
                                            .foregroundStyle(DuGoTheme.ink)

                                        Spacer()

                                        Picker("카테고리", selection: $model.category) {
                                            ForEach(categories, id: \.self) { category in
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
                        } footer: {
                            if !model.isLoadingPreview,
                                model.previewedLink == model.link
                            {
                                Text("상품 정보를 채웠어요 가격이 맞는지 확인해주세요")
                            }
                        }
                        .transition(revealTransition)

                        if showsAdditionalDetails {
                            Group {
                                section("사고 싶은 이유") {
                                    TextField("어떤 순간에 필요할까요?", text: $model.reason, axis: .vertical)
                                        .font(DuGoFont.body16Regular.font)
                                        .lineLimit(4...7)
                                        .focused($focusedField, equals: .reason)
                                        .frame(minHeight: 96, alignment: .topLeading)
                                }

                                section("다시 만나는 날") {
                                    VStack(alignment: .leading, spacing: 16) {
                                        Toggle("다시 볼 날짜 정하기", isOn: $model.hasReviewDate)
                                            .font(DuGoFont.body16Medium.font)
                                            .tint(DuGoTheme.accent)

                                        if model.hasReviewDate {
                                            cardDivider

                                            reviewDateChips
                                                .padding(.horizontal, -16)

                                            cardDivider

                                            Toggle("알림 받기", isOn: $model.wantsReminder)
                                                .font(DuGoFont.body16Medium.font)
                                                .tint(DuGoTheme.accent)
                                        }
                                    }
                                } footer: {
                                    if model.hasReviewDate && model.wantsReminder {
                                        Text("선택한 날 \(ReminderTimePreference.displayText)에 알림을 보내드려요")
                                    }
                                }
                            }
                            .transition(revealTransition)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 48)
                .animation(revealAnimation, value: showsDetails)
                .animation(revealAnimation, value: showsAdditionalDetails)
            }
            .scrollDismissesKeyboard(.interactively)
            .dugoScreen()
            .navigationTitle("마음 담기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소", action: onCancel)
                        .tint(DuGoTheme.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
                        model.isSaving = true
                        focusedField = nil
                        Task {
                            defer { model.isSaving = false }
                            do {
                                if let notice = try await model.save() {
                                    saveNotice = notice
                                } else {
                                    onSaved()
                                }
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .tint(DuGoTheme.accent)
                    .fontWeight(.semibold)
                    .disabled(model.validURL == nil || model.isSaving || saveNotice != nil)
                }
            }
            .dismissKeyboardOnBackgroundTap()
            .alert("마음은 저장했어요", isPresented: Binding(
                get: { saveNotice != nil },
                set: { if !$0 { saveNotice = nil } }
            )) {
                Button("확인", action: onSaved)
            } message: {
                Text(saveNotice ?? "")
            }
            .overlay(alignment: .top) {
                if let visibleErrorMessage {
                    shareErrorToast(visibleErrorMessage)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .top).combined(with: .opacity)
                        )
                        .allowsHitTesting(false)
                        .zIndex(10)
                }
            }
            .onChange(of: focusedField) { previousField, currentField in
                if previousField == .link, currentField != .link {
                    presentInvalidLinkErrorIfNeeded()
                }

                if previousField == .price, currentField != .price {
                    model.formatPrice()
                } else if currentField == .price {
                    model.preparePriceForEditing()
                }
            }
            .onChange(of: model.errorMessage, initial: true) { _, message in
                guard let message, !message.isEmpty else { return }
                presentErrorToast(message)
            }
            .onDisappear { errorDismissTask?.cancel() }
            .task(id: model.link) {
                selectedPhoto = nil
                photoSelectionMessage = nil
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                    model.preparePreview()
                }
                guard model.validURL != nil else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await model.loadPreview(
                    animate: !reduceMotion,
                    isEditingPrice: focusedField == .price
                )
            }
            .task(id: model.highlightedFields) {
                guard !model.highlightedFields.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                    model.highlightedFields = []
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                await loadSelectedPhoto(selectedPhoto)
            }
        }
    }

    // MARK: - Subviews

    private var productImage: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let data = model.imageData, let image = UIImage(data: data) {
                HStack(spacing: 14) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            if isLoadingSelectedPhoto {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.black.opacity(0.35))

                                ProgressView()
                                    .tint(.white)
                            }
                        }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedPhoto == nil ? "대표 사진을 가져왔어요" : "대표 사진을 추가했어요")
                            .font(DuGoFont.button14Medium.font)
                            .foregroundStyle(DuGoTheme.ink)

                        if selectedPhoto == nil {
                            HStack(spacing: 12) {
                                Button {
                                    Task { await model.loadPreview(animate: !reduceMotion) }
                                } label: {
                                    Text("다시 불러오기")
                                        .font(DuGoFont.caption12Regular.font)
                                        .foregroundStyle(DuGoTheme.secondary)
                                        .underline()
                                }
                                .buttonStyle(.plain)

                                galleryPicker("사진 바꾸기")
                            }
                        } else {
                            galleryPicker("사진 바꾸기")
                        }
                    }
                }
            } else if isLoadingSelectedPhoto {
                HStack(spacing: 10) {
                    ProgressView()

                    Text("사진을 추가하는 중이에요")
                        .font(DuGoFont.body14Regular.font)
                        .foregroundStyle(DuGoTheme.secondary)
                }
                .frame(minHeight: 54)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("대표 사진을 찾지 못했어요")
                        .font(DuGoFont.body14Regular.font)
                        .foregroundStyle(DuGoTheme.secondary)

                    galleryPicker("갤러리에서 직접 추가")
                }
                .frame(minHeight: 54, alignment: .leading)
            }

            if let photoSelectionMessage {
                Text(photoSelectionMessage)
                    .font(DuGoFont.caption12Regular.font)
                    .foregroundStyle(.red)
            }
        }
    }

    private func galleryPicker(_ title: String) -> some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Text(title)
                .font(DuGoFont.caption12Regular.font)
                .foregroundStyle(DuGoTheme.secondary)
                .underline()
        }
    }

    private func section<Content: View, Footer: View>(
        _ title: String,
        optional: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title, optional: optional)

            let verticalSpacing: CGFloat = {
                switch title {
                case "상품 링크": return 6
                case "상품 정보": return 0
                default: return 16
                }
            }()

            editorCard(verticalSpacing: verticalSpacing) {
                content()
            }
            footer()
                .font(DuGoFont.caption12Regular.font)
                .foregroundStyle(DuGoTheme.secondary)
        }
    }

    private func section<Content: View>(
        _ title: String,
        optional: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        section(title, optional: optional, content: content) { EmptyView() }
    }

    private func sectionTitle(_ title: String, optional: Bool) -> some View {
        Text(title)
            .font(DuGoFont.title18SemiBold.font)
            .foregroundStyle(DuGoTheme.ink)
            .overlay(alignment: .topTrailing) {
                if !optional {
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
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(DuGoTheme.surface)
                    .shadow(color: cardShadowColor, radius: 5)
            }
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(DuGoTheme.border.opacity(0.65))
            .frame(height: 1)
            .padding(.horizontal, -16)
    }

    private var reviewDateChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(reviewDayOptions, id: \.self) { days in
                    let isSelected = selectedReviewDays == days

                    Button {
                        selectReviewDay(days)
                    } label: {
                        Text(days == 1 ? "내일" : "\(days)일 뒤")
                            .font(DuGoFont.button14Medium.font)
                            .foregroundStyle(isSelected ? DuGoTheme.onAccent : DuGoTheme.secondary)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background {
                                Capsule()
                                    .fill(isSelected ? DuGoTheme.accent : DuGoTheme.surface)
                                    .shadow(color: cardShadowColor, radius: 4)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .frame(height: 44)
    }

    private var selectedReviewDays: Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let selectedDay = calendar.startOfDay(for: model.reviewDate)
        return calendar.dateComponents([.day], from: today, to: selectedDay).day
    }

    // MARK: - Methods

    private func selectReviewDay(_ days: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        model.reviewDate = calendar.date(byAdding: .day, value: days, to: today) ?? today
    }

    private func loadSelectedPhoto(_ photo: PhotosPickerItem) async {
        isLoadingSelectedPhoto = true
        photoSelectionMessage = nil
        defer { isLoadingSelectedPhoto = false }

        do {
            guard let data = try await photo.loadTransferable(type: Data.self),
                let image = UIImage(data: data),
                let imageData = linkPreviewService.resizedJPEGData(from: image)
            else {
                photoSelectionMessage = "사진을 불러오지 못했어요 다시 선택해주세요"
                selectedPhoto = nil
                return
            }

            try Task.checkCancellation()
            guard selectedPhoto == photo, !model.isSaving else { return }

            withAnimation(revealAnimation) {
                model.imageData = imageData
            }
        } catch is CancellationError {
        } catch {
            photoSelectionMessage = "사진을 불러오지 못했어요 다시 선택해주세요"
            selectedPhoto = nil
        }
    }

    // MARK: - Computed Properties

    private var showsDetails: Bool { model.validURL != nil }

    private var showsAdditionalDetails: Bool {
        model.previewedLink == model.link
    }

    private var isShowingProductLoading: Bool {
        model.isLoadingPreview || (showsDetails && model.previewedLink != model.link)
    }

    private var revealAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.28)
    }

    private var revealTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    // MARK: - Methods

    private func presentInvalidLinkErrorIfNeeded() {
        let trimmed = model.link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, model.validURL == nil else { return }
        model.errorMessage = DraftError.invalidLink.errorDescription
    }

    private func presentErrorToast(_ message: String) {
        errorDismissTask?.cancel()

        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            visibleErrorMessage = message
        }

        errorDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) {
                if visibleErrorMessage == message {
                    visibleErrorMessage = nil
                }
            }

            if model.errorMessage == message {
                model.errorMessage = nil
            }
        }
    }

    private func shareErrorToast(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(DuGoFont.button16Medium.font)

            Text(message)
                .font(DuGoFont.button14Medium.font)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DuGoTheme.background)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(
            DuGoTheme.ink,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 5)
    }

    private func autofillBackground(for field: ShareComposerModel.AutofilledField) -> some View {
        Rectangle()
            .fill(DuGoTheme.accent.opacity(0.12))
            .opacity(model.highlightedFields.contains(field) ? 1 : 0)
            .padding(.horizontal, -16)
            .allowsHitTesting(false)
    }
}
