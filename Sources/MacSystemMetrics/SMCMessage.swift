import MacStatusCore

// Undocumented AppleSMC wire layout. Explicit offsets avoid Swift struct ABI assumptions.
struct SMCMessage {
    enum ReadCommand: UInt8 {
        case keyInfo = 9
        case bytes = 5
    }

    static let byteCount = 80
    var bytes = [UInt8](repeating: 0, count: SMCMessage.byteCount)

    init() {}

    init(key: String, command: ReadCommand, dataSize: UInt32 = 0) {
        precondition(key.utf8.count == 4)
        let code = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        store(code, at: 0)
        store(dataSize, at: 28)
        bytes[42] = command.rawValue
    }

    var dataSize: UInt32 { word(at: 28) }

    func validate(reportedSize: Int, key: String) throws(TemperatureReadError) {
        guard reportedSize == Self.byteCount, bytes.count == Self.byteCount else {
            throw .invalidResponse
        }
        guard bytes[40] == 0 else {
            throw .sensorFailure(key: key, code: bytes[40])
        }
    }

    func requireFloat(key: String) throws(TemperatureReadError) {
        guard dataSize == 4, word(at: 32) == 0x666C7420 /* flt */ else {
            throw .unsupportedFormat(key: key)
        }
    }

    var celsius: Double {
        Double(Float(bitPattern: word(at: 48)))
    }

    private func word(at offset: Int) -> UInt32 {
        bytes.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }

    private mutating func store(_ value: UInt32, at offset: Int) {
        withUnsafeBytes(of: value.littleEndian) {
            bytes.replaceSubrange(offset..<(offset + 4), with: $0)
        }
    }
}
