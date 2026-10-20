import MacStatusCore

enum CPUTemperatureSensors {
    // Confirmed performance-core sensors on this Mac. No guessed or PMU keys.
    static let model = "Mac14,15"
    static let keys = ["Tp01", "Tp05", "Tp09", "Tp0D"]

    static func requireSupportedModel(_ candidate: String) throws(TemperatureReadError) {
        guard candidate == model else { throw .unsupportedModel }
    }

    static func maximum(_ values: [Double]) throws(TemperatureReadError) -> Double {
        guard values.count == keys.count, let highest = values.max() else {
            throw .invalidResponse
        }
        // Reject sentinel/corrupt readings, not clamp them into plausible values.
        guard values.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 150 }) else {
            throw .invalidValue
        }
        return highest
    }
}
