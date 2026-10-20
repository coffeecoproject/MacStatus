import Combine
import Foundation
import MacStatusCore
import Testing
@testable import MacStatus

@MainActor
struct SystemMonitorMemoryTests {
    private let first = MemoryUsage(
        usedBytes: 4 * 1_073_741_824, totalBytes: 8 * 1_073_741_824,
        pressure: .success(.normal), sampledAt: Date(timeIntervalSince1970: 1_000)
    )
    private let second = MemoryUsage(
        usedBytes: 6 * 1_073_741_824, totalBytes: 8 * 1_073_741_824,
        pressure: .success(.warning), sampledAt: Date(timeIntervalSince1970: 2_000)
    )

    @Test func memoryDoesNotNeedCPUsSecondBaselineRead() async throws {
        let cpu = ProbeCPUCollector([.baseline])
        let memory = ProbeMemoryCollector([.reading(first)])
        let monitor = SystemMonitor(
            cpuCollector: cpu, memoryCollector: memory,
            temperatureCollector: ProbeTemperatureCollector()
        )
        defer { monitor.pause() }
        monitor.start()
        try await waitUntil { monitor.snapshot.memory == .ready(first) }
        #expect(monitor.snapshot.cpu == .collecting(lastReading: nil))
        #expect(await memory.activity().samples == 1)
    }

    @Test func memoryFailurePreservesHistoryWhileCPUContinues() async throws {
        let memory = ProbeMemoryCollector([
            .reading(first), .failure(.systemFailure(code: 5)), .reading(second)
        ])
        let monitor = SystemMonitor(
            cpuCollector: ProbeCPUCollector([]), memoryCollector: memory,
            temperatureCollector: ProbeTemperatureCollector()
        )
        defer { monitor.pause() }
        monitor.setPanelVisible(true)
        monitor.start()
        try await waitUntil { monitor.snapshot.memory == .ready(first) }
        let firstCPUTime = monitor.snapshot.cpu.currentReading?.sampledAt
        try await waitUntil {
            if case .unavailable = monitor.snapshot.memory { return true }
            return false
        }
        #expect(monitor.snapshot.memory == .unavailable(
            error: .systemFailure(code: 5), lastReading: first
        ))
        #expect(monitor.snapshot.memory.currentReading == nil)
        try await waitUntil {
            monitor.snapshot.cpu.currentReading != nil
                && monitor.snapshot.cpu.currentReading?.sampledAt != firstCPUTime
        }
        try await waitUntil { monitor.snapshot.memory == .ready(second) }
    }

    @Test func pressureFailureDoesNotDiscardTheUsageReading() async throws {
        let reading = MemoryUsage(
            usedBytes: first.usedBytes, totalBytes: first.totalBytes,
            pressure: .failure(.unsupportedLevel(99)), sampledAt: first.sampledAt
        )
        let monitor = SystemMonitor(
            cpuCollector: ProbeCPUCollector([]),
            memoryCollector: ProbeMemoryCollector([.reading(reading)]),
            temperatureCollector: ProbeTemperatureCollector()
        )
        defer { monitor.pause() }
        monitor.start()
        try await waitUntil { monitor.snapshot.memory.currentReading != nil }
        #expect(monitor.snapshot.memory == .ready(reading))
        #expect(monitor.snapshot.memory.pressureText == "内存压力：不可用")
        try await waitUntil { monitor.snapshot.cpu.currentReading != nil }
    }

    @Test func aPreSleepMemoryResultCannotOverwriteTheResumedSnapshot() async throws {
        let cpu = ProbeCPUCollector([])
        let memory = ProbeMemoryCollector([.held(first), .reading(second)])
        let monitor = SystemMonitor(
            cpuCollector: cpu, memoryCollector: memory,
            temperatureCollector: ProbeTemperatureCollector()
        )
        var updates: [MemoryStatus] = []
        let subscription = monitor.$snapshot.sink { updates.append($0.memory) }
        defer {
            subscription.cancel()
            monitor.pause()
            Task { await memory.releaseHeldSample() }
        }
        monitor.start()
        try await waitUntil { await memory.activity().samples == 1 }
        monitor.pause()
        #expect(monitor.snapshot.memory == .paused(lastReading: nil))
        monitor.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await memory.activity().samples == 1)
        #expect(await cpu.activity().resets == 2)
        #expect(monitor.snapshot.cpu.currentReading != nil)
        await memory.releaseHeldSample()
        try await waitUntil { monitor.snapshot.memory == .ready(second) }
        #expect(!updates.contains(.ready(first)))
        #expect(await memory.activity().maxConcurrentSamples == 1)
        #expect(await cpu.activity().resets == 2)
    }

    @Test func bothFailuresAreReportedWithoutInventingReadings() async throws {
        let monitor = SystemMonitor(
            cpuCollector: ProbeCPUCollector([.failure(.incompleteSnapshot)]),
            memoryCollector: ProbeMemoryCollector([.failure(.invalidStatistics)]),
            temperatureCollector: ProbeTemperatureCollector()
        )
        defer { monitor.pause() }
        monitor.start()
        try await waitUntil {
            if case .unavailable = monitor.snapshot.memory { return true }
            return false
        }
        try await waitUntil {
            monitor.snapshot.cpu == .unavailable(error: .incompleteSnapshot, lastReading: nil)
                && monitor.snapshot.temperature.currentReading != nil
        }
        #expect(monitor.snapshot.memory == .unavailable(error: .invalidStatistics, lastReading: nil))
        #expect(monitor.snapshot.temperature.currentReading != nil)
    }
}
