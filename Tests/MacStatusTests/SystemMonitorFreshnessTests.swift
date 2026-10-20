import Foundation
import MacStatusCore
import Testing
@testable import MacStatus

@MainActor
struct SystemMonitorFreshnessTests {
    @Test func expiredValuesBecomeUnavailableAndPreserveOnlyHistory() async throws {
        let monitor = SystemMonitor(
            cpuCollector: ProbeCPUCollector([]),
            memoryCollector: ProbeMemoryCollector(),
            diskCollector: ProbeDiskCollector(),
            temperatureCollector: ProbeTemperatureCollector(),
            policy: SamplingPolicy(collapsedInterval: .seconds(2), maximumAge: .milliseconds(200))
        )
        defer { monitor.pause() }
        monitor.start()
        try await waitUntil {
            monitor.snapshot.cpu.currentReading != nil
                && monitor.snapshot.memory.currentReading != nil
                && monitor.snapshot.disk.currentReading != nil
                && monitor.snapshot.temperature.currentReading != nil
        }
        let live = monitor.snapshot
        try await waitUntil {
            monitor.snapshot.cpu == .unavailable(error: .staleReading, lastReading: live.cpu.lastReading)
                && monitor.snapshot.memory == .unavailable(error: .staleReading, lastReading: live.memory.lastReading)
                && monitor.snapshot.disk == .unavailable(error: .staleReading, lastReading: live.disk.lastReading)
                && monitor.snapshot.temperature == .unavailable(
                    error: .staleReading, lastReading: live.temperature.lastReading
                )
        }
        #expect(monitor.snapshot.cpu.percentageText == "—")
        #expect(monitor.snapshot.memory.amountText == "—")
        #expect(monitor.snapshot.memory.pressureText == "内存压力：—")
        #expect(monitor.snapshot.disk.amountText == "—")
        #expect(monitor.snapshot.temperature.valueText == "—")
    }

    @Test func unchangedDisplayedValuesStillReceiveFreshSamples() async throws {
        let firstTime = Date(timeIntervalSince1970: 1_000)
        let secondTime = Date(timeIntervalSince1970: 2_000)
        let firstCPU = CPUUsage(fraction: 0.55, sampledAt: firstTime)
        let secondCPU = CPUUsage(fraction: 0.55, sampledAt: secondTime)
        let firstMemory = MemoryUsage(
            usedBytes: 6_979_321_856, totalBytes: 8 * 1_073_741_824,
            pressure: .success(.normal), sampledAt: firstTime
        )
        let secondMemory = MemoryUsage(
            usedBytes: firstMemory.usedBytes, totalBytes: firstMemory.totalBytes,
            pressure: firstMemory.pressure, sampledAt: secondTime
        )
        let firstDisk = DiskUsage(
            usedBytes: 330 * 1_073_741_824,
            totalBytes: 500 * 1_073_741_824,
            sampledAt: firstTime
        )
        let secondDisk = DiskUsage(
            usedBytes: firstDisk.usedBytes,
            totalBytes: firstDisk.totalBytes,
            sampledAt: secondTime
        )
        let monitor = SystemMonitor(
            cpuCollector: ProbeCPUCollector([.reading(firstCPU), .reading(secondCPU)]),
            memoryCollector: ProbeMemoryCollector([.reading(firstMemory), .reading(secondMemory)]),
            diskCollector: ProbeDiskCollector([.reading(firstDisk), .reading(secondDisk)]),
            temperatureCollector: ProbeTemperatureCollector([
                .reading(CPUTemperature(celsius: 60, sampledAt: firstTime)),
                .reading(CPUTemperature(celsius: 60, sampledAt: secondTime))
            ])
        )
        defer { monitor.pause() }
        monitor.setPanelVisible(true)
        monitor.start()
        try await waitUntil {
            monitor.snapshot.cpu.currentReading?.sampledAt == firstTime
                && monitor.snapshot.memory.currentReading?.sampledAt == firstTime
                && monitor.snapshot.disk.currentReading?.sampledAt == firstTime
                && monitor.snapshot.temperature.currentReading?.sampledAt == firstTime
        }
        let original = monitor.snapshot
        try await waitUntil {
            monitor.snapshot.cpu.currentReading?.sampledAt == secondTime
                && monitor.snapshot.memory.currentReading?.sampledAt == secondTime
                && monitor.snapshot.disk.currentReading?.sampledAt == secondTime
                && monitor.snapshot.temperature.currentReading?.sampledAt == secondTime
        }

        #expect(monitor.snapshot.memory.currentReading?.sampledAt == secondTime)
        #expect(monitor.snapshot.disk.currentReading?.sampledAt == secondTime)
        #expect(monitor.snapshot.temperature.currentReading?.sampledAt == secondTime)
        #expect(monitor.snapshot != original)
        #expect(monitor.snapshot.cpu.percentageText == original.cpu.percentageText)
        #expect(monitor.snapshot.memory.amountText == original.memory.amountText)
        #expect(monitor.snapshot.disk.amountText == original.disk.amountText)
        #expect(monitor.snapshot.temperature.valueText == original.temperature.valueText)
    }
}
