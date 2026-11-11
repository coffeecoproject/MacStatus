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

    @Test func elapsedTimeGrowsCoarser() {
        #expect(Format.elapsed(-5) == "不到 1 分钟")
        #expect(Format.elapsed(59) == "不到 1 分钟")
        #expect(Format.elapsed(3 * 60) == "3 分钟")
        #expect(Format.elapsed(115 * 60) == "1 小时 55 分")
        #expect(Format.elapsed((52 * 60 + 10) * 60) == "2 天 4 小时")
    }

    @Test func compactRatesFitTheMenuBar() {
        #expect(Format.compactRate(0) == "0K")
        #expect(Format.compactRate(35_400) == "35K")
        #expect(Format.compactRate(999_400) == "999K")
        #expect(Format.compactRate(999_600) == "1.0M")
        #expect(Format.compactRate(1_240_000) == "1.2M")
        #expect(Format.compactRate(9_960_000) == "10M")
        #expect(Format.compactRate(125_000_000) == "125M")
        #expect(Format.compactRate(2_500_000_000) == "2.5G")
    }
}
