import Combine
import Foundation
import MacStatusCore
import Testing
@testable import MacStatus

@MainActor
struct SystemMonitorIsolationTests {
    enum BlockedMetric: CaseIterable {
        case cpu, memory, temperature
    }

    private let policy = SamplingPolicy(
        expandedInterval: .milliseconds(80), collapsedInterval: .milliseconds(100),
        baselineInterval: .milliseconds(20), readTimeout: .milliseconds(400),
        maximumAge: .seconds(2)
    )
    private let firstCPU = CPUUsage(fraction: 0.2, sampledAt: Date(timeIntervalSince1970: 1_000))
    private let lateCPU = CPUUsage(fraction: 0.9, sampledAt: Date(timeIntervalSince1970: 2_000))
    private let firstMemory = MemoryUsage(
        usedBytes: 3_221_225_472, totalBytes: 8_589_934_592,
        pressure: .success(.normal), sampledAt: Date(timeIntervalSince1970: 1_000)
    )
    private let lateMemory = MemoryUsage(
        usedBytes: 7_516_192_768, totalBytes: 8_589_934_592,
        pressure: .success(.critical), sampledAt: Date(timeIntervalSince1970: 2_000)
    )
    private let firstTemperature = CPUTemperature(celsius: 60, sampledAt: Date(timeIntervalSince1970: 1_000))
    private let lateTemperature = CPUTemperature(celsius: 99, sampledAt: Date(timeIntervalSince1970: 2_000))

    @Test(arguments: BlockedMetric.allCases)
    func hangingReadExpiresWithoutBlockingOtherMetricsOrResume(blocked: BlockedMetric) async throws {
        let cpu = ProbeCPUCollector(blocked == .cpu ? [.reading(firstCPU), .held(lateCPU)] : [])
        let memory = ProbeMemoryCollector(blocked == .memory ? [.reading(firstMemory), .held(lateMemory)] : [])
        let temperature = ProbeTemperatureCollector(
            blocked == .temperature ? [.reading(firstTemperature), .held(lateTemperature)] : []
        )
        let monitor = SystemMonitor(
            cpuCollector: cpu, memoryCollector: memory, temperatureCollector: temperature, policy: policy
        )
        var updates: [SystemSnapshot] = []
        let subscription = monitor.$snapshot.sink { updates.append($0) }
        defer {
            subscription.cancel()
            monitor.pause()
            Task {
                await cpu.releaseHeldSample()
                await memory.releaseHeldSample()
                await temperature.releaseHeldSample()
            }
        }
        monitor.setPanelVisible(true)
        monitor.start()
        try await waitUntil { allReady(monitor.snapshot) }
        try await waitUntil { isTimedOut(monitor.snapshot, blocked: blocked) }
        let atTimeout = monitor.snapshot
        try await waitUntil { healthyMetricsAdvanced(monitor.snapshot, since: atTimeout, blocked: blocked) }
        expectHistoryAndDash(monitor.snapshot, blocked: blocked)

        let beforeResume = monitor.snapshot
        // Repeated lifecycle changes must not queue replacement calls behind a hung collector.
        for _ in 0..<5 {
            monitor.pause()
            monitor.start()
        }
        try await waitUntil {
            isTimedOut(monitor.snapshot, blocked: blocked)
                && healthyMetricsAdvanced(monitor.snapshot, since: beforeResume, blocked: blocked)
        }
        let counts = (await cpu.activity(), await memory.activity(), await temperature.activity())
        switch blocked {
        case .cpu: #expect(counts.0.samples == 2)
        case .memory: #expect(counts.1.samples == 2)
        case .temperature: #expect(counts.2.samples == 2)
        }
        #expect(counts.0.maxConcurrentSamples == 1)
        #expect(counts.1.maxConcurrentSamples == 1)
        #expect(counts.2.maxConcurrentSamples == 1)

        await cpu.releaseHeldSample()
        await memory.releaseHeldSample()
        await temperature.releaseHeldSample()
        try await waitUntil { allReady(monitor.snapshot) }
        #expect(!updates.contains { $0.cpu == .ready(lateCPU) })
        #expect(!updates.contains { $0.memory == .ready(lateMemory) })
        #expect(!updates.contains { $0.temperature == .ready(lateTemperature) })
    }

