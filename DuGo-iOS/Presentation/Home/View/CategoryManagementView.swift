//
//  CategoryManagementView.swift
//  DuGo-iOS
//
//  Created by 김승원 on 1/10/26.
//

import SwiftUI

struct CategoryManagementView: View {
    // MARK: - Types

    private enum ManagementAlert: Identifiable {
        case limitReached
        case delete(String)

        var id: String {
            switch self {
            case .limitReached: "limitReached"
            case .delete(let category): "delete.\(category)"
            }
        }
    }

    // MARK: - Properties

    @ObservedObject private var viewModel: HomeViewModel
    @State private var isShowingAddSheet = false
    @State private var editingCategory: String?
    @State private var editedName = ""
    @State private var renameError: String?
    @State private var managementAlert: ManagementAlert?
    @State private var editMode: EditMode = .inactive
    @FocusState private var focusedCategory: String?

    // MARK: - Initializer

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body

    var body: some View {
        List {
            categoryHeader
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .listRowInsets(
                    EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16)
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            ForEach(movableCategories, id: \.self) { category in
                categoryRow(category)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(
                        EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                guard saveInlineCategory() else { return }
                viewModel.moveCategory(fromOffsets: source, toOffset: destination)
            }

            categoryRow(WishCategory.other.rawValue)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .listRowInsets(
                    EdgeInsets(top: 5, leading: 16, bottom: 40, trailing: 16)
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .moveDisabled(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .navigationTitle("카테고리 관리")
        .navigationBarTitleDisplayMode(.inline)
        .dugoScreen()
        .dugoErrorToast(message: $viewModel.errorMessage)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard saveInlineCategory() else { return }
                    if viewModel.categories.count >= 10 {
                        managementAlert = .limitReached
                    } else {
                        isShowingAddSheet = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DuGoTheme.ink)
                        .frame(width: 24, height: 24)
                }
                .tint(DuGoTheme.ink)
                .disabled(viewModel.isWorking)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnBackgroundTap()
        .onAppear { viewModel.reload() }
        .onDisappear { saveInlineCategory() }
        .onChange(of: focusedCategory) { previous, current in
            guard let previous, previous != current else { return }
            saveInlineCategory(expected: previous)
        }
        .sheet(isPresented: $isShowingAddSheet) {
            CategoryEditorSheet(viewModel: viewModel)
        }
        .alert(item: $managementAlert) { alert in
            switch alert {
            case .limitReached:
                Alert(
                    title: Text("카테고리는 최대 10개까지 만들 수 있어요"),
                    dismissButton: .cancel(Text("확인"))
                )
            case .delete(let category):
                Alert(
                    title: Text("\(category) 카테고리를 삭제할까요?"),
                    message: Text("이 카테고리에 담긴 상품은 모두 미분류로 이동해요"),
                    primaryButton: .cancel(Text("취소")),
                    secondaryButton: .destructive(Text("삭제")) {
                        deleteCategory(category)
                    }
                )
            }
        }
    }

    // MARK: - Subviews

    private var categoryHeader: some View {
        HStack {
            Text("카테고리 \(viewModel.categories.count)개")
                .applyDuGoFont(.body14Regular)
                .foregroundStyle(DuGoTheme.secondary)

            Spacer()

            Button(editMode.isEditing ? "완료" : "수정") {
                toggleEditing()
            }
            .applyDuGoFont(.button14Medium)
            .foregroundStyle(DuGoTheme.accent)
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .contentTransition(.identity)
            .animation(nil, value: editMode.isEditing)
        }
    }

    private var movableCategories: [String] {
        viewModel.categories.filter { $0 != WishCategory.other.rawValue }
    }

    private func categoryRow(_ category: String) -> some View {
        let isProtected = category == WishCategory.other.rawValue
        let isRenaming = editingCategory == category
        let count = viewModel.keptItems.filter { $0.categoryRaw == category }.count

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if isRenaming {
                    TextField("카테고리 이름", text: $editedName)
                        .applyDuGoFont(.body16Medium)
                        .foregroundStyle(DuGoTheme.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focusedCategory, equals: category)
                        .onSubmit { saveInlineCategory(expected: category) }
                        .onChange(of: editedName) { _, value in
                            if value.count > 5 {
                                editedName = String(value.prefix(5))
                            }
                            renameError = nil
                        }

                    Text("\(editedName.count)/5")
                        .applyDuGoFont(.caption12Regular)
                        .foregroundStyle(DuGoTheme.secondary)
                } else {
                    Text(category)
                        .applyDuGoFont(.body16Medium)
                        .foregroundStyle(DuGoTheme.ink)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if editMode.isEditing && !isProtected {
                        Button {
                            beginRenaming(category)
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(DuGoTheme.secondary)
                                .frame(width: 36, height: 40)
                        }
                        .buttonStyle(.plain)

                        Button {
                            guard saveInlineCategory() else { return }
                            managementAlert = .delete(category)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(DuGoTheme.accent)
                                .frame(width: 36, height: 40)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("\(count)개")
                            .applyDuGoFont(.caption12Regular)
                            .foregroundStyle(DuGoTheme.secondary)

                    }
                }
            }

            if isRenaming, let renameError {
                Text(renameError)
                    .applyDuGoFont(.caption12Regular)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 58)
        .dugoRoundedSurface()
    }

    // MARK: - Methods

    private func toggleEditing() {
        guard saveInlineCategory() else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            editMode = editMode.isEditing ? .inactive : .active
        }
    }

    private func beginRenaming(_ category: String) {
        guard saveInlineCategory() else { return }
        editingCategory = category
        editedName = category
        renameError = nil
        focusedCategory = category
    }

    @discardableResult
    private func saveInlineCategory(expected category: String? = nil) -> Bool {
        guard let original = editingCategory else { return true }
        guard category == nil || category == original else { return true }

        do {
            try viewModel.renameCategory(original, to: editedName)
            editingCategory = nil
            renameError = nil
            if focusedCategory == original {
                focusedCategory = nil
            }
            return true
        } catch {
            renameError = error.localizedDescription
            return false
        }
    }

    private func deleteCategory(_ category: String) {
        do {
            try viewModel.deleteCategory(category)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
