import AppKit
import ServiceManagement
import SwiftUI

@main
struct EpexMenuBarApp: App {
    @StateObject private var model = PriceViewModel()

    var body: some Scene {
        MenuBarExtra {
            PricePanel()
                .environmentObject(model)
                .frame(width: 740, height: 900)
                .task {
                    await model.refresh()
                }
        } label: {
            MenuBarLabel()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject private var model: PriceViewModel

    var body: some View {
        Label {
            if let current = model.currentPoint {
                Text("Import app \(current.importAppCentsPerKWh, format: .number.precision(.fractionLength(1)))c")
            } else if model.isLoading {
                Text("EPEX ...")
            } else {
                Text("EPEX")
            }
        } icon: {
            FrankMenuBarIcon()
        }
    }
}

struct FrankMenuBarIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(PanelStyle.frankGreen)
                .frame(width: 27, height: 18)

            VStack(spacing: -2) {
                Text("frank")
                    .font(.system(size: 7.2, weight: .black, design: .rounded))
                Text("energie")
                    .font(.system(size: 4.7, weight: .bold, design: .rounded))
            }
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .offset(y: -0.2)
        }
        .frame(width: 27, height: 18)
        .accessibilityLabel("Frank Energie")
    }
}

struct PricePanel: View {
    @EnvironmentObject private var model: PriceViewModel
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @AppStorage("registeredLoginItemMetadataVersion") private var registeredLoginItemMetadataVersion = 0
    @State private var selectedPoint: PricePoint?
    @State private var selectedQuarterStart: Date?
    @State private var loginItemMessage: String?

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Versie \(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(PanelStyle.warningText)
                        .font(.callout)
                }

            VStack(alignment: .leading, spacing: 8) {
                header

                PriceChart(points: model.points, selectedPoint: $selectedPoint, selectedQuarterStart: $selectedQuarterStart)
                    .frame(height: 230)

                detail
            }
            .padding(10)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))

            P1UsageSection(
                status: model.p1Status,
                currentSample: model.p1CurrentSample,
                intervals: model.p1Intervals,
                selectedQuarterStart: $selectedQuarterStart
            )
            .frame(height: 430)

            MonthlyAverageSection(
                monthKeys: model.availableMonthKeys,
                monthKeysWithData: model.monthKeysWithData,
                selectedMonthKey: model.selectedMonthKey,
                summaries: model.selectedMonthSummaries
            ) { monthKey in
                model.selectMonth(monthKey)
            }
            .frame(height: 430)

            DailyAverageView(summary: model.selectedDaySummary)

            HStack {
                Text(model.sourceDescription)
                    .foregroundStyle(PanelStyle.secondaryText)
                Text(appVersionText)
                    .foregroundStyle(PanelStyle.secondaryText.opacity(0.85))
                Spacer()
                Toggle("Start bij login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { enabled in
                        updateLaunchAtLogin(enabled)
                    }
                Button("Stop app") {
                    NSApplication.shared.terminate(nil)
                }
                Button("Ververs") {
                    Task { await model.refresh() }
                }
                .disabled(model.isLoading)
            }
            .font(.caption)

                if let loginItemMessage {
                    Text(loginItemMessage)
                        .font(.caption2)
                        .foregroundStyle(PanelStyle.secondaryText)
                }
            }
            .padding(18)
        }
        .foregroundStyle(.white)
        .background(PanelStyle.background)
        .onAppear {
            updateLaunchAtLogin(launchAtLogin)
        }
        .onChange(of: selectedQuarterStart) { quarterStart in
            selectedPoint = point(containing: quarterStart)
        }
        .onChange(of: model.points) { _ in
            selectedPoint = point(containing: selectedQuarterStart)
        }
    }

    private func point(containing quarterStart: Date?) -> PricePoint? {
        guard let quarterStart else {
            return nil
        }

        return model.points.first { $0.displayStart <= quarterStart && quarterStart < $0.displayEnd }
            ?? model.points.min { left, right in
                abs(left.displayStart.timeIntervalSince(quarterStart)) < abs(right.displayStart.timeIntervalSince(quarterStart))
            }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("EPEX kwartiertarieven")
                    .font(.headline)
                    Text("Import app/factuur/all-in en export in cent/kWh")
                    .font(.caption)
                    .foregroundStyle(PanelStyle.secondaryText)
            }

            Spacer()

            DaySelector(
                selectedDay: model.selectedDay,
                isLoading: model.isLoading,
                hasTomorrowPrices: model.hasTomorrowPrices
            ) { day in
                Task { await model.selectDay(day) }
            }

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var detail: some View {
        let point = selectedPoint ?? model.currentPoint

        return HStack(spacing: 14) {
            if let point {
                VStack(alignment: .leading, spacing: 2) {
                    Text(point.displayStart, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.headline)
                    Text("tot \(point.displayEnd, format: .dateTime.hour().minute())")
                        .font(.caption)
                        .foregroundStyle(PanelStyle.secondaryText)
                }

                Spacer()

                PricePill(title: "Import app", value: point.importAppCentsPerKWh, color: PanelStyle.importAppLine)
                PricePill(title: "Import factuur", value: point.importCentsPerKWh, color: PanelStyle.importLine)
                PricePill(title: "All-in import", value: point.allInImportCentsPerKWh, color: PanelStyle.allInImportLine)
                PricePill(title: "EPEX export", value: point.marketCentsPerKWh, color: PanelStyle.marketLine)
                PricePill(title: "Export", value: point.exportCentsPerKWh, color: PanelStyle.exportLine)
            } else {
                Text("Geen tariefdata beschikbaar")
                    .foregroundStyle(PanelStyle.secondaryText)
            }
        }
        .frame(height: 48)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        let metadataVersion = 3

        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled, registeredLoginItemMetadataVersion < metadataVersion {
                    try SMAppService.mainApp.unregister()
                }

                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                registeredLoginItemMetadataVersion = metadataVersion
                loginItemMessage = "Start bij login is actief."
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                registeredLoginItemMetadataVersion = 0
                loginItemMessage = "Start bij login is uitgeschakeld."
            }
        } catch {
            loginItemMessage = "Kon start bij login niet aanpassen: \(error.localizedDescription)"
        }
    }
}

