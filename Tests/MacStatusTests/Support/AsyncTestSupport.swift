import Foundation

enum ProbeError: Error {
    case timeout
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(3),
    _ condition: @MainActor () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw ProbeError.timeout }
        try await Task.sleep(for: .milliseconds(20))
    }
}
