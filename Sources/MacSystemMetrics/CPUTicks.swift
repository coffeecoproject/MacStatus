struct CPUTicks: Sendable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func busyFraction(since previous: CPUTicks) -> Double? {
        // Mach's cumulative 32-bit counters can wrap on long uptimes.
        let userDelta = UInt64(user &- previous.user)
        let systemDelta = UInt64(system &- previous.system)
        let idleDelta = UInt64(idle &- previous.idle)
        let niceDelta = UInt64(nice &- previous.nice)
        let busy = userDelta + systemDelta + niceDelta
        let total = busy + idleDelta
        guard total > 0 else { return nil }
        return Double(busy) / Double(total)
    }
}
