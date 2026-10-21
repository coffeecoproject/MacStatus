import Foundation
import Security

/// How much of one usage-limit window has been used.
struct QuotaWindow: Equatable, Sendable, Identifiable {
    /// Length of the window: 300 for five hours, 10080 for a week.
    let minutes: Int
    /// 0...1 of the limit.
    let used: Double
    let resetsAt: Date?

    var id: Int { minutes }
}

/// Usage limits as the provider last reported them.
struct QuotaReading: Equatable, Sendable {
    let windows: [QuotaWindow]
    /// Extra Codex credits left after the plan's limits; nil when there are none.
    var credits: Double?
    /// When the provider reported it. Codex reports on each turn, so this is when Codex was last used.
    let reportedAt: Date
}

enum QuotaIssue: Error, Equatable, Sendable {
    /// Claude Code's sign-in has expired; Claude Code renews it the next time it is used.
    case expired
    /// The user refused keychain access; asking again would show the system prompt again.
    case denied
    /// Shown as is.
    case unavailable(String)
}

/// Codex writes its rate limits into the session log after each turn; the newest log has the latest.
enum CodexQuota {
    static let sessionsPath = ".codex/sessions"
    /// Covers the last turns of a long session; a turn's events are a few kilobytes.
    static let tailLength: UInt64 = 256 * 1024
    /// A log just started may have no turn yet.
    static let logsToTry = 5

    /// Lists every session log's date, so run it off the main thread.
    static func read(home: URL) -> Result<QuotaReading, QuotaIssue> {
        for log in logs(in: home.appending(path: sessionsPath)).prefix(logsToTry) {
            if let reading = (try? tail(of: log)).flatMap(reading(fromLog:)) {
                return .success(reading)
            }
        }
        return .failure(.unavailable("没有找到 Codex 的使用记录"))
    }

    /// The latest rate limits in a session log; a line cut off at the start of the tail fails to decode and is skipped.
    static func reading(fromLog text: String) -> QuotaReading? {
        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let event = try? JSONDecoder.agentLogs.decode(Event.self, from: Data(line.utf8)),
                  let limits = event.payload.rateLimits else { continue }
            let windows = [limits.primary, limits.secondary].compactMap { $0 }.map {
                QuotaWindow(
                    minutes: $0.windowMinutes,
                    used: $0.usedPercent / 100,
                    resetsAt: $0.resetsAt.map(Date.init(timeIntervalSince1970:))
                )
            }
            let credits = limits.credits.flatMap { $0.hasCredits && !$0.unlimited ? $0.balance.flatMap(Double.init) : nil }
            return QuotaReading(windows: windows.sorted { $0.minutes < $1.minutes }, credits: credits, reportedAt: event.timestamp)
        }
        return nil
    }

    /// Most recently written first.
    private static func logs(in directory: URL) -> [URL] {
        let key = URLResourceKey.contentModificationDateKey
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [key], errorHandler: { _, _ in true }
        ) else { return [] }
        let dated = enumerator.compactMap { item -> (URL, Date)? in
            guard let url = item as? URL, url.pathExtension == "jsonl",
                  let date = try? url.resourceValues(forKeys: [key]).contentModificationDate else { return nil }
            return (url, date)
        }
        return dated.sorted { $0.1 > $1.1 }.map(\.0)
    }

    private static func tail(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        try handle.seek(toOffset: end > tailLength ? end - tailLength : 0)
        return String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
    }

    private struct Event: Decodable {
        struct Payload: Decodable {
            let rateLimits: Limits?
        }

        struct Limits: Decodable {
            let primary: Window?
            let secondary: Window?
            let credits: Credits?
        }

        struct Window: Decodable {
            let usedPercent: Double
            let windowMinutes: Int
            /// Seconds since 1970.
            let resetsAt: Double?
        }

        struct Credits: Decodable {
            let hasCredits: Bool
            let unlimited: Bool
            let balance: String?
        }

        let timestamp: Date
        let payload: Payload
    }
}

/// A Claude Code access token and when it stops working.
struct ClaudeToken: Equatable, Sendable {
    let value: String
    /// Nil when the credentials give no expiry.
    let expiresAt: Date?

    func hasExpired(at date: Date) -> Bool {
        expiresAt.map { $0 <= date } ?? false
    }
}