struct MonthlyAverageSection: View {
    let monthKeys: [String]
    let monthKeysWithData: Set<String>
    let selectedMonthKey: String
    let summaries: [DailyPriceSummary]
    let onSelectMonth: (String) -> Void
    @State private var selectedSummary: DailyPriceSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daggemiddelden")
                        .font(.caption.weight(.semibold))
                    Text("Import app/factuur/all-in, EPEX export en export per dag")
                        .font(.caption2)
                        .foregroundStyle(PanelStyle.secondaryText)
                }

                Spacer()

                MonthSelector(
                    monthKeys: monthKeys,
                    monthKeysWithData: monthKeysWithData,
                    selectedMonthKey: selectedMonthKey,
                    onSelect: onSelectMonth
                )
            }

            MonthlyAverageChart(summaries: summaries, selectedSummary: $selectedSummary)
                .frame(maxHeight: .infinity)

            MonthlyAverageDetail(summary: selectedSummary ?? summaries.last)
        }
        .padding(10)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }
}

enum P1PeriodMode: String, CaseIterable, Identifiable {
    case day
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Dag"
        case .month: return "Maand"
        case .year: return "Jaar"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .month: return .month
        case .year: return .year
        }
    }

    var chartUnit: String {
        switch self {
        case .day: return "kWh per kwartier"
        case .month: return "kWh per dag"
        case .year: return "kWh per maand"
        }
    }
}

struct P1ChartItem: Identifiable, Hashable {
    let start: Date
    let end: Date
    let label: String
    let importKWh: Double
    let exportKWh: Double
    let importCostEUR: Double
    let exportCreditEUR: Double
    let intervalCount: Int

    var id: Date { start }
    var netCostEUR: Double { importCostEUR - exportCreditEUR }
    var hasUsage: Bool { importKWh > 0 || exportKWh > 0 }
}

struct P1UsageSection: View {
    let status: String
    let currentSample: P1Sample?
    let intervals: [P1UsageInterval]
    @Binding var selectedQuarterStart: Date?
    @State private var mode: P1PeriodMode = .day
    @State private var selectedDate = Date()
    @State private var selectedItem: P1ChartItem?

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Brussels") ?? .current
        return calendar
    }

    private var items: [P1ChartItem] {
        P1UsageAggregator.items(for: mode, selectedDate: selectedDate, intervals: intervals, calendar: calendar)
    }

    private var total: P1ChartItem {
        P1UsageAggregator.total(from: items, mode: mode, selectedDate: selectedDate, calendar: calendar)
    }

    private var effectiveSelectedItem: P1ChartItem? {
        if mode == .day, let selectedQuarterStart {
            return items.first { $0.start <= selectedQuarterStart && selectedQuarterStart < $0.end }
        }

        return selectedItem
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("P1 netgebruik")
                        .font(.caption.weight(.semibold))
                    Text("Dag per kwartier, maand per dag, jaar per maand.")
                        .font(.caption2)
                        .foregroundStyle(PanelStyle.secondaryText)
                }

                Spacer()

                if let currentSample {
                    Text("\(currentSample.activePowerW, format: .number.precision(.fractionLength(0))) W nu")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(currentSample.activePowerW >= 0 ? PanelStyle.importLine : PanelStyle.exportLine)
                }
            }

            HStack(spacing: 8) {
                P1ModeSelector(mode: $mode, selectedDate: $selectedDate, selectedItem: $selectedItem, selectedQuarterStart: $selectedQuarterStart)

                Spacer()

                Button {
                    movePeriod(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(periodTitle)
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 132)

                Button {
                    movePeriod(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }

            P1AggregatedChart(items: items, mode: mode, selectedItem: $selectedItem, selectedQuarterStart: $selectedQuarterStart)
                .frame(height: 230)

            P1AggregateDetail(item: effectiveSelectedItem ?? items.last(where: \.hasUsage) ?? total, mode: mode)

            HStack(spacing: 12) {
                CompactAveragePill(title: "Totaal import", value: total.importKWh, color: PanelStyle.importLine, suffix: "kWh")
                CompactAveragePill(title: "Totaal injectie", value: total.exportKWh, color: PanelStyle.exportLine, suffix: "kWh")
                CompactAveragePill(title: "All-in te betalen", value: total.importCostEUR, color: PanelStyle.importAppLine, suffix: "EUR")
                CompactAveragePill(title: "Teruglevering", value: total.exportCreditEUR, color: PanelStyle.exportLine, suffix: "EUR")
                Spacer()
                CompactAveragePill(title: "Netto", value: total.netCostEUR, color: PanelStyle.marketLine, suffix: "EUR")
            }

            Text(status)
                .font(.caption2)
                .foregroundStyle(PanelStyle.secondaryText.opacity(0.82))
        }
        .padding(10)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }

    private var periodTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_BE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone

        switch mode {
        case .day:
            formatter.dateFormat = "d MMM yyyy"
        case .month:
            formatter.dateFormat = "LLLL yyyy"
        case .year:
            formatter.dateFormat = "yyyy"
        }

        return formatter.string(from: selectedDate).capitalized
    }

    private func movePeriod(by value: Int) {
        selectedDate = calendar.date(byAdding: mode.component, value: value, to: selectedDate) ?? selectedDate
        selectedItem = nil
        selectedQuarterStart = nil
    }
}

