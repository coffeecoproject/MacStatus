import Foundation
import MacStatusCore

actor ProbeCPUCollector: CPUSampling {
    enum Step: Sendable {
        case baseline
        case reading(CPUUsage)
        case failure(CPUReadError)
        case held(CPUUsage)
    }

    struct Activity: Sendable {
        let samples: Int
        let resets: Int
        let maxConcurrentSamples: Int
        let sampleTimes: [ContinuousClock.Instant]
    }

    private var steps: [Step]
    private var sampleTimes: [ContinuousClock.Instant] = []
    private var resets = 0
    private var concurrentSamples = 0
    private var maxConcurrentSamples = 0
    private var heldResult: CPUUsage?
    private var continuation: CheckedContinuation<CPUUsage?, Never>?

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func reset() {
        resets += 1
    }

    func sample() async throws(CPUReadError) -> CPUUsage? {
        sampleTimes.append(.now)
        concurrentSamples += 1
        maxConcurrentSamples = max(maxConcurrentSamples, concurrentSamples)
        defer { concurrentSamples -= 1 }

        let step = steps.isEmpty
            ? .reading(CPUUsage(fraction: 0.5, sampledAt: Date()))
            : steps.removeFirst()
        switch step {
        case .baseline:
            return nil
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
        continuation?.resume(returning: heldResult)
        continuation = nil
        heldResult = nil
    }

    func activity() -> Activity {
        Activity(
            samples: sampleTimes.count,
            resets: resets,
            maxConcurrentSamples: maxConcurrentSamples,
            sampleTimes: sampleTimes
        )
    }
}
