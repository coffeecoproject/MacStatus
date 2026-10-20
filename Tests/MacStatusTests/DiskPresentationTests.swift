import Foundation
import MacStatusCore
import Testing
@testable import MacStatus

struct DiskPresentationTests {
    private let reading = DiskUsage(
        usedBytes: 330 * 1_073_741_824,
        totalBytes: 500 * 1_073_741_824,
        sampledAt: Date(timeIntervalSince1970: 1_000)
    )

    @Test func displaysUsedAndTotalCapacityWithExplicitUnits() {
        let status = DiskStatus.ready(reading)
        #expect(status.amountText == "330 / 500 GiB")
        #expect(status.accessibilitySummary == "硬盘已用 330 GiB，总量 500 GiB")
        #expect(status.displayState == .live)
        #expect(status.displayState.symbol == nil)
    }

    @Test func staleDiskUsageIsNotDisplayedAsCurrent() {
        let statuses: [DiskStatus] = [
            .collecting(lastReading: reading),
            .unavailable(error: .timedOut, lastReading: reading),
            .unavailable(error: .staleReading, lastReading: reading),
            .paused(lastReading: reading)
        ]
        for status in statuses {
            #expect(status.amountText == "—")
            #expect(!status.accessibilitySummary.contains("330"))
            #expect(status.displayState.symbol != nil)
        }
    }

    @Test(arguments: [DiskReadError.unavailable, .invalidStatistics])
    func failuresUseAShortStateWithoutDiagnosticCopy(error: DiskReadError) {
        let status = DiskStatus.unavailable(error: error, lastReading: nil)
        #expect(status.displayState == .unavailable)
        #expect(status.accessibilitySummary == "硬盘 不可用")
    }

    @Test func collectingAndPausedStatesRemainDistinguishable() {
        let collecting = DiskStatus.collecting(lastReading: nil)
        let paused = DiskStatus.paused(lastReading: reading)
        #expect(collecting.displayState == .collecting)
        #expect(paused.displayState == .paused)
        #expect(collecting.displayState.symbol != paused.displayState.symbol)
        #expect(collecting.accessibilitySummary == "硬盘 采样中")
        #expect(paused.accessibilitySummary == "硬盘 已暂停")
    }
}
