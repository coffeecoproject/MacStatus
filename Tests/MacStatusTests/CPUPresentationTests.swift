import Foundation
import MacStatusCore
import Testing
@testable import MacStatus

struct CPUPresentationTests {
    @Test(arguments: [
        (0.0, "0%"),
        (0.554, "55%"),
        (1.0, "100%")
    ])
    func percentageIsWholeMachineAndRounded(fraction: Double, expected: String) {
        let reading = CPUUsage(fraction: fraction, sampledAt: Date())
        #expect(reading.percentageText == expected)
        #expect(CPUStatus.ready(reading).percentageText == expected)
    }

    @Test func staleReadingsAreReplacedWithADash() {
        let reading = CPUUsage(fraction: 0.55, sampledAt: Date())
        let statuses: [CPUStatus] = [
            .collecting(lastReading: reading),
            .unavailable(error: .incompleteSnapshot, lastReading: reading),
            .unavailable(error: .timedOut, lastReading: reading),
            .unavailable(error: .staleReading, lastReading: reading),
            .paused(lastReading: reading)
        ]
        for status in statuses {
            #expect(status.percentageText == "—")
            #expect(!status.accessibilitySummary.contains("55%"))
            #expect(status.displayState.symbol != nil)
            #expect(!status.displayState.title.isEmpty)
        }
    }

    @Test(arguments: [CPUReadError.systemFailure(code: 5), .incompleteSnapshot])
    func failuresHaveACompactAccessibleState(error: CPUReadError) {
        let status = CPUStatus.unavailable(error: error, lastReading: nil)
        #expect(status.displayState == .unavailable)
        #expect(status.accessibilitySummary == "CPU 不可用")
    }

    @Test func normalReadingsHaveNoExtraStatusHint() {
        let status = CPUStatus.ready(CPUUsage(fraction: 0.5, sampledAt: Date()))
        #expect(status.displayState == .live)
        #expect(status.displayState.symbol == nil)
        #expect(status.displayState.title.isEmpty)
        #expect(status.accessibilitySummary == "CPU 使用率 50%")
    }

    @Test func collectingAndPausedStatesRemainDistinguishable() {
        let collecting = CPUStatus.collecting(lastReading: nil)
        let paused = CPUStatus.paused(lastReading: nil)
        #expect(collecting.displayState == .collecting)
        #expect(paused.displayState == .paused)
        #expect(collecting.displayState.symbol != paused.displayState.symbol)
        #expect(collecting.accessibilitySummary == "CPU 采样中")
        #expect(paused.accessibilitySummary == "CPU 已暂停")
    }
}
