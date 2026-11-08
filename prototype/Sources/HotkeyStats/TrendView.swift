import SwiftUI
import Charts

struct TrendView: View {
    let points: [TrendPoint]
    let notice: String
    let conflicts: String
    let details: String
    private var axisDays: [String] {
        let stride = max(1, (points.count + 5) / 6)
        return points.enumerated().filter { $0.offset % stride == 0 || $0.offset == points.count - 1 }.map { $0.element.day }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(notice).font(.caption).foregroundStyle(.secondary)
            Chart(points) { point in
                BarMark(x: .value("日期", point.day), y: .value("次数", point.count))
                    .foregroundStyle(.mint)
                    .accessibilityLabel(point.day)
                    .accessibilityValue("\(point.count) 次")
            }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                        .chartXAxis {
                AxisMarks(values: axisDays) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(anchor: .top) {
                        if let day = value.as(String.self) { Text(String(day.suffix(5))) }
                    }
                }
            }
            .overlay {
                if points.allSatisfy({ $0.count == 0 }) { Text("此范围暂无日明细").foregroundStyle(.secondary) }
            }
            Text(conflicts).font(.caption).foregroundStyle(.orange).lineLimit(2)
            ScrollView { Text(details).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(height: 44)
        }.padding(12)
    }
}