struct P1ModeSelector: View {
    @Binding var mode: P1PeriodMode
    @Binding var selectedDate: Date
    @Binding var selectedItem: P1ChartItem?
    @Binding var selectedQuarterStart: Date?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(P1PeriodMode.allCases) { candidate in
                Button {
                    mode = candidate
                    selectedItem = nil
                    selectedQuarterStart = nil
                } label: {
                    Text(candidate.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(candidate == mode ? PanelStyle.daySelectedText : PanelStyle.dayText)
                        .frame(minWidth: 54)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(candidate == mode ? PanelStyle.daySelectedBackground : PanelStyle.dayBackground)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(PanelStyle.dayContainerBackground, in: RoundedRectangle(cornerRadius: 9))
    }
}

enum P1UsageAggregator {
    static func items(for mode: P1PeriodMode, selectedDate: Date, intervals: [P1UsageInterval], calendar: Calendar) -> [P1ChartItem] {
        switch mode {
        case .day:
            return dayItems(selectedDate: selectedDate, intervals: intervals, calendar: calendar)
        case .month:
            return monthItems(selectedDate: selectedDate, intervals: intervals, calendar: calendar)
        case .year:
            return yearItems(selectedDate: selectedDate, intervals: intervals, calendar: calendar)
        }
    }

    static func total(from items: [P1ChartItem], mode: P1PeriodMode, selectedDate: Date, calendar: Calendar) -> P1ChartItem {
        let period = calendar.dateInterval(of: mode.component, for: selectedDate)
        return P1ChartItem(
            start: period?.start ?? selectedDate,
            end: period?.end ?? selectedDate,
            label: "Totaal",
            importKWh: items.map(\.importKWh).reduce(0, +),
            exportKWh: items.map(\.exportKWh).reduce(0, +),
            importCostEUR: items.map(\.importCostEUR).reduce(0, +),
            exportCreditEUR: items.map(\.exportCreditEUR).reduce(0, +),
            intervalCount: items.map(\.intervalCount).reduce(0, +)
        )
    }

    private static func dayItems(selectedDate: Date, intervals: [P1UsageInterval], calendar: Calendar) -> [P1ChartItem] {
        guard let day = calendar.dateInterval(of: .day, for: selectedDate) else {
            return []
        }

        return (0..<96).compactMap { index in
            guard
                let start = calendar.date(byAdding: .minute, value: index * 15, to: day.start),
                let end = calendar.date(byAdding: .minute, value: 15, to: start)
            else {
                return nil
            }

            return item(start: start, end: end, label: label(for: start, dateFormat: "HH:mm", calendar: calendar), intervals: intervals)
        }
    }

    private static func monthItems(selectedDate: Date, intervals: [P1UsageInterval], calendar: Calendar) -> [P1ChartItem] {
        guard
            let month = calendar.dateInterval(of: .month, for: selectedDate),
            let dayRange = calendar.range(of: .day, in: .month, for: selectedDate)
        else {
            return []
        }

        return dayRange.compactMap { day in
            guard
                let start = calendar.date(byAdding: .day, value: day - 1, to: month.start),
                let end = calendar.date(byAdding: .day, value: 1, to: start)
            else {
                return nil
            }

            return item(start: start, end: end, label: "\(day)", intervals: intervals)
        }
    }

    private static func yearItems(selectedDate: Date, intervals: [P1UsageInterval], calendar: Calendar) -> [P1ChartItem] {
        guard let year = calendar.dateInterval(of: .year, for: selectedDate) else {
            return []
        }

        return (0..<12).compactMap { monthOffset in
            guard
                let start = calendar.date(byAdding: .month, value: monthOffset, to: year.start),
                let end = calendar.date(byAdding: .month, value: 1, to: start)
            else {
                return nil
            }

            return item(start: start, end: end, label: label(for: start, dateFormat: "MMM", calendar: calendar), intervals: intervals)
        }
    }

    private static func item(start: Date, end: Date, label: String, intervals: [P1UsageInterval]) -> P1ChartItem {
        let overlapping = intervals.compactMap { interval -> (P1UsageInterval, Double)? in
            let overlapStart = max(start, interval.start)
            let overlapEnd = min(end, interval.end)
            let overlapSeconds = overlapEnd.timeIntervalSince(overlapStart)
            let intervalSeconds = interval.end.timeIntervalSince(interval.start)
            guard overlapSeconds > 0, intervalSeconds > 0 else {
                return nil
            }

            return (interval, overlapSeconds / intervalSeconds)
        }

        return P1ChartItem(
            start: start,
            end: end,
            label: label,
            importKWh: overlapping.map { $0.0.importKWh * $0.1 }.reduce(0, +),
            exportKWh: overlapping.map { $0.0.exportKWh * $0.1 }.reduce(0, +),
            importCostEUR: overlapping.map { $0.0.importCostEUR * $0.1 }.reduce(0, +),
            exportCreditEUR: overlapping.map { $0.0.exportCreditEUR * $0.1 }.reduce(0, +),
            intervalCount: overlapping.count
        )
    }

    private static func label(for date: Date, dateFormat: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_BE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = dateFormat
        return formatter.string(from: date).capitalized
    }
}

struct P1AggregatedChart: View {
    let items: [P1ChartItem]
    let mode: P1PeriodMode
    @Binding var selectedItem: P1ChartItem?
    @Binding var selectedQuarterStart: Date?

    private var effectiveSelectedItem: P1ChartItem? {
        if mode == .day, let selectedQuarterStart {
            return items.first { $0.start <= selectedQuarterStart && selectedQuarterStart < $0.end }
        }

        return selectedItem
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGrid(in: &context, size: size)
                    drawYAxisLabels(in: &context, size: size)
                    drawXAxisLabels(in: &context, size: size)
                    drawBars(in: &context, size: size)
                    drawSelection(in: &context, size: size)
                }
                .background(PanelStyle.chartBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PanelStyle.chartBorder, lineWidth: 1)
                )

                if items.allSatisfy({ $0.hasUsage == false }) {
                    Text("Nog geen P1-data voor deze selectie.")
                        .font(.caption2)
                        .foregroundStyle(PanelStyle.secondaryText)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }

                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        LegendDot(color: PanelStyle.importLine, title: "Netafname")
                        LegendDot(color: PanelStyle.exportLine, title: "Injectie")
                        Spacer()
                        Text(mode.chartUnit)
                            .foregroundStyle(PanelStyle.secondaryText)
                    }
                    .font(.caption2)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 5)
                }

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                selectItem(atX: value.location.x, width: geometry.size.width)
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            selectItem(atX: location.x, width: geometry.size.width)
                        case .ended:
                            selectedItem = nil
                            selectedQuarterStart = nil
                        }
                    }
            }
        }
    }

    private var maxKWh: Double {
        max(items.map { max($0.importKWh, $0.exportKWh) }.max() ?? 0.001, 0.001)
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let plot = plotRect(size: size)
        var path = Path()
        for index in 0...3 {
            let y = plot.minY + plot.height * CGFloat(index) / 3
            path.move(to: CGPoint(x: plot.minX, y: y))
            path.addLine(to: CGPoint(x: plot.maxX, y: y))
        }
        context.stroke(path, with: .color(PanelStyle.gridLine), lineWidth: 1)
    }

    private func drawYAxisLabels(in context: inout GraphicsContext, size: CGSize) {
        let plot = plotRect(size: size)
        for index in 0...3 {
            let ratio = Double(index) / 3
            let value = maxKWh - maxKWh * ratio
            let y = plot.minY + plot.height * CGFloat(index) / 3
            context.draw(
                Text("\(value, format: .number.precision(.fractionLength(2)))")
                    .font(.caption2)
                    .foregroundColor(PanelStyle.secondaryText),
                at: CGPoint(x: plot.minX - 26, y: y)
            )
        }
    }

    private func drawXAxisLabels(in context: inout GraphicsContext, size: CGSize) {
        let plot = plotRect(size: size)

        if mode == .day, let first = items.first {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Brussels") ?? .current
            let dayStart = calendar.startOfDay(for: first.start)

            for hour in stride(from: 0, through: 24, by: 4) {
                guard
                    let labelDate = calendar.date(byAdding: .hour, value: hour, to: dayStart),
                    let x = xPosition(for: labelDate, size: size)
                else {
                    continue
                }

                drawXAxisTick(in: &context, x: x, label: "\(hour % 24)u", plot: plot)
            }
            return
        }

        for index in xLabelIndices {
            drawXAxisTick(in: &context, x: xPosition(index: index, size: size), label: items[index].label, plot: plot)
        }
    }

    private func drawXAxisTick(in context: inout GraphicsContext, x: CGFloat, label: String, plot: CGRect) {
        var tick = Path()
        tick.move(to: CGPoint(x: x, y: plot.maxY))
        tick.addLine(to: CGPoint(x: x, y: plot.maxY + 4))
        context.stroke(tick, with: .color(PanelStyle.gridLine), lineWidth: 1)

        context.draw(
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(PanelStyle.axisText),
            at: CGPoint(x: x, y: plot.maxY + 13)
        )
    }

    private var xLabelIndices: [Int] {
        guard items.isEmpty == false else {
            return []
        }

        switch mode {
        case .day:
            return stride(from: 0, through: items.count - 1, by: 16).map { $0 }
        case .month:
            return stride(from: 0, through: items.count - 1, by: 5).map { $0 }
        case .year:
            return Array(items.indices)
        }
    }

    private func drawBars(in context: inout GraphicsContext, size: CGSize) {
        guard items.isEmpty == false else {
            return
        }

        let plot = plotRect(size: size)

        for index in items.indices {
            let item = items[index]
            let slotWidth: CGFloat
            let x: CGFloat

            if mode == .day, let startX = xPosition(for: item.start, size: size), let endX = xPosition(for: item.end, size: size) {
                slotWidth = max(endX - startX, 1)
                x = startX + slotWidth / 2
            } else {
                slotWidth = plot.width / CGFloat(items.count)
                x = plot.minX + (CGFloat(index) + 0.5) * slotWidth
            }

            let barWidth = max(slotWidth * 0.32, 1)
            drawBar(in: &context, x: x - barWidth * 0.58, width: barWidth, value: item.importKWh, plot: plot, color: PanelStyle.importLine)
            drawBar(in: &context, x: x + barWidth * 0.58, width: barWidth, value: item.exportKWh, plot: plot, color: PanelStyle.exportLine)
        }
    }

    private func drawBar(in context: inout GraphicsContext, x: CGFloat, width: CGFloat, value: Double, plot: CGRect, color: Color) {
        guard value > 0 else {
            return
        }

        let height = plot.height * CGFloat(value / maxKWh)
        let rect = CGRect(x: x - width / 2, y: plot.maxY - height, width: width, height: max(height, 1))
        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(0.85)))
    }

    private func drawSelection(in context: inout GraphicsContext, size: CGSize) {
        guard let selectedItem = effectiveSelectedItem, let index = items.firstIndex(of: selectedItem) else {
            return
        }

        let plot = plotRect(size: size)
        let x: CGFloat
        if mode == .day,
           let startX = xPosition(for: selectedItem.start, size: size),
           let endX = xPosition(for: selectedItem.end, size: size) {
            x = startX + (endX - startX) / 2
        } else {
            x = xPosition(index: index, size: size)
        }
        var rule = Path()
        rule.move(to: CGPoint(x: x, y: plot.minY))
        rule.addLine(to: CGPoint(x: x, y: plot.maxY))
        context.stroke(rule, with: .color(.white.opacity(0.82)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    private func selectItem(atX x: CGFloat, width: CGFloat) {
        let item = item(atX: x, width: width)
        selectedItem = item
        selectedQuarterStart = mode == .day ? item?.start : nil
    }

    private func item(atX x: CGFloat, width: CGFloat) -> P1ChartItem? {
        guard items.isEmpty == false else {
            return nil
        }

        let plot = plotRect(size: CGSize(width: width, height: 1))
        let clampedX = min(max(x, plot.minX), plot.maxX)
        let ratio = (clampedX - plot.minX) / plot.width

        if mode == .day, let first = items.first, let last = items.last {
            let duration = last.end.timeIntervalSince(first.start)
            let date = first.start.addingTimeInterval(duration * Double(ratio))
            if let containingItem = items.first(where: { $0.start <= date && date < $0.end }) {
                return containingItem
            }
        }

        let index = Int((ratio * CGFloat(items.count - 1)).rounded())
        return items[min(max(index, items.startIndex), items.endIndex - 1)]
    }

    private func xPosition(index: Int, size: CGSize) -> CGFloat {
        let plot = plotRect(size: size)
        guard items.count > 1 else {
            return plot.midX
        }

        if mode == .day, let x = xPosition(for: items[index].start, size: size) {
            return x
        }

        let slotWidth = plot.width / CGFloat(items.count)
        return plot.minX + (CGFloat(index) + 0.5) * slotWidth
    }

    private func xPosition(for date: Date, size: CGSize) -> CGFloat? {
        guard mode == .day, let first = items.first, let last = items.last else {
            return nil
        }

        let duration = last.end.timeIntervalSince(first.start)
        guard duration > 0, first.start <= date, date <= last.end else {
            return nil
        }

        let plot = plotRect(size: size)
        let ratio = CGFloat(date.timeIntervalSince(first.start) / duration)
        return plot.minX + plot.width * ratio
    }

    private func plotRect(size: CGSize) -> CGRect {
        ChartGeometry.plotRect(size: size)
    }
}

struct P1AggregateDetail: View {
    let item: P1ChartItem
    let mode: P1PeriodMode

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.caption.weight(.semibold))
                Text(detailSubtitle)
                    .font(.caption2)
                    .foregroundStyle(PanelStyle.secondaryText)
            }

            Spacer()

            CompactAveragePill(title: "Import", value: item.importKWh, color: PanelStyle.importLine, suffix: "kWh")
            CompactAveragePill(title: "Injectie", value: item.exportKWh, color: PanelStyle.exportLine, suffix: "kWh")
            CompactAveragePill(title: "All-in kost", value: item.importCostEUR, color: PanelStyle.importAppLine, suffix: "EUR")
            CompactAveragePill(title: "Credit", value: item.exportCreditEUR, color: PanelStyle.exportLine, suffix: "EUR")
        }
        .frame(height: 34)
    }

    private var detailSubtitle: String {
        switch mode {
        case .day:
            return "\(item.start.formatted(date: .omitted, time: .shortened)) - \(item.end.formatted(date: .omitted, time: .shortened))"
        case .month:
            return "\(item.intervalCount) P1-intervallen"
        case .year:
            return "\(item.intervalCount) P1-intervallen"
        }
    }
}