/// Claude Code's plan limits, from the usage endpoint behind its `/usage`, signed in with Claude Code's own
/// credentials. The token is only read, never refreshed: refreshing would replace Claude Code's sign-in.
/// It is kept between queries, so the keychain, which may prompt, is read again only once the token has
/// expired or been refused.
actor ClaudeQuota {
    static let keychainService = "Claude Code-credentials"
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// No cache, so the response and credentials are not written to disk.
    private static let session = URLSession(configuration: .ephemeral)

    private var heldToken: ClaudeToken?

    func fetch() async -> Result<QuotaReading, QuotaIssue> {
        if let heldToken, !heldToken.hasExpired(at: Date()) {
            let result = await Self.usage(with: heldToken)
            // Otherwise Claude Code may have renewed its sign-in since the token was read.
            guard result == .failure(.expired) else { return result }
        }
        heldToken = nil
        let token: ClaudeToken
        switch await Self.credentials().flatMap(Self.accessToken(fromCredentials:)) {
        case .success(let value): token = value
        case .failure(let issue): return .failure(issue)
        }
        guard !token.hasExpired(at: Date()) else { return .failure(.expired) }
        let result = await Self.usage(with: token)
        if result != .failure(.expired) { heldToken = token }
        return result
    }

    static func accessToken(fromCredentials data: Data) -> Result<ClaudeToken, QuotaIssue> {
        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data),
              let oauth = credentials.claudeAiOauth else {
            return .failure(.unavailable("Claude Code 未用 Claude 账号登录"))
        }
        return .success(ClaudeToken(
            value: oauth.accessToken,
            expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        ))
    }

    private static func usage(with token: ClaudeToken) async -> Result<QuotaReading, QuotaIssue> {
        var request = URLRequest(url: usageURL, timeoutInterval: 15)
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        do {
            let (data, response) = try await session.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200:
                guard let reading = reading(fromUsage: data, at: Date()) else {
                    return .failure(.unavailable("无法识别额度数据"))
                }
                return .success(reading)
            case 401:
                return .failure(.expired)
            case 429:
                return .failure(.unavailable("查询太频繁，稍后自动重试"))
            case let code:
                return .failure(.unavailable("额度查询失败（\(code.map(String.init) ?? "无响应")）"))
            }
        } catch {
            return .failure(.unavailable("网络请求失败"))
        }
    }

    /// Nil when the response has none of the known windows.
    static func reading(fromUsage data: Data, at date: Date) -> QuotaReading? {
        guard let usage = try? JSONDecoder.agentLogs.decode(Usage.self, from: data) else { return nil }
        let windows = [(300, usage.fiveHour), (10080, usage.sevenDay)].compactMap { minutes, window in
            window?.utilization.map { QuotaWindow(minutes: minutes, used: $0 / 100, resetsAt: window?.resetsAt) }
        }
        return windows.isEmpty ? nil : QuotaReading(windows: windows, reportedAt: date)
    }

    /// The first read shows the system's keychain prompt and blocks until it is answered, so it runs on its own queue.
    private static func credentials() async -> Result<Data, QuotaIssue> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: readKeychain())
            }
        }
    }

    private static func readKeychain() -> Result<Data, QuotaIssue> {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess:
            guard let data = item as? Data else { return .failure(.unavailable("无法读取 Claude Code 登录信息")) }
            return .success(data)
        case errSecItemNotFound:
            return .failure(.unavailable("没有找到 Claude Code 登录信息"))
        case errSecUserCanceled, errSecAuthFailed:
            return .failure(.denied)
        case let status:
            return .failure(.unavailable("无法读取钥匙串（\(status)）"))
        }
    }

    private struct Credentials: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            /// Milliseconds since 1970.
            let expiresAt: Double?
        }

        let claudeAiOauth: OAuth?
    }

    private struct Usage: Decodable {
        struct Window: Decodable {
            /// Percent used.
            let utilization: Double?
            let resetsAt: Date?
        }

        let fiveHour: Window?
        let sevenDay: Window?
    }
}

extension JSONDecoder {
    /// Snake-case keys and ISO 8601 dates with or without fractional seconds, as both tools write them.
    static var agentLogs: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            try Date(decoder.singleValueContainer().decode(String.self), strategy: .iso8601)
        }
        return decoder
    }
}
