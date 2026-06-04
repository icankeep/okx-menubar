import Foundation

struct OKXCredentials: Codable, Equatable {
    let apiKey: String
    let secretKey: String
    let passphrase: String

    var isComplete: Bool {
        !apiKey.isEmpty && !secretKey.isEmpty && !passphrase.isEmpty
    }

    static func load() -> OKXCredentials? {
        if let credentials = loadFromEnvironment(), credentials.isComplete {
            return credentials
        }
        if let credentials = loadFromConfigFile(), credentials.isComplete {
            return credentials
        }
        return nil
    }

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".okx-menubar.json")
    }

    var maskedApiKey: String {
        guard apiKey.count > 8 else { return String(repeating: "*", count: apiKey.count) }
        return "\(apiKey.prefix(4))****\(apiKey.suffix(4))"
    }

    func save() throws {
        let data = try JSONEncoder.pretty.encode(self)
        try data.write(to: Self.configURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: Self.configURL.path
        )
    }

    private static func loadFromEnvironment() -> OKXCredentials? {
        let environment = ProcessInfo.processInfo.environment
        guard let apiKey = environment["OKX_API_KEY"],
              let secretKey = environment["OKX_SECRET_KEY"],
              let passphrase = environment["OKX_PASSPHRASE"] else {
            return nil
        }
        return OKXCredentials(apiKey: apiKey, secretKey: secretKey, passphrase: passphrase)
    }

    private static func loadFromConfigFile() -> OKXCredentials? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(OKXCredentials.self, from: data)
    }
}

private extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
