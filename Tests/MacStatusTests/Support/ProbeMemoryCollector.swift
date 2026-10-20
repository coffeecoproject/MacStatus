import Foundation
import MacStatusCore

actor ProbeMemoryCollector: MemorySampling {
    enum Step: Sendable {
        case reading(MemoryUsage)
        case failure(MemoryReadError)
        case held(MemoryUsage)
    }

    struct Activity: Sendable {
        let samples: Int
        let maxConcurrentSamples: Int
    }

    private var steps: [Step]
    private var samples = 0
    private var concurrentSamples = 0
    private var maxConcurrentSamples = 0
    private var heldResult: MemoryUsage?
    private var continuation: CheckedContinuation<MemoryUsage, Never>?

    init(_ steps: [Step] = []) {
        self.steps = steps
    }

    func sample() async throws(MemoryReadError) -> MemoryUsage {
        samples += 1
        concurrentSamples += 1
        maxConcurrentSamples = max(maxConcurrentSamples, concurrentSamples)
        defer { concurrentSamples -= 1 }

        let step = steps.isEmpty
            ? .reading(MemoryUsage(
                usedBytes: 4 * 1_073_741_824,
                totalBytes: 8 * 1_073_741_824,
                pressure: .success(.normal),
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
