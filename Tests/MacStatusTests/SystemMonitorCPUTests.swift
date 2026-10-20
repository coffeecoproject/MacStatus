import Combine
import Foundation
import MacStatusCore
import Testing
@testable import MacStatus

@MainActor
struct SystemMonitorCPUTests {
    private let first = CPUUsage(
        fraction: 0.6, sampledAt: Date(timeIntervalSince1970: 1_000)
    )
    private let second = CPUUsage(
        fraction: 0.2, sampledAt: Date(timeIntervalSince1970: 2_000)
    )

    @Test func repeatedStartCreatesOnlyOneSamplingLoop() async throws {
        let collector = ProbeCPUCollector([.held(first)])
        let monitor = makeMonitor(collector)
        defer {
            monitor.pause()
            Task { await collector.releaseHeldSample() }
        }

        #expect(monitor.snapshot.cpu == .collecting(lastReading: nil))
        monitor.start()
        monitor.start()
        try await waitUntil { await collector.activity().samples == 1 }
        #expect(await collector.activity().resets == 1)
        await collector.releaseHeldSample()
        try await waitUntil { monitor.snapshot.cpu == .ready(first) }
        #expect(await collector.activity().samples == 1)
    }

    @Test func baselineIsNotDisplayedAsZero() async throws {
        let collector = ProbeCPUCollector([.baseline, .reading(first)])
        let monitor = makeMonitor(collector)
        defer { monitor.pause() }
        monitor.start()

        try await waitUntil { monitor.snapshot.memory.currentReading != nil }
        #expect(monitor.snapshot.cpu == .collecting(lastReading: nil))
        #expect(monitor.snapshot.cpu.currentReading == nil)
        try await waitUntil { monitor.snapshot.cpu == .ready(first) }
        #expect(await collector.activity().samples == 2)
    }

    @Test func pauseAndResumeResetTheBaselineAndPreserveHistory() async throws {
        let collector = ProbeCPUCollector([
            .baseline, .reading(first), .baseline, .reading(second)
        ])
        let monitor = makeMonitor(collector)
        defer { monitor.pause() }
        monitor.start()
        try await waitUntil {
            monitor.snapshot.cpu == .ready(first)
                && monitor.snapshot.memory.currentReading != nil
                && monitor.snapshot.temperature.currentReading != nil
        }
        let memoryBeforePause = monitor.snapshot.memory.lastReading
        let temperatureBeforePause = monitor.snapshot.temperature.lastReading

        monitor.pause()
        monitor.pause()
        #expect(monitor.snapshot.cpu == .paused(lastReading: first))
        #expect(monitor.snapshot.memory == .paused(lastReading: memoryBeforePause))
        #expect(monitor.snapshot.temperature == .paused(lastReading: temperatureBeforePause))
        try await Task.sleep(for: .milliseconds(100))
        #expect(await collector.activity().samples == 2)

        monitor.start()
        try await waitUntil { await collector.activity().samples == 3 }
        #expect(monitor.snapshot.cpu == .collecting(lastReading: first))
        #expect(monitor.snapshot.cpu.currentReading == nil)
        try await waitUntil { monitor.snapshot.cpu == .ready(second) }
        #expect(monitor.snapshot.memory.currentReading != nil)
        #expect(monitor.snapshot.temperature.currentReading != nil)
        #expect(await collector.activity().resets == 2)
    }

