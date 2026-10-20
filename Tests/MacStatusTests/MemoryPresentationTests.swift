import Foundation
import MacStatusCore
import Testing
@testable import MacStatus

struct MemoryPresentationTests {
    private func reading(
        usedBytes: UInt64 = 6_979_321_856,
        pressure: Result<MemoryPressure, MemoryPressureReadError> = .success(.normal)
    ) -> MemoryUsage {
        MemoryUsage(
            usedBytes: usedBytes, totalBytes: 8 * 1_073_741_824,
            pressure: pressure, sampledAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    @Test func displaysBinaryCapacityWithExplicitUnits() {
        let status = MemoryStatus.ready(reading())
        #expect(status.amountText == "6.5 / 8 GiB")
        #expect(status.accessibilitySummary == "内存已用 6.5 GiB，总量 8 GiB")
        #expect(status.displayState == .live)
        #expect(status.displayState.symbol == nil)
        #expect(status.displayState.title.isEmpty)
    }

    @Test(arguments: [
        (MemoryPressure.normal, "内存压力：正常"),
        (.warning, "内存压力：警告"),
        (.critical, "内存压力：严重")
    ])
    func pressureComesFromTheSystemEvenWhenUsageIsHigh(pressure: MemoryPressure, expected: String) {
        let status = MemoryStatus.ready(reading(
            usedBytes: 8 * 1_073_741_824, pressure: .success(pressure)
        ))
        #expect(status.pressureText == expected)
        #expect("内存压力：\(status.pressureValueText)" == expected)
    }

    @Test(arguments: [
        MemoryPressureReadError.systemFailure(code: 2),
        .incompleteValue,
        .unsupportedLevel(99)
    ])
    func missingPressureDoesNotHideValidUsage(error: MemoryPressureReadError) {
        let status = MemoryStatus.ready(reading(pressure: .failure(error)))
        #expect(status.amountText == "6.5 / 8 GiB")
        #expect(status.pressureText == "内存压力：不可用")
        #expect(status.displayState == .live)
        #expect(status.pressureValueText == "不可用")
        #expect(!status.pressureText.contains("正常"))
    }

    @Test func staleUsageAndPressureAreNotDisplayedAsCurrent() {
        let old = reading(pressure: .success(.critical))
        let statuses: [MemoryStatus] = [
            .collecting(lastReading: old),
            .unavailable(error: .incompleteSnapshot, lastReading: old),
            .unavailable(error: .timedOut, lastReading: old),
            .unavailable(error: .staleReading, lastReading: old),
            .paused(lastReading: old)
        ]
        for status in statuses {
            #expect(status.amountText == "—")
            #expect(status.pressureText == "内存压力：—")
            #expect(!status.accessibilitySummary.contains("6.5"))
            #expect(status.displayState.symbol != nil)
        }
    }

    @Test(arguments: [
        MemoryReadError.systemFailure(code: 5), .incompleteSnapshot, .invalidStatistics
    ])
    func failuresUseAShortStateWithoutDiagnosticCopy(error: MemoryReadError) {
        let status = MemoryStatus.unavailable(error: error, lastReading: nil)
        #expect(status.displayState == .unavailable)
        #expect(status.accessibilitySummary == "内存 不可用")
    }

    @Test func collectingAndPausedStatesRemainDistinguishable() {
        let collecting = MemoryStatus.collecting(lastReading: nil)
        let paused = MemoryStatus.paused(lastReading: reading())
        #expect(collecting.displayState == .collecting)
        #expect(paused.displayState == .paused)
        #expect(collecting.displayState.symbol != paused.displayState.symbol)
        #expect(collecting.accessibilitySummary == "内存 采样中")
        #expect(paused.accessibilitySummary == "内存 已暂停")
    }
}
