import Combine
import Foundation

@MainActor
final class MarketStore: ObservableObject {
    @Published private(set) var snapshots: [MarketSnapshot]
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var streamState: MarketStreamState = .idle
    @Published private(set) var positions: [Position] = []
    @Published private(set) var positionState: PositionState = .notConfigured
    @Published var selectedContractId: String
    @Published var selectedInterval: CandleInterval = .m15
    @Published private(set) var statusItemDisplayMode: StatusItemDisplayMode

    private let client: OKXClient
    private let webSocketClient: OKXWebSocketClient
    private let defaults: UserDefaults
    private var refreshTask: Task<Void, Never>?
    private var positionTask: Task<Void, Never>?
    private var uiFlushTask: Task<Void, Never>?
    private var pendingTickers: [String: Ticker] = [:]
    private var pendingCandles: [String: [Candle]] = [:]

    init(
        client: OKXClient = OKXClient(),
        contracts: [Contract] = Contract.defaults,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults
        self.webSocketClient = OKXWebSocketClient(contracts: contracts)
        self.snapshots = contracts.map { MarketSnapshot(contract: $0) }
        self.selectedContractId = contracts.first?.id ?? "BTC-USDT-SWAP"
        self.statusItemDisplayMode = Self.loadStatusItemDisplayMode(defaults: defaults)
        bindWebSocket()
    }

    var selectedSnapshot: MarketSnapshot? {
        snapshots.first { $0.contract.id == selectedContractId }
    }

    var currentCredentials: OKXCredentials? {
        client.currentCredentials
    }

    var statusTitle: String {
        let text = snapshots.compactMap(statusSummary).joined(separator: "  ")
        return text.isEmpty ? "OKX --" : text
    }

    func start() {
        if client.hasCredentials {
            positionState = .loading
        } else {
            positionState = .notConfigured
            positions = []
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.loadInitialMarketData(resetStreamState: true)
            self.webSocketClient.connect()
        }
        startPositionPolling()
        startUIFlushLoop()
    }

    func stop() {
        refreshTask?.cancel()
        positionTask?.cancel()
        uiFlushTask?.cancel()
        webSocketClient.disconnect()
    }

    func refreshAll() async {
        await refreshMarketData()
        await refreshPositions()
    }

    func refreshMarketData() async {
        await loadInitialMarketData(resetStreamState: false)
    }

