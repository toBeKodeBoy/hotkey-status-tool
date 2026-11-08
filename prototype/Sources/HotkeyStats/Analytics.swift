import Foundation

struct ApplicationIdentity: Codable, Equatable {
    let bundleID: String?
    var name: String
    static let unknown = ApplicationIdentity(bundleID: nil, name: "未知应用")
}

struct AppHotkeyRecord: Codable {
    var application: ApplicationIdentity
    var combo: String
    var keycode: Int
    var flagsRaw: UInt64
    var count: Int
    var firstSeen: Date
    var lastSeen: Date
    var daily: [String: Int]
    // Old files have no time zone. Preserve evidence without guessing daily buckets.
    var legacyToday: [HotkeyRecord]
}

struct TrendPoint: Identifiable, Equatable {
    var id: String { day }
    let day: String
    let count: Int
}

struct HotkeyConflict {
    let combo: String
    let applications: [(ApplicationIdentity, Int)]
}

struct StatisticsCalendar {
    let timeZone: TimeZone
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
    func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    func days(ending date: Date, count: Int) -> [String] {
        guard count > 0 else { return [] }
        let start = calendar.startOfDay(for: date)
        return (0..<count).reversed().map {
            day(calendar.date(byAdding: .day, value: -$0, to: start)!)
        }
    }
    func isValid(_ day: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: day) else { return false }
        return self.day(date) == day
    }
}

enum RankingPresentation {
    static func title(leader: String?, running: Bool) -> String {
        guard running, let leader else { return "" }
        return leader.count > 12 ? String(leader.prefix(11)) + "…" : leader
    }
}
