import Foundation

final class OKXWebSocketClient {
    var onTicker: ((Ticker) -> Void)?
    var onCandles: ((String, CandleInterval, [Candle]) -> Void)?
    var onStateChange: ((WebSocketState) -> Void)?

    private let url = URL(string: "wss://ws.okx.com:8443/ws/v5/public")!
    private let contracts: [Contract]
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var shouldReconnect = true
    private var reconnectAttempts = 0

    init(contracts: [Contract], session: URLSession = .shared) {
        self.contracts = contracts
        self.session = session
    }

    func connect() {
        shouldReconnect = true
        reconnectTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        reconnectAttempts = 0
        onStateChange?(.connecting)
        subscribe()
        startReceiveLoop()
        startPingLoop()
        onStateChange?(.connected)
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        receiveTask?.cancel()
        pingTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onStateChange?(.disconnected)
    }

    private func subscribe() {
        let args = contracts.flatMap { contract in
            [
                SubscriptionArg(channel: "tickers", instId: contract.id),
                SubscriptionArg(channel: CandleInterval.m15.channel, instId: contract.id),
                SubscriptionArg(channel: CandleInterval.h4.channel, instId: contract.id)
            ]
        }
        guard let data = try? JSONEncoder().encode(SubscriptionRequest(op: "subscribe", args: args)),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        task?.send(.string(text)) { [weak self] error in
            if error != nil {
                self?.scheduleReconnect()
            }
        }
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    guard let self, let task = self.task else { return }
                    let message = try await task.receive()
                    self.handle(message)
                } catch {
                    self?.scheduleReconnect()
                    return
                }
            }
        }
    }

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, let task = self.task else { return }
                task.send(.string("ping")) { [weak self] error in
                    if error != nil {
                        self?.scheduleReconnect()
                    }
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .data(let payload):
            data = payload
        case .string(let text):
            guard text != "pong", text != "ping" else { return }
            data = Data(text.utf8)
        @unknown default:
            data = nil
        }
        guard let data else { return }

        if let tickerMessage = try? JSONDecoder().decode(WSTickerMessage.self, from: data),
           tickerMessage.arg.channel == "tickers" {
            tickerMessage.data.compactMap { try? $0.toTicker() }.forEach { onTicker?($0) }
            return
        }

        if let candleMessage = try? JSONDecoder().decode(WSCandleMessage.self, from: data),
           let interval = CandleInterval(channel: candleMessage.arg.channel) {
            let candles = candleMessage.data.compactMap { try? Candle(okxRow: $0) }
            onCandles?(candleMessage.arg.instId, interval, candles)
        }
    }

    private func scheduleReconnect() {
        guard shouldReconnect, reconnectTask == nil else { return }
        onStateChange?(.reconnecting)
        receiveTask?.cancel()
        pingTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            self.reconnectAttempts += 1
            let delay = min(30, max(2, self.reconnectAttempts * 2))
            try? await Task.sleep(for: .seconds(delay))
            self.reconnectTask = nil
            guard self.shouldReconnect else { return }
            self.connect()
        }
    }
}

enum WebSocketState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

private struct SubscriptionRequest: Encodable {
    let op: String
    let args: [SubscriptionArg]
}

private struct SubscriptionArg: Codable {
    let channel: String
    let instId: String
}

private struct WSArg: Decodable {
    let channel: String
    let instId: String
}

private struct WSTickerMessage: Decodable {
    let arg: WSArg
    let data: [OKXTickerDTO]
}

private struct WSCandleMessage: Decodable {
    let arg: WSArg
    let data: [[String]]
}

private extension CandleInterval {
    var channel: String {
        switch self {
        case .m15: return "candle15m"
        case .h4: return "candle4H"
        }
    }

    init?(channel: String) {
        switch channel {
        case "candle15m": self = .m15
        case "candle4H": self = .h4
        default: return nil
        }
    }
}