    func refreshSelectedContractCandles() async {
        let instId = selectedContractId
        state = .loading
        do {
            async let candles15m = client.fetchCandles(instId: instId, interval: .m15)
            async let candles4h = client.fetchCandles(instId: instId, interval: .h4)
            let refreshed15m = try await candles15m
            let refreshed4h = try await candles4h

            if let index = snapshots.firstIndex(where: { $0.contract.id == instId }) {
                snapshots[index].candles15m = refreshed15m
                snapshots[index].candles4h = refreshed4h
            }
            state = .loaded(Date())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func loadInitialMarketData(resetStreamState: Bool) async {
        state = .loading
        if resetStreamState {
            streamState = .loading
        }
        do {
            var updated = snapshots
            try await withThrowingTaskGroup(of: MarketSnapshot.self) { group in
                for snapshot in snapshots {
                    group.addTask { [client] in
                        async let ticker = client.fetchTicker(instId: snapshot.contract.id)
                        async let candles15m = client.fetchCandles(instId: snapshot.contract.id, interval: .m15)
                        async let candles4h = client.fetchCandles(instId: snapshot.contract.id, interval: .h4)
                        return try await MarketSnapshot(
                            contract: snapshot.contract,
                            ticker: ticker,
                            candles15m: candles15m,
                            candles4h: candles4h
                        )
                    }
                }
                for try await snapshot in group {
                    if let index = updated.firstIndex(where: { $0.contract.id == snapshot.contract.id }) {
                        updated[index] = snapshot
                    }
                }
            }
            snapshots = updated
            state = .loaded(Date())
        } catch {
            state = .failed(error.localizedDescription)
            if resetStreamState {
                streamState = .failed(error.localizedDescription)
            }
        }
    }

    func saveCredentials(apiKey: String, secretKey: String, passphrase: String) throws {
        let credentials = OKXCredentials(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            secretKey: secretKey.trimmingCharacters(in: .whitespacesAndNewlines),
            passphrase: passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard credentials.isComplete else {
            throw OKXError.credentialsMissing
        }
        try credentials.save()
        client.updateCredentials(credentials)
        positionState = .loading
    }

    func reloadCredentialsFromDisk() {
        client.updateCredentials(OKXCredentials.load())
        positionState = client.hasCredentials ? .loading : .notConfigured
    }

    func setStatusItemDisplayMode(_ mode: StatusItemDisplayMode) {
        statusItemDisplayMode = mode
        defaults.set(mode.rawValue, forKey: Self.statusItemDisplayModeKey)
    }

    private static let statusItemDisplayModeKey = "statusItemDisplayMode"

    private static func loadStatusItemDisplayMode(defaults: UserDefaults) -> StatusItemDisplayMode {
        guard let rawValue = defaults.string(forKey: statusItemDisplayModeKey),
              let mode = StatusItemDisplayMode(rawValue: rawValue) else {
            return .iconOnly
        }
        return mode
    }

    private func statusSummary(for snapshot: MarketSnapshot) -> String? {
        guard let ticker = snapshot.ticker else { return nil }
        return "\(symbolPrefix(for: snapshot.contract.symbol)) \(NumberFormat.compactPrice(ticker.last)) \(NumberFormat.percent(ticker.change24h))"
    }

    private func symbolPrefix(for symbol: String) -> String {
        switch symbol {
        case "BTC": return "₿"
        case "ETH": return "Ξ"
        default: return symbol
        }
    }

    private func refreshPositions() async {
        guard client.hasCredentials else {
            positions = []
            positionState = .notConfigured
            return
        }
        do {
            positions = try await client.fetchPositions()
            positionState = .loaded(Date())
        } catch {
            positions = []
            positionState = .failed(error.localizedDescription)
        }
    }

    private func startPositionPolling() {
        positionTask?.cancel()
        positionTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshPositions()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self.refreshPositions()
            }
        }
    }

    private func bindWebSocket() {
        webSocketClient.onTicker = { [weak self] ticker in
            Task { @MainActor [weak self] in
                self?.pendingTickers[ticker.id] = ticker
            }
        }
        webSocketClient.onCandles = { [weak self] instId, interval, candles in
            Task { @MainActor [weak self] in
                self?.pendingCandles["\(instId)-\(interval.rawValue)"] = candles
            }
        }
        webSocketClient.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .disconnected, .connecting:
                    self?.streamState = .loading
                case .connected:
                    self?.streamState = .streaming
                case .reconnecting:
                    self?.streamState = .reconnecting
                }
            }
        }
    }

    private func startUIFlushLoop() {
        uiFlushTask?.cancel()
        uiFlushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    self?.flushPendingMarketUpdates()
                }
            }
        }
    }

    private func flushPendingMarketUpdates() {
        guard !pendingTickers.isEmpty || !pendingCandles.isEmpty else { return }

        let tickers = pendingTickers.values
        let candleUpdates = pendingCandles
        pendingTickers.removeAll()
        pendingCandles.removeAll()

        for ticker in tickers {
            applyTicker(ticker)
        }
        for (key, candles) in candleUpdates {
            let parts = key.split(separator: "-", maxSplits: 3).map(String.init)
            guard parts.count >= 4 else { continue }
            let instId = "\(parts[0])-\(parts[1])-\(parts[2])"
            guard let interval = CandleInterval(rawValue: parts[3]) else { continue }
            applyCandles(candles, instId: instId, interval: interval)
        }
    }

    private func applyTicker(_ ticker: Ticker) {
        guard let index = snapshots.firstIndex(where: { $0.contract.id == ticker.id }) else { return }
        snapshots[index].ticker = ticker
        state = .loaded(Date())
    }

    private func applyCandles(_ candles: [Candle], instId: String, interval: CandleInterval) {
        guard let index = snapshots.firstIndex(where: { $0.contract.id == instId }) else { return }
        switch interval {
        case .m15:
            snapshots[index].candles15m = mergedCandles(existing: snapshots[index].candles15m, updates: candles)
        case .h4:
            snapshots[index].candles4h = mergedCandles(existing: snapshots[index].candles4h, updates: candles)
        }
    }

    private func mergedCandles(existing: [Candle], updates: [Candle]) -> [Candle] {
        var byTimestamp = Dictionary(uniqueKeysWithValues: existing.map { ($0.timestamp, $0) })
        for candle in updates {
            byTimestamp[candle.timestamp] = candle
        }
        return Array(byTimestamp.values.sorted { $0.timestamp < $1.timestamp }.suffix(120))
    }
}
