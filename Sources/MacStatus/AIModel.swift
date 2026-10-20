import Foundation

/// A tool's usage limits. The last reading is kept while later reads fail, so a passing error does not hide it.
struct QuotaState: Equatable {
    var reading: QuotaReading?
    var issue: QuotaIssue?
    var isUpdating = false

    mutating func apply(_ result: Result<QuotaReading, QuotaIssue>) {
        switch result {
        case .success(let reading):
            self.reading = reading
            issue = nil
        case .failure(let issue):
            self.issue = issue
        }
        isUpdating = false
    }
}

/// Usage limits and running sessions of the AI coding tools; read only while the AI page is open.
@MainActor
final class AIModel: ObservableObject {
    static let sessionInterval: Duration = .seconds(2)
    /// Reading the newest Codex log is cheap; it changes only when Codex is used.
    static let codexInterval: TimeInterval = 30
    /// The usage endpoint is rate limited.
    static let claudeInterval: TimeInterval = 300

    @Published private(set) var sessions: MetricState<[AgentSession]> = .loading
    @Published private(set) var codex = QuotaState()
    @Published private(set) var claude = QuotaState()

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var loop: Task<Void, Never>?
    private var codexAttemptedAt: Date?
    private var claudeAttemptedAt: Date?

    /// Sessions are read before returning, so they are part of the size the panel opens at.
    func setActive(_ active: Bool) {
        guard active != (loop != nil) else { return }
        guard active else {
            loop?.cancel()
            loop = nil
            return
        }
        refreshSessions()
        loop = Task {
            while !Task.isCancelled {
                refreshQuotasIfDue()
                try? await Task.sleep(for: Self.sessionInterval)
                guard !Task.isCancelled else { return }
                refreshSessions()
            }
        }
    }

    /// Asks again after keychain access was refused or a query failed.
    func retryClaude() {
        refreshClaude()
    }

    private func refreshSessions() {
        do {
            sessions = .ready(try ClaudeSessions.read(home: home))
        } catch {
            sessions = .unavailable
        }
    }

    private func refreshQuotasIfDue() {
        let now = Date()
        if !codex.isUpdating, codexAttemptedAt.map({ now.timeIntervalSince($0) >= Self.codexInterval }) ?? true {
            refreshCodex()
        }
        // After a refusal the prompt would come back every few minutes; only the retry button asks again.
        if !claude.isUpdating, claude.issue != .denied,
           claudeAttemptedAt.map({ now.timeIntervalSince($0) >= Self.claudeInterval }) ?? true {
            refreshClaude()
        }
    }

    private func refreshCodex() {
        codexAttemptedAt = Date()
        codex.isUpdating = true
        let home = home
        Task {
            // The user is looking at the page; utility I/O is throttled to minutes under load.
            let result = await Task.detached(priority: .userInitiated) { CodexQuota.read(home: home) }.value
            codex.apply(result)
        }
    }

    private func refreshClaude() {
        guard !claude.isUpdating else { return }
        claudeAttemptedAt = Date()
        claude.isUpdating = true
        Task {
            claude.apply(await ClaudeQuota.fetch())
        }
    }
}
