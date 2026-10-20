import Testing
@testable import MacSystemMetrics

struct TemperatureTests {
    @Test(arguments: [
        ("Tp01", TemperatureSensorGroup.cpu), ("Tp0g", .cpu), ("Te05", .cpu),
        ("Tg0f", .gpu), ("TH0x", .ssd), ("TB0T", .battery)
    ])
    func knownKeysAreGrouped(key: String, group: TemperatureSensorGroup) {
        #expect(TemperatureSensorGroup(key: key) == group)
    }

    @Test(arguments: ["TVM2", "Ta09", "TB1T", "TPD0", "#KEY"])
    func otherKeysAreIgnored(key: String) {
        #expect(TemperatureSensorGroup(key: key) == nil)
    }

    @Test func summarizesGroupsAndSkipsImplausibleValues() throws {
        let reading = try #require(TemperatureAggregator.reading([
            (.cpu, 80), (.cpu, 90), (.cpu, 0), (.cpu, .nan), (.cpu, 200),
            (.gpu, 60), (.ssd, 45), (.battery, 31)
        ], thermal: .fair))
        #expect(reading.cpu == TemperatureSummary(maximum: 90, average: 85))
        #expect(reading.gpu == TemperatureSummary(maximum: 60, average: 60))
        #expect(reading.ssd == 45)
        #expect(reading.battery == 31)
        #expect(reading.thermalPressure == .fair)
    }

    @Test func noCPUOrGPUValueMeansNoReading() {
        #expect(TemperatureAggregator.reading([(.cpu, 0), (.battery, 30)], thermal: .nominal) == nil)
    }
}
