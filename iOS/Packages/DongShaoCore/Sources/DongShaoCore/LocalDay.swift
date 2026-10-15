import Foundation

public enum LocalDay {
    public static func dateString(_ date: Date) -> String {
        formatter("yyyy-MM-dd").string(from: date)
    }
    public static func timestamp(_ date: Date) -> String {
        formatter("yyyy-MM-dd'T'HH:mm:ssXXXXX").string(from: date)
    }
    public static func start(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.startOfDay(for: date)
    }
    public static func period(_ date: Date) -> JSONValue {
        let begin = start(date)
        return .object(["start": .string(timestamp(begin)), "end": .string(timestamp(begin.addingTimeInterval(86_400)))])
    }
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = format
        return formatter
    }
}
