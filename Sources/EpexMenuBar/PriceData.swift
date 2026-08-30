import Foundation

struct PricePoint: Identifiable, Hashable {
    let id = UUID()
    let start: Date
    let end: Date
    let marketCentsPerKWh: Double
    let importAppCentsPerKWh: Double
    let importCentsPerKWh: Double
    let allInImportCentsPerKWh: Double
    let exportCentsPerKWh: Double

    var displayStart: Date {
        start
    }

    var displayEnd: Date {
        end
    }
}

struct DailyPriceSummary: Identifiable, Codable, Hashable {
    let dateKey: String
    let marketAverageCentsPerKWh: Double
    let importAppAverageCentsPerKWh: Double?
    let importAverageCentsPerKWh: Double
    let exportAverageCentsPerKWh: Double
    let pointCount: Int
    let updatedAt: Date

    var id: String { dateKey }
    var resolvedImportAppAverageCentsPerKWh: Double { importAppAverageCentsPerKWh ?? importAverageCentsPerKWh }
}

struct P1Sample: Codable, Hashable {
    let timestamp: Date
    let totalImportKWh: Double
    let totalExportKWh: Double
    let activePowerW: Double
}

struct P1UsageInterval: Codable, Hashable {
    let start: Date
    let end: Date
    let importKWh: Double
    let exportKWh: Double
    let activePowerW: Double
    let importCostEUR: Double
    let exportCreditEUR: Double

    var netCostEUR: Double {
        importCostEUR - exportCreditEUR
    }
}

struct P1DailySummary: Identifiable, Codable, Hashable {
    let dateKey: String
    let importKWh: Double
    let exportKWh: Double
    let importCostEUR: Double
    let exportCreditEUR: Double
    let intervalCount: Int
    let updatedAt: Date

    var id: String { dateKey }
    var netCostEUR: Double { importCostEUR - exportCreditEUR }
}

enum PriceDay: String, CaseIterable, Identifiable {
    case today
    case tomorrow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "Vandaag"
        case .tomorrow:
            return "Morgen"
        }
    }

    var dayOffset: Int {
        switch self {
        case .today:
            return 0
        case .tomorrow:
            return 1
        }
    }
}

@MainActor
final class PriceViewModel: ObservableObject {
    @Published private(set) var points: [PricePoint] = []
    @Published private(set) var dailySummaries: [DailyPriceSummary] = []
    @Published private(set) var p1DailySummaries: [P1DailySummary] = []
    @Published private(set) var p1Intervals: [P1UsageInterval] = []
    @Published private(set) var p1TodayIntervals: [P1UsageInterval] = []
    @Published private(set) var p1CurrentSample: P1Sample?
    @Published private(set) var p1Status = "P1 nog niet gelezen"
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var sourceDescription = "Demo-data"
    @Published private(set) var hasTomorrowPrices = false
    @Published var selectedDay: PriceDay = .today
    @Published var selectedMonthKey = PriceHistoryStore.monthKey(for: Date())

    private let service: PriceService
    private let historyStore: PriceHistoryStore
    private let p1Service: P1Service
    private let p1Store: P1HistoryStore
    private var backgroundTask: Task<Void, Never>?
    private var p1Task: Task<Void, Never>?

    init(
        service: PriceService = PriceService(),
        historyStore: PriceHistoryStore = PriceHistoryStore(),
        p1Service: P1Service = P1Service(),
        p1Store: P1HistoryStore = P1HistoryStore()
    ) {
        self.service = service
        self.historyStore = historyStore
        self.p1Service = p1Service
        self.p1Store = p1Store
        self.dailySummaries = historyStore.loadSummaries()
        refreshP1PublishedState()

        backgroundTask = Task { [weak self] in
            await self?.bootstrapAndStartBackgroundRefresh()
        }

        p1Task = Task { [weak self] in
            await self?.startP1Logging()
        }
    }

    deinit {
        backgroundTask?.cancel()
        p1Task?.cancel()
    }

    var currentPoint: PricePoint? {
        let now = Date()
        if selectedDay == .today, let point = points.first(where: { $0.displayStart <= now && now < $0.displayEnd }) {
            return point
        }

        return points.first
    }

    var selectedDaySummary: DailyPriceSummary? {
        let key = PriceHistoryStore.dateKey(for: Date(), dayOffset: selectedDay.dayOffset)
        return dailySummaries.first { $0.dateKey == key }
    }