    @Test func failureRetriesWithoutPresentingOldDataAsCurrent() async throws {
        let collector = ProbeCPUCollector([
            .reading(first), .failure(.systemFailure(code: 5)), .baseline, .reading(second)
        ])
        let monitor = makeMonitor(collector)
        defer { monitor.pause() }
        monitor.setPanelVisible(true)
        monitor.start()
        try await waitUntil { monitor.snapshot.cpu == .ready(first) }
        try await waitUntil {
            if case .unavailable = monitor.snapshot.cpu { return true }
            return false
        }
        #expect(monitor.snapshot.cpu == .unavailable(
            error: .systemFailure(code: 5), lastReading: first
        ))
        #expect(monitor.snapshot.cpu.currentReading == nil)
        try await waitUntil { monitor.snapshot.memory.currentReading != nil }
        try await waitUntil { monitor.snapshot.cpu == .collecting(lastReading: first) }
        try await waitUntil { monitor.snapshot.cpu == .ready(second) }
    }

    @Test(arguments: [CPUReadError.systemFailure(code: 5), .incompleteSnapshot])
    func initialFailurePreservesItsTypeWithoutInventingAReading(error: CPUReadError) async throws {
        let collector = ProbeCPUCollector([.failure(error)])
        let monitor = makeMonitor(collector)
        defer { monitor.pause() }
        monitor.start()
        try await waitUntil {
            if case .unavailable = monitor.snapshot.cpu { return true }
            return false
        }
        #expect(monitor.snapshot.cpu == .unavailable(error: error, lastReading: nil))
        #expect(monitor.snapshot.cpu.currentReading == nil)
        try await waitUntil { monitor.snapshot.memory.currentReading != nil }
        monitor.pause()
        #expect(monitor.snapshot.cpu == .paused(lastReading: nil))
    }

    @Test func resumeWaitsForAnOldReadAndDiscardsItsResult() async throws {
        let collector = ProbeCPUCollector([.held(first), .baseline, .reading(second)])
        let monitor = makeMonitor(collector)
        var updates: [CPUStatus] = []
        let subscription = monitor.$snapshot.sink { updates.append($0.cpu) }
        defer {
            subscription.cancel()
            monitor.pause()
            Task { await collector.releaseHeldSample() }
        }

        monitor.start()
        try await waitUntil { await collector.activity().samples == 1 }
        monitor.pause()
        monitor.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await collector.activity().samples == 1)
        #expect(await collector.activity().resets == 1)

        await collector.releaseHeldSample()
        try await waitUntil { monitor.snapshot.cpu == .ready(second) }
        #expect(!updates.contains(.ready(first)))
        #expect(await collector.activity().resets == 2)
        #expect(await collector.activity().maxConcurrentSamples == 1)
    }

    @Test func monitorCanDeallocateWithAnInFlightRead() async throws {
        let collector = ProbeCPUCollector([.held(first)])
        var monitor: SystemMonitor? = makeMonitor(collector)
        weak let weakMonitor = monitor
        defer { Task { await collector.releaseHeldSample() } }
        monitor?.start()
        try await waitUntil { await collector.activity().samples == 1 }

        monitor = nil
        #expect(weakMonitor == nil)
        await collector.releaseHeldSample()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await collector.activity().samples == 1)
    }

    @Test func independentMetricsUseTheSameVisibilityPolicy() async throws {
        let collector = ProbeCPUCollector([])
        let memory = ProbeMemoryCollector()
        let temperature = ProbeTemperatureCollector()
        let monitor = SystemMonitor(
            cpuCollector: collector, memoryCollector: memory, temperatureCollector: temperature
        )
        defer { monitor.pause() }
        monitor.setPanelVisible(true)
        monitor.start()
        try await waitUntil {
            monitor.snapshot.cpu.currentReading != nil
                && monitor.snapshot.memory.currentReading != nil
                && monitor.snapshot.temperature.currentReading != nil
        }

        monitor.setPanelVisible(false)
        try await waitUntil(timeout: .seconds(10)) {
            await collector.activity().samples >= 3
        }
        let activity = await collector.activity()
        let expandedInterval = activity.sampleTimes[0].duration(to: activity.sampleTimes[1])
        let collapsedInterval = activity.sampleTimes[1].duration(to: activity.sampleTimes[2])
        #expect(expandedInterval >= .milliseconds(1_800))
        #expect(collapsedInterval >= .milliseconds(4_800))
        #expect(activity.maxConcurrentSamples == 1)
        try await waitUntil { await memory.activity().samples == activity.samples }
        #expect(await memory.activity().maxConcurrentSamples == 1)
        try await waitUntil { await temperature.activity().samples == activity.samples }
        #expect(await temperature.activity().maxConcurrentSamples == 1)
    }

    private func makeMonitor(_ collector: ProbeCPUCollector) -> SystemMonitor {
        SystemMonitor(
            cpuCollector: collector,
            memoryCollector: ProbeMemoryCollector(),
            temperatureCollector: ProbeTemperatureCollector()
        )
    }
}
