import Combine
import Foundation
import MacStatusCore
import Testing
@testable import MacStatus

@MainActor
struct SystemMonitorDiskTests {
    private let first = DiskUsage(
        usedBytes: 330 * 1_073_741_824,
        totalBytes: 500 * 1_073_741_824,
        sampledAt: Date(timeIntervalSince1970: 1_000)
    )
    private let second = DiskUsage(
        usedBytes: 340 * 1_073_741_824,
        totalBytes: 500 * 1_073_741_824,
        sampledAt: Date(timeIntervalSince1970: 2_000)
    )

    @Test func diskDoesNotNeedCPUsSecondBaselineRead() async throws {
        let cpu = ProbeCPUCollector([.baseline])
        let disk = ProbeDiskCollector([.reading(first)])
        let monitor = SystemMonitor(
            cpuCollector: cpu,
            memoryCollector: ProbeMemoryCollector(),
            diskCollector: disk,
            temperatureCollector: ProbeTemperatureCollector()
        )
        defer { monitor.pause() }
        monitor.start()
        try await waitUntil { monitor.snapshot.disk == .ready(first) }
        #expect(monitor.snapshot.cpu == .collecting(lastReading: nil))
        #expect(await disk.activity().samples == 1)
    }

    @Test func diskFailurePreservesHistoryWhileOtherMetricsContinue() async throws {
        let disk = ProbeDiskCollector([
            .reading(first), .failure(.invalidStatistics), .reading(second)
        ])
        let monitor = SystemMonitor(
            cpuCollector: ProbeCPUCollector([]),
            memoryCollector: ProbeMemoryCollector(),
            diskCollector: disk,
            temperatureCollector: ProbeTemperatureCollector()
        )
        defer { monitor.pause() }
        monitor.setPanelVisible(true)
        monitor.start()
        try await waitUntil { monitor.snapshot.disk == .ready(first) }
        try await waitUntil {
            if case .unavailable = monitor.snapshot.disk { return true }
            return false
        }
        #expect(monitor.snapshot.disk == .unavailable(
            error: .invalidStatistics, lastReading: first
        ))
        #expect(monitor.snapshot.disk.amountText == "—")
        try await waitUntil {
            monitor.snapshot.cpu.currentReading != nil
                && monitor.snapshot.memory.currentReading != nil
                && monitor.snapshot.temperature.currentReading != nil
        }
        try await waitUntil { monitor.snapshot.disk == .ready(second) }
    }

    @Test func aPreSleepDiskResultCannotOverwriteTheResumedSnapshot() async throws {
        let disk = ProbeDiskCollector([.held(first), .reading(second)])
        let monitor = SystemMonitor(
            cpuCollector: ProbeCPUCollector([]),
            memoryCollector: ProbeMemoryCollector(),
            diskCollector: disk,
            temperatureCollector: ProbeTemperatureCollector()
        )
        var updates: [DiskStatus] = []
        let subscription = monitor.$snapshot.sink { updates.append($0.disk) }
        defer {
            subscription.cancel()
            monitor.pause()
            Task { await disk.releaseHeldSample() }
        }
        monitor.start()
        try await waitUntil { await disk.activity().samples == 1 }
        monitor.pause()
        #expect(monitor.snapshot.disk == .paused(lastReading: nil))
        monitor.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await disk.activity().samples == 1)
        await disk.releaseHeldSample()
        try await waitUntil { monitor.snapshot.disk == .ready(second) }
        #expect(!updates.contains(.ready(first)))
        #expect(await disk.activity().maxConcurrentSamples == 1)
    }
}
