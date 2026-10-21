import Combine
import Foundation
import MacSystemMetrics

enum MetricState<Value: Equatable>: Equatable {
    case loading
    case ready(Value)
    case unavailable

    var value: Value? {
        guard case .ready(let value) = self else { return nil }
        return value
    }
}

struct MonitorSnapshot: Equatable {
    var cpu: MetricState<CPUReading> = .loading
    var memory: MetricState<MemoryReading> = .loading
    var disk: MetricState<DiskReading> = .loading
    var temperature: MetricState<TemperatureReading> = .loading
    /// Read only while the process page is open.
    var apps: MetricState<[AppMemoryUsage]> = .loading
    var history = MetricHistory()
    var updatedAt: Date?
}

/// CPU, memory and disk are cheap kernel counters read together each tick.
private actor CoreSampler {
    private let cpu = CPUReader()
    private let memory = MemoryReader()
    private let disk = DiskReader()

    func reset() {
        cpu.reset()
        disk.reset()
    }

    func read() -> (
        cpu: Result<CPUReading?, MetricError>,
        memory: Result<MemoryReading, MetricError>,
        disk: Result<DiskReading, MetricError>
    ) {
        (
            Result { () throws(MetricError) in try cpu.read() },
            Result { () throws(MetricError) in try memory.read() },
            Result { () throws(MetricError) in try disk.read() }
        )
    }
}

/// SMC goes through an undocumented driver interface, so it runs apart from the core tick.
private actor TemperatureSampler {
    private let reader = TemperatureReader()

    func read() -> Result<TemperatureReading, MetricError> {
        Result { () throws(MetricError) in try reader.read() }
    }
}

/// What the panel currently shows; drives the sampling interval and whether the app list is read.
enum PanelDemand: Equatable {
    case hidden
    case metrics
    case processes
}

@MainActor
final class SystemMonitor: ObservableObject {
    static let expandedInterval: Duration = .seconds(1)
    static let collapsedInterval: Duration = .seconds(2)
    /// Spacing used right after a CPU baseline and when the panel asks for fresh data.
    static let minimumSpacing: Duration = .milliseconds(500)
    static let temperatureTimeout: Duration = .seconds(3)
    static let appLimit = 10

    @Published private(set) var snapshot = MonitorSnapshot()
    private(set) var interval = SystemMonitor.collapsedInterval

    private let core = CoreSampler()
    private let thermal = TemperatureSampler()
    /// Read on the main actor (a few milliseconds), so the list is ready in the same update that opens the page.
    private let apps = AppMemoryReader()
    private var loop: Task<Void, Never>?
    private var sleeper: Task<Void, Never>?
    private var lastTick: ContinuousClock.Instant?
    private var hurry = false
    private var demand = PanelDemand.hidden
    private var temperatureStartedAt: ContinuousClock.Instant?
    /// Applied by the next tick, so each tick changes the snapshot, and redraws the panel, once.
    private var finishedTemperature: (result: Result<TemperatureReading, MetricError>, at: Date)?

    func start() {
        guard loop == nil else { return }
        snapshot.cpu = .loading
        loop = Task {
            // Deltas must not span a pause or sleep.
            await core.reset()
            while !Task.isCancelled {
                await tick()
                await waitForNextTick()
            }
        }
    }

    func pause() {
        loop?.cancel()
        loop = nil
        sleeper?.cancel()
    }

    func setPanelDemand(_ demand: PanelDemand) {
        guard demand != self.demand else { return }
        self.demand = demand
        interval = demand == .hidden ? Self.collapsedInterval : Self.expandedInterval
        // Whatever the panel just started showing gets fresh data right away.
        hurry = demand != .hidden
        // A list read for an earlier view must not reappear as current.
        snapshot.apps = demand == .processes ? readApps() : .loading
        sleeper?.cancel()
    }

    private func tick() async {
        lastTick = .now
        hurry = false
        startTemperatureReadIfIdle()

        let result = await core.read()
        guard !Task.isCancelled else { return }
        let now = Date()
        var next = snapshot
        switch result.cpu {
        case .success(let reading?):
            next.cpu = .ready(reading)
            next.history.append(reading.total, to: .cpu, at: now)
        case .success(nil):
            next.cpu = .loading
            hurry = true
        case .failure:
            next.cpu = .unavailable
        }
        switch result.memory {
        case .success(let reading):
            next.memory = .ready(reading)
        case .failure:
            next.memory = .unavailable
        }
        switch result.disk {
        case .success(let reading):
            next.disk = .ready(reading)
            if let read = reading.readRate, let write = reading.writeRate {
                next.history.append(read, to: .diskRead, at: now)
                next.history.append(write, to: .diskWrite, at: now)
            }
        case .failure:
            next.disk = .unavailable
        }
        if demand == .processes {
            next.apps = readApps()
        }
        if let finished = finishedTemperature {
            finishedTemperature = nil
            switch finished.result {
            case .success(let reading):
                next.temperature = .ready(reading)
                if let cpu = reading.cpu {
                    next.history.append(cpu.maximum, to: .temperature, at: finished.at)
                }
            case .failure:
                next.temperature = .unavailable
            }
        }
        if let started = temperatureStartedAt, started.duration(to: .now) > Self.temperatureTimeout {
            next.temperature = .unavailable
        }
        next.updatedAt = now
        snapshot = next
    }

    private func readApps() -> MetricState<[AppMemoryUsage]> {
        do {
            return .ready(try apps.read(apps: QuittableApps.bundlePaths(), limit: Self.appLimit))
        } catch {
            return .unavailable
        }
    }

    private func startTemperatureReadIfIdle() {
        // At most one SMC call in flight; a hung call only blocks temperature.
        guard temperatureStartedAt == nil else { return }
        temperatureStartedAt = .now
        Task {
            let result = await thermal.read()
            temperatureStartedAt = nil
            finishedTemperature = (result, Date())
        }
    }

    private func waitForNextTick() async {
        // Re-evaluated after each wake-up so interval changes apply to the current wait.
        while !Task.isCancelled, let lastTick {
            let spacing = hurry ? Self.minimumSpacing : interval
            let deadline = lastTick.advanced(by: spacing)
            guard ContinuousClock.now < deadline else { return }
            // The leeway lets the system wake the app together with other work.
            let sleeper = Task {
                _ = try? await Task.sleep(until: deadline, tolerance: spacing / 10, clock: .continuous)
            }
            self.sleeper = sleeper
            await sleeper.value
            self.sleeper = nil
        }
    }
}