struct MonthlyAverageDetail: View {
    let summary: DailyPriceSummary?

    var body: some View {
        HStack(spacing: 12) {
            if let summary {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.dateKey)
                        .font(.caption.weight(.semibold))
                    Text("\(summary.pointCount) kwartieren")
                        .font(.caption2)
                        .foregroundStyle(PanelStyle.secondaryText)
                }

                Spacer()

                CompactAveragePill(title: "Import app", value: summary.resolvedImportAppAverageCentsPerKWh, color: PanelStyle.importAppLine)
                CompactAveragePill(title: "Import factuur", value: summary.importAverageCentsPerKWh, color: PanelStyle.importLine)
                CompactAveragePill(title: "All-in import", value: summary.resolvedAllInImportAverageCentsPerKWh, color: PanelStyle.allInImportLine)
                CompactAveragePill(title: "EPEX export", value: summary.marketAverageCentsPerKWh, color: PanelStyle.marketLine)
                CompactAveragePill(title: "Export", value: summary.exportAverageCentsPerKWh, color: PanelStyle.exportLine)
            } else {
                Text("Geen daggemiddelden voor deze maand")
                    .font(.caption)
                    .foregroundStyle(PanelStyle.secondaryText)
                Spacer()
            }
        }
        .frame(height: 34)
    }
}