    var availableMonthKeys: [String] {
        let monthKeys = Set(dailySummaries.map { PriceHistoryStore.monthKey(fromDateKey: $0.dateKey) } + PriceHistoryStore.recentMonthKeys())
        return monthKeys.sorted(by: >)
    }

    var monthKeysWithData: Set<String> {
        Set(dailySummaries.map { PriceHistoryStore.monthKey(fromDateKey: $0.dateKey) })
    }

    var selectedMonthSummaries: [DailyPriceSummary] {
        dailySummaries
            .filter { PriceHistoryStore.monthKey(fromDateKey: $0.dateKey) == selectedMonthKey }
            .sorted { $0.dateKey < $1.dateKey }
    }

    var selectedMonthP1Summaries: [P1DailySummary] {
        p1DailySummaries
            .filter { PriceHistoryStore.monthKey(fromDateKey: $0.dateKey) == selectedMonthKey }
            .sorted { $0.dateKey < $1.dateKey }
    }

    var selectedDayP1Summary: P1DailySummary? {
        let key = PriceHistoryStore.dateKey(for: Date(), dayOffset: selectedDay.dayOffset)
        return p1DailySummaries.first { $0.dateKey == key }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await service.loadPrices(for: selectedDay)
            points = response.points
            sourceDescription = response.sourceDescription
            recordSummary(for: response.points)
        } catch {
            if selectedDay == .tomorrow {
                selectedDay = .today
                await refresh()
                errorMessage = "Morgentarieven zijn nog niet beschikbaar."
            } else {
                points = PriceService.demoPrices()
                sourceDescription = "Demo-data"
                errorMessage = "Kon echte tariefdata niet laden: \(error.localizedDescription)"
            }
        }

        await refreshTomorrowAvailability()
    }

    func selectDay(_ day: PriceDay) async {
        guard day != selectedDay else {
            return
        }

        selectedDay = day
        await refresh()
    }

    func selectMonth(_ monthKey: String) {
        selectedMonthKey = monthKey
    }

    private func refreshTomorrowAvailability() async {
        hasTomorrowPrices = (try? await service.hasPrices(for: .tomorrow)) ?? false
    }

    private func bootstrapAndStartBackgroundRefresh() async {
        await refresh()
        await refreshInBackground()

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60 * 60 * 1_000_000_000)
            await refreshInBackground()
        }
    }

    private func refreshInBackground() async {
        for day in PriceDay.allCases {
            if let response = try? await service.loadPrices(for: day) {
                recordSummary(for: response.points)
                if day == selectedDay {
                    points = response.points
                    sourceDescription = response.sourceDescription
                }
            }
        }

        await refreshTomorrowAvailability()
    }

    private func startP1Logging() async {
        await recordP1Sample()

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            await recordP1Sample()
        }
    }

    private func recordP1Sample() async {
        do {
            let sample = try await p1Service.loadSample()
            let pricePointsForUsage: [PricePoint]
            if selectedDay == .today, points.isEmpty == false {
                pricePointsForUsage = points
            } else {
                pricePointsForUsage = (try? await service.loadPrices(for: .today).points) ?? points
            }

            let interval = p1Store.appendSample(sample, pricePoints: pricePointsForUsage)
            p1CurrentSample = sample
            p1Status = interval == nil ? "P1 verbonden, wacht op volgende sample" : "P1 verbonden, laatste sample opgeslagen"
            refreshP1PublishedState()
        } catch {
            p1Status = "P1 niet bereikbaar: \(error.localizedDescription)"
            refreshP1PublishedState()
        }
    }

    private func refreshP1PublishedState() {
        p1Intervals = p1Store.loadIntervals()
        p1DailySummaries = p1Store.loadDailySummaries()
        p1TodayIntervals = p1Store.loadIntervals(for: PriceHistoryStore.dateKey(for: Date()))
        p1CurrentSample = p1CurrentSample ?? p1Store.loadLastSample()
    }

    private func recordSummary(for points: [PricePoint]) {
        guard let summary = PriceHistoryStore.summary(from: points) else {
            return
        }

        historyStore.upsert(summary)
        dailySummaries = historyStore.loadSummaries()
    }
}

struct PriceService {
    struct Response {
        let points: [PricePoint]
        let sourceDescription: String
    }

    private let endpoint: URL?
    private let frankEndpoint = URL(string: "https://graphql.frankenergie.nl")!

