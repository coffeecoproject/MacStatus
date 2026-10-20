import Darwin
import MacStatusCore

enum MemoryPressureReader {
    static func read() -> Result<MemoryPressure, MemoryPressureReadError> {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        guard result == 0 else {
            return .failure(.systemFailure(code: errno))
        }
        guard size == MemoryLayout<Int32>.size else {
            return .failure(.incompleteValue)
        }
        return decode(level)
    }

    static func decode(_ level: Int32) -> Result<MemoryPressure, MemoryPressureReadError> {
        switch level {
        case 1: .success(.normal)
        case 2: .success(.warning)
        case 4: .success(.critical)
        default: .failure(.unsupportedLevel(level))
        }
    }
}
