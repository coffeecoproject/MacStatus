import Foundation
import MacStatusCore
import Testing

struct CPUStatusTests {
    private let reading = CPUUsage(
        fraction: 0.55,
        sampledAt: Date(timeIntervalSince1970: 1_000)
    )

    @Test func readyExposesTheCurrentReading() {
        let status = CPUStatus.ready(reading)
        #expect(status.currentReading == reading)
        #expect(status.lastReading == reading)
    }

    @Test func nonReadyStatesNeverExposeHistoryAsCurrentData() {
        let states: [CPUStatus] = [
            .collecting(lastReading: reading),
            .unavailable(error: .incompleteSnapshot, lastReading: reading),
            .paused(lastReading: reading)
        ]
        for status in states {
            #expect(status.currentReading == nil)
            #expect(status.lastReading == reading)
        }
    }

    @Test func missingReadingIsNotZero() {
        let states: [CPUStatus] = [
            .collecting(lastReading: nil),
            .unavailable(error: .incompleteSnapshot, lastReading: nil),
            .paused(lastReading: nil)
        ]
        for status in states {
            #expect(status.currentReading == nil)
            #expect(status.lastReading == nil)
        }
        #expect(CPUStatus.ready(CPUUsage(fraction: 0, sampledAt: Date())).currentReading != nil)
    }

    @Test func failurePreservesTheStructuredSystemError() {
        let status = CPUStatus.unavailable(error: .systemFailure(code: 5), lastReading: reading)
        guard case .unavailable(let error, _) = status else {
            Issue.record("Expected a structured read failure.")
            return
        }
        #expect(error == .systemFailure(code: 5))
    }
}
