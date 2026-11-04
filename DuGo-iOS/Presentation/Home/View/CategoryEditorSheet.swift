//
//  CategoryEditorSheet.swift
//  DuGo-iOS
//
//  Created by 김승원 on 4/11/26.
//

import SwiftUI

struct CategoryEditorSheet: View {
    // MARK: - Properties

    @ObservedObject private var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedItemIDs = Set<UUID>()
    @State private var validationMessage: String?
    @FocusState private var isNameFocused: Bool

    // MARK: - Initializer

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body

    var body: some View {
        DuGoSheet(
            height: .large,
            isWorking: viewModel.isWorking,
            scrollsContent: true,
            closeAction: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 24) {
                heading

                nameSection

                itemSelectionSection
            }
        } footer: {
            DuGoPrimaryButton(
                title: primaryTitle,
                isEnabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                isLoading: viewModel.isWorking,
                action: save
            )
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnBackgroundTap()
        .onChange(of: availableItemIDs) { _, itemIDs in
            updateSelection(selectedItemIDs.intersection(itemIDs))
        }
    }

    // MARK: - Computed Properties

    private var availableItemIDs: Set<UUID> {
        Set(viewModel.keptItems.map(\.id))
    }

    private var selectedCount: Int {
        selectedItemIDs.intersection(availableItemIDs).count
    }

    private var primaryTitle: String {
        selectedCount == 0 ? "카테고리 추가" : "\(selectedCount)개 옮기고 추가"
    }

    // MARK: - Subviews

    private var heading: some View {
        Text("카테고리 추가")
            .applyDuGoFont(.display24SemiBold)
            .foregroundStyle(DuGoTheme.ink)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("카테고리 이름")
                .applyDuGoFont(.body14Regular)
                .foregroundStyle(DuGoTheme.secondary)

            HStack(spacing: 10) {
                TextField("이름을 입력해주세요", text: $name)
                    .applyDuGoFont(.body16Regular)
                    .foregroundStyle(DuGoTheme.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { isNameFocused = false }
                    .onChange(of: name) { _, value in
                        if value.count > 5 {
                            name = String(value.prefix(5))
                        }
                        validationMessage = nil
                    }

                Text("\(name.count)/5")
                    .applyDuGoFont(.caption12Regular)
                    .foregroundStyle(DuGoTheme.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .dugoRoundedSurface()

            if let validationMessage {
                Text(validationMessage)
                    .applyDuGoFont(.caption12Regular)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var itemSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("함께 옮길 상품")
                    .applyDuGoFont(.body14Regular)
                    .foregroundStyle(DuGoTheme.secondary)

                Text("\(selectedCount)개 선택")
                    .applyDuGoFont(.caption12Medium)
                    .foregroundStyle(DuGoTheme.accent)

                Spacer()
            }

            if viewModel.keptItems.isEmpty {
                emptyMessage("담아 둔 상품이 아직 없어요\n상품을 선택하지 않아도 카테고리를 만들 수 있어요")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.keptItems, id: \.id) { item in
                        selectionRow(item)
                    }
                }
            }
        }
    }

    private func selectionRow(_ item: WishItem) -> some View {
        let isSelected = selectedItemIDs.contains(item.id)

        return Button {
            var itemIDs = selectedItemIDs
            if itemIDs.contains(item.id) {
                itemIDs.remove(item.id)
            } else {
                itemIDs.insert(item.id)
            }
            updateSelection(itemIDs)
        } label: {
            HStack(spacing: 12) {
                FillWishImage(item: item, size: 48)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .applyDuGoFont(.body14Medium)
                        .foregroundStyle(DuGoTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        Text(item.categoryRaw)

                        if let price = item.price {
                            Text("·")
                            Text(price.dugoFormattedPrice)
                        }
                    }
                    .applyDuGoFont(.caption12Regular)
                    .foregroundStyle(DuGoTheme.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? DuGoTheme.accent : DuGoTheme.secondary)
                    .contentTransition(.identity)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dugoRoundedSurface(
                fill: isSelected ? DuGoTheme.accent.opacity(0.06) : DuGoTheme.surface,
                borderColor: isSelected ? DuGoTheme.accent : DuGoTheme.border
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .applyDuGoFont(.body14Regular)
            .foregroundStyle(DuGoTheme.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
    }

    // MARK: - Methods

    private func updateSelection(_ itemIDs: Set<UUID>) {
        guard itemIDs != selectedItemIDs else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedItemIDs = itemIDs
        }
    }

    private func save() {
        isNameFocused = false

        do {
            try viewModel.addCategory(name, moving: selectedItemIDs.intersection(availableItemIDs))
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
