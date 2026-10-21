import Foundation
import Testing
@testable import MacStatus

struct MetricHistoryTests {
    @Test func keepsOnlyTheRecentWindowPerSeries() {
        var history = MetricHistory()
        let start = Date(timeIntervalSince1970: 1_000)
        history.append(0.1, to: .cpu, at: start)
        history.append(0.2, to: .cpu, at: start.addingTimeInterval(30))
        history.append(0.5, to: .temperature, at: start)
        history.append(0.3, to: .cpu, at: start.addingTimeInterval(MetricHistory.window + 1))

        #expect(history.cpu.map(\.value) == [0.2, 0.3])
        #expect(history.temperature.map(\.value) == [0.5])
    }

    @Test func clearingASeriesLeavesTheOthers() {
        var history = MetricHistory()
        let start = Date(timeIntervalSince1970: 1_000)
        history.append(0.1, to: .cpu, at: start)
        history.append(0.2, to: .diskRead, at: start)
        history.clear(.diskRead)

        #expect(history.diskRead.isEmpty)
        #expect(history.cpu.map(\.value) == [0.1])
    }
}
