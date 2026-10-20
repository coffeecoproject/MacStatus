import MacStatusCore
import Testing
@testable import MacSystemMetrics

struct SMCMessageTests {
    @Test func requestsUseTheConfirmedReadOnlyWireLayout() {
        let info = SMCMessage(key: "Tp01", command: .keyInfo)
        #expect(info.bytes.count == 80)
        #expect(Array(info.bytes[0..<4]) == [0x31, 0x30, 0x70, 0x54])
        #expect(info.bytes[42] == 9)
        #expect(info.dataSize == 0)
        #expect(info.bytes[48..<80].allSatisfy { $0 == 0 })

        let read = SMCMessage(key: "Tp01", command: .bytes, dataSize: 4)
        #expect(read.bytes[42] == 5)
        #expect(Array(read.bytes[28..<32]) == [4, 0, 0, 0])
    }

    @Test func decodesLittleEndianFloatWithoutStructCasting() throws {
        var response = floatResponse()
        // IEEE-754 float 67.25 = 0x42868000.
        response.bytes.replaceSubrange(48..<52, with: [0x00, 0x80, 0x86, 0x42])
        try response.validate(reportedSize: 80, key: "Tp01")
        try response.requireFloat(key: "Tp01")
        #expect(response.celsius == 67.25)
    }

    @Test(arguments: [0, 48, 79, 81])
    func unexpectedResponseSizeIsRejected(size: Int) {
        #expect(throws: TemperatureReadError.invalidResponse) {
            try SMCMessage().validate(reportedSize: size, key: "Tp01")
        }
    }

    @Test func truncatedStorageIsRejectedBeforeDecoding() {
        var response = SMCMessage()
        response.bytes = []
        #expect(throws: TemperatureReadError.invalidResponse) {
            try response.validate(reportedSize: 80, key: "Tp01")
        }
    }

    @Test func smcErrorIsNotMistakenForASuccessfulKernelCall() {
        var response = SMCMessage()
        response.bytes[40] = 132
        #expect(throws: TemperatureReadError.sensorFailure(key: "Tp01", code: 132)) {
            try response.validate(reportedSize: 80, key: "Tp01")
        }
    }

    @Test func unknownFormatIsNotReinterpretedAsTemperature() {
        var response = floatResponse()
        response.bytes[32] = 0
        #expect(throws: TemperatureReadError.unsupportedFormat(key: "Tp01")) {
            try response.requireFloat(key: "Tp01")
        }
    }

    @Test func wrongFloatLengthIsRejected() {
        var response = floatResponse()
        response.bytes[28] = 8
        #expect(throws: TemperatureReadError.unsupportedFormat(key: "Tp01")) {
            try response.requireFloat(key: "Tp01")
        }
    }

    private func floatResponse() -> SMCMessage {
        var response = SMCMessage()
        response.bytes[28] = 4
        response.bytes.replaceSubrange(32..<36, with: [0x20, 0x74, 0x6C, 0x66])
        return response
    }
}
