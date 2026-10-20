import Combine
import MacStatusCore

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()

    private let cpu: MetricSampler<CPUUsage?, CPUReadError>
    private let memory: MetricSampler<MemoryUsage, MemoryReadError>
    private let disk: MetricSampler<DiskUsage, DiskReadError>
    private let temperature: MetricSampler<CPUTemperature, TemperatureReadError>
    private let policy: SamplingPolicy
    private var isRunning = false

    init(
        cpuCollector: any CPUSampling,
        memoryCollector: any MemorySampling,
        diskCollector: any DiskSampling = MissingDiskCollector(),
        temperatureCollector: any TemperatureSampling,
        policy: SamplingPolicy = SamplingPolicy()
    ) {
        self.policy = policy
        cpu = MetricSampler(
            policy: policy, timeoutError: .timedOut, staleError: .staleReading,
            isBaseline: { $0 == nil }
        ) { reset in
            if reset { await cpuCollector.reset() }
            do throws(CPUReadError) {
                return .success(try await cpuCollector.sample())
            } catch {
                return .failure(error)
            }
        }
        memory = MetricSampler(
            policy: policy, timeoutError: .timedOut, staleError: .staleReading
        ) { _ in
            do throws(MemoryReadError) {
                return .success(try await memoryCollector.sample())
            } catch {
                return .failure(error)
            }
        }
        disk = MetricSampler(
            policy: policy, timeoutError: .timedOut, staleError: .staleReading
        ) { _ in
            do throws(DiskReadError) {
                return .success(try await diskCollector.sample())
            } catch {
                return .failure(error)
            }
        }
        temperature = MetricSampler(
            policy: policy, timeoutError: .timedOut, staleError: .staleReading
        ) { _ in
            do throws(TemperatureReadError) {
                return .success(try await temperatureCollector.sample())
            } catch {
                return .failure(error)
            }
        }
        cpu.onResult = { [weak self] in self?.acceptCPU($0) }
        memory.onResult = { [weak self] in self?.acceptMemory($0) }
        disk.onResult = { [weak self] in self?.acceptDisk($0) }
        temperature.onResult = { [weak self] in self?.acceptTemperature($0) }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        snapshot = SystemSnapshot(
            cpu: .collecting(lastReading: snapshot.cpu.lastReading),
            memory: .collecting(lastReading: snapshot.memory.lastReading),
            disk: .collecting(lastReading: snapshot.disk.lastReading),
            temperature: .collecting(lastReading: snapshot.temperature.lastReading)
        )
        guard isRunning else { return }
        cpu.start()
        memory.start()
        disk.start()
        temperature.start()
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        cpu.pause()
        memory.pause()
        disk.pause()
        temperature.pause()
        snapshot = SystemSnapshot(
            cpu: .paused(lastReading: snapshot.cpu.lastReading),
            memory: .paused(lastReading: snapshot.memory.lastReading),
            disk: .paused(lastReading: snapshot.disk.lastReading),
            temperature: .paused(lastReading: snapshot.temperature.lastReading)
        )
    }

    func setPanelVisible(_ visible: Bool) {
        let interval = visible ? policy.expandedInterval : policy.collapsedInterval
        cpu.interval = interval
        memory.interval = interval
        disk.interval = interval
        temperature.interval = interval
    }

    private func acceptCPU(_ result: Result<CPUUsage?, CPUReadError>) {
        let status: CPUStatus
        switch result {
        case .success(let reading?):
            status = .ready(reading)
        case .success(nil):
            status = .collecting(lastReading: snapshot.cpu.lastReading)
        case .failure(let error):
            status = .unavailable(error: error, lastReading: snapshot.cpu.lastReading)
        }
        snapshot = SystemSnapshot(
            cpu: status, memory: snapshot.memory, disk: snapshot.disk,
            temperature: snapshot.temperature
        )
    }

    private func acceptMemory(_ result: Result<MemoryUsage, MemoryReadError>) {
        let status: MemoryStatus
        switch result {
        case .success(let reading):
            status = .ready(reading)
        case .failure(let error):
            status = .unavailable(error: error, lastReading: snapshot.memory.lastReading)
        }
        snapshot = SystemSnapshot(
            cpu: snapshot.cpu, memory: status, disk: snapshot.disk,
            temperature: snapshot.temperature
        )
    }

    private func acceptDisk(_ result: Result<DiskUsage, DiskReadError>) {
        let status: DiskStatus
        switch result {
        case .success(let reading):
            status = .ready(reading)
        case .failure(let error):
            status = .unavailable(error: error, lastReading: snapshot.disk.lastReading)
        }
        snapshot = SystemSnapshot(
            cpu: snapshot.cpu, memory: snapshot.memory, disk: status,
            temperature: snapshot.temperature
        )
    }

    private func acceptTemperature(_ result: Result<CPUTemperature, TemperatureReadError>) {
        let status: TemperatureStatus
        switch result {
        case .success(let reading):
            status = .ready(reading)
        case .failure(let error):
            status = .unavailable(error: error, lastReading: snapshot.temperature.lastReading)
        }
        snapshot = SystemSnapshot(
            cpu: snapshot.cpu, memory: snapshot.memory, disk: snapshot.disk,
            temperature: status
        )
    }
}

private actor MissingDiskCollector: DiskSampling {
    func sample() throws(DiskReadError) -> DiskUsage {
        throw .unavailable
    }
}
