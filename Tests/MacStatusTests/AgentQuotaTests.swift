import Foundation
import Testing
@testable import MacStatus

struct CodexQuotaTests {
    private func tokenCount(at time: String, used: Double, resetsAt: Int, credits: String = #"{"has_credits":true,"unlimited":false,"balance":"45042.05"}"#) -> String {
        #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":\#(used),"window_minutes":10080,"resets_at":\#(resetsAt)},"secondary":null,"credits":\#(credits),"plan_type":"pro"}}}"#
    }

    @Test func takesTheLastRateLimitsInTheLog() throws {
        let log = [
            // Cut off where the tail starts.
            #"ent_msg","payload":{"rate_limits":{"primary""#,
            tokenCount(at: "2026-10-20T06:26:10.482Z", used: 8, resetsAt: 1_792_896_056),
            tokenCount(at: "2026-10-20T06:30:00Z", used: 9.5, resetsAt: 1_792_896_056),
            #"{"timestamp":"2026-10-20T06:31:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":null}}"#,
            #"{"timestamp":"2026-10-20T06:32:00Z","type":"response_item","payload":{"type":"message"}}"#
        ].joined(separator: "\n")

        let reading = try #require(CodexQuota.reading(fromLog: log))
        #expect(reading.windows == [QuotaWindow(minutes: 10080, used: 0.095, resetsAt: Date(timeIntervalSince1970: 1_792_896_056))])
        #expect(reading.credits == 45042.05)
        #expect(reading.reportedAt == (try Date("2026-10-20T06:30:00Z", strategy: .iso8601)))
    }

    @Test func noCreditsWhenNoneOrUnlimited() throws {
        let none = tokenCount(at: "2026-10-20T06:30:00Z", used: 1, resetsAt: 0, credits: #"{"has_credits":false,"unlimited":false,"balance":"0"}"#)
        let unlimited = tokenCount(at: "2026-10-20T06:30:00Z", used: 1, resetsAt: 0, credits: #"{"has_credits":true,"unlimited":true,"balance":null}"#)
        #expect(try #require(CodexQuota.reading(fromLog: none)).credits == nil)
        #expect(try #require(CodexQuota.reading(fromLog: unlimited)).credits == nil)
    }

    @Test func aLogWithoutLimitsHasNoReading() {
        #expect(CodexQuota.reading(fromLog: #"{"timestamp":"2026-10-20T06:32:00Z","type":"session_meta","payload":{}}"#) == nil)
    }

    @Test func readsTheNewestLogThatHasLimits() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let day = home.appending(path: "\(CodexQuota.sessionsPath)/2026/10/20")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let older = day.appending(path: "rollout-a.jsonl")
        let newest = day.appending(path: "rollout-b.jsonl")
        try tokenCount(at: "2026-10-20T05:00:00Z", used: 7, resetsAt: 0).write(to: older, atomically: true, encoding: .utf8)
        // Just started, no turn yet.
        try #"{"type":"session_meta","payload":{}}"#.write(to: newest, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: older.path)

        let reading = try CodexQuota.read(home: home).get()
        #expect(reading.windows.map(\.used) == [0.07])
    }

    @Test func noLogsIsUnavailable() {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        guard case .failure(.unavailable) = CodexQuota.read(home: home) else {
            Issue.record("expected unavailable")
            return
        }
    }
}

struct ClaudeQuotaTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func credentials(expiresAt: Double?) -> Data {
        let expiry = expiresAt.map { #","expiresAt":\#(Int64($0 * 1000))"# } ?? ""
        return Data(#"{"claudeAiOauth":{"accessToken":"token","refreshToken":"refresh"\#(expiry),"scopes":["user:inference"]}}"#.utf8)
    }

    @Test func readsTheTokenAndWhenItExpires() throws {
        let token = try ClaudeQuota.accessToken(fromCredentials: credentials(expiresAt: now.timeIntervalSince1970 + 60)).get()
        #expect(token.value == "token")
        #expect(!token.hasExpired(at: now))
        #expect(token.hasExpired(at: now.addingTimeInterval(60)))
        let lasting = try ClaudeQuota.accessToken(fromCredentials: credentials(expiresAt: nil)).get()
        #expect(lasting.expiresAt == nil)
        #expect(!lasting.hasExpired(at: now))
    }

    @Test func credentialsWithoutAClaudeSignInAreUnavailable() {
        guard case .failure(.unavailable) = ClaudeQuota.accessToken(fromCredentials: Data(#"{"other":{}}"#.utf8)) else {
            Issue.record("expected unavailable")
            return
        }
    }

    @Test func readsBothWindows() throws {
        let usage = Data(#"""
        {"five_hour":{"utilization":23.0,"resets_at":"2026-10-20T08:00:00.123456+00:00"},
         "seven_day":{"utilization":8,"resets_at":"2026-10-23T14:00:00+00:00"},
         "seven_day_opus":null,"extra_usage":{"is_enabled":false}}
        """#.utf8)
        let reading = try #require(ClaudeQuota.reading(fromUsage: usage, at: now))
        #expect(reading.windows.map(\.minutes) == [300, 10080])
        #expect(reading.windows.map(\.used) == [0.23, 0.08])
        let resetsAt = try #require(reading.windows.first?.resetsAt)
        #expect(abs(resetsAt.timeIntervalSince(try Date("2026-10-20T08:00:00Z", strategy: .iso8601))) < 1)
        #expect(reading.reportedAt == now)
    }

    @Test func missingWindowsAreLeftOutAndNoneIsNoReading() throws {
        let partial = Data(#"{"five_hour":null,"seven_day":{"utilization":50,"resets_at":null}}"#.utf8)
        #expect(try #require(ClaudeQuota.reading(fromUsage: partial, at: now)).windows == [QuotaWindow(minutes: 10080, used: 0.5, resetsAt: nil)])
        #expect(ClaudeQuota.reading(fromUsage: Data(#"{"five_hour":null,"seven_day":null}"#.utf8), at: now) == nil)
        #expect(ClaudeQuota.reading(fromUsage: Data("not json".utf8), at: now) == nil)
    }
}
