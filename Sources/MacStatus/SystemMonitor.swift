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
    var network: MetricState<NetworkReading> = .loading
    var temperature: MetricState<TemperatureReading> = .loading
    /// Read only while the memory page is open.
    var apps: MetricState<[AppMemoryUsage]> = .loading
    var history = MetricHistory()
    var updatedAt: Date?
}

/// SMC goes through an undocumented driver interface, so it runs apart from the tick.
private actor TemperatureSampler {
    private let reader = TemperatureReader()

    func read(_ scope: TemperatureScope) -> Result<TemperatureReading, MetricError> {
        Result { () throws(MetricError) in try reader.read(scope) }
    }
}

/// What the open panel shows, besides the menu bar's own metrics.
enum PanelDemand: Equatable {
    /// The panel is closed or shows a page without system metrics.
    case menuBarOnly
    case overview
    case memory
    case cleanup
}

/// What each tick reads and how often: the menu bar's metrics, plus what the open page shows.
struct Sampling: Equatable {
    static let panelInterval: Duration = .seconds(2)
    static let menuBarInterval: Duration = .seconds(3)

    var cpu = false
    var memory = false
    var disk = false
    var network = false
    /// Nil when temperature is not read.
    var temperature: TemperatureScope?
    var apps = false
    var interval = Sampling.menuBarInterval

    init(demand: PanelDemand, menuBar: Set<MenuBarMetric>) {
        cpu = menuBar.contains(.cpu)
        memory = menuBar.contains(.memory)
        disk = menuBar.contains(.disk)
        network = menuBar.contains(.network)
        temperature = menuBar.contains(.temperature) ? .cpu : nil
        switch demand {
        case .menuBarOnly:
            break
        case .overview:
            cpu = true
            memory = true
            disk = true
            network = true
            temperature = .all
            interval = Self.panelInterval
        case .memory:
            memory = true
            apps = true
            interval = Self.panelInterval
        case .cleanup:
            disk = true
        }
    }
}

@MainActor
final class SystemMonitor: ObservableObject {
    /// Spacing used while a delta (CPU, disk and network rates) has no baseline yet.
    static let minimumSpacing: Duration = .milliseconds(500)
    static let temperatureTimeout: Duration = .seconds(3)

    @Published private(set) var snapshot = MonitorSnapshot()
    private(set) var sampling = Sampling(demand: .menuBarOnly, menuBar: [])

    // Kernel counters take microseconds and the app list a few milliseconds, so they are read on the main
    // actor: whatever the panel starts showing is read in the same update that shows it.
    private let cpu = CPUReader()
    private let memory = MemoryReader()
    private let disk = DiskReader()
    private let network = NetworkReader()
    private let apps = AppMemoryReader()
    private let thermal = TemperatureSampler()
    private var demand = PanelDemand.menuBarOnly
    private var menuBar: Set<MenuBarMetric> = []
    private var loop: Task<Void, Never>?
    private var sleeper: Task<Void, Never>?
    private var lastTick: ContinuousClock.Instant?
    private var hurry = false
    private var temperatureStartedAt: ContinuousClock.Instant?
    /// What the shown temperature covers; a reading covering something else is shown as soon as it arrives.
    private var shownTemperature: TemperatureScope?
    /// Applied by the next tick, so each tick changes the snapshot, and redraws the panel, once.
    private var finishedTemperature: (result: Result<TemperatureReading, MetricError>, at: Date)?