    init(endpoint: URL? = PriceService.configuredEndpoint()) {
        self.endpoint = endpoint
    }

    func loadPrices(for day: PriceDay) async throws -> Response {
        if let endpoint {
            return try await loadRemoteJSON(from: endpoint)
        }

        return try await loadFrankPrices(for: day)
    }

    func hasPrices(for day: PriceDay) async throws -> Bool {
        if endpoint != nil {
            return true
        }

        return try await loadFrankPrices(for: day).points.isEmpty == false
    }

    private func loadRemoteJSON(from endpoint: URL) async throws -> Response {
        let (data, _) = try await URLSession.shared.data(from: endpoint)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([RemotePriceRecord].self, from: data)
        let points = records.map { record in
            PricePoint(
                start: record.start,
                end: record.end,
                marketCentsPerKWh: record.marketCentsPerKWh ?? record.importCentsPerKWh,
                importAppCentsPerKWh: record.importAppCentsPerKWh ?? record.importCentsPerKWh,
                importCentsPerKWh: record.importCentsPerKWh,
                allInImportCentsPerKWh: record.allInImportCentsPerKWh ?? record.importCentsPerKWh,
                exportCentsPerKWh: record.exportCentsPerKWh
            )
        }
        .sorted { $0.start < $1.start }

        return Response(points: points, sourceDescription: endpoint.absoluteString)
    }

    private func loadFrankPrices(for day: PriceDay) async throws -> Response {
        var request = URLRequest(url: frankEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(FrankGraphQLRequest(
            query: """
            query MarketPrices($date: String!, $resolution: PriceResolution!) {
              marketPrices(date: $date, resolution: $resolution) {
                electricityPrices {
                  from
                  till
                  marketPrice
                  marketPricePlus
                  allInPrice
                  perUnit
                }
              }
            }
            """,
            variables: FrankGraphQLVariables(
                date: Self.localDateString(for: Date(), dayOffset: day.dayOffset),
                resolution: "PT15M"
            )
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw PriceServiceError.httpStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        let graphQLResponse = try decoder.decode(FrankGraphQLResponse.self, from: data)

        if let message = graphQLResponse.errors?.first?.message {
            throw PriceServiceError.graphQL(message)
        }

        let records = graphQLResponse.data?.marketPrices.electricityPrices ?? []
        let points = records
            .filter { $0.perUnit == "KWH" }
            .map { record in
                let marketPrice = FrankBelgianFormula.marketCentsPerKWh(fromFrankMarketPrice: record.marketPrice)
                let importAppPrice = FrankBelgianFormula.importAppCentsPerKWh(fromFrankMarketPrice: record.marketPrice)
                let importPrice = FrankBelgianFormula.importCentsPerKWh(fromFrankMarketPrice: record.marketPrice)
                let allInImportPrice = record.allInPrice * 100
                let exportPrice = FrankBelgianFormula.exportCentsPerKWh(fromFrankMarketPrice: record.marketPrice)
                return PricePoint(
                    start: record.from,
                    end: record.till,
                    marketCentsPerKWh: marketPrice,
                    importAppCentsPerKWh: importAppPrice,
                    importCentsPerKWh: importPrice,
                    allInImportCentsPerKWh: allInImportPrice,
                    exportCentsPerKWh: exportPrice
                )
            }
            .sorted { $0.start < $1.start }

        if points.isEmpty {
            throw PriceServiceError.noPrices
        }

        return Response(
            points: points,
            sourceDescription: "Frank Energie Belgie \(day.title.lowercased()): Dynamisch SL FEB26 QH formule"
        )
    }

    static func demoPrices() -> [PricePoint] {
        let calendar = Calendar(identifier: .gregorian)
        let startOfDay = calendar.startOfDay(for: Date())

        return (0..<96).compactMap { quarterIndex in
            guard
                let start = calendar.date(byAdding: .minute, value: quarterIndex * 15, to: startOfDay),
                let end = calendar.date(byAdding: .minute, value: 15, to: start)
            else {
                return nil
            }

            let hour = Double(quarterIndex) / 4.0
            let morningPeak = exp(-pow((hour - 8.0) / 2.1, 2.0)) * 6.0
            let eveningPeak = exp(-pow((hour - 19.0) / 2.6, 2.0)) * 9.0
            let solarDip = exp(-pow((hour - 13.0) / 3.0, 2.0)) * 7.5
            let base = 11.0 + morningPeak + eveningPeak - solarDip
            let importPrice = max(-2.0, base + sin(hour * 1.7) * 0.8)
            let exportPrice = importPrice - 3.2

            return PricePoint(
                start: start,
                end: end,
                marketCentsPerKWh: importPrice - 1.5,
                importAppCentsPerKWh: importPrice - 1.5,
                importCentsPerKWh: importPrice,
                allInImportCentsPerKWh: importPrice + 14.0,
                exportCentsPerKWh: exportPrice
            )
        }
    }

    private static func configuredEndpoint() -> URL? {
        if let url = UserDefaults.standard.url(forKey: "PriceEndpointURL") {
            return url
        }

        if let value = UserDefaults.standard.string(forKey: "PriceEndpointURL") {
            return URL(string: value)
        }

        if let value = ProcessInfo.processInfo.environment["EPEX_PRICE_ENDPOINT"] {
            return URL(string: value)
        }

        return nil
    }

    private static func localDateString(for date: Date, dayOffset: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        formatter.dateFormat = "yyyy-MM-dd"

        let calendar = Calendar(identifier: .gregorian)
        let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: date) ?? date
        return formatter.string(from: targetDate)
    }
}

struct P1Service {
    private let endpoint: URL

    init(endpoint: URL = P1Service.configuredEndpoint()) {
        self.endpoint = endpoint
    }

    func loadSample() async throws -> P1Sample {
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw PriceServiceError.httpStatus(httpResponse.statusCode)
        }

        let record = try JSONDecoder().decode(HomeWizardP1Record.self, from: data)
        return P1Sample(
            timestamp: Date(),
            totalImportKWh: record.totalPowerImportKWh,
            totalExportKWh: record.totalPowerExportKWh,
            activePowerW: record.activePowerW
        )
    }

    private static func configuredEndpoint() -> URL {
        if let url = UserDefaults.standard.url(forKey: "P1EndpointURL") {
            return url
        }

        if let value = UserDefaults.standard.string(forKey: "P1EndpointURL"), let url = URL(string: value) {
            return url
        }

        return URL(string: "http://192.168.68.112/api/v1/data")!
    }
}

struct HomeWizardP1Record: Decodable {
    let totalPowerImportKWh: Double
    let totalPowerExportKWh: Double
    let activePowerW: Double

