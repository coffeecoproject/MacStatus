import Darwin
import Testing
@testable import MacSystemMetrics

struct NetworkTests {
    private typealias Counts = NetworkCounters.Counts

    @Test func ratesAreSummedPerInterfaceInBytesPerSecond() throws {
        let previous = NetworkCounters(interfaces: [
            "en0": Counts(received: 1_000, sent: 500),
            "en1": Counts(received: 0, sent: 0)
        ])
        let current = NetworkCounters(interfaces: [
            "en0": Counts(received: 5_000, sent: 1_500),
            "en1": Counts(received: 2_000, sent: 500)
        ])
        let rates = try #require(current.rates(since: previous, elapsed: 2))
        #expect(rates.download == 3_000)
        #expect(rates.upload == 750)
    }

    @Test func anInterfaceThatAppearedOrWasResetAddsNothing() throws {
        let previous = NetworkCounters(interfaces: [
            "en0": Counts(received: 1_000, sent: 1_000),
            "en5": Counts(received: 9_000, sent: 9_000)
        ])
        let current = NetworkCounters(interfaces: [
            "en0": Counts(received: 2_000, sent: 1_000),
            // Reset when it went down and up again.
            "en5": Counts(received: 10, sent: 10),
            // Plugged in since: its lifetime total is not traffic of the last interval.
            "en7": Counts(received: 50_000_000, sent: 50_000_000)
        ])
        let rates = try #require(current.rates(since: previous, elapsed: 1))
        #expect(rates.download == 1_000)
        #expect(rates.upload == 0)
        #expect(current.rates(since: previous, elapsed: 0) == nil)
    }

    @Test func aggregatesOfOtherInterfacesAreNotCounted() {
        let interfaces = [
            NetworkHardware(bsdName: "en0", displayName: "Wi-Fi", type: "IEEE80211", index: 1),
            NetworkHardware(bsdName: "en1", displayName: "Thunderbolt 1", type: "Ethernet", index: 1),
            NetworkHardware(bsdName: "bridge0", displayName: "Thunderbolt Bridge", type: "Bridge", index: 1),
            NetworkHardware(bsdName: "bond0", displayName: "Bond", type: "Bond", index: 1),
            NetworkHardware(bsdName: "vlan0", displayName: "VLAN", type: "VLAN", index: 1)
        ]
        #expect(NetworkHardware.countable(interfaces).map(\.bsdName) == ["en0", "en1"])
    }

    @Test func theConnectionIsNamedAfterTheHardwareOfTheDefaultRoute() {
        let hardware = [NetworkHardware(bsdName: "en0", displayName: "Wi-Fi", type: "IEEE80211", index: 1)]
        #expect(NetworkReader.connection(primary: "en0", hardware: hardware) == .hardware("Wi-Fi"))
        #expect(NetworkReader.connection(primary: "utun4", hardware: hardware) == .other)
        #expect(NetworkReader.connection(primary: nil, hardware: hardware) == .offline)
    }

    /// Reads the kernel's counters for real. Loopback exists on every Mac and carries the system's own
    /// traffic, so its counters are nonzero and only grow.
    @Test func readsTheCountersOfTheGivenInterfaces() throws {
        let loopback = NetworkHardware(bsdName: "lo0", displayName: "lo0", type: "Loopback", index: if_nametoindex("lo0"))
        let first = try #require(NetworkCounters.current(of: [loopback]).interfaces["lo0"])
        let again = NetworkCounters.current(of: [loopback])
        let second = try #require(again.interfaces["lo0"])
        #expect(Array(again.interfaces.keys) == ["lo0"])
        #expect(first.received > 0 && first.sent > 0)
        #expect(second.received >= first.received && second.sent >= first.sent)
    }

    /// An index the kernel has since given to another interface is not read as this one.
    @Test func skipsAnInterfaceWhoseIndexNoLongerMatchesItsName() {
        let stale = NetworkHardware(bsdName: "en99", displayName: "Gone", type: "Ethernet", index: if_nametoindex("lo0"))
        #expect(NetworkCounters.current(of: [stale]).interfaces.isEmpty)
    }
}
