import MacStatusCore
import Testing
@testable import MacSystemMetrics

struct MemoryPressureReaderTests {
    @Test(arguments: [
        (Int32(1), MemoryPressure.normal),
        (Int32(2), .warning),
        (Int32(4), .critical)
    ])
    func decodesSystemLevelsWithoutGuessingFromUsage(raw: Int32, expected: MemoryPressure) {
        #expect(MemoryPressureReader.decode(raw) == .success(expected))
    }

    @Test(arguments: [Int32(0), 3, 8, -1, .max])
    func unknownValuesAreNotReportedAsNormal(raw: Int32) {
        #expect(MemoryPressureReader.decode(raw) == .failure(.unsupportedLevel(raw)))
    }
}