    enum CodingKeys: String, CodingKey {
        case totalPowerImportKWh = "total_power_import_kwh"
        case totalPowerExportKWh = "total_power_export_kwh"
        case activePowerW = "active_power_w"
    }
}

struct P1HistoryStore {
    private let samplesURL: URL
    private let intervalsURL: URL
    private let calendar: Calendar

    init(baseDirectory: URL? = nil) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .current
        self.calendar = calendar

        let directory: URL
        if let baseDirectory {
            directory = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            directory = appSupport.appendingPathComponent("EPEX MenuBar", isDirectory: true)
        }

        self.samplesURL = directory.appendingPathComponent("p1-samples.json")
        self.intervalsURL = directory.appendingPathComponent("p1-usage-intervals.json")
    }

    func loadLastSample() -> P1Sample? {
        loadSamples().last
    }

    func loadIntervals(for dateKey: String? = nil) -> [P1UsageInterval] {
        let intervals = prune(load([P1UsageInterval].self, from: intervalsURL))
        guard let dateKey else {
            return intervals
        }

        return intervals.filter { PriceHistoryStore.dateKey(for: $0.end) == dateKey }
    }

    func loadDailySummaries() -> [P1DailySummary] {
        let grouped = Dictionary(grouping: loadIntervals(), by: { PriceHistoryStore.dateKey(for: $0.end) })
        return grouped.map { dateKey, intervals in
            P1DailySummary(
                dateKey: dateKey,
                importKWh: intervals.map(\.importKWh).reduce(0, +),
                exportKWh: intervals.map(\.exportKWh).reduce(0, +),
                importCostEUR: intervals.map(\.importCostEUR).reduce(0, +),
                exportCreditEUR: intervals.map(\.exportCreditEUR).reduce(0, +),
                intervalCount: intervals.count,
                updatedAt: intervals.map(\.end).max() ?? Date()
            )
        }
        .sorted { $0.dateKey > $1.dateKey }
    }

