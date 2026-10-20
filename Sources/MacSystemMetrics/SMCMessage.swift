// Undocumented AppleSMC wire layout. Explicit offsets avoid Swift struct ABI assumptions.
struct SMCMessage {
    enum Command: UInt8 {
        case readBytes = 5
        case keyAtIndex = 8
        case keyInfo = 9
    }

    static let byteCount = 80
    static let floatType: UInt32 = 0x666C7420 // "flt "

    var bytes = [UInt8](repeating: 0, count: SMCMessage.byteCount)

    init() {}

    init(command: Command, key: String? = nil, dataSize: UInt32 = 0, index: UInt32 = 0) {
        if let key { store(Self.code(key), at: 0) }
        store(dataSize, at: 28)
        bytes[42] = command.rawValue
        store(index, at: 44)
    }

    static func code(_ key: String) -> UInt32 {
        precondition(key.utf8.count == 4)
        return key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    static func key(_ code: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, as: UTF8.self)
    }

    var keyCode: UInt32 { word(at: 0) }
    var dataSize: UInt32 { word(at: 28) }
    var dataType: UInt32 { word(at: 32) }

    var float: Double {
        Double(Float(bitPattern: word(at: 48)))
    }

    /// SMC integer payloads ("ui32") are big-endian.
    var bigEndianWord: UInt32 {
        bytes[48..<52].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    func validate(reportedSize: Int) throws(MetricError) {
        guard reportedSize == Self.byteCount, bytes.count == Self.byteCount else {
            throw .invalidData
        }
        guard bytes[40] == 0 else { throw .systemFailure(code: Int32(bytes[40])) }
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
