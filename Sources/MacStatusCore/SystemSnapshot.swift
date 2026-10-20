public struct SystemSnapshot: Sendable, Equatable {
    public let cpu: CPUStatus
    public let memory: MemoryStatus
    public let disk: DiskStatus
    public let temperature: TemperatureStatus

    public init(
        cpu: CPUStatus = .collecting(lastReading: nil),
        memory: MemoryStatus = .collecting(lastReading: nil),
        disk: DiskStatus = .collecting(lastReading: nil),
        temperature: TemperatureStatus = .collecting(lastReading: nil)
    ) {
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.temperature = temperature
    }
}
