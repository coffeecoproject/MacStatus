public protocol CPUSampling: Sendable {
    /// Returns nil until two usable counter snapshots are available.
    func sample() async throws(CPUReadError) -> CPUUsage?

    /// Discards the baseline, notably after system sleep or a sampling failure.
    func reset() async
}
