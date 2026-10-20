import Foundation
import MacStatusCore
import Testing

struct DiskStatusTests {
    private let reading = DiskUsage(
        usedBytes: 330 * 1_073_741_824,
        totalBytes: 500 * 1_073_741_824,
        sampledAt: Date(timeIntervalSince1970: 1_000)
    )

    @Test func readyExposesTheCurrentReading() {
        let status = DiskStatus.ready(reading)
        #expect(status.currentReading == reading)
        #expect(status.lastReading == reading)
        #expect(reading.fraction == 0.66)
    }

    @Test func nonReadyStatesDoNotPresentHistoryAsCurrent() {
        let states: [DiskStatus] = [
            .collecting(lastReading: reading),
            .unavailable(error: .invalidStatistics, lastReading: reading),
            .paused(lastReading: reading)
        ]
        for state in states {
            #expect(state.currentReading == nil)
            #expect(state.lastReading == reading)
        }
    }

    @Test func systemSnapshotStartsWithoutInventedDiskValues() {
        #expect(SystemSnapshot().disk == .collecting(lastReading: nil))
    }
}
