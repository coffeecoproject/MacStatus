import Foundation
import MacStatusCore

actor ProbeDiskCollector: DiskSampling {
    enum Step: Sendable {
        case reading(DiskUsage)
        case failure(DiskReadError)
        case held(DiskUsage)
    }

    struct Activity: Sendable {
        let samples: Int
        let maxConcurrentSamples: Int
    }

    private var steps: [Step]
    private var samples = 0
    private var concurrentSamples = 0
    private var maxConcurrentSamples = 0
    private var heldResult: DiskUsage?
    private var continuation: CheckedContinuation<DiskUsage, Never>?

    init(_ steps: [Step] = []) {
        self.steps = steps
    }

    func sample() async throws(DiskReadError) -> DiskUsage {
        samples += 1
        concurrentSamples += 1
        maxConcurrentSamples = max(maxConcurrentSamples, concurrentSamples)
        defer { concurrentSamples -= 1 }

        let step = steps.isEmpty
            ? .reading(DiskUsage(
                usedBytes: 330 * 1_073_741_824,
                totalBytes: 500 * 1_073_741_824,
                sampledAt: Date()
            ))
            : steps.removeFirst()
        switch step {
        case .reading(let reading):
            return reading
        case .failure(let error):
            throw error
        case .held(let reading):
            heldResult = reading
            return await withCheckedContinuation { continuation = $0 }
        }
    }

    func releaseHeldSample() {
        guard let continuation, let heldResult else { return }
        self.continuation = nil
        self.heldResult = nil
        continuation.resume(returning: heldResult)
    }

    func activity() -> Activity {
        Activity(samples: samples, maxConcurrentSamples: maxConcurrentSamples)
    }
}
