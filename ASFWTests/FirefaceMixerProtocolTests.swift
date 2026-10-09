import Foundation
import Testing
@testable import ASFW

struct FirefaceMixerProtocolTests {
    @Test func addressesStayWithinFireface800MixerLayout() {
        #expect(FirefaceMixerProtocol.address(for: .input(0), destination: 0) == 0x8008_0000)
        #expect(FirefaceMixerProtocol.address(for: .playback(0), destination: 0) == 0x8008_0080)
        #expect(FirefaceMixerProtocol.address(for: .input(27), destination: 27) == 0x8008_1B6C)
        #expect(FirefaceMixerProtocol.address(for: .playback(27), destination: 27) == 0x8008_1BEC)
        #expect(FirefaceMixerProtocol.address(for: .output(27), destination: 0) == 0x8008_1FEC)
        #expect(FirefaceMixerProtocol.address(for: .input(28), destination: 0) == nil)
        #expect(FirefaceMixerProtocol.address(for: .output(0), destination: 28) == nil)
    }

    @Test func gainConversionAndWireOrder() {
        #expect(FirefaceMixerProtocol.gain(for: -90) == 0)
        #expect(FirefaceMixerProtocol.gain(for: 0) == 32_768)
        #expect(FirefaceMixerProtocol.gain(for: 6) <= 65_536)
        let bytes = FirefaceMixerProtocol.littleEndianQuadlet(0x1234_5678)
        #expect(bytes == Data([0x78, 0x56, 0x34, 0x12]))
        #expect(FirefaceMixerProtocol.readLittleEndianQuadlet(bytes) == 0x1234_5678)
        #expect(FirefaceMixerProtocol.savedGain(volume: 0x323, pan: 0, oddOutput: false) == 32_768)
        #expect(FirefaceMixerProtocol.savedGain(volume: 0x323, pan: 0, oddOutput: true) == 0)
        #expect(FirefaceMixerProtocol.savedGain(volume: 0x323, pan: 256, oddOutput: true) == 32_768)
        #expect(FirefaceMixerProtocol.savedOutputGain(volume: 0x323) == 32_768)
        #expect(FirefaceMixerProtocol.savedOutputGain(volume: 0xFFFF) == nil)
    }
}
