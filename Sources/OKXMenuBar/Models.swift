import Foundation

struct Contract: Identifiable, Hashable {
    let id: String
    let symbol: String
    let displayName: String
    let contractValue: Double

    static let defaults: [Contract] = [
        Contract(id: "BTC-USDT-SWAP", symbol: "BTC", displayName: "BTC 永续", contractValue: 0.01),
        Contract(id: "ETH-USDT-SWAP", symbol: "ETH", displayName: "ETH 永续", contractValue: 0.1),
        Contract(id: "SOL-USDT-SWAP", symbol: "SOL", displayName: "SOL 永续", contractValue: 1)
    ]

    static func contractValue(for instId: String) -> Double {
        defaults.first(where: { $0.id == instId })?.contractValue ?? 1
    }
}

struct Ticker: Identifiable, Equatable {
    let id: String
    let last: Double
    let open24h: Double
    let high24h: Double
    let low24h: Double
    let volume24h: Double
    let timestamp: Date

    var change24h: Double {
        guard open24h != 0 else { return 0 }
        return (last - open24h) / open24h
    }
}

struct Candle: Identifiable, Equatable {
    let timestamp: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double

    var isUp: Bool { close >= open }

    var id: TimeInterval { timestamp.timeIntervalSince1970 }

    init(timestamp: Date, open: Double, high: Double, low: Double, close: Double, volume: Double) {
        self.timestamp = timestamp
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }

    init(okxRow row: [String]) throws {
        guard row.count >= 6,
              let milliseconds = Double(row[0]),
              let open = Double(row[1]),
              let high = Double(row[2]),
              let low = Double(row[3]),
              let close = Double(row[4]),
              let volume = Double(row[5]) else {
            throw OKXError.parseError
        }
        self.init(
            timestamp: Date(timeIntervalSince1970: milliseconds / 1000),
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume
        )
    }
}

enum CandleInterval: String, CaseIterable, Identifiable {
    case m15 = "15m"
    case h4 = "4H"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .m15: return "15 分钟"
        case .h4: return "4 小时"
        }
    }
}

struct MarketSnapshot: Identifiable, Equatable {
    var id: String { contract.id }

    let contract: Contract
    var ticker: Ticker?
    var candles15m: [Candle] = []
    var candles4h: [Candle] = []
}

struct Position: Identifiable, Equatable {
    let id: String
    let instId: String
    let symbol: String
    let side: String
    let size: Double
    let averagePrice: Double?
    let markPrice: Double?
    let unrealizedPnl: Double?
    let unrealizedPnlRatio: Double?
    let leverage: Double?
    let liquidationPrice: Double?
    let marginMode: String

    var isLong: Bool {
        if side.lowercased() == "long" { return true }
        if side.lowercased() == "short" { return false }
        return size >= 0
    }

    var displaySide: String {
        if side.lowercased() == "long" { return "多" }
        if side.lowercased() == "short" { return "空" }
        return size >= 0 ? "净多" : "净空"
    }
}

enum PositionState: Equatable {
    case notConfigured
    case loading
    case loaded(Date)
    case failed(String)
}

enum MarketStreamState: Equatable {
    case idle
    case loading
    case streaming
    case reconnecting
    case failed(String)
}

enum LoadState: Equatable {
    case idle
    case loading
    case loaded(Date)
    case failed(String)
}
