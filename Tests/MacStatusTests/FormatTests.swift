import Testing
@testable import MacStatus

struct FormatTests {
    @Test func percentAndTemperatureRound() {
        #expect(Format.percent(0.825) == "83%")
        #expect(Format.percent(0) == "0%")
        #expect(Format.celsius(86.6) == "87°C")
    }

    @Test func loadAverageShowsThreeValuesOrPlaceholder() {
        #expect(Format.loadAverage([1, 2.5, 3.456]) == "1.00  2.50  3.46")
        #expect(Format.loadAverage([]) == Format.placeholder)
    }
}
