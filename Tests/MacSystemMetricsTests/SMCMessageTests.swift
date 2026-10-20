import Testing
@testable import MacSystemMetrics

struct SMCMessageTests {
    @Test func requestsUseTheReadOnlyWireLayout() {
        let info = SMCMessage(command: .keyInfo, key: "Tp01")
        #expect(info.bytes.count == 80)
        #expect(Array(info.bytes[0..<4]) == [0x31, 0x30, 0x70, 0x54])
        #expect(info.bytes[42] == 9)
        #expect(info.bytes[48..<80].allSatisfy { $0 == 0 })

        let read = SMCMessage(command: .readBytes, key: "Tp01", dataSize: 4)
        #expect(read.bytes[42] == 5)
        #expect(Array(read.bytes[28..<32]) == [4, 0, 0, 0])

        let byIndex = SMCMessage(command: .keyAtIndex, index: 0x0102)
        #expect(byIndex.bytes[42] == 8)
        #expect(Array(byIndex.bytes[44..<48]) == [2, 1, 0, 0])
    }

    @Test func keyCodesRoundTrip() {
        #expect(SMCMessage.key(SMCMessage.code("TB0T")) == "TB0T")
    }

    @Test func decodesFloatAndBigEndianPayloads() {
        var response = SMCMessage()
        // IEEE-754 float 67.25 = 0x42868000, little-endian in the payload.
        response.bytes.replaceSubrange(48..<52, with: [0x00, 0x80, 0x86, 0x42])
        #expect(response.float == 67.25)

        response.bytes.replaceSubrange(48..<52, with: [0x00, 0x00, 0x06, 0x82])
        #expect(response.bigEndianWord == 1_666)
    }

    @Test func readsKeyInfoFields() {
        var response = SMCMessage()
        response.bytes[28] = 4
        response.bytes.replaceSubrange(32..<36, with: [0x20, 0x74, 0x6C, 0x66])
        #expect(response.dataSize == 4)
        #expect(response.dataType == SMCMessage.floatType)
    }

    @Test(arguments: [0, 48, 79, 81])
    func unexpectedResponseSizeIsRejected(size: Int) {
        #expect(throws: MetricError.invalidData) {
            try SMCMessage().validate(reportedSize: size)
        }
    }

    @Test func smcResultCodeIsAFailure() {
        var response = SMCMessage()
        response.bytes[40] = 132
        #expect(throws: MetricError.systemFailure(code: 132)) {
            try response.validate(reportedSize: 80)
        }
    }
}
