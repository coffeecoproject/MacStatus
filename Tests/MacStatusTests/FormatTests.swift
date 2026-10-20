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

    @Test func windowsAndElapsedTimeReadNaturally() {
        #expect(Format.window(minutes: 300) == "5 小时")
        #expect(Format.window(minutes: 10080) == "7 天")
        #expect(Format.window(minutes: 45) == "45 分钟")
        #expect(Format.elapsed(30) == "不到 1 分钟")
        #expect(Format.elapsed(3 * 60 + 59) == "3 分钟")
        #expect(Format.elapsed(115 * 60) == "1 小时 55 分")
        #expect(Format.age(59) == "刚刚")
        #expect(Format.age(3 * 60) == "3 分钟前")
        #expect(Format.age(4 * 3600 + 120) == "4 小时前")
        #expect(Format.age(2 * 86400) == "2 天前")
    }
}
