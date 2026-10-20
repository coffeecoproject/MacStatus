import Foundation
import MacStatusCore
import Testing

struct MemoryStatusTests {
    private let reading = MemoryUsage(
        usedBytes: 6 * 1_073_741_824, totalBytes: 8 * 1_073_741_824,
        pressure: .success(.warning), sampledAt: Date(timeIntervalSince1970: 1_000)
    )

    @Test func readyExposesUsageAndPressureAsOneReading() {
        let status = MemoryStatus.ready(reading)
        #expect(status.currentReading == reading)
        #expect(status.lastReading == reading)
        #expect(reading.fraction == 0.75)
    }

    @Test func nonReadyStatesDoNotPresentHistoricalPressureAsCurrent() {
        let states: [MemoryStatus] = [
            .collecting(lastReading: reading),
            .unavailable(error: .invalidStatistics, lastReading: reading),
            .paused(lastReading: reading)
        ]
        for state in states {
            #expect(state.currentReading == nil)
            #expect(state.lastReading == reading)
        }
    }

    @Test func systemSnapshotStartsWithoutInventedValues() {
        let snapshot = SystemSnapshot()
        #expect(snapshot.cpu == .collecting(lastReading: nil))
        #expect(snapshot.memory == .collecting(lastReading: nil))
    }

    @Test func systemSnapshotKeepsMetricFailuresIndependent() {
        let snapshot = SystemSnapshot(
            cpu: .unavailable(error: .incompleteSnapshot, lastReading: nil),
            memory: .ready(reading)
        )
        #expect(snapshot.cpu.currentReading == nil)
        #expect(snapshot.memory.currentReading == reading)
    }
}