    func start() {
        guard loop == nil else { return }
        // Deltas must not span a pause or sleep.
        cpu.reset()
        disk.reset()
        network.reset()
        tick()
        loop = Task {
            while !Task.isCancelled {
                await waitForNextTick()
                guard !Task.isCancelled else { return }
                tick()
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
        resample()
    }

    func setMenuBarMetrics(_ metrics: Set<MenuBarMetric>) {
        guard metrics != menuBar else { return }
        menuBar = metrics
        resample()
    }

    /// Drops what is no longer read, so it cannot reappear later as current, and reads what is newly shown.
    private func resample() {
        let previous = sampling
        sampling = Sampling(demand: demand, menuBar: menuBar)
        let now = Date()
        var next = snapshot
        // A delta started here is measured from now, not from the last tick.
        var startedDelta = false
        switch (previous.cpu, sampling.cpu) {
        case (false, true):
            readCPU(into: &next, at: now)
            startedDelta = true
        case (true, false):
            cpu.reset()
            next.cpu = .loading
            next.history.clear(.cpu)
        default: break
        }
        switch (previous.memory, sampling.memory) {
        case (false, true): readMemory(into: &next)
        case (true, false): next.memory = .loading
        default: break
        }
        switch (previous.disk, sampling.disk) {
        case (false, true):
            readDisk(into: &next, at: now)
            startedDelta = true
        case (true, false):
            disk.reset()
            next.disk = .loading
            next.history.clear(.diskRead)
            next.history.clear(.diskWrite)
        default: break
        }
        switch (previous.network, sampling.network) {
        case (false, true):
            readNetwork(into: &next, at: now)
            startedDelta = true
        case (true, false):
            network.reset()
            next.network = .loading
            next.history.clear(.download)
            next.history.clear(.upload)
        default: break
        }
        if sampling.temperature == nil {
            finishedTemperature = nil
            shownTemperature = nil
            next.temperature = .loading
            next.history.clear(.temperature)
        }
        next.apps = sampling.apps ? readApps() : .loading
        snapshot = next
        if startedDelta { lastTick = .now }
        guard loop != nil else { return }
        startTemperatureReadIfIdle()
        sleeper?.cancel()
    }

    private func tick() {
        lastTick = .now
        hurry = false
        startTemperatureReadIfIdle()
        let now = Date()
        var next = snapshot
        if sampling.cpu { readCPU(into: &next, at: now) }
        if sampling.memory { readMemory(into: &next) }
        if sampling.disk { readDisk(into: &next, at: now) }
        if sampling.network { readNetwork(into: &next, at: now) }
        if sampling.apps { next.apps = readApps() }
        if let finished = finishedTemperature {
            finishedTemperature = nil
            apply(finished.result, at: finished.at, to: &next)
        }
        if let started = temperatureStartedAt, started.duration(to: .now) > Self.temperatureTimeout {
            next.temperature = .unavailable
        }
        next.updatedAt = now
        snapshot = next
    }

    private func readCPU(into next: inout MonitorSnapshot, at now: Date) {
        do {
            if let reading = try cpu.read() {
                next.cpu = .ready(reading)
                next.history.append(reading.total, to: .cpu, at: now)
            } else {
                next.cpu = .loading
                hurry = true
            }
        } catch {
            next.cpu = .unavailable
        }
    }

    private func readMemory(into next: inout MonitorSnapshot) {
        do {
            next.memory = .ready(try memory.read())
        } catch {
            next.memory = .unavailable
        }
    }

    private func readDisk(into next: inout MonitorSnapshot, at now: Date) {
        do {
            let reading = try disk.read()
            next.disk = .ready(reading)
            if let read = reading.readRate, let write = reading.writeRate {
                next.history.append(read, to: .diskRead, at: now)
                next.history.append(write, to: .diskWrite, at: now)
            } else {
                hurry = true
            }
        } catch {
            next.disk = .unavailable
        }
    }

    private func readNetwork(into next: inout MonitorSnapshot, at now: Date) {
        let reading = network.read()
        next.network = .ready(reading)
        if let download = reading.downloadRate, let upload = reading.uploadRate {
            next.history.append(download, to: .download, at: now)
            next.history.append(upload, to: .upload, at: now)
        } else {
            hurry = true
        }
    }

    private func readApps() -> MetricState<[AppMemoryUsage]> {
        do {
            return .ready(try apps.read(apps: QuittableApps.bundlePaths()))
        } catch {
            return .unavailable
        }
    }

    private func startTemperatureReadIfIdle() {
        // At most one SMC call in flight; a hung call only blocks temperature.
        guard let scope = sampling.temperature, temperatureStartedAt == nil else { return }
        temperatureStartedAt = .now
        Task {
            let result = await thermal.read(scope)
            temperatureStartedAt = nil
            temperatureFinished(result, scope: scope)
        }
    }

    private func temperatureFinished(_ result: Result<TemperatureReading, MetricError>, scope: TemperatureScope) {
        guard scope == sampling.temperature else {
            // Read for what was sampled before; read what is sampled now instead.
            startTemperatureReadIfIdle()
            return
        }
        guard scope == shownTemperature else {
            // The first reading, or one covering more sensors, is not held back a tick.
            var next = snapshot
            apply(result, at: Date(), to: &next)
            finishedTemperature = nil
            shownTemperature = scope
            snapshot = next
            return
        }
        finishedTemperature = (result, Date())
    }

    private func apply(_ result: Result<TemperatureReading, MetricError>, at time: Date, to next: inout MonitorSnapshot) {
        switch result {
        case .success(let reading):
            next.temperature = .ready(reading)
            if let cpu = reading.cpu {
                next.history.append(cpu.maximum, to: .temperature, at: time)
            }
        case .failure:
            next.temperature = .unavailable
        }
    }

    private func waitForNextTick() async {
        // Re-evaluated after each wake-up so interval changes apply to the current wait.
        while !Task.isCancelled, let lastTick {
            let spacing = hurry ? Self.minimumSpacing : sampling.interval
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