struct MonthSelector: View {
    let monthKeys: [String]
    let monthKeysWithData: Set<String>
    let selectedMonthKey: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(monthKeys, id: \.self) { monthKey in
                let hasData = monthKeysWithData.contains(monthKey)
                Button {
                    onSelect(monthKey)
                } label: {
                    Text(PriceHistoryStore.monthTitle(fromMonthKey: monthKey))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(monthTextColor(monthKey: monthKey, hasData: hasData))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(monthBackgroundColor(monthKey: monthKey, hasData: hasData))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(hasData ? PanelStyle.monthSelectorBorder : PanelStyle.monthSelectorDisabledBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize()
    }

    private func monthTextColor(monthKey: String, hasData: Bool) -> Color {
        if monthKey == selectedMonthKey {
            return PanelStyle.monthSelectorSelectedText
        }

        return hasData ? PanelStyle.monthSelectorText : PanelStyle.monthSelectorDisabledText
    }

    private func monthBackgroundColor(monthKey: String, hasData: Bool) -> Color {
        if monthKey == selectedMonthKey {
            return hasData ? PanelStyle.monthSelectorSelectedBackground : PanelStyle.monthSelectorDisabledSelectedBackground
        }

        return hasData ? PanelStyle.monthSelectorBackground : PanelStyle.monthSelectorDisabledBackground
    }
}

struct MonthlyAverageChart: View {
    let summaries: [DailyPriceSummary]
    @Binding var selectedSummary: DailyPriceSummary?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGrid(in: &context, size: size)
                    drawLine(in: &context, size: size, values: summaries.map(\.marketAverageCentsPerKWh), color: PanelStyle.marketLine)
                    drawLine(in: &context, size: size, values: summaries.map(\.resolvedImportAppAverageCentsPerKWh), color: PanelStyle.importAppLine)
                    drawLine(in: &context, size: size, values: summaries.map(\.importAverageCentsPerKWh), color: PanelStyle.importLine)
                    drawLine(in: &context, size: size, values: summaries.map(\.resolvedAllInImportAverageCentsPerKWh), color: PanelStyle.allInImportLine)
                    drawLine(in: &context, size: size, values: summaries.map(\.exportAverageCentsPerKWh), color: PanelStyle.exportLine)
                    drawPoints(in: &context, size: size)
                    drawDayLabels(in: &context, size: size)
                    drawYAxisLabels(in: &context, size: size)
                    drawSelection(in: &context, size: size)
                }
                .background(PanelStyle.chartBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PanelStyle.chartBorder, lineWidth: 1)
                )

