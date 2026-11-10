import Darwin
import Foundation
import SystemConfiguration

public struct NetworkReading: Sendable, Equatable {
    /// Bytes per second across the network hardware; nil until a baseline exists.
    public let downloadRate: Double?
    public let uploadRate: Double?
    public let connection: NetworkConnection
}

public enum NetworkConnection: Sendable, Equatable {
    /// The default route goes over this hardware, by its name in System Settings ("Wi-Fi").
    case hardware(String)
    /// The default route goes over something else, such as a VPN tunnel.
    case other
    case offline
}

/// A network interface backed by hardware, as System Settings lists them.
struct NetworkHardware: Sendable, Equatable {
    let bsdName: String
    let displayName: String
    let type: String
    /// The kernel's index for the interface, which its counters are read by.
    let index: UInt32

    /// Bridges, bonds and VLANs carry their member interfaces' traffic, so counting them would count it twice.
    static func countable(_ interfaces: [NetworkHardware]) -> [NetworkHardware] {
        let aggregates: Set<String> = [
            // The SDK keeps the bridge type's constant private; this is its value, as Thunderbolt Bridge reports.
            "Bridge",
            kSCNetworkInterfaceTypeBond as String,
            kSCNetworkInterfaceTypeVLAN as String
        ]
        return interfaces.filter { !aggregates.contains($0.type) }
    }

    static func current() -> [NetworkHardware] {
        let interfaces = (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? []
        return interfaces.compactMap { interface in
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface).map({ $0 as String }),
                  let type = SCNetworkInterfaceGetInterfaceType(interface).map({ $0 as String }) else { return nil }
            // Zero when the interface is not up in the kernel, as for an unplugged adapter.
            let index = if_nametoindex(bsdName)
            guard index != 0 else { return nil }
            let displayName = SCNetworkInterfaceGetLocalizedDisplayName(interface).map { $0 as String } ?? bsdName
            return NetworkHardware(bsdName: bsdName, displayName: displayName, type: type, index: index)
        }
    }
}

/// Bytes each interface has received and sent since it came up.
struct NetworkCounters: Sendable, Equatable {
    struct Counts: Sendable, Equatable {
        var received: UInt64
        var sent: UInt64
    }

    var interfaces: [String: Counts]

    /// Summed per interface, so one that appeared or was reset in between adds nothing rather than its
    /// whole lifetime; nil when no time elapsed.
    func rates(since previous: NetworkCounters, elapsed: Double) -> (download: Double, upload: Double)? {
        guard elapsed > 0 else { return nil }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, now) in interfaces {
            guard let before = previous.interfaces[name], now.received >= before.received, now.sent >= before.sent
            else { continue }
            received += now.received - before.received
            sent += now.sent - before.sent
        }
        return (Double(received) / elapsed, Double(sent) / elapsed)
    }

    /// Read per interface from its MIB, which has the full 64-bit counts `netstat` shows. `getifaddrs` has
    /// 32-bit ones, and the interface list (`NET_RT_IFLIST2`) wraps at 4 GB too, despite its 64-bit fields.
    static func current(of interfaces: [NetworkHardware]) -> NetworkCounters {
        var counters = NetworkCounters(interfaces: [:])
        for interface in interfaces {
            var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(interface.index), IFDATA_GENERAL]
            var data = ifmibdata()
            var size = MemoryLayout<ifmibdata>.size
            // Fails for an interface removed since it was listed; an index reused by another is told by its name.
            guard sysctl(&mib, UInt32(mib.count), &data, &size, nil, 0) == 0,
                  name(of: data) == interface.bsdName else { continue }
            counters.interfaces[interface.bsdName] = Counts(
                received: data.ifmd_data.ifi_ibytes, sent: data.ifmd_data.ifi_obytes
            )
        }
        return counters
    }

    private static func name(of data: ifmibdata) -> String {
        withUnsafeBytes(of: data.ifmd_name) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

public final class NetworkReader {
    /// Listing the hardware goes through System Configuration; it only changes when an adapter is plugged in.
    static let hardwareRefresh: Duration = .seconds(10)

    private var hardware: (interfaces: [NetworkHardware], readAt: ContinuousClock.Instant)?
    private var baseline: (counters: NetworkCounters, at: ContinuousClock.Instant)?

    public init() {}

    /// Drops the throughput baseline, e.g. after system sleep.
    public func reset() {
        baseline = nil
    }

    public func read() -> NetworkReading {
        let now = ContinuousClock.now
        let interfaces: [NetworkHardware]
        if let cached = hardware, cached.readAt.duration(to: now) < Self.hardwareRefresh {
            interfaces = cached.interfaces
        } else {
            interfaces = NetworkHardware.countable(NetworkHardware.current())
            hardware = (interfaces, now)
        }

        let counters = NetworkCounters.current(of: interfaces)
        let rates = baseline.flatMap { counters.rates(since: $0.counters, elapsed: $0.at.duration(to: now).seconds) }
        baseline = (counters, now)

        return NetworkReading(
            downloadRate: rates?.download,
            uploadRate: rates?.upload,
            connection: Self.connection(primary: Self.primaryInterface(), hardware: interfaces)
        )
    }

    static func connection(primary: String?, hardware: [NetworkHardware]) -> NetworkConnection {
        guard let primary else { return .offline }
        return hardware.first { $0.bsdName == primary }.map { .hardware($0.displayName) } ?? .other
    }

    /// The interface of the default route, IPv4 first, as System Settings picks the active service.
    private static func primaryInterface() -> String? {
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            if let value = SCDynamicStoreCopyValue(nil, key as CFString) as? [String: Any],
               let interface = value[kSCDynamicStorePropNetPrimaryInterface as String] as? String {
                return interface
            }
        }
        return nil
    }
}
