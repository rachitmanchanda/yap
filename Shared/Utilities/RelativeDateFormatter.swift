import Foundation

enum RelativeDateFormatter {
    static func string(from date: Date, relativeTo now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
