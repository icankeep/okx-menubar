import Foundation

enum NumberFormat {
    static func price(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = value >= 100 ? 1 : 3
        formatter.maximumFractionDigits = value >= 100 ? 1 : 4
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func compactPrice(_ value: Double) -> String {
        if value >= 100_000 {
            return String(format: "%.1fk", value / 1_000)
        }
        if value >= 10_000 {
            return String(format: "%.2fk", value / 1_000)
        }
        if value >= 1_000 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    static func percent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f%%", value * 100)
    }

    static func volume(_ value: Double) -> String {
        switch value {
        case 1_000_000...:
            return String(format: "%.2fM", value / 1_000_000)
        case 1_000...:
            return String(format: "%.2fK", value / 1_000)
        default:
            return String(format: "%.2f", value)
        }
    }
}
