import Combine
import Foundation
import MacStatusCore
import Testing
@testable import MacStatus

@MainActor
struct SystemMonitorTemperatureTests {
    private let first = CPUTemperature(celsius: 67, sampledAt: Date(timeIntervalSince1970: 1_000))
    private let second = CPUTemperature(celsius: 60, sampledAt: Date(timeIntervalSince1970: 2_000))

    @Test func temperatureDoesNotNeedACPUBaseline() async throws {
        let temperature = ProbeTemperatureCollector([.reading(first)])
        let monitor = SystemMonitor(
            cpuCollector: ProbeCPUCollector([.baseline]),
            memoryCollector: ProbeMemoryCollector(),
            temperatureCollector: temperature
        )
        defer { monitor.pause() }
        monitor.start()
        try await waitUntil { monitor.snapshot.temperature == .ready(first) }
        #expect(monitor.snapshot.cpu.currentReading == nil)
        try await waitUntil { monitor.snapshot.memory.currentReading != nil }
        #expect(await temperature.activity().samples == 1)
    }

    @Test func failureRetriesWithoutFreezingOtherMetricsOrShowingHistory() async throws {
        let temperature = ProbeTemperatureCollector([
            .reading(first), .failure(.serviceUnavailable), .reading(second)
        ])
        let monitor = SystemMonitor(
            cpuCollector: ProbeCPUCollector([]),
            memoryCollector: ProbeMemoryCollector(),
            temperatureCollector: temperature
        )
        defer { monitor.pause() }
        monitor.setPanelVisible(true)
        monitor.start()
        try await waitUntil { monitor.snapshot.temperature == .ready(first) }
        let original = monitor.snapshot
        try await waitUntil {
            if case .unavailable = monitor.snapshot.temperature { return true }
            return false
        }
        #expect(monitor.snapshot.temperature == .unavailable(
            error: .serviceUnavailable, lastReading: first
        ))
        #expect(monitor.snapshot.temperature.currentReading == nil)
        try await waitUntil {
            monitor.snapshot.cpu.currentReading != nil
                && monitor.snapshot.memory.currentReading != nil
                && monitor.snapshot.cpu.currentReading?.sampledAt != original.cpu.currentReading?.sampledAt
                && monitor.snapshot.memory.currentReading?.sampledAt != original.memory.currentReading?.sampledAt
        }
        try await waitUntil { monitor.snapshot.temperature == .ready(second) }
    }

    @Test(arguments: [
        TemperatureReadError.unsupportedModel, .modelReadFailed(code: 5),
        .serviceUnavailable, .systemFailure(code: 5),
        .sensorFailure(key: "Tp01", code: 132), .invalidResponse,
        .unsupportedFormat(key: "Tp01"), .invalidValue, .timedOut, .staleReading
    ])
    func failuresRemainTypedAndDoNotInventZero(error: TemperatureReadError) async throws {
        let monitor = SystemMonitor(
            cpuCollector: ProbeCPUCollector([]),
            memoryCollector: ProbeMemoryCollector(),
            temperatureCollector: ProbeTemperatureCollector([.failure(error)])
        )
        defer { monitor.pause() }
        monitor.start()
        try await waitUntil {
            if case .unavailable = monitor.snapshot.temperature { return true }
            return false
        }
        #expect(monitor.snapshot.temperature == .unavailable(error: error, lastReading: nil))
        #expect(monitor.snapshot.temperature.valueText == "—")
        try await waitUntil {
            monitor.snapshot.cpu.currentReading != nil && monitor.snapshot.memory.currentReading != nil
        }
    }

    @Test func sleepPreservesHistoryAndDiscardsAnInFlightTemperature() async throws {
        let latest = CPUTemperature(celsius: 55, sampledAt: Date(timeIntervalSince1970: 3_000))
        let temperature = ProbeTemperatureCollector([.reading(first), .held(second), .reading(latest)])
        let monitor = SystemMonitor(
            cpuCollector: ProbeCPUCollector([]),
            memoryCollector: ProbeMemoryCollector(),
            temperatureCollector: temperature
        )
        var updates: [TemperatureStatus] = []
        let subscription = monitor.$snapshot.sink { updates.append($0.temperature) }
        defer {
            subscription.cancel()
            monitor.pause()
            Task { await temperature.releaseHeldSample() }
        }
        monitor.start()
        try await waitUntil { monitor.snapshot.temperature == .ready(first) }
        monitor.pause()
        #expect(monitor.snapshot.temperature == .paused(lastReading: first))
        monitor.start()
        try await waitUntil { await temperature.activity().samples == 2 }
        #expect(monitor.snapshot.temperature == .collecting(lastReading: first))
        monitor.pause()
        monitor.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await temperature.activity().samples == 2)
        await temperature.releaseHeldSample()
        try await waitUntil { monitor.snapshot.temperature == .ready(latest) }
        #expect(!updates.contains(.ready(second)))
        #expect(await temperature.activity().maxConcurrentSamples == 1)
    }
}
