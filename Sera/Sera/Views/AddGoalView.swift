import SwiftUI

/// End-goal composer drawn inside the notch island.
/// The island becomes key while this is visible so the title field can take input.
struct NotchAddGoalView: View {
    @EnvironmentObject private var appState: AppState

    @State private var title: String = ""
    @State private var startDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var endDate: Date = defaultEndDate()
    @State private var editingBound: DateBound = .start
    @State private var visibleMonth: Date = monthStart(for: Date())
    @FocusState private var titleFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var datesAreValid: Bool {
        endDate > startDate
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && datesAreValid
    }

    private var draftGoal: Goal {
        let calendar = Calendar.current
        return Goal(
            title: trimmedTitle.isEmpty ? "End goal" : trimmedTitle,
            startDate: calendar.startOfDay(for: startDate),
            endDate: calendar.startOfDay(for: endDate),
            progressKind: .timeBased
        )
    }

    private var preview: ProgressSnapshot {
        appState.goalEngine.snapshot(for: draftGoal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("new end goal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    titleField
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(datesAreValid ? preview.percentWhole : "—")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .tracking(-1)

                    Text(datesAreValid ? dayCaption : "choose an end date")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    composerBar
                        .frame(width: 132, height: 4)
                        .padding(.top, 2)
                }
            }

            HStack(spacing: 8) {
                boundChip(.start)
                boundChip(.end)
                Spacer(minLength: 8)
                Button("Cancel", action: cancel)
                    .buttonStyle(NotchComposerButtonStyle())
                Button("Add", action: save)
                    .buttonStyle(NotchComposerButtonStyle(prominent: true))
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.4)
            }

            NotchRangeCalendar(
                start: startDate,
                end: endDate,
                visibleMonth: $visibleMonth,
                onSelect: select(day:)
            )

            if !datesAreValid {
                Text("End date has to come after the start.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(SeraTheme.progress.opacity(0.9))
            }
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                titleFocused = true
            }
        }
        .onExitCommand(perform: cancel)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                "",
                text: $title,
                prompt: Text("Name this timeline")
                    .foregroundColor(Color.primary.opacity(0.28))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .focused($titleFocused)
            .onSubmit {
                if canSave { save() }
            }

            Capsule()
                .fill(titleFocused ? SeraTheme.progress : Color.primary.opacity(0.16))
                .frame(height: 2)
        }
    }

    private func boundChip(_ bound: DateBound) -> some View {
        let date = bound == .start ? startDate : endDate
        let active = editingBound == bound
        return Button {
            editingBound = bound
            visibleMonth = Self.monthStart(for: date)
        } label: {
            HStack(spacing: 8) {
                Text(bound.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(active ? SeraTheme.progress : .secondary)
                Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? SeraTheme.progress.opacity(0.14) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(active ? SeraTheme.progress.opacity(0.85) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func select(day: Date) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: day)
        switch editingBound {
        case .start:
            startDate = day
            if endDate <= day {
                endDate = calendar.date(byAdding: .day, value: 7, to: day) ?? day.addingTimeInterval(7 * 24 * 60 * 60)
            }
            editingBound = .end
        case .end:
            if day <= startDate {
                startDate = day
                if endDate <= day {
                    endDate = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(24 * 60 * 60)
                }
            } else {
                endDate = day
            }
        }
        if !calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                visibleMonth = Self.monthStart(for: day)
            }
        }
    }

    private var composerBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.14))
                Capsule()
                    .fill(SeraTheme.progress)
                    .frame(width: datesAreValid ? max(4, proxy.size.width * min(1, preview.progress)) : 4)
            }
        }
    }

    private var dayCaption: String {
        let days = max(preview.totalDays, 1)
        return days == 1 ? "1 day" : "\(days) days"
    }

    private func cancel() {
        appState.cancelAddGoal()
    }

    private func save() {
        guard canSave else { return }
        let goal = draftGoal
        appState.goalEngine.add(goal)
        appState.selectGoal(id: goal.id)
        appState.dismissAddGoal()
    }

    private static func defaultEndDate() -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .month, value: 3, to: start) ?? start.addingTimeInterval(90 * 24 * 60 * 60)
    }

    private static func monthStart(for date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}

private enum DateBound {
    case start
    case end

    var title: String {
        switch self {
        case .start: return "Starts"
        case .end: return "Ends"
        }
    }
}

/// Month grid drawn in the notch. Start and end are filled; days between them share a soft range.
private struct NotchRangeCalendar: View {
    var start: Date
    var end: Date
    @Binding var visibleMonth: Date
    var onSelect: (Date) -> Void

    private let calendar = Calendar.current

