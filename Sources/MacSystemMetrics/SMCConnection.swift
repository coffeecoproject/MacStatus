import IOKit
import MacStatusCore

// Scoped to one sampling round so failed reads and sleep never retain a stale connection.
final class SMCConnection {
    private let port: io_connect_t

    init() throws(TemperatureReadError) {
        guard let matching = IOServiceMatching("AppleSMC") else {
            throw .serviceUnavailable
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { throw .serviceUnavailable }
        defer { _ = IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw .systemFailure(code: result) }
        guard connection != IO_OBJECT_NULL else { throw .invalidResponse }
        port = connection
    }

    func readTemperature(key: String) throws(TemperatureReadError) -> Double {
        let info = try call(SMCMessage(key: key, command: .keyInfo), key: key)
        try info.requireFloat(key: key)
        let reading = try call(
            SMCMessage(key: key, command: .bytes, dataSize: info.dataSize), key: key
        )
        return reading.celsius
    }

    private func call(
        _ request: SMCMessage, key: String
    ) throws(TemperatureReadError) -> SMCMessage {
        var response = SMCMessage()
        var size = SMCMessage.byteCount
        let result = request.bytes.withUnsafeBytes { input in
            response.bytes.withUnsafeMutableBytes { output in
                IOConnectCallStructMethod(port, 2, input.baseAddress, input.count, output.baseAddress, &size)
            }
        }
        guard result == kIOReturnSuccess else { throw .systemFailure(code: result) }
        try response.validate(reportedSize: size, key: key)
        return response
    }

    deinit {
        _ = IOServiceClose(port)
    }
}
