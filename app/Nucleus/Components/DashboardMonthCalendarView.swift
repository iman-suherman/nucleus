import CalendarKit
import NucleusKit
import SwiftUI

struct DashboardMonthCalendarView: View {
    let month: Date
    let birthdays: [CalendarEventSummary]
    let scheduledEvents: [CalendarEventSummary]
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            if !birthdays.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "birthday.cake.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                    Text("Birthdays")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
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
                        Color.clear.frame(minHeight: 44)
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private struct DayCellModel {
        let day: Int
        let date: Date
        let birthdays: [CalendarEventSummary]
        let hasEvent: Bool
        let isToday: Bool
    }

    @ViewBuilder
    private func dayCell(_ cell: DayCellModel) -> some View {
        let hasBirthdays = !cell.birthdays.isEmpty

        VStack(alignment: .leading, spacing: 3) {
            Text("\(cell.day)")
                .font(.caption2.weight(cell.isToday ? .bold : .semibold))
                .foregroundStyle(cell.isToday ? .white : .primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
                .background {
                    if cell.isToday {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 22, height: 22)
                    }
                }

            if hasBirthdays {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(cell.birthdays.prefix(2)) { birthday in
                        Text(BirthdayCalendarFormatting.displayName(from: birthday.title))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.pink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    if cell.birthdays.count > 2 {
                        Text("+\(cell.birthdays.count - 2) more")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.pink.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            } else if cell.hasEvent {
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 4, height: 4)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
        .background {
            if hasBirthdays {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.pink.opacity(cell.isToday ? 0.28 : 0.16))
            }
        }
        .overlay {
            if hasBirthdays {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.pink.opacity(0.35), lineWidth: 1)
            }
        }
        .help(birthdayHelp(for: cell))
    }

    private func birthdayHelp(for cell: DayCellModel) -> String {
        guard !cell.birthdays.isEmpty else { return "" }
        let names = cell.birthdays.map { BirthdayCalendarFormatting.displayName(from: $0.title) }
        return names.joined(separator: ", ")
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
            let dayBirthdays = birthdays.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
            let hasEvent = scheduledEvents.contains { calendar.isDate($0.startDate, inSameDayAs: date) }
            cells.append(
                DayCellModel(
                    day: day,
                    date: date,
                    birthdays: dayBirthdays,
                    hasEvent: hasEvent,
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
}
