import Foundation
import MacStatusCore
import Testing
@testable import MacStatus

@MainActor
struct MetricSamplerTests {
    private let reading = CPUTemperature(celsius: 60, sampledAt: Date(timeIntervalSince1970: 1_000))

    @Test func staleReadingExpiresEvenWhileWaitingForTheNextPoll() async throws {
        let collector = ProbeTemperatureCollector([.reading(reading)])
        let sampler = makeSampler(collector, policy: SamplingPolicy(
            collapsedInterval: .seconds(2), maximumAge: .milliseconds(150)
        ))
        var values: [Result<CPUTemperature, TemperatureReadError>] = []
        sampler.onResult = { values.append($0) }
        defer { sampler.pause() }
        sampler.start()
        try await waitUntil { values.contains(.failure(.staleReading)) }
        #expect(values == [.success(reading), .failure(.staleReading)])
        #expect(await collector.activity().samples == 1)
    }

    @Test func aNewReadingReplacesTheOldExpiryDeadline() async throws {
        let collector = ProbeTemperatureCollector()
        let sampler = makeSampler(collector, policy: SamplingPolicy(
            collapsedInterval: .milliseconds(60), maximumAge: .milliseconds(350)
        ))
        var failures: [TemperatureReadError] = []
        sampler.onResult = { if case .failure(let error) = $0 { failures.append(error) } }
        defer { sampler.pause() }
        sampler.start()
        try await waitUntil { await collector.activity().samples >= 9 }
        #expect(failures.isEmpty)
    }

    @Test func lateSuccessAfterTimeoutIsDiscardedWithoutAResume() async throws {
        let late = CPUTemperature(celsius: 99, sampledAt: Date(timeIntervalSince1970: 2_000))
        let collector = ProbeTemperatureCollector([.held(late), .reading(reading)])
        let sampler = makeSampler(collector, policy: SamplingPolicy(readTimeout: .milliseconds(150)))
        var values: [Result<CPUTemperature, TemperatureReadError>] = []
        sampler.onResult = { values.append($0) }
        defer {
            sampler.pause()
            Task { await collector.releaseHeldSample() }
        }
        sampler.start()
        try await waitUntil { values.contains(.failure(.timedOut)) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(await collector.activity().samples == 1)
        await collector.releaseHeldSample()
        try await waitUntil { values.contains(.success(reading)) }
        #expect(!values.contains(.success(late)))
        #expect(await collector.activity().maxConcurrentSamples == 1)
    }

    @Test func pausingCancelsAPendingDeadlineNotification() async throws {
        let collector = ProbeTemperatureCollector([.held(reading)])
        let sampler = makeSampler(collector, policy: SamplingPolicy(
            readTimeout: .seconds(1)
        ))
        var values: [Result<CPUTemperature, TemperatureReadError>] = []
        sampler.onResult = { values.append($0) }
        defer { Task { await collector.releaseHeldSample() } }
        sampler.start()
        try await waitUntil { await collector.activity().samples == 1 }
        try #require(values.isEmpty)
        sampler.pause()
        try await Task.sleep(for: .milliseconds(1_200))
        #expect(values.isEmpty)
        await collector.releaseHeldSample()
        try await Task.sleep(for: .milliseconds(50))
        #expect(values.isEmpty)
    }

    @Test func consumerCanPauseDuringPublicationWithoutRestartingTheWorker() async throws {
        let collector = ProbeTemperatureCollector()
        let sampler = makeSampler(collector, policy: SamplingPolicy(
            collapsedInterval: .milliseconds(50), maximumAge: .milliseconds(100)
        ))
        var publications = 0
        sampler.onResult = { [weak sampler] _ in
            publications += 1
            sampler?.pause()
        }
        sampler.start()
        try await waitUntil { publications > 0 }
        try await Task.sleep(for: .milliseconds(200))
        #expect(publications == 1)
        #expect(await collector.activity().samples == 1)
    }

    private func makeSampler(
        _ collector: ProbeTemperatureCollector, policy: SamplingPolicy
    ) -> MetricSampler<CPUTemperature, TemperatureReadError> {
        MetricSampler(policy: policy, timeoutError: .timedOut, staleError: .staleReading) { _ in
            do throws(TemperatureReadError) {
                return .success(try await collector.sample())
            } catch {
                return .failure(error)
            }
        }
    }
}
