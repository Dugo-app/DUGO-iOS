//
//  CategoryManagementView.swift
//  DuGo-iOS
//
//  Created by 김승원 on 1/10/26.
//

import SwiftData
import SwiftUI

struct CategoryManagementView: View {
    // MARK: - Properties

    @ObservedObject private var viewModel: HomeViewModel
    @State private var newCategory = ""
    @State private var editingCategory: String?
    @State private var editedCategory = ""
    @State private var categoryToDelete: String?
    @State private var validationMessage: String?
    @State private var isShowingCategoryLimitAlert = false
    @State private var editMode: EditMode = .inactive
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case newCategory
        case editedCategory
    }

    // MARK: - Initializer

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body

    var body: some View {
        List {
            addSection
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .listRowInsets(
                    EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16)
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            categoryHeader
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .listRowInsets(
                    EdgeInsets(top: 12, leading: 16, bottom: 5, trailing: 16)
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            ForEach(movableCategories, id: \.self) { category in
                movableCategoryRow(category)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(
                        EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove(perform: viewModel.moveCategory)

            if let uncategorizedCategory {
                categoryRow(uncategorizedCategory)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(
                        EdgeInsets(top: 5, leading: 16, bottom: 40, trailing: 16)
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .moveDisabled(true)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .navigationTitle("카테고리 관리")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleReordering()
                } label: {
                    Image(systemName: editMode.isEditing ? "checkmark" : "arrow.up.arrow.down")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DuGoTheme.ink)
                        .frame(width: 24, height: 24)
                        .contentTransition(.identity)
                        .animation(nil, value: editMode.isEditing)
                }
                .tint(DuGoTheme.ink)
                .accessibilityLabel(editMode.isEditing ? "순서 변경 완료" : "카테고리 순서 변경")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnBackgroundTap()
        .dugoScreen()
        .dugoErrorToast(message: $viewModel.errorMessage)
        .dugoConfirmationAlert(
            title: "카테고리를 삭제할까요?",
            message: "이 카테고리에 담긴 상품은 모두 미분류로 이동해요 삭제한 카테고리는 되돌릴 수 없어요",
            confirmTitle: "삭제",
            isPresented: deleteAlertBinding
        ) {
            deleteSelectedCategory()
        }
    }

    // MARK: - Subviews

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("새 카테고리")

            HStack(spacing: 10) {
                TextField("카테고리 이름", text: $newCategory)
                    .font(DuGoFont.body16Regular.font)
                    .foregroundStyle(DuGoTheme.ink)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .newCategory)
                    .onSubmit(addCategory)
                    .onChange(of: newCategory) { _, value in
                        limitLength(of: &newCategory, value: value)
                        validationMessage = nil
                    }

                Text("\(newCategory.count)/5")
                    .applyDuGoFont(.caption12Regular)
                    .foregroundStyle(DuGoTheme.secondary)
            }
            .frame(minHeight: 58)
            .padding(.horizontal, 14)
            .dugoRoundedSurface()

            if let validationMessage {
                Text(validationMessage)
                    .applyDuGoFont(.caption12Regular)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
        }
        .alert("카테고리는 최대 10개까지 만들 수 있어요", isPresented: $isShowingCategoryLimitAlert) {
            Button("확인", role: .cancel) {}
        }
    }

    private var categoryHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            sectionTitle("카테고리")

            Spacer()

            Text("\(viewModel.categories.count)개")
                .applyDuGoFont(.caption12Regular)
                .foregroundStyle(DuGoTheme.secondary)
        }
    }

    private var movableCategories: [String] {
        viewModel.categories.filter { $0 != WishCategory.other.rawValue }
    }

    private var uncategorizedCategory: String? {
        viewModel.categories.first { $0 == WishCategory.other.rawValue }
    }

    @ViewBuilder
    private func movableCategoryRow(_ category: String) -> some View {
        if editMode.isEditing {
            categoryRow(category)
        } else {
            categoryRow(category)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        categoryToDelete = category
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }

                    Button {
                        beginEditing(category)
                    } label: {
                        Label("수정", systemImage: "pencil")
                    }
                    .tint(DuGoTheme.secondary)
                }
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: String) -> some View {
        let isProtected = category == WishCategory.other.rawValue

        HStack(spacing: 12) {
            if editingCategory == category {
                TextField("카테고리 이름", text: $editedCategory)
                    .font(DuGoFont.body16Medium.font)
                    .foregroundStyle(DuGoTheme.ink)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .editedCategory)
                    .onSubmit { saveEditedCategory(category) }
                    .onChange(of: editedCategory) { _, value in
                        limitLength(of: &editedCategory, value: value)
                        validationMessage = nil
                    }

                Button("취소") {
                    cancelEditing()
                }
                .applyDuGoFont(.button14Medium)
                .foregroundStyle(DuGoTheme.secondary)

                Button("저장") {
                    saveEditedCategory(category)
                }
                .applyDuGoFont(.button14Medium)
                .foregroundStyle(DuGoTheme.accent)
                .disabled(editedCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Text(category)
                    .applyDuGoFont(.body16Medium)
                    .foregroundStyle(DuGoTheme.ink)

                Spacer()

                if isProtected {
                    Text("기본")
                        .applyDuGoFont(.caption12Regular)
                        .foregroundStyle(DuGoTheme.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .dugoRoundedSurface()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .applyDuGoFont(.body14Regular)
            .foregroundStyle(DuGoTheme.secondary)
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { categoryToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    categoryToDelete = nil
                }
            }
        )
    }

    // MARK: - Methods

    private func addCategory() {
        do {
            try viewModel.addCategory(newCategory)
            newCategory = ""
            focusedField = nil
            validationMessage = nil
        } catch WishCategoryManagementError.limitReached {
            isShowingCategoryLimitAlert = true
            validationMessage = nil
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func beginEditing(_ category: String) {
        editingCategory = category
        editedCategory = category
        validationMessage = nil
        focusedField = .editedCategory
    }

    private func cancelEditing() {
        editingCategory = nil
        validationMessage = nil
        focusedField = nil
        DispatchQueue.main.async {
            editedCategory = ""
        }
    }

    private func saveEditedCategory(_ category: String) {
        guard editingCategory == category else { return }

        do {
            try viewModel.renameCategory(category, to: editedCategory)
            cancelEditing()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func deleteSelectedCategory() {
        guard let categoryToDelete else { return }
        do {
            try viewModel.deleteCategory(categoryToDelete)
            self.categoryToDelete = nil
            validationMessage = nil
        } catch {
            self.categoryToDelete = nil
            validationMessage = error.localizedDescription
        }
    }

    private func toggleReordering() {
        if editMode.isEditing {
            editMode = .inactive
        } else {
            cancelEditing()
            editMode = .active
        }
    }

    private func limitLength(of text: inout String, value: String) {
        if value.count > 5 {
            text = String(value.prefix(5))
        }
    }
}
