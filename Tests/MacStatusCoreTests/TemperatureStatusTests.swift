import Foundation
import MacStatusCore
import Testing

struct TemperatureStatusTests {
    private let reading = CPUTemperature(celsius: 67.25, sampledAt: Date(timeIntervalSince1970: 1_000))

    @Test func readyExposesTheReading() {
        let status = TemperatureStatus.ready(reading)
        #expect(status.currentReading == reading)
        #expect(status.lastReading == reading)
    }

    @Test func historyIsNeverPresentedAsCurrentTemperature() {
        let states: [TemperatureStatus] = [
            .collecting(lastReading: reading),
            .unavailable(error: .serviceUnavailable, lastReading: reading),
            .paused(lastReading: reading)
        ]
        for state in states {
            #expect(state.lastReading == reading)
            #expect(state.currentReading == nil)
        }
    }

    @Test func aNewSnapshotHasNoInventedTemperature() {
        #expect(SystemSnapshot().temperature == .collecting(lastReading: nil))
    }

    @Test func temperatureParticipatesInSnapshotEquality() {
        let first = SystemSnapshot(temperature: .ready(reading))
        let second = SystemSnapshot(temperature: .unavailable(error: .invalidValue, lastReading: reading))
        #expect(first != second)
        #expect(first.cpu == second.cpu)
        #expect(first.memory == second.memory)
    }
}
