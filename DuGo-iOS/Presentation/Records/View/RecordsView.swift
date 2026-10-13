//
//  RecordsView.swift
//  DuGo-iOS
//
//  Created by 김승원 on 19/9/26.
//

import SwiftData
import SwiftUI

struct RecordsView: View {
    // MARK: - Types

    private struct DecisionCount: Identifiable {
        let decision: WishDecision
        let count: Int

        var id: WishDecision { decision }
    }

    private struct RecordGroup: Identifiable {
        let itemID: UUID
        let records: [DecisionRecord]
        let latest: DecisionRecord
        let sortDate: Date

        var id: UUID { itemID }
    }

    // MARK: - Properties

    @ObservedObject private var viewModel: HomeViewModel
    private let scrollToTopRequest: Int
    @State private var search = ""
    @State private var filter: WishDecision?
    @State private var selectedMonth: Date?
    @State private var expandedItemIDs: Set<UUID> = []
    @State private var isSearchPresented = false
    @FocusState private var isSearchFieldFocused: Bool

    // MARK: - Initializer

    init(viewModel: HomeViewModel, scrollToTopRequest: Int = 0) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.scrollToTopRequest = scrollToTopRequest
    }

    // MARK: - Computed Properties

    private var filteredGroups: [RecordGroup] {
        let calendar = Calendar.current
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)

        return Dictionary(grouping: viewModel.records, by: \.itemID)
            .compactMap { itemID, records -> RecordGroup? in
                let ordered = records.sorted {
                    if $0.createdAt == $1.createdAt {
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    return $0.createdAt < $1.createdAt
                }
                guard let latest = ordered.last else { return nil }
                guard filter == nil || latest.decision == filter else { return nil }

                let matching = ordered.filter { record in
                    let matchesMonth = selectedMonth.map {
                        calendar.isDate(record.createdAt, equalTo: $0, toGranularity: .month)
                    } ?? true
                    let matchesSearch = text.isEmpty
                        || record.title.localizedCaseInsensitiveContains(text)
                        || record.note.localizedCaseInsensitiveContains(text)

                    return matchesMonth && matchesSearch
                }
                guard let lastMatch = matching.last else { return nil }

                return RecordGroup(
                    itemID: itemID,
                    records: ordered,
                    latest: latest,
                    sortDate: lastMatch.createdAt
                )
            }
            .sorted {
                if $0.sortDate == $1.sortDate {
                    return $0.itemID.uuidString < $1.itemID.uuidString
                }
                return $0.sortDate > $1.sortDate
            }
    }

    private var availableMonths: [Date] {
        let calendar = Calendar.current
        return Array(
            Set(
                viewModel.records.compactMap { record -> Date? in
                    let components = calendar.dateComponents(
                        [.year, .month],
                        from: record.createdAt
                    )
                    return calendar.date(from: components)
                }
            )
        )
        .sorted(by: >)
    }

    private var summaryRecords: [DecisionRecord] {
        guard let selectedMonth else { return viewModel.records }

        let calendar = Calendar.current
        return viewModel.records.filter {
            calendar.isDate($0.createdAt, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    private var decisionCounts: [DecisionCount] {
        return WishDecision.allCases.map { decision in
            DecisionCount(
                decision: decision,
                count: summaryRecords.count { $0.decision == decision }
            )
        }
    }

    private var activeDecisionCounts: [DecisionCount] {
        decisionCounts.filter { $0.count > 0 }
    }

    private var decisionTotal: Int {
        decisionCounts.reduce(0) { $0 + $1.count }
    }

    private var mostFrequentDecision: WishDecision? {
        guard let highestCount = activeDecisionCounts.map(\.count).max() else {
            return nil
        }

        let mostFrequent = activeDecisionCounts.filter { $0.count == highestCount }
        return mostFrequent.count == 1 ? mostFrequent.first?.decision : nil
    }

    @ViewBuilder
    private var decisionSummaryTitle: some View {
        let period = selectedMonth.map {
            "\(Calendar.current.component(.month, from: $0))월에는"
        } ?? "지금까지"

        if let decision = mostFrequentDecision {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    summaryText(period)
                    decisionTag(decision)
                    summaryText("를 가장 많이 선택했어요")
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        summaryText(period)
                        decisionTag(decision)
                        summaryText("를")
                    }

                    summaryText("가장 많이 선택했어요")
                }
            }
        } else if decisionTotal == 0 {
            Text("\(period) 아직 선택이 없어요")
                .applyDuGoFont(.title16Medium)
                .foregroundStyle(DuGoTheme.ink)
        } else {
            Text("\(period) \(decisionTotal)번 마음을 정리했어요")
                .applyDuGoFont(.title16Medium)
                .foregroundStyle(DuGoTheme.ink)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header

                if isSearchPresented {
                    searchField
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            recordsList
        }
        .dismissKeyboardOnBackgroundTap()
        .dugoScreen()
        .dugoErrorToast(message: $viewModel.errorMessage)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("결정 기록")
                .applyDuGoFont(.display32SemiBold)
                .foregroundStyle(DuGoTheme.ink)

            Spacer()

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    searchButton

                    HStack(spacing: 12) {
                        monthFilterMenu

                        filterMenu
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DuGoTheme.secondary)

            TextField("물건이나 결정 이유 검색", text: $search)
                .font(DuGoFont.body14Regular.font)
                .foregroundStyle(DuGoTheme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFieldFocused)

            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DuGoTheme.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
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

    private var searchButton: some View {
        Button {
            if isSearchPresented {
                search = ""
                isSearchFieldFocused = false
                withAnimation(.easeOut(duration: 0.18)) {
                    isSearchPresented = false
                }
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    isSearchPresented = true
                }
                isSearchFieldFocused = true
            }
        } label: {
            Image(systemName: isSearchPresented ? "xmark" : "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(DuGoTheme.ink)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
    }

    private var filterMenu: some View {
        Menu {
            Picker("기록 종류", selection: $filter) {
                Text("전체")
                    .tag(nil as WishDecision?)

                ForEach(WishDecision.allCases) { decision in
                    Text(decision.rawValue).tag(Optional(decision))
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.body.weight(.semibold))
                .foregroundStyle(filter == nil ? DuGoTheme.ink : DuGoTheme.accent)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("결정 종류 필터")
    }

    private var monthFilterMenu: some View {
        Menu {
            Picker("기록 월", selection: $selectedMonth) {
                Text("전체")
                    .tag(nil as Date?)

                ForEach(availableMonths, id: \.self) { month in
                    Text(monthFilterTitle(month))
                        .tag(Optional(month))
                }
            }
        } label: {
            Image(systemName: selectedMonth == nil ? "calendar" : "calendar.badge.checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(selectedMonth == nil ? DuGoTheme.ink : DuGoTheme.accent)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("월별 기록 필터")
    }

    private var recordsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if !viewModel.records.isEmpty {
                        decisionSummary
                    }

                    if filteredGroups.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ForEach(filteredGroups) { group in
                            recordCard(group, item: viewModel.item(id: group.itemID))
                        }
                    }
                }
                .id("records-scroll-top")
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .onChange(of: scrollToTopRequest) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("records-scroll-top", anchor: .top)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            search = ""
            filter = nil
            selectedMonth = nil
            isSearchFieldFocused = false
            viewModel.resetFilters()
            await viewModel.refresh()
        }
    }

    private var decisionSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                decisionSummaryTitle

                Spacer()
            }
            .padding(.bottom, 10)

            decisionGraph

            if !activeDecisionCounts.isEmpty {
                HStack(spacing: 12) {
                    ForEach(activeDecisionCounts) { summary in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(decisionColor(for: summary.decision))
                                .frame(width: 7, height: 7)

                            Text("\(summary.decision.rawValue) \(summary.count)")
                                .applyDuGoFont(.caption12Regular)
                                .foregroundStyle(DuGoTheme.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dugoRoundedSurface(cornerRadius: 18)
    }

    private var decisionGraph: some View {
        GeometryReader { geometry in
            if decisionTotal == 0 {
                Capsule()
                    .fill(DuGoTheme.border)
            } else {
                let spacing = CGFloat(Swift.max(activeDecisionCounts.count - 1, 0)) * 3
                let availableWidth = Swift.max(geometry.size.width - spacing, 0)

                HStack(spacing: 3) {
                    ForEach(activeDecisionCounts) { summary in
                        Capsule()
                            .fill(decisionColor(for: summary.decision))
                            .frame(
                                width: availableWidth
                                    * CGFloat(summary.count)
                                    / CGFloat(decisionTotal)
                            )
                    }
                }
            }
        }
        .frame(height: 10)
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(viewModel.records.isEmpty ? "아직은 비어 있어요" : "찾는 기록이 없어요")
                .applyDuGoFont(.title18SemiBold)
                .foregroundStyle(DuGoTheme.ink)
                .frame(maxWidth: .infinity)

            Text(
                viewModel.records.isEmpty
                    ? "마음을 결정하면 여기에 기록이 쌓여요"
                    : "검색어나 필터를 바꿔 다시 찾아보세요"
            )
            .applyDuGoFont(.caption12Regular)
            .foregroundStyle(DuGoTheme.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private func recordCard(_ group: RecordGroup, item: WishItem?) -> some View {
        let isExpanded = expandedItemIDs.contains(group.itemID)

        return VStack(alignment: .leading, spacing: 0) {
            if let item {
                NavigationLink {
                    WishDetailView(item: item, viewModel: viewModel)
                } label: {
                    recordHeader(group, item: item)
                }
                .buttonStyle(.plain)
            } else {
                recordHeader(group, item: nil)
            }

            HStack(spacing: 8) {
                decisionTrail(group)

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        if isExpanded {
                            expandedItemIDs.remove(group.itemID)
                        } else {
                            expandedItemIDs.insert(group.itemID)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DuGoTheme.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "선택 내역 접기" : "선택 내역 펼치기")
            }
            .padding(.top, 12)

            if isExpanded {
                Rectangle()
                    .fill(DuGoTheme.border.opacity(0.65))
                    .frame(height: 1)
                    .padding(.vertical, 14)

                expandedHistory(group)
                    .transition(.opacity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dugoRoundedSurface(cornerRadius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    private func recordHeader(_ group: RecordGroup, item: WishItem?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            recordImage(for: item)

            VStack(alignment: .leading, spacing: 6) {
                Text(item?.title ?? group.latest.title)
                    .applyDuGoFont(.title16Medium)
                    .foregroundStyle(DuGoTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Text("최근 결정 · \(group.latest.createdAt.dugoFormattedDate())")
                    .applyDuGoFont(.caption12Regular)
                    .foregroundStyle(DuGoTheme.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private func decisionTrail(_ group: RecordGroup) -> some View {
        let previous = Array(group.records.dropLast())
        let visiblePrevious = Array(previous.suffix(3).reversed())
        let hiddenCount = previous.count - visiblePrevious.count

        return HStack(spacing: 6) {
            decisionTag(group.latest.decision)

            ForEach(visiblePrevious) { record in
                trailArrow

                compactDecisionIcon(record.decision)
            }

            if hiddenCount > 0 {
                trailArrow

                Text("+\(hiddenCount)")
                    .applyDuGoFont(.caption12Medium)
                    .foregroundStyle(DuGoTheme.secondary)
                    .frame(minWidth: 26, minHeight: 26)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "최신 결정부터: "
                + group.records.reversed().map(\.decision.rawValue).joined(separator: ", ")
        )
    }

    private var trailArrow: some View {
        Image(systemName: "chevron.left")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(DuGoTheme.secondary)
            .accessibilityHidden(true)
    }

    private func compactDecisionIcon(_ decision: WishDecision) -> some View {
        DuGoDecisionIcon(
            decision: decision,
            size: 14,
            color: decisionColor(for: decision)
        )
        .frame(width: 26, height: 26)
        .background {
            Circle()
                .fill(decisionColor(for: decision).opacity(0.10))
        }
    }

    private func expandedHistory(_ group: RecordGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("선택 내역")
                    .applyDuGoFont(.body14Medium)
                    .foregroundStyle(DuGoTheme.ink)

                Spacer()

                Text("\(group.records.count)번")
                    .applyDuGoFont(.caption12Regular)
                    .foregroundStyle(DuGoTheme.secondary)
            }
            .padding(.bottom, 8)

            ForEach(Array(group.records.reversed())) { record in
                HStack(alignment: .top, spacing: 10) {
                    compactDecisionIcon(record.decision)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(record.decision.rawValue)
                                .applyDuGoFont(.body14Medium)
                                .foregroundStyle(DuGoTheme.ink)

                            Spacer(minLength: 0)

                            Text(record.createdAt.dugoFormattedDate())
                                .applyDuGoFont(.caption12Regular)
                                .foregroundStyle(DuGoTheme.secondary)
                        }

                        if !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(record.note)
                                .applyDuGoFont(.caption14Regular)
                                .foregroundStyle(DuGoTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 10)

                if record.id != group.records.first?.id {
                    Rectangle()
                        .fill(DuGoTheme.border.opacity(0.65))
                        .frame(height: 1)
                }
            }
        }
    }

    private func recordImage(for item: WishItem?) -> some View {
        Group {
            if let data = item?.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                DuGoImagePlaceholder()
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func decisionColor(for decision: WishDecision) -> Color {
        switch decision {
        case .purchase: DuGoTheme.accent
        case .wait: DuGoTheme.complement
        case .release: DuGoTheme.accent.opacity(0.55)
        case .restore: DuGoTheme.complement.opacity(0.55)
        }
    }

    private func decisionTag(_ decision: WishDecision) -> some View {
        DuGoDecisionTag(
            decision: decision,
            color: decisionColor(for: decision)
        )
    }

    private func summaryText(_ text: String) -> some View {
        Text(text)
            .applyDuGoFont(.title16Medium)
            .foregroundStyle(DuGoTheme.ink)
    }

    private func monthFilterTitle(_ month: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: month)
    }
}
