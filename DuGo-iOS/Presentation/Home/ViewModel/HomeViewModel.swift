//
//  HomeViewModel.swift
//  DuGo-iOS
//
//  Created by 김승원 on 19/9/26.
//

import Combine
import Foundation
import SwiftData

@MainActor
final class HomeViewModel: ObservableObject {
    // MARK: - Properties

    @Published var searchText = ""
    @Published var selectedCategory: String?
    @Published private(set) var categories: [String]
    @Published private(set) var items: [WishItem] = []
    @Published private(set) var records: [DecisionRecord] = []
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var reminderNotice: String?
    @Published private(set) var scheduledIDs: Set<UUID> = []
    private let context: ModelContext
    private let reminders: ReminderManager
    private let categoryRepository: WishCategoryRepository

    // MARK: - Initializer

    init(context: ModelContext, reminders: ReminderManager) {
        let categoryRepository = WishCategoryRepository()
        self.context = context
        self.reminders = reminders
        self.categoryRepository = categoryRepository
        categories = categoryRepository.load()
        context.autosaveEnabled = false
        migrateLegacyCategoriesIfNeeded()
        reload()
    }

    // MARK: - Computed Properties

    var keptItems: [WishItem] { items.filter { $0.status == .keeping } }
    var filteredItems: [WishItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return keptItems.filter { item in
            (selectedCategory == nil || item.categoryRaw == selectedCategory)
                && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
                    || item.reason.localizedCaseInsensitiveContains(query))
        }
    }
    var reviewItems: [WishItem] {
        keptItems.filter { $0.reviewAt.map { $0 <= .now } ?? false }
            .sorted { ($0.reviewAt ?? .distantFuture) < ($1.reviewAt ?? .distantFuture) }
    }

    // MARK: - Methods

    func item(id: UUID) -> WishItem? { items.first { $0.id == id } }
    func resetFilters() {
        searchText = ""
        selectedCategory = nil
    }

    func reload() {
        do {
            let sharedWishes = SharedLinkInbox.pending()
            if !sharedWishes.isEmpty {
                let existingIDs = Set(try context.fetch(FetchDescriptor<WishItem>()).map(\.id))
                for shared in sharedWishes where !existingIDs.contains(shared.id) {
                    let item = WishItem(
                        title: shared.title,
                        link: shared.link,
                        category: WishCategory(rawValue: shared.categoryRaw) ?? .other,
                        price: shared.price,
                        reason: shared.reason,
                        reviewAt: shared.reviewAt,
                        wantsReminder: shared.wantsReminder ?? false,
                        imageData: shared.imageData
                    )
                    item.categoryRaw = shared.categoryRaw
                    item.id = shared.id
                    item.createdAt = shared.createdAt
                    context.insert(item)
                }
                try context.save()
                for shared in sharedWishes {
                    try? SharedLinkInbox.remove(id: shared.id)
                }
            }
            items = try context.fetch(
                FetchDescriptor<WishItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            )
            records = try context.fetch(
                FetchDescriptor<DecisionRecord>(sortBy: [
                    SortDescriptor(\.createdAt, order: .reverse)
                ])
            )
            let categoryEntries = try context.fetch(FetchDescriptor<CategoryEntry>())
            categories = resolvedCategories(from: categoryEntries)
            try reconcileItemsWithDeletedCategories(categoryEntries)
            try synchronizeCategoriesWithItems(categoryEntries)
            categoryRepository.save(categories)
            if let selectedCategory, !categories.contains(selectedCategory) {
                self.selectedCategory = nil
            }
        } catch { errorMessage = "보관함을 불러오지 못했어요 다시 시도해주세요" }
    }

    func refresh() async {
        reload()
        if keptItems.contains(where: \.wantsReminder) {
            await reminders.requestPermissionIfNeeded()
        }
        await syncReminders()
    }

    func syncReminders() async {
        let requests = keptItems.compactMap { item -> WishReminder? in
            guard item.wantsReminder, let date = item.reviewAt else { return nil }
            return WishReminder(itemID: item.id, title: item.title, date: date)
        }
        await reminders.synchronize(requests)
        scheduledIDs = reminders.scheduledIDs
        reminderNotice = reminders.notice
    }

    func save(_ draft: WishDraft, editing item: WishItem? = nil) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let values = try draft.validated(previousReviewDate: item?.reviewAt)
            let target: WishItem
            if let item {
                target = item
            } else {
                target = WishItem(title: values.title, link: values.link.absoluteString)
                context.insert(target)
            }
            target.title = values.title
            target.link = values.link.absoluteString
            target.categoryRaw = draft.category
            target.price = values.price
            target.reason = draft.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if target.initialReason.isEmpty {
                target.initialReason = target.reason
            }
            target.imageData = draft.imageData
            target.reviewAt = draft.hasReviewDate ? draft.reviewDate : nil
            target.wantsReminder =
                draft.hasReviewDate && draft.wantsReminder && target.status == .keeping
            try context.save()
            reload()
            resetFilters()
            if target.wantsReminder {
                await reminders.requestPermissionIfNeeded()
            }
            await syncReminders()
            return true
        } catch {
            context.rollback()
            errorMessage =
                (error as? DraftError)?.errorDescription ?? "저장하지 못했어요 입력한 내용은 유지했으니 다시 시도해주세요"
            return false
        }
    }

    func decide(
        _ item: WishItem,
        decision: WishDecision,
        feeling: String,
        note: String,
        nextDate: Date? = nil,
        notify: Bool = false
    ) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        if let nextDate, decision == .wait, nextDate <= .now {
            errorMessage = DraftError.pastDate.errorDescription
            return false
        }
        switch decision {
        case .purchase: item.statusRaw = WishStatus.purchased.rawValue
        case .release: item.statusRaw = WishStatus.released.rawValue
        case .wait, .restore: item.statusRaw = WishStatus.keeping.rawValue
        }
        item.reviewAt = decision == .wait ? nextDate : nil
        item.wantsReminder = decision == .wait && nextDate != nil && notify
        context.insert(
            DecisionRecord(
                item: item,
                decision: decision,
                feeling: feeling,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        do {
            try context.save()
            reload()
            if item.wantsReminder {
                await reminders.requestPermissionIfNeeded()
            }
            await syncReminders()
            return true
        } catch {
            context.rollback()
            errorMessage = "선택을 저장하지 못했어요 다시 시도해주세요"
            return false
        }
    }

    func delete(_ item: WishItem) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        for record in records where record.itemID == item.id { context.delete(record) }
        context.delete(item)
        do {
            try context.save()
            reload()
            await syncReminders()
            return true
        } catch {
            context.rollback()
            errorMessage = "삭제하지 못했어요 다시 시도해주세요"
            return false
        }
    }

    func addCategory(_ rawName: String) throws {
        guard categories.count < 10 else {
            throw WishCategoryManagementError.limitReached
        }
        let name = try validatedCategoryName(rawName)
        guard !categories.contains(name) else {
            throw WishCategoryManagementError.duplicate
        }

        let uncategorized = WishCategory.other.rawValue
        let insertionIndex = categories.firstIndex(of: uncategorized) ?? categories.endIndex
        do {
            let entries = try ensureCategoryEntries()
            updateCategoryEntry(
                name: name,
                sortOrder: insertionIndex,
                isDeleted: false,
                entries: entries
            )
            try context.save()
            categories.insert(name, at: insertionIndex)
            categoryRepository.save(categories)
        } catch {
            context.rollback()
            reload()
            throw WishCategoryManagementError.saveFailed
        }
    }

    func renameCategory(_ category: String, to rawName: String) throws {
        guard category != WishCategory.other.rawValue else {
            throw WishCategoryManagementError.protected
        }
        guard let index = categories.firstIndex(of: category) else {
            throw WishCategoryManagementError.missing
        }

        let name = try validatedCategoryName(rawName)
        guard name == category || !categories.contains(name) else {
            throw WishCategoryManagementError.duplicate
        }
        guard name != category else { return }

        do {
            let entries = try ensureCategoryEntries()
            let changedAt = Date.now
            updateCategoryEntry(
                name: category,
                sortOrder: index,
                isDeleted: true,
                replacementName: name,
                updatedAt: changedAt,
                entries: entries
            )
            updateCategoryEntry(
                name: name,
                sortOrder: index,
                isDeleted: false,
                updatedAt: changedAt,
                entries: entries
            )
            for item in items where item.categoryRaw == category {
                item.categoryRaw = name
            }
            try context.save()
            categories[index] = name
            categoryRepository.save(categories)
            if selectedCategory == category {
                selectedCategory = name
            }
            reload()
        } catch {
            context.rollback()
            reload()
            throw WishCategoryManagementError.saveFailed
        }
    }

    func deleteCategory(_ category: String) throws {
        guard category != WishCategory.other.rawValue else {
            throw WishCategoryManagementError.protected
        }
        guard categories.contains(category) else {
            throw WishCategoryManagementError.missing
        }

        do {
            let entries = try ensureCategoryEntries()
            updateCategoryEntry(
                name: category,
                sortOrder: categories.firstIndex(of: category) ?? 0,
                isDeleted: true,
                entries: entries
            )
            for item in items where item.categoryRaw == category {
                item.categoryRaw = WishCategory.other.rawValue
            }
            try context.save()
            categories.removeAll { $0 == category }
            categoryRepository.save(categories)
            if selectedCategory == category {
                selectedCategory = nil
            }
            reload()
        } catch {
            context.rollback()
            reload()
            throw WishCategoryManagementError.saveFailed
        }
    }

    func moveCategory(fromOffsets source: IndexSet, toOffset destination: Int) {
        let uncategorized = WishCategory.other.rawValue
        var movableCategories = categories.filter { $0 != uncategorized }

        let sourceIndices = source.sorted()
        guard sourceIndices.allSatisfy({ movableCategories.indices.contains($0) }) else { return }
        let movingCategories = sourceIndices.map { movableCategories[$0] }
        for index in sourceIndices.reversed() {
            movableCategories.remove(at: index)
        }

        let removedBeforeDestination = sourceIndices.filter { $0 < destination }.count
        let insertionIndex = min(
            max(destination - removedBeforeDestination, 0),
            movableCategories.count
        )
        movableCategories.insert(contentsOf: movingCategories, at: insertionIndex)

        do {
            let entries = try ensureCategoryEntries()
            let changedAt = Date.now
            for (index, name) in movableCategories.enumerated() {
                updateCategoryEntry(
                    name: name,
                    sortOrder: index,
                    isDeleted: false,
                    updatedAt: changedAt,
                    entries: entries
                )
            }
            try context.save()
            categories = movableCategories + [uncategorized]
            categoryRepository.save(categories)
        } catch {
            context.rollback()
            reload()
            errorMessage = WishCategoryManagementError.saveFailed.errorDescription
        }
    }

    // MARK: - Private Methods

    private func validatedCategoryName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WishCategoryManagementError.empty }
        guard name.count <= 5 else { throw WishCategoryManagementError.tooLong }
        guard name != WishCategory.other.rawValue else {
            throw WishCategoryManagementError.duplicate
        }
        return name
    }

    private func migrateLegacyCategoriesIfNeeded() {
        guard !categoryRepository.hasMigratedToCloud else { return }
        guard categoryRepository.hasStoredCategories else {
            categoryRepository.markMigratedToCloud()
            return
        }

        do {
            let entries = try context.fetch(FetchDescriptor<CategoryEntry>())
            let storedNames = Set(entries.map(\.name))
            let legacyNames = Set(categories)
            for (index, name) in categories.enumerated()
            where name != WishCategory.other.rawValue && !storedNames.contains(name) {
                context.insert(
                    CategoryEntry(
                        name: name,
                        sortOrder: index,
                        updatedAt: Date(timeIntervalSince1970: 0)
                    )
                )
            }
            for name in WishCategoryRepository.defaultCategories
            where name != WishCategory.other.rawValue
                && !legacyNames.contains(name)
                && !storedNames.contains(name) {
                context.insert(
                    CategoryEntry(
                        name: name,
                        sortOrder: 0,
                        isDeleted: true
                    )
                )
            }
            try context.save()
            categoryRepository.markMigratedToCloud()
        } catch {
            context.rollback()
            errorMessage = "카테고리를 동기화할 준비를 하지 못했어요 다시 실행해 주세요"
        }
    }

    private func resolvedCategories(from entries: [CategoryEntry]) -> [String] {
        let latest = latestCategoryEntries(from: entries)
        let active = latest.values
            .filter { !$0.isDeleted }
            .map { (name: $0.name, sortOrder: $0.sortOrder) }
        let implicitDefaults = WishCategoryRepository.defaultCategories.enumerated()
            .filter { $0.element != WishCategory.other.rawValue && latest[$0.element] == nil }
            .map { (name: $0.element, sortOrder: $0.offset) }
        let ordered = (active + implicitDefaults)
            .sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.name < $1.name
                    : $0.sortOrder < $1.sortOrder
            }
            .map(\.name)
        return ordered + [WishCategory.other.rawValue]
    }

    private func latestCategoryEntries(from entries: [CategoryEntry]) -> [String: CategoryEntry] {
        var latest: [String: CategoryEntry] = [:]
        for entry in entries {
            guard let current = latest[entry.name] else {
                latest[entry.name] = entry
                continue
            }
            if entry.updatedAt > current.updatedAt
                || (entry.updatedAt == current.updatedAt && entry.isDeleted && !current.isDeleted)
            {
                latest[entry.name] = entry
            }
        }
        return latest
    }

    private func ensureCategoryEntries() throws -> [CategoryEntry] {
        var entries = try context.fetch(FetchDescriptor<CategoryEntry>())
        let storedNames = Set(entries.map(\.name))
        for (index, name) in categories.enumerated()
        where name != WishCategory.other.rawValue && !storedNames.contains(name) {
            let entry = CategoryEntry(
                name: name,
                sortOrder: index,
                updatedAt: Date(timeIntervalSince1970: 0)
            )
            context.insert(entry)
            entries.append(entry)
        }
        return entries
    }

    private func updateCategoryEntry(
        name: String,
        sortOrder: Int,
        isDeleted: Bool,
        replacementName: String? = nil,
        updatedAt: Date = .now,
        entries: [CategoryEntry]
    ) {
        let entry = latestCategoryEntries(from: entries)[name]
        if let entry {
            entry.sortOrder = sortOrder
            entry.isDeleted = isDeleted
            entry.replacementName = replacementName
            entry.updatedAt = updatedAt
        } else {
            context.insert(
                CategoryEntry(
                    name: name,
                    sortOrder: sortOrder,
                    isDeleted: isDeleted,
                    replacementName: replacementName,
                    updatedAt: updatedAt
                )
            )
        }
    }

    private func reconcileItemsWithDeletedCategories(_ entries: [CategoryEntry]) throws {
        let deleted = latestCategoryEntries(from: entries).filter { $0.value.isDeleted }
        var hasChanges = false
        for item in items {
            guard let entry = deleted[item.categoryRaw] else { continue }
            item.categoryRaw = entry.replacementName ?? WishCategory.other.rawValue
            hasChanges = true
        }
        if hasChanges { try context.save() }
    }

    private func synchronizeCategoriesWithItems(_ entries: [CategoryEntry]) throws {
        let uncategorized = WishCategory.other.rawValue
        let storedNames = Set(entries.map(\.name)).union(categories)
        let missingNames =
            items
            .map(\.categoryRaw)
            .filter { !$0.isEmpty && $0 != uncategorized && !storedNames.contains($0) }

        guard !missingNames.isEmpty else { return }

        let uniqueMissingNames = Array(Set(missingNames)).sorted()
        let insertionIndex = categories.firstIndex(of: uncategorized) ?? categories.endIndex
        for (offset, name) in uniqueMissingNames.enumerated() {
            context.insert(
                CategoryEntry(
                    name: name,
                    sortOrder: insertionIndex + offset,
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
            )
        }
        try context.save()
        categories.insert(contentsOf: uniqueMissingNames, at: insertionIndex)
    }
}
