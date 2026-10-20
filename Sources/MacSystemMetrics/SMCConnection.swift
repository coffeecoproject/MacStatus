import IOKit

/// Read-only AppleSMC client. Never writes hardware parameters.
final class SMCConnection {
    private let port: io_connect_t

    init() throws(MetricError) {
        guard let matching = IOServiceMatching("AppleSMC") else { throw .unavailable }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { throw .unavailable }
        defer { _ = IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw .systemFailure(code: result) }
        guard connection != IO_OBJECT_NULL else { throw .invalidData }
        port = connection
    }

    func keyCount() throws(MetricError) -> Int {
        let info = try call(SMCMessage(command: .keyInfo, key: "#KEY"))
        let value = try call(SMCMessage(command: .readBytes, key: "#KEY", dataSize: info.dataSize))
        return Int(value.bigEndianWord)
    }

    func key(at index: Int) throws(MetricError) -> String {
        SMCMessage.key(try call(SMCMessage(command: .keyAtIndex, index: UInt32(index))).keyCode)
    }

    func info(for key: String) throws(MetricError) -> (size: UInt32, type: UInt32) {
        let info = try call(SMCMessage(command: .keyInfo, key: key))
        return (info.dataSize, info.dataType)
    }

    /// Reads a 4-byte "flt " key; callers check the type once via `info(for:)`.
    func float(for key: String) throws(MetricError) -> Double {
        try call(SMCMessage(command: .readBytes, key: key, dataSize: 4)).float
    }

    private func call(_ request: SMCMessage) throws(MetricError) -> SMCMessage {
        var response = SMCMessage()
        var size = SMCMessage.byteCount
        let result = request.bytes.withUnsafeBytes { input in
            response.bytes.withUnsafeMutableBytes { output in
                IOConnectCallStructMethod(port, 2, input.baseAddress, input.count, output.baseAddress, &size)
            }
        }
        guard result == kIOReturnSuccess else { throw .systemFailure(code: result) }
        try response.validate(reportedSize: size)
        return response
    }

    deinit {
        _ = IOServiceClose(port)
    }
}
