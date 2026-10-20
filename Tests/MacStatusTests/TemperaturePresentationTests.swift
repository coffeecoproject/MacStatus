import Foundation
import MacStatusCore
import Testing
@testable import MacStatus

struct TemperaturePresentationTests {
    @Test(arguments: [(67.25, "67°C"), (67.8, "68°C"), (100.1, "100°C")])
    func usesWholeDegreesWithExplicitUnits(celsius: Double, expected: String) {
        let status = TemperatureStatus.ready(CPUTemperature(celsius: celsius, sampledAt: Date()))
        #expect(status.valueText == expected)
        #expect(status.accessibilitySummary == "CPU 温度 \(expected)")
        #expect(status.displayState == .live)
        #expect(status.displayState.symbol == nil)
    }

    @Test func staleReadingsDisappearAndStatesRemainDistinguishable() {
        let old = CPUTemperature(celsius: 67, sampledAt: Date())
        let states: [(TemperatureStatus, MetricDisplayState, String)] = [
            (.collecting(lastReading: old), .collecting, "CPU 温度 采样中"),
            (.paused(lastReading: old), .paused, "CPU 温度 已暂停"),
            (.unavailable(error: .timedOut, lastReading: old), .unavailable, "CPU 温度 不可用"),
            (.unavailable(error: .staleReading, lastReading: old), .unavailable, "CPU 温度 不可用"),
            (.unavailable(error: .invalidValue, lastReading: old), .unavailable, "CPU 温度 不可用")
        ]
        for (status, state, summary) in states {
            #expect(status.valueText == "—")
            #expect(status.displayState == state)
            #expect(status.displayState.symbol != nil)
            #expect(status.accessibilitySummary == summary)
            #expect(!status.accessibilitySummary.contains("67"))
        }
    }
}