                if summaries.isEmpty {
                    Text("Nog geen opgeslagen daggemiddelden voor deze maand.")
                        .font(.caption)
                        .foregroundStyle(PanelStyle.secondaryText)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }

                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        LegendDot(color: PanelStyle.importAppLine, title: "Import app")
                        LegendDot(color: PanelStyle.importLine, title: "Factuur")
                        LegendDot(color: PanelStyle.allInImportLine, title: "All-in")
                        LegendDot(color: PanelStyle.marketLine, title: "EPEX export")
                        LegendDot(color: PanelStyle.exportLine, title: "Export")
                        Spacer()
                        Text("cent/kWh")
                            .foregroundStyle(PanelStyle.secondaryText)
                    }
                    .font(.caption2)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 5)
                }

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                selectedSummary = summary(atX: value.location.x, width: geometry.size.width)
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            selectedSummary = summary(atX: location.x, width: geometry.size.width)
                        case .ended:
                            selectedSummary = nil
                        }
                    }
            }
        }
    }

    private var valueRange: ClosedRange<Double> {
        let values = summaries.flatMap {
            [$0.marketAverageCentsPerKWh, $0.resolvedImportAppAverageCentsPerKWh, $0.importAverageCentsPerKWh, $0.resolvedAllInImportAverageCentsPerKWh, $0.exportAverageCentsPerKWh]
        }
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        let padding = max((maximum - minimum) * 0.16, 0.7)
        return (minimum - padding)...(maximum + padding)
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let plot = plotRect(size: size)
        var grid = Path()

        for index in 0...3 {
            let y = plot.minY + plot.height * CGFloat(index) / 3
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
        }

        context.stroke(grid, with: .color(PanelStyle.gridLine), lineWidth: 1)
    }

    private func drawYAxisLabels(in context: inout GraphicsContext, size: CGSize) {
        let plot = plotRect(size: size)
        let range = valueRange

        for index in 0...3 {
            let ratio = Double(index) / 3
            let value = range.upperBound - (range.upperBound - range.lowerBound) * ratio
            let y = plot.minY + plot.height * CGFloat(index) / 3
            context.draw(
                Text("\(value, format: .number.precision(.fractionLength(1)))")
                    .font(.caption2)
                    .foregroundColor(PanelStyle.secondaryText),
                at: CGPoint(x: plot.minX - 22, y: y)
            )
        }
    }

    private func drawLine(in context: inout GraphicsContext, size: CGSize, values: [Double], color: Color) {
        guard summaries.count > 1, values.count == summaries.count else {
            return
        }

        var path = Path()
        for index in values.indices {
            let point = canvasPoint(index: index, value: values[index], size: size)
            if index == values.startIndex {
                path.move(to: point)
            } else {
                let previous = canvasPoint(index: index - 1, value: values[index - 1], size: size)
                path.addLine(to: CGPoint(x: point.x, y: previous.y))
                path.addLine(to: point)
            }
        }

        context.stroke(path, with: .color(color), lineWidth: 1.2)
    }

    private func drawPoints(in context: inout GraphicsContext, size: CGSize) {
        for index in summaries.indices {
            let summary = summaries[index]
            fillPoint(in: &context, at: canvasPoint(index: index, value: summary.marketAverageCentsPerKWh, size: size), color: PanelStyle.marketLine)
            fillPoint(in: &context, at: canvasPoint(index: index, value: summary.resolvedImportAppAverageCentsPerKWh, size: size), color: PanelStyle.importAppLine)
            fillPoint(in: &context, at: canvasPoint(index: index, value: summary.importAverageCentsPerKWh, size: size), color: PanelStyle.importLine)
            fillPoint(in: &context, at: canvasPoint(index: index, value: summary.resolvedAllInImportAverageCentsPerKWh, size: size), color: PanelStyle.allInImportLine)
            fillPoint(in: &context, at: canvasPoint(index: index, value: summary.exportAverageCentsPerKWh, size: size), color: PanelStyle.exportLine)
        }
    }

    private func fillPoint(in context: inout GraphicsContext, at point: CGPoint, color: Color) {
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
            with: .color(color)
        )
    }

    private func drawDayLabels(in context: inout GraphicsContext, size: CGSize) {
        guard summaries.isEmpty == false else {
            return
        }

        let plot = plotRect(size: size)
        let labelIndices = evenlySpacedIndices(count: summaries.count, maxLabels: 9)

        for index in labelIndices.sorted() {
            guard let day = PriceHistoryStore.dayNumber(fromDateKey: summaries[index].dateKey) else {
                continue
            }

            let x = xPosition(index: index, size: size)
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: plot.maxY))
            tick.addLine(to: CGPoint(x: x, y: plot.maxY + 4))
            context.stroke(tick, with: .color(PanelStyle.gridLine), lineWidth: 1)

            context.draw(
                Text("\(day)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(PanelStyle.axisText),
                at: CGPoint(x: x, y: plot.maxY + 13)
            )
        }
    }

    private func drawSelection(in context: inout GraphicsContext, size: CGSize) {
        guard let selectedSummary, let index = summaries.firstIndex(of: selectedSummary) else {
            return
        }

        let plot = plotRect(size: size)
        let x = xPosition(index: index, size: size)
        var rule = Path()
        rule.move(to: CGPoint(x: x, y: plot.minY))
        rule.addLine(to: CGPoint(x: x, y: plot.maxY))
        context.stroke(rule, with: .color(.white.opacity(0.82)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        fillPoint(in: &context, at: canvasPoint(index: index, value: selectedSummary.marketAverageCentsPerKWh, size: size), color: PanelStyle.marketLine)
        fillPoint(in: &context, at: canvasPoint(index: index, value: selectedSummary.resolvedImportAppAverageCentsPerKWh, size: size), color: PanelStyle.importAppLine)
        fillPoint(in: &context, at: canvasPoint(index: index, value: selectedSummary.importAverageCentsPerKWh, size: size), color: PanelStyle.importLine)
        fillPoint(in: &context, at: canvasPoint(index: index, value: selectedSummary.resolvedAllInImportAverageCentsPerKWh, size: size), color: PanelStyle.allInImportLine)
        fillPoint(in: &context, at: canvasPoint(index: index, value: selectedSummary.exportAverageCentsPerKWh, size: size), color: PanelStyle.exportLine)
    }

    private func summary(atX x: CGFloat, width: CGFloat) -> DailyPriceSummary? {
        guard summaries.isEmpty == false else {
            return nil
        }

        let plot = plotRect(size: CGSize(width: width, height: 1))
        guard summaries.count > 1 else {
            return summaries.first
        }

        let clampedX = min(max(x, plot.minX), plot.maxX)
        let ratio = (clampedX - plot.minX) / plot.width
        let index = Int((ratio * CGFloat(summaries.count - 1)).rounded())
        return summaries[min(max(index, summaries.startIndex), summaries.endIndex - 1)]
    }

    private func canvasPoint(index: Int, value: Double, size: CGSize) -> CGPoint {
        let plot = plotRect(size: size)
        let range = valueRange
        let rangeSize = max(range.upperBound - range.lowerBound, 0.001)
        let yRatio = CGFloat((value - range.lowerBound) / rangeSize)

        return CGPoint(
            x: xPosition(index: index, size: size),
            y: plot.maxY - plot.height * yRatio
        )
    }

    private func xPosition(index: Int, size: CGSize) -> CGFloat {
        let plot = plotRect(size: size)
        guard summaries.count > 1 else {
            return plot.midX
        }

        let ratio = CGFloat(index) / CGFloat(summaries.count - 1)
        return plot.minX + plot.width * ratio
    }

    private func evenlySpacedIndices(count: Int, maxLabels: Int) -> Set<Int> {
        guard count > 1 else {
            return count == 1 ? [0] : []
        }

        let labelCount = min(maxLabels, count)
        let lastIndex = count - 1
        return Set((0..<labelCount).map { labelIndex in
            Int((Double(lastIndex) * Double(labelIndex) / Double(labelCount - 1)).rounded())
        })
    }

    private func plotRect(size: CGSize) -> CGRect {
        CGRect(x: 44, y: 10, width: max(size.width - 54, 1), height: max(size.height - 62, 1))
    }
}

struct DailyAverageView: View {
    let summary: DailyPriceSummary?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daggemiddelde")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                if let summary {
                    Text("\(summary.dateKey) - \(summary.pointCount) kwartieren")
                        .font(.caption2)
                        .foregroundStyle(PanelStyle.secondaryText)
                } else {
                    Text("Nog geen opgeslagen gemiddelde")
                        .font(.caption2)
                        .foregroundStyle(PanelStyle.secondaryText)
                }
            }

            Spacer()

            if let summary {
                CompactAveragePill(title: "Import app", value: summary.resolvedImportAppAverageCentsPerKWh, color: PanelStyle.importAppLine)
                CompactAveragePill(title: "Import factuur", value: summary.importAverageCentsPerKWh, color: PanelStyle.importLine)
                CompactAveragePill(title: "All-in import", value: summary.resolvedAllInImportAverageCentsPerKWh, color: PanelStyle.allInImportLine)
                CompactAveragePill(title: "EPEX export", value: summary.marketAverageCentsPerKWh, color: PanelStyle.marketLine)
                CompactAveragePill(title: "Export", value: summary.exportAverageCentsPerKWh, color: PanelStyle.exportLine)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CompactAveragePill: View {
    let title: String
    let value: Double
    let color: Color
    var suffix = "c"

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(PanelStyle.secondaryText)
            Text("\(value, format: .number.precision(.fractionLength(2))) \(suffix)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(minWidth: 62, alignment: .trailing)
    }
}

struct DaySelector: View {
    let selectedDay: PriceDay
    let isLoading: Bool
    let hasTomorrowPrices: Bool
    let onSelect: (PriceDay) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PriceDay.allCases) { day in
                Button {
                    onSelect(day)
                } label: {
                    HStack(spacing: 5) {
                        Text(day.title)
                        if day == .tomorrow && hasTomorrowPrices {
                            Circle()
                                .fill(PanelStyle.exportLine)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(day == selectedDay ? PanelStyle.daySelectedText : PanelStyle.dayText)
                    .frame(minWidth: 72)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(day == selectedDay ? PanelStyle.daySelectedBackground : PanelStyle.dayBackground)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
        }
        .padding(3)
        .background(PanelStyle.dayContainerBackground, in: RoundedRectangle(cornerRadius: 9))
        .help(hasTomorrowPrices ? "Morgentarieven beschikbaar" : "Morgentarieven verschijnen meestal na 15u of 16u")
    }
}

struct PricePill: View {
    let title: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(PanelStyle.secondaryText)
            Text("\(value, format: .number.precision(.fractionLength(2))) c/kWh")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PriceChart: View {
    let points: [PricePoint]
    @Binding var selectedPoint: PricePoint?
    @Binding var selectedQuarterStart: Date?

    private var effectiveSelectedPoint: PricePoint? {
        if let selectedQuarterStart {
            return points.first { $0.displayStart <= selectedQuarterStart && selectedQuarterStart < $0.displayEnd }
        }

        return selectedPoint
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    Canvas { context, size in
                        drawGrid(in: &context, size: size)
                        drawYAxisLabels(in: &context, size: size)
                        drawXAxisLabels(in: &context, size: size)
                        drawLine(in: &context, size: size, values: points.map(\.marketCentsPerKWh), color: PanelStyle.marketLine)
                        drawLine(in: &context, size: size, values: points.map(\.importAppCentsPerKWh), color: PanelStyle.importAppLine)
                        drawLine(in: &context, size: size, values: points.map(\.importCentsPerKWh), color: PanelStyle.importLine)
                        drawLine(in: &context, size: size, values: points.map(\.allInImportCentsPerKWh), color: PanelStyle.allInImportLine)
                        drawLine(in: &context, size: size, values: points.map(\.exportCentsPerKWh), color: PanelStyle.exportLine)
                        drawNow(in: &context, size: size, now: timeline.date)
                        drawSelection(in: &context, size: size)
                    }
                }
                .background(PanelStyle.chartBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PanelStyle.chartBorder, lineWidth: 1)
                )

                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        LegendDot(color: PanelStyle.importAppLine, title: "Import app")
                        LegendDot(color: PanelStyle.importLine, title: "Factuur")
                        LegendDot(color: PanelStyle.allInImportLine, title: "All-in import")
                        LegendDot(color: PanelStyle.marketLine, title: "EPEX export")
                        LegendDot(color: PanelStyle.exportLine, title: "Export")
                        LegendDot(color: PanelStyle.nowLine, title: "Nu")
                        Spacer()
                        Text("cent/kWh")
                            .foregroundStyle(PanelStyle.secondaryText)
                    }
                    .font(.caption)
                    .padding(10)
                }

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                selectPoint(atX: value.location.x, width: geometry.size.width)
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            selectPoint(atX: location.x, width: geometry.size.width)
                        case .ended:
                            selectedPoint = nil
                            selectedQuarterStart = nil
                        }
                    }
            }
        }
    }

    private var valueRange: ClosedRange<Double> {
        let values = points.flatMap { [$0.marketCentsPerKWh, $0.importAppCentsPerKWh, $0.importCentsPerKWh, $0.allInImportCentsPerKWh, $0.exportCentsPerKWh] }
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        let padding = max((maximum - minimum) * 0.12, 1)
        return (minimum - padding)...(maximum + padding)
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let plot = plotRect(size: size)
        var grid = Path()

        for index in 0...4 {
            let y = plot.minY + plot.height * CGFloat(index) / 4
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
        }

        context.stroke(grid, with: .color(PanelStyle.gridLine), lineWidth: 1)
    }

    private func drawYAxisLabels(in context: inout GraphicsContext, size: CGSize) {
        let plot = plotRect(size: size)
        let range = valueRange

        for index in 0...4 {
            let ratio = Double(index) / 4
            let value = range.upperBound - (range.upperBound - range.lowerBound) * ratio
            let y = plot.minY + plot.height * CGFloat(index) / 4
            context.draw(
                Text("\(value, format: .number.precision(.fractionLength(1)))")
                    .font(.caption2)
                    .foregroundColor(PanelStyle.secondaryText),
                at: CGPoint(x: plot.minX - 22, y: y)
            )
        }
    }

    private func drawXAxisLabels(in context: inout GraphicsContext, size: CGSize) {
        guard let first = points.first, let last = points.last else {
            return
        }

        let plot = plotRect(size: size)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Brussels") ?? .current
        let firstHour = calendar.component(.hour, from: first.displayStart)
        let startStep = Int(ceil(Double(firstHour) / 4.0)) * 4

        for hour in stride(from: startStep, through: firstHour + 24, by: 4) {
            guard
                let labelDate = calendar.date(bySettingHour: hour % 24, minute: 0, second: 0, of: first.displayStart),
                let adjustedDate = hour >= 24 ? calendar.date(byAdding: .day, value: 1, to: labelDate) : labelDate,
                first.displayStart <= adjustedDate,
                adjustedDate <= last.displayEnd,
                let x = xPosition(for: adjustedDate, size: size)
            else {
                continue
            }

            var tick = Path()
            tick.move(to: CGPoint(x: x, y: plot.maxY))
            tick.addLine(to: CGPoint(x: x, y: plot.maxY + 4))
            context.stroke(tick, with: .color(PanelStyle.gridLine), lineWidth: 1)

            context.draw(
                Text("\(hour % 24)u")
                    .font(.caption2)
                    .foregroundColor(PanelStyle.secondaryText),
                at: CGPoint(x: x, y: plot.maxY + 13)
            )
        }
    }

    private func drawLine(in context: inout GraphicsContext, size: CGSize, values: [Double], color: Color) {
        guard points.count > 1, values.count == points.count else {
            return
        }

        var path = Path()

        for index in values.indices {
            let point = canvasPoint(index: index, value: values[index], size: size)
            if index == values.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        context.stroke(path, with: .color(color), lineWidth: 1.4)
    }

    private func drawNow(in context: inout GraphicsContext, size: CGSize, now: Date) {
        guard let x = xPosition(for: now, size: size) else {
            return
        }

        let plot = plotRect(size: size)
        var rule = Path()
        rule.move(to: CGPoint(x: x, y: plot.minY))
        rule.addLine(to: CGPoint(x: x, y: plot.maxY))
        context.stroke(rule, with: .color(PanelStyle.nowLine), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))

        context.draw(
            Text("Nu")
                .font(.caption2.bold())
                .foregroundColor(PanelStyle.nowLine),
            at: CGPoint(x: min(max(x + 14, plot.minX + 14), plot.maxX - 14), y: plot.minY + 10)
        )
    }

    private func drawSelection(in context: inout GraphicsContext, size: CGSize) {
        guard let selectedPoint = effectiveSelectedPoint, let index = points.firstIndex(of: selectedPoint) else {
            return
        }

        let plot = plotRect(size: size)
        let x = canvasPoint(index: index, value: selectedPoint.importCentsPerKWh, size: size).x
        var rule = Path()
        rule.move(to: CGPoint(x: x, y: plot.minY))
        rule.addLine(to: CGPoint(x: x, y: plot.maxY))
        context.stroke(rule, with: .color(.white.opacity(0.82)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        let importPoint = canvasPoint(index: index, value: selectedPoint.importCentsPerKWh, size: size)
        let allInImportPoint = canvasPoint(index: index, value: selectedPoint.allInImportCentsPerKWh, size: size)
        let importAppPoint = canvasPoint(index: index, value: selectedPoint.importAppCentsPerKWh, size: size)
        let exportPoint = canvasPoint(index: index, value: selectedPoint.exportCentsPerKWh, size: size)
        let marketPoint = canvasPoint(index: index, value: selectedPoint.marketCentsPerKWh, size: size)
        context.fill(Path(ellipseIn: CGRect(x: marketPoint.x - 4, y: marketPoint.y - 4, width: 8, height: 8)), with: .color(PanelStyle.marketLine))
        context.fill(Path(ellipseIn: CGRect(x: importAppPoint.x - 4, y: importAppPoint.y - 4, width: 8, height: 8)), with: .color(PanelStyle.importAppLine))
        context.fill(Path(ellipseIn: CGRect(x: importPoint.x - 4, y: importPoint.y - 4, width: 8, height: 8)), with: .color(PanelStyle.importLine))
        context.fill(Path(ellipseIn: CGRect(x: allInImportPoint.x - 4, y: allInImportPoint.y - 4, width: 8, height: 8)), with: .color(PanelStyle.allInImportLine))
        context.fill(Path(ellipseIn: CGRect(x: exportPoint.x - 4, y: exportPoint.y - 4, width: 8, height: 8)), with: .color(PanelStyle.exportLine))
    }

    private func selectPoint(atX x: CGFloat, width: CGFloat) {
        let point = point(atX: x, width: width)
        selectedPoint = point
        selectedQuarterStart = point?.displayStart
    }

    private func point(atX x: CGFloat, width: CGFloat) -> PricePoint? {
        guard
            points.count > 1,
            let first = points.first,
            let last = points.last
        else {
            return points.first
        }

        let plot = plotRect(size: CGSize(width: width, height: 1))
        let clampedX = min(max(x, plot.minX), plot.maxX)
        let ratio = (clampedX - plot.minX) / plot.width
        let duration = last.displayEnd.timeIntervalSince(first.displayStart)
        let date = first.displayStart.addingTimeInterval(duration * Double(ratio))

        if let containingPoint = points.first(where: { $0.displayStart <= date && date < $0.displayEnd }) {
            return containingPoint
        }

        return points.min { left, right in
            abs(left.displayStart.timeIntervalSince(date)) < abs(right.displayStart.timeIntervalSince(date))
        }
    }

    private func canvasPoint(index: Int, value: Double, size: CGSize) -> CGPoint {
        let plot = plotRect(size: size)
        let range = valueRange
        let rangeSize = max(range.upperBound - range.lowerBound, 0.001)
        let yRatio = CGFloat((value - range.lowerBound) / rangeSize)

        return CGPoint(
            x: xPosition(for: points[index].displayStart, size: size) ?? plot.minX,
            y: plot.maxY - plot.height * yRatio
        )
    }

    private func xPosition(for date: Date, size: CGSize) -> CGFloat? {
        guard let first = points.first, let last = points.last else {
            return nil
        }

        let duration = last.displayEnd.timeIntervalSince(first.displayStart)
        guard duration > 0, first.displayStart <= date, date <= last.displayEnd else {
            return nil
        }

        let plot = plotRect(size: size)
        let ratio = CGFloat(date.timeIntervalSince(first.displayStart) / duration)
        return plot.minX + plot.width * ratio
    }

    private func plotRect(size: CGSize) -> CGRect {
        ChartGeometry.plotRect(size: size)
    }
}

enum ChartGeometry {
    static func plotRect(size: CGSize) -> CGRect {
        CGRect(x: 52, y: 10, width: max(size.width - 62, 1), height: max(size.height - 58, 1))
    }
}

struct LegendDot: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
        }
    }
}