    @discardableResult
    func appendSample(_ sample: P1Sample, pricePoints: [PricePoint]) -> P1UsageInterval? {
        var samples = loadSamples()
        guard shouldAppend(sample, after: samples.last) else {
            return nil
        }

        let previous = samples.last
        samples.append(sample)
        save(prune(samples), to: samplesURL)

        guard
            let previous,
            sample.totalImportKWh >= previous.totalImportKWh,
            sample.totalExportKWh >= previous.totalExportKWh
        else {
            return nil
        }

        let importKWh = sample.totalImportKWh - previous.totalImportKWh
        let exportKWh = sample.totalExportKWh - previous.totalExportKWh
        guard importKWh > 0 || exportKWh > 0 else {
            return nil
        }

        let pricePoint = pricePoints.first { $0.displayStart <= sample.timestamp && sample.timestamp < $0.displayEnd }
        let importCost = importKWh * ((pricePoint?.allInImportCentsPerKWh ?? 0) / 100)
        let exportCredit = exportKWh * ((pricePoint?.exportCentsPerKWh ?? 0) / 100)
        let interval = P1UsageInterval(
            start: previous.timestamp,
            end: sample.timestamp,
            importKWh: importKWh,
            exportKWh: exportKWh,
            activePowerW: sample.activePowerW,
            importCostEUR: importCost,
            exportCreditEUR: exportCredit
        )

        var intervals = loadIntervals()
        intervals.append(interval)
        save(prune(intervals), to: intervalsURL)
        return interval
    }

    private func shouldAppend(_ sample: P1Sample, after previous: P1Sample?) -> Bool {
        guard let previous else {
            return true
        }

        return sample.timestamp.timeIntervalSince(previous.timestamp) >= 60
            && (sample.totalImportKWh != previous.totalImportKWh || sample.totalExportKWh != previous.totalExportKWh)
    }

    private func loadSamples() -> [P1Sample] {
        prune(load([P1Sample].self, from: samplesURL))
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let value = try? decoder.decode(type, from: data) else {
            if let emptyArray = [] as? T {
                return emptyArray
            }
            fatalError("Unsupported P1 store type")
        }

        return value
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            // P1 logging should never break price loading.
        }
    }

    private func prune(_ samples: [P1Sample]) -> [P1Sample] {
        guard let cutoff = calendar.date(byAdding: .month, value: -24, to: Date()) else {
            return samples
        }

        return samples.filter { $0.timestamp >= cutoff }
    }

    private func prune(_ intervals: [P1UsageInterval]) -> [P1UsageInterval] {
        guard let cutoff = calendar.date(byAdding: .month, value: -24, to: Date()) else {
            return intervals
        }

        return intervals.filter { $0.end >= cutoff }
    }
}

struct PriceHistoryStore {
    private let fileURL: URL
    private let calendar: Calendar

    init(fileURL: URL? = nil) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .current
        self.calendar = calendar

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = appSupport
                .appendingPathComponent("EPEX MenuBar", isDirectory: true)
                .appendingPathComponent("price-history.json")
        }
    }

    func loadSummaries() -> [DailyPriceSummary] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let summaries = (try? decoder.decode([DailyPriceSummary].self, from: data)) ?? []
        return prune(summaries).sorted { $0.dateKey > $1.dateKey }
    }

    func upsert(_ summary: DailyPriceSummary) {
        var summaries = loadSummaries().filter { $0.dateKey != summary.dateKey }
        summaries.append(summary)
        save(prune(summaries))
    }

    static func summary(from points: [PricePoint]) -> DailyPriceSummary? {
        guard let first = points.first, !points.isEmpty else {
            return nil
        }

        let count = Double(points.count)
        return DailyPriceSummary(
            dateKey: dateKey(for: first.start),
            marketAverageCentsPerKWh: points.map(\.marketCentsPerKWh).reduce(0, +) / count,
            importAppAverageCentsPerKWh: points.map(\.importAppCentsPerKWh).reduce(0, +) / count,
            importAverageCentsPerKWh: points.map(\.importCentsPerKWh).reduce(0, +) / count,
            exportAverageCentsPerKWh: points.map(\.exportCentsPerKWh).reduce(0, +) / count,
            pointCount: points.count,
            updatedAt: Date()
        )
    }

    static func dateKey(for date: Date, dayOffset: Int = 0) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .current
        let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: date) ?? date

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: targetDate)
    }

    static func monthKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .current

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    static func monthKey(fromDateKey dateKey: String) -> String {
        String(dateKey.prefix(7))
    }

    static func recentMonthKeys(count: Int = 4) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .current

        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: Date()) else {
                return nil
            }

            return monthKey(for: date)
        }
    }

    static func dayNumber(fromDateKey dateKey: String) -> Int? {
        Int(dateKey.suffix(2))
    }

    static func monthTitle(fromMonthKey monthKey: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_BE")
        formatter.dateFormat = "yyyy-MM"

        guard let date = formatter.date(from: monthKey) else {
            return monthKey
        }

        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }

    private func save(_ summaries: [DailyPriceSummary]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(summaries.sorted { $0.dateKey > $1.dateKey })
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // History is useful but non-critical; live prices should keep working if persistence fails.
        }
    }

    private func prune(_ summaries: [DailyPriceSummary]) -> [DailyPriceSummary] {
        guard let cutoff = calendar.date(byAdding: .month, value: -3, to: Date()) else {
            return summaries
        }

        let cutoffKey = Self.dateKey(for: cutoff)
        return summaries.filter { $0.dateKey >= cutoffKey }
    }
}