    @Test func cpuTimeoutResetsItsBaselineBeforeRecoveryWithoutSleep() async throws {
        let fresh = CPUUsage(fraction: 0.4, sampledAt: Date(timeIntervalSince1970: 3_000))
        let cpu = ProbeCPUCollector([.reading(firstCPU), .held(lateCPU), .baseline, .reading(fresh)])
        let monitor = SystemMonitor(
            cpuCollector: cpu, memoryCollector: ProbeMemoryCollector(),
            temperatureCollector: ProbeTemperatureCollector(), policy: policy
        )
        var updates: [CPUStatus] = []
        let subscription = monitor.$snapshot.sink { updates.append($0.cpu) }
        defer {
            subscription.cancel()
            monitor.pause()
            Task { await cpu.releaseHeldSample() }
        }
        monitor.start()
        try await waitUntil { isTimedOut(monitor.snapshot, blocked: .cpu) }
        #expect(await cpu.activity().resets == 1)
        await cpu.releaseHeldSample()
        try await waitUntil { monitor.snapshot.cpu == .ready(fresh) }
        #expect(await cpu.activity().resets == 2)
        #expect(updates.contains(.collecting(lastReading: firstCPU)))
        #expect(!updates.contains(.ready(lateCPU)))
    }

    @Test func monitorAndItsWorkersCanDeallocateWhileTemperatureIsHung() async throws {
        let temperature = ProbeTemperatureCollector([.held(lateTemperature)])
        let cpu = ProbeCPUCollector([])
        var monitor: SystemMonitor? = SystemMonitor(
            cpuCollector: cpu, memoryCollector: ProbeMemoryCollector(),
            temperatureCollector: temperature, policy: policy
        )
        weak let weakMonitor = monitor
        defer { Task { await temperature.releaseHeldSample() } }
        monitor?.start()
        try await waitUntil { await temperature.activity().samples == 1 }
        monitor = nil
        #expect(weakMonitor == nil)
        // Allow an already-started call to complete, then verify sampling has stopped.
        try await Task.sleep(for: .milliseconds(150))
        let count = await cpu.activity().samples
        try await Task.sleep(for: .milliseconds(200))
        #expect(await cpu.activity().samples == count)
        await temperature.releaseHeldSample()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await temperature.activity().samples == 1)
    }

    private func allReady(_ snapshot: SystemSnapshot) -> Bool {
        snapshot.cpu.currentReading != nil && snapshot.memory.currentReading != nil
            && snapshot.temperature.currentReading != nil
    }

    private func isTimedOut(_ snapshot: SystemSnapshot, blocked: BlockedMetric) -> Bool {
        switch blocked {
        case .cpu:
            snapshot.cpu == .unavailable(error: .timedOut, lastReading: firstCPU)
        case .memory:
            snapshot.memory == .unavailable(error: .timedOut, lastReading: firstMemory)
        case .temperature:
            snapshot.temperature == .unavailable(error: .timedOut, lastReading: firstTemperature)
        }
    }

    private func healthyMetricsAdvanced(
        _ current: SystemSnapshot, since previous: SystemSnapshot, blocked: BlockedMetric
    ) -> Bool {
        (blocked == .cpu || (current.cpu.currentReading != nil && current.cpu != previous.cpu))
            && (blocked == .memory || (current.memory.currentReading != nil && current.memory != previous.memory))
            && (blocked == .temperature || (
                current.temperature.currentReading != nil && current.temperature != previous.temperature
            ))
    }

    private func expectHistoryAndDash(_ snapshot: SystemSnapshot, blocked: BlockedMetric) {
        switch blocked {
        case .cpu:
            #expect(snapshot.cpu.currentReading == nil)
            #expect(snapshot.cpu.lastReading == firstCPU)
            #expect(snapshot.cpu.percentageText == "—")
        case .memory:
            #expect(snapshot.memory.currentReading == nil)
            #expect(snapshot.memory.lastReading == firstMemory)
            #expect(snapshot.memory.amountText == "—")
            #expect(snapshot.memory.pressureText == "内存压力：—")
        case .temperature:
            #expect(snapshot.temperature.currentReading == nil)
            #expect(snapshot.temperature.lastReading == firstTemperature)
            #expect(snapshot.temperature.valueText == "—")
        }
    }
}
