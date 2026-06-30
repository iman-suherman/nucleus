import CalendarKit
import NucleusKit
import SwiftUI

struct DashboardMonthCalendarView: View {
    enum DisplayMode {
        case birthdays
        case events
    }

    let mode: DisplayMode
    let month: Date
    let birthdays: [CalendarEventSummary]
    let scheduledEvents: [CalendarEventSummary]
    let showsMonthNavigation: Bool
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void

    init(
        mode: DisplayMode,
        month: Date,
        birthdays: [CalendarEventSummary],
        scheduledEvents: [CalendarEventSummary],
        showsMonthNavigation: Bool = true,
        onPreviousMonth: @escaping () -> Void,
        onNextMonth: @escaping () -> Void
    ) {
        self.mode = mode
        self.month = month
        self.birthdays = birthdays
        self.scheduledEvents = scheduledEvents
        self.showsMonthNavigation = showsMonthNavigation
        self.onPreviousMonth = onPreviousMonth
        self.onNextMonth = onNextMonth
    }

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsMonthNavigation {
                monthHeader
            } else if mode == .events {
                Text(monthTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 6) {
                Image(systemName: "birthday.cake.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Birthdays")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(calendarCells.enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        dayCell(cell)
                    } else {
                        Color.clear.frame(minHeight: cellMinHeight)
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var monthHeader: some View {
        HStack {
            Button(action: onPreviousMonth) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Spacer()

            Text(monthTitle)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button(action: onNextMonth) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
    }

    private struct DayCellModel {
        let day: Int
        let date: Date
        let birthdays: [CalendarEventSummary]
        let events: [CalendarEventSummary]
        let isToday: Bool
    }

    private var cellMinHeight: CGFloat {
        mode == .birthdays ? 58 : 52
    }

    @ViewBuilder
    private func dayCell(_ cell: DayCellModel) -> some View {
        switch mode {
        case .birthdays:
            birthdayDayCell(cell)
        case .events:
            eventsDayCell(cell)
        }
    }

    @ViewBuilder
    private func birthdayDayCell(_ cell: DayCellModel) -> some View {
        let hasBirthdays = !cell.birthdays.isEmpty

        VStack(alignment: .leading, spacing: 4) {
            dayNumber(cell, onColoredBackground: hasBirthdays)

            if hasBirthdays {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(cell.birthdays.prefix(2)) { birthday in
                        Text(BirthdayCalendarFormatting.displayName(from: birthday.title))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .help(BirthdayCalendarFormatting.detailTooltip(for: birthday))
                            .pointerCursor()
                    }
                    if cell.birthdays.count > 2 {
                        Text("+\(cell.birthdays.count - 2) more")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .help(birthdayHelp(for: cell))
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: cellMinHeight, alignment: .top)
        .background {
            if hasBirthdays {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(cell.isToday ? 1.0 : 0.9))
            }
        }
        .overlay {
            if hasBirthdays {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            }
        }
        .help(hasBirthdays ? birthdayHelp(for: cell) : "")
        .pointerCursor()
    }

    @ViewBuilder
    private func eventsDayCell(_ cell: DayCellModel) -> some View {
        let dayEvents = cell.events
        let hasEvents = !dayEvents.isEmpty

        VStack(alignment: .leading, spacing: 4) {
            dayNumber(cell)

            if hasEvents {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(dayEvents.prefix(2)) { event in
                        Text(event.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .help(eventDetailTooltip(for: event))
                            .pointerCursor()
                    }
                    if dayEvents.count > 2 {
                        Text("+\(dayEvents.count - 2) more")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.blue.opacity(0.85))
                            .lineLimit(1)
                            .help(eventsHelp(for: dayEvents))
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: cellMinHeight, alignment: .top)
        .background {
            if hasEvents {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(cell.isToday ? 0.22 : 0.10))
            }
        }
        .overlay {
            if hasEvents {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.28), lineWidth: 1)
            }
        }
        .help(hasEvents ? eventsHelp(for: dayEvents) : "")
        .pointerCursor()
    }

    @ViewBuilder
    private func dayNumber(_ cell: DayCellModel, onColoredBackground: Bool = false) -> some View {
        Text("\(cell.day)")
            .font(.caption2.weight(cell.isToday ? .bold : .semibold))
            .foregroundStyle(onColoredBackground ? .white : (cell.isToday ? .white : .primary))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
            .background {
                if cell.isToday && !onColoredBackground {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 22, height: 22)
                }
            }
    }

    private func birthdayHelp(for cell: DayCellModel) -> String {
        cell.birthdays.map { BirthdayCalendarFormatting.detailTooltip(for: $0) }.joined(separator: "\n\n")
    }

    private func eventsHelp(for events: [CalendarEventSummary]) -> String {
        events.map { eventDetailTooltip(for: $0) }.joined(separator: "\n\n")
    }

    private func eventDetailTooltip(for event: CalendarEventSummary) -> String {
        var lines = [event.title, eventTimeLabel(for: event.startDate)]
        if !event.accountEmail.isEmpty {
            lines.append(event.accountEmail)
        }
        if !event.location.isEmpty {
            lines.append(event.location)
        }
        return lines.joined(separator: "\n")
    }

    private func eventTimeLabel(for date: Date) -> String {
        Self.eventTimeFormatter.string(from: date)
    }

    private var monthTitle: String {
        Self.monthFormatter.string(from: month)
    }

    private var weekdaySymbols: [String] {
        calendar.shortWeekdaySymbols
    }

    private var calendarCells: [DayCellModel?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let dayRange = calendar.range(of: .day, in: .month, for: month) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [DayCellModel?] = Array(repeating: nil, count: leadingBlanks)

        for day in dayRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) else {
                continue
            }
            let dayBirthdays = mode == .birthdays
                ? birthdays.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
                : []
            let dayEvents = mode == .events
                ? scheduledEvents.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
                : []
            cells.append(
                DayCellModel(
                    day: day,
                    date: date,
                    birthdays: dayBirthdays,
                    events: dayEvents,
                    isToday: calendar.isDateInToday(date)
                )
            )
        }

        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .medium
        return formatter
    }()
}
