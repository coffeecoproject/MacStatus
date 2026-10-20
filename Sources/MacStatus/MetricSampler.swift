import Foundation

// Owns one collector's task and deadlines, but never stores the displayed reading.
@MainActor
final class MetricSampler<Value: Sendable, Failure: Error & Sendable> {
    typealias Read = @Sendable (_ reset: Bool) async -> Result<Value, Failure>

    var onResult: (@MainActor (Result<Value, Failure>) -> Void)?
    var interval: Duration

    private let policy: SamplingPolicy
    private let read: Read
    private let isBaseline: (Value) -> Bool
    private let timeoutError: Failure
    private let staleError: Failure
    private var isRunning = false
    private var generation = UUID()
    private var needsReset = true
    private var request: Request?
    private var validUntil: ContinuousClock.Instant?
    private var operationTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?

    private struct Request: Sendable {
        let id: UUID
        let generation: UUID
        let deadline: ContinuousClock.Instant
        var timedOut = false
    }

    init(
        policy: SamplingPolicy,
        timeoutError: Failure,
        staleError: Failure,
        isBaseline: @escaping (Value) -> Bool = { _ in false },
        read: @escaping Read
    ) {
        self.policy = policy
        self.timeoutError = timeoutError
        self.staleError = staleError
        self.isBaseline = isBaseline
        self.read = read
        interval = policy.collapsedInterval
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        generation = UUID()
        needsReset = true
        if let request {
            // A non-cancellable old call keeps only its own slot occupied.
            armTimeout(for: request)
        } else {
            beginRequest()
        }
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        generation = UUID()
        needsReset = true
        wakeTask?.cancel()
        wakeTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        clearExpiry()
        operationTask?.cancel()
        // Keep the slot until the call actually returns; cancellation is not completion.
    }

    private func beginRequest() {
        guard isRunning, request == nil else { return }
        wakeTask = nil
        let activation = generation
        expireIfNeeded()
        guard isRunning, generation == activation, request == nil else { return }

        let request = Request(
            id: UUID(), generation: generation,
            deadline: .now.advanced(by: policy.readTimeout)
        )
        self.request = request
        let reset = needsReset
        needsReset = false
        armTimeout(for: request)

        // An unstructured, tracked task lets the deadline fire without joining
        // a collector that ignores cancellation. At most one call is in flight.
        operationTask = Task.detached(priority: .utility) { [weak self, read] in
            guard !Task.isCancelled else {
                await self?.finish(requestID: request.id, result: nil)
                return
            }
            let result = await read(reset)
            await self?.finish(requestID: request.id, result: result)
        }
    }

    private func finish(requestID: UUID, result: Result<Value, Failure>?) {
        guard let request, request.id == requestID else { return }
        self.request = nil
        operationTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        guard isRunning else { return }

        guard request.generation == generation, !request.timedOut, let result else {
            scheduleNext(after: .zero)
            return
        }
        // Timer delivery can be late. Never accept an overdue result just
        // because its completion callback ran before the timeout callback.
        guard ContinuousClock.now < request.deadline else {
            needsReset = true
            clearExpiry()
            scheduleNext(after: .zero)
            onResult?(.failure(timeoutError))
            return
        }

        let delay: Duration
        switch result {
        case .success(let value) where isBaseline(value):
            clearExpiry()
            delay = policy.baselineInterval
        case .success:
            armExpiry()
            delay = interval
        case .failure:
            clearExpiry()
            delay = interval
        }
        // Prepare internal state before publishing; a consumer may pause us.
        scheduleNext(after: delay)
        onResult?(result)
    }

    private func scheduleNext(after delay: Duration) {
        wakeTask?.cancel()
        let activation = generation
        let deadline = ContinuousClock.now.advanced(by: delay)
        wakeTask = Task { [weak self] in
            do {
                try await Task.sleep(until: deadline, clock: .continuous)
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  self.isRunning, self.generation == activation else { return }
            self.beginRequest()
        }
    }

    private func armTimeout(for request: Request) {
        timeoutTask?.cancel()
        let activation = generation
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(until: request.deadline, clock: .continuous)
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  self.isRunning, self.generation == activation,
                  self.request?.id == request.id else { return }
            self.request?.timedOut = true
            self.needsReset = true
            self.timeoutTask = nil
            self.operationTask?.cancel()
            self.clearExpiry()
            self.onResult?(.failure(self.timeoutError))
        }
    }

    private func armExpiry() {
        clearExpiry()
        let activation = generation
        let deadline = ContinuousClock.now.advanced(by: policy.maximumAge)
        validUntil = deadline
        expiryTask = Task { [weak self] in
            do {
                try await Task.sleep(until: deadline, clock: .continuous)
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  self.isRunning, self.generation == activation,
                  self.validUntil == deadline else { return }
            self.expireIfNeeded()
        }
    }

    private func expireIfNeeded() {
        guard let validUntil, ContinuousClock.now >= validUntil else { return }
        clearExpiry()
        needsReset = true
        onResult?(.failure(staleError))
    }

    private func clearExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        validUntil = nil
    }

    deinit {
        operationTask?.cancel()
        wakeTask?.cancel()
        timeoutTask?.cancel()
        expiryTask?.cancel()
    }
}
