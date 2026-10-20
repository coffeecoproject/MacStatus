import MacStatusCore
import Testing
@testable import MacSystemMetrics

struct CPUTemperatureSensorsTests {
    @Test func onlyConfirmedModelAndKeysAreUsed() throws {
        try CPUTemperatureSensors.requireSupportedModel("Mac14,15")
        #expect(CPUTemperatureSensors.keys == ["Tp01", "Tp05", "Tp09", "Tp0D"])
    }

    @Test(arguments: ["Mac14,2", "MacBookAir10,1", "Mac16,1", ""])
    func otherModelsAreNotGuessed(model: String) {
        #expect(throws: TemperatureReadError.unsupportedModel) {
            try CPUTemperatureSensors.requireSupportedModel(model)
        }
    }

    @Test func reportsTheMaximumNotTheAverage() throws {
        #expect(try CPUTemperatureSensors.maximum([65.1, 67.25, 62, 63]) == 67.25)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1, 0, 150, 300])
    func oneInvalidSensorInvalidatesTheWholeReading(value: Double) {
        #expect(throws: TemperatureReadError.invalidValue) {
            try CPUTemperatureSensors.maximum([60, value, 65, 66])
        }
    }

    @Test(arguments: [[], [60.0], [60, 61, 62], [60, 61, 62, 63, 64]])
    func missingOrAdditionalSensorsAreNotSilentlyAccepted(values: [Double]) {
        #expect(throws: TemperatureReadError.invalidResponse) {
            try CPUTemperatureSensors.maximum(values)
        }
    }
}