enum FrankBelgianFormula {
    // Tariefkaart Frank Energie Dynamisch SL - februari 2026, incl. 6% btw unless noted.
    // User invoice states contracttype "Stroom Dynamisch SL - FEB26 - QH".
    // Stroomprijs: (0.1068 x BELPEX + 1.500) x 1.06 EURct/kWh.
    // Teruglevering: 0.1 x BELPEX - 1.150 EURct/kWh, vrijgesteld van btw.
    // The Frank app graph appears to show this market component excluding VAT and fixed supplier markup.
    static func importAppCentsPerKWh(fromFrankMarketPrice marketPrice: Double) -> Double {
        let belpex = belpexEuroPerMWh(fromFrankMarketPrice: marketPrice)
        return 0.1068 * belpex
    }

    static func importCentsPerKWh(fromFrankMarketPrice marketPrice: Double) -> Double {
        let belpex = belpexEuroPerMWh(fromFrankMarketPrice: marketPrice)
        return ((0.1068 * belpex) + 1.500) * 1.06
    }

    static func exportCentsPerKWh(fromFrankMarketPrice marketPrice: Double) -> Double {
        let belpex = belpexEuroPerMWh(fromFrankMarketPrice: marketPrice)
        return (0.1 * belpex) - 1.150
    }

    static func marketCentsPerKWh(fromFrankMarketPrice marketPrice: Double) -> Double {
        marketPrice * 100
    }

    private static func belpexEuroPerMWh(fromFrankMarketPrice marketPrice: Double) -> Double {
        marketPrice * 1_000
    }
}

struct RemotePriceRecord: Decodable {
    let start: Date
    let end: Date
    let marketCentsPerKWh: Double?
    let importAppCentsPerKWh: Double?
    let importCentsPerKWh: Double
    let allInImportCentsPerKWh: Double?
    let exportCentsPerKWh: Double
}

struct FrankGraphQLRequest: Encodable {
    let query: String
    let variables: FrankGraphQLVariables
}

struct FrankGraphQLVariables: Encodable {
    let date: String
    let resolution: String
}

struct FrankGraphQLResponse: Decodable {
    let data: FrankGraphQLData?
    let errors: [FrankGraphQLError]?
}

struct FrankGraphQLError: Decodable {
    let message: String
}

struct FrankGraphQLData: Decodable {
    let marketPrices: FrankMarketPrices
}

struct FrankMarketPrices: Decodable {
    let electricityPrices: [FrankElectricityPrice]
}

struct FrankElectricityPrice: Decodable {
    let from: Date
    let till: Date
    let marketPrice: Double
    let marketPricePlus: Double
    let allInPrice: Double
    let perUnit: String
}

enum PriceServiceError: LocalizedError {
    case graphQL(String)
    case httpStatus(Int)
    case noPrices

    var errorDescription: String? {
        switch self {
        case .graphQL(let message):
            return message
        case .httpStatus(let status):
            return "Frank API gaf HTTP \(status) terug"
        case .noPrices:
            return "Frank API gaf geen kwartierprijzen terug"
        }
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static let iso8601WithFractionalSeconds = custom { decoder in
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)

        if let date = PriceDateFormatter.iso8601WithFractionalSeconds.date(from: string) {
            return date
        }

        if let date = PriceDateFormatter.iso8601.date(from: string) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid ISO 8601 date: \(string)"
        )
    }
}

enum PriceDateFormatter {
    static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
