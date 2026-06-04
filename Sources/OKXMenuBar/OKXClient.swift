import Foundation
import CryptoKit

final class OKXClient {
    private let baseURL = URL(string: "https://www.okx.com")!
    private let session: URLSession
    private var credentials: OKXCredentials?

    init(session: URLSession = .shared, credentials: OKXCredentials? = OKXCredentials.load()) {
        self.session = session
        self.credentials = credentials
    }

    var hasCredentials: Bool {
        credentials?.isComplete == true
    }

    var currentCredentials: OKXCredentials? {
        credentials
    }

    func updateCredentials(_ credentials: OKXCredentials?) {
        self.credentials = credentials
    }

    func fetchTicker(instId: String) async throws -> Ticker {
        let response: OKXResponse<[OKXTickerDTO]> = try await get(
            path: "/api/v5/market/ticker",
            query: ["instId": instId]
        )
        guard let dto = response.data.first else {
            throw OKXError.emptyResponse
        }
        return try dto.toTicker()
    }

    func fetchCandles(instId: String, interval: CandleInterval, limit: Int = 80) async throws -> [Candle] {
        let response: OKXResponse<[[String]]> = try await get(
            path: "/api/v5/market/candles",
            query: [
                "instId": instId,
                "bar": interval.rawValue,
                "limit": String(limit)
            ]
        )
        return try response.data.map(Candle.init(okxRow:)).reversed()
    }

    func fetchPositions() async throws -> [Position] {
        guard let credentials, credentials.isComplete else {
            throw OKXError.credentialsMissing
        }

        let response: OKXResponse<[OKXPositionDTO]> = try await get(
            path: "/api/v5/account/positions",
            query: ["instType": "SWAP"],
            credentials: credentials
        )
        return response.data
            .compactMap { try? $0.toPosition() }
            .filter { abs($0.size) > 0 }
            .sorted { abs($0.unrealizedPnl ?? 0) > abs($1.unrealizedPnl ?? 0) }
    }

    private func get<T: Decodable>(
        path: String,
        query: [String: String],
        credentials: OKXCredentials? = nil
    ) async throws -> OKXResponse<T> {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw OKXError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("OKXMenuBar/1.0", forHTTPHeaderField: "User-Agent")
        if let credentials {
            let requestPath = path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
            sign(&request, requestPath: requestPath, credentials: credentials)
        }

        let (data, urlResponse) = try await session.data(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw OKXError.httpError((urlResponse as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let decoded = try JSONDecoder().decode(OKXResponse<T>.self, from: data)
        guard decoded.code == "0" else {
            throw OKXError.apiError(decoded.message)
        }
        return decoded
    }

    private func sign(_ request: inout URLRequest, requestPath: String, credentials: OKXCredentials) {
        let timestamp = ISO8601DateFormatter.okx.string(from: Date())
        let method = request.httpMethod ?? "GET"
        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let prehash = timestamp + method + requestPath + body
        let key = SymmetricKey(data: Data(credentials.secretKey.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(prehash.utf8), using: key)
        let encodedSignature = Data(signature).base64EncodedString()

        request.setValue(credentials.apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
        request.setValue(encodedSignature, forHTTPHeaderField: "OK-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
        request.setValue(credentials.passphrase, forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
    }
}

struct OKXResponse<T: Decodable>: Decodable {
    let code: String
    let message: String
    let data: T

    enum CodingKeys: String, CodingKey {
        case code
        case message = "msg"
        case data
    }
}

struct OKXTickerDTO: Decodable {
    let instId: String
    let last: String
    let open24h: String
    let high24h: String
    let low24h: String
    let volCcy24h: String
    let ts: String

    func toTicker() throws -> Ticker {
        guard let last = Double(last),
              let open24h = Double(open24h),
              let high24h = Double(high24h),
              let low24h = Double(low24h),
              let volume24h = Double(volCcy24h),
              let milliseconds = Double(ts) else {
            throw OKXError.parseError
        }

        return Ticker(
            id: instId,
            last: last,
            open24h: open24h,
            high24h: high24h,
            low24h: low24h,
            volume24h: volume24h,
            timestamp: Date(timeIntervalSince1970: milliseconds / 1000)
        )
    }
}

struct OKXPositionDTO: Decodable {
    let instId: String
    let mgnMode: String
    let posSide: String
    let pos: String
    let avgPx: String
    let markPx: String
    let upl: String
    let uplRatio: String
    let lever: String
    let liqPx: String

    func toPosition() throws -> Position {
        guard let contracts = Double(pos) else { throw OKXError.parseError }
        let symbol = instId
            .replacingOccurrences(of: "-USDT-SWAP", with: "")
            .replacingOccurrences(of: "-USD-SWAP", with: "")
        let size = contracts * Contract.contractValue(for: instId)
        return Position(
            id: "\(instId)-\(posSide)",
            instId: instId,
            symbol: symbol,
            side: posSide,
            size: size,
            averagePrice: Double(avgPx),
            markPrice: Double(markPx),
            unrealizedPnl: Double(upl),
            unrealizedPnlRatio: Double(uplRatio),
            leverage: Double(lever),
            liquidationPrice: Double(liqPx),
            marginMode: mgnMode
        )
    }
}

enum OKXError: LocalizedError {
    case invalidURL
    case emptyResponse
    case httpError(Int)
    case apiError(String)
    case parseError
    case credentialsMissing

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL 无效"
        case .emptyResponse: return "OKX 返回为空"
        case .httpError(let code): return "HTTP 错误：\(code)"
        case .apiError(let message): return "OKX API 错误：\(message)"
        case .parseError: return "数据解析失败"
        case .credentialsMissing: return "未配置 OKX API 凭证"
        }
    }
}

private extension ISO8601DateFormatter {
    static let okx: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