enum PanelStyle {
    static let background = Color(red: 0.025, green: 0.075, blue: 0.16)
    static let chartBackground = Color(red: 0.035, green: 0.105, blue: 0.22)
    static let chartBorder = Color.white.opacity(0.12)
    static let gridLine = Color.white.opacity(0.12)
    static let axisText = Color.white.opacity(0.88)
    static let secondaryText = Color.white.opacity(0.68)
    static let marketLine = Color(red: 1.0, green: 0.92, blue: 0.54)
    static let importAppLine = Color(red: 1.0, green: 0.68, blue: 0.22)
    static let importLine = Color(red: 1.0, green: 0.36, blue: 0.18)
    static let allInImportLine = Color(red: 0.55, green: 0.78, blue: 1.0)
    static let importValue = Color.white
    static let exportLine = Color(red: 0.26, green: 0.88, blue: 0.58)
    static let nowLine = Color(red: 1.0, green: 0.78, blue: 0.24)
    static let warningText = Color(red: 1.0, green: 0.55, blue: 0.48)
    static let dayContainerBackground = Color.white.opacity(0.09)
    static let dayBackground = Color.white.opacity(0.06)
    static let daySelectedBackground = Color.white.opacity(0.92)
    static let dayText = Color.white.opacity(0.84)
    static let daySelectedText = Color(red: 0.025, green: 0.075, blue: 0.16)
    static let monthSelectorBackground = Color(red: 0.06, green: 0.16, blue: 0.32)
    static let monthSelectorSelectedBackground = Color(red: 0.0, green: 0.72, blue: 0.34)
    static let monthSelectorBorder = Color.white.opacity(0.22)
    static let monthSelectorText = Color.white.opacity(0.95)
    static let monthSelectorSelectedText = Color.white
    static let monthSelectorDisabledBackground = Color.white.opacity(0.045)
    static let monthSelectorDisabledSelectedBackground = Color.white.opacity(0.13)
    static let monthSelectorDisabledBorder = Color.white.opacity(0.08)
    static let monthSelectorDisabledText = Color.white.opacity(0.34)
    static let frankGreen = Color(red: 0.0, green: 0.72, blue: 0.34)
}
