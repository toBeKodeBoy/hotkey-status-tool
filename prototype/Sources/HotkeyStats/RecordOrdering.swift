import Foundation

enum RecordOrdering {
    static func sorted(_ records: [HotkeyRecord], key: String, ascending: Bool, today: String) -> [HotkeyRecord] {
        records.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch key {
            case "今日":
                let l = lhs.todayDate == today ? lhs.todayCount : 0
                let r = rhs.todayDate == today ? rhs.todayCount : 0
                comparison = l == r ? .orderedSame : (l < r ? .orderedAscending : .orderedDescending)
            case "最近使用": comparison = lhs.lastSeen.compare(rhs.lastSeen)
            default: comparison = lhs.count == rhs.count ? .orderedSame : (lhs.count < rhs.count ? .orderedAscending : .orderedDescending)
            }
            if comparison == .orderedSame { return lhs.combo < rhs.combo }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
}