    /// 0 at rest. -1 while the next month slides in, +1 while the previous month slides in.
    @State private var slide: CGFloat = 0
    @State private var slideDirection: CGFloat = 0
    @State private var incomingMonth: Date?

    private let rowHeight: CGFloat = 28
    private let rowSpacing: CGFloat = 2

    private var gridHeight: CGFloat {
        rowHeight * 6 + rowSpacing * 5
    }

    private var isPaging: Bool { incomingMonth != nil }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                monthButton("chevron.left", help: "Previous month") {
                    shiftMonth(by: -1)
                }

                slidingStrip(height: 20) { month in
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }

                monthButton("chevron.right", help: "Next month") {
                    shiftMonth(by: 1)
                }
            }

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            slidingStrip(height: gridHeight) { month in
                monthGrid(month)
            }
        }
    }

    /// Current month, with the incoming month parked beside it, clipped to one page.
    private func slidingStrip<Page: View>(height: CGFloat, @ViewBuilder page: @escaping (Date) -> Page) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            HStack(spacing: 0) {
                if slideDirection > 0, let incomingMonth {
                    page(incomingMonth).frame(width: width, height: height, alignment: .top)
                }
                page(visibleMonth).frame(width: width, height: height, alignment: .top)
                if slideDirection < 0, let incomingMonth {
                    page(incomingMonth).frame(width: width, height: height, alignment: .top)
                }
            }
            .offset(x: slideDirection > 0 ? (slide - 1) * width : slide * width)
        }
        .frame(height: height)
        .clipped()
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = max(0, calendar.firstWeekday - 1)
        guard shift < symbols.count else { return symbols }
        return Array(symbols[shift...]) + Array(symbols[..<shift])
    }

    private func monthGrid(_ month: Date) -> some View {
        let pageDays = days(in: month)
        return VStack(spacing: rowSpacing) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let index = row * 7 + column
                        if index < pageDays.count {
                            dayCell(pageDays[index], in: month)
                        }
                    }
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func days(in month: Date) -> [Date] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) else {
            return []
        }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func dayCell(_ day: Date, in month: Date) -> some View {
        let dayStart = calendar.startOfDay(for: day)
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isStart = calendar.isDate(dayStart, inSameDayAs: startDay)
        let isEnd = calendar.isDate(dayStart, inSameDayAs: endDay)
        let inRange = dayStart > startDay && dayStart < endDay
        let isToday = calendar.isDateInToday(dayStart)
        let endpoint = isStart || isEnd

        return Button {
            onSelect(dayStart)
        } label: {
            ZStack {
                if isStart || isEnd || inRange {
                    rangeBand(isStart: isStart, isEnd: isEnd)
                }

                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 12, weight: endpoint ? .semibold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(dayForeground(endpoint: endpoint, inMonth: inMonth))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(endpoint ? SeraTheme.progress : Color.clear))
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isToday && !endpoint ? SeraTheme.progress.opacity(0.95) : Color.clear,
                                lineWidth: 1
                            )
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayForeground(endpoint: Bool, inMonth: Bool) -> Color {
        if endpoint { return .white }
        if inMonth { return .primary.opacity(0.9) }
        return .primary.opacity(0.28)
    }

    /// Soft bar linking the start day to the end day. Each half is hidden on its endpoint so the orange circle covers the join.
    private func rangeBand(isStart: Bool, isEnd: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(SeraTheme.progress.opacity(0.2))
                .opacity(isStart ? 0 : 1)
            Rectangle()
                .fill(SeraTheme.progress.opacity(0.2))
                .opacity(isEnd ? 0 : 1)
        }
        .frame(height: 26)
    }

    private func monthButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.82))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(isPaging)
        .opacity(isPaging ? 0.45 : 1)
    }

    private func shiftMonth(by value: Int) {
        guard incomingMonth == nil else { return }
        guard let next = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        let nextMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: next)) ?? next
        let direction: CGFloat = value > 0 ? -1 : 1

        var setup = Transaction()
        setup.disablesAnimations = true
        withTransaction(setup) {
            incomingMonth = nextMonth
            slideDirection = direction
            slide = 0
        }

        let duration = 0.34
        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: duration)) {
                slide = direction
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) {
            var done = Transaction()
            done.disablesAnimations = true
            withTransaction(done) {
                visibleMonth = nextMonth
                incomingMonth = nil
                slide = 0
                slideDirection = 0
            }
        }
    }
}

private struct NotchComposerButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary.opacity(0.82))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? SeraTheme.progress : Color.primary.opacity(configuration.isPressed ? 0.14 : 0.08))
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
