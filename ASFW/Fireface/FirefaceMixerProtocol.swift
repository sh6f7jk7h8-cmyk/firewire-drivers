import Foundation

/// Fireface 800 mixer RAM layout. Addresses and Q1 clock bits are based on
/// independently documented FFADO protocol behavior; no FFADO code is used.
enum FirefaceMixerProtocol {
    static let channelCount = 28
    static let vendorID: UInt32 = 0x000A35
    static let modelID: UInt32 = 0x101800
    static let mixerBase: UInt64 = 0x8008_0000
    static let outputGainBase: UInt64 = mixerBase + 0x1F80
    static let savedVolumeBase: UInt64 = 0x0003_000E_2000
    static let savedPanBase: UInt64 = 0x0003_000E_2800
    static let savedOutputBase: UInt64 = 0x0003_000E_3000

    enum Source: Equatable {
        case input(Int)
        case playback(Int)
        case output(Int)
    }

    static func address(for source: Source, destination: Int) -> UInt64? {
        guard (0..<channelCount).contains(destination) else { return nil }
        switch source {
        case .input(let channel):
            guard (0..<channelCount).contains(channel) else { return nil }
            return mixerBase + UInt64(destination * 0x100 + channel * 4)
        case .playback(let channel):
            guard (0..<channelCount).contains(channel) else { return nil }
            return mixerBase + UInt64(destination * 0x100 + 0x80 + channel * 4)
        case .output(let channel):
            guard (0..<channelCount).contains(channel) else { return nil }
            return outputGainBase + UInt64(channel * 4)
        }
    }

    static func decibels(for gain: UInt32) -> Double {
        guard gain > 0 else { return -90 }
        return max(-90, min(6, 20 * log10(Double(gain) / 32_768)))
    }

    static func gain(for decibels: Double) -> UInt32 {
        guard decibels.isFinite, decibels > -90 else { return 0 }
        return UInt32(max(0, min(65_536, (32_768 * pow(10, decibels / 20)).rounded())))
    }

    static func readLittleEndianQuadlet(_ bytes: Data) -> UInt32? {
        guard bytes.count >= 4 else { return nil }
        return UInt32(bytes[0]) | UInt32(bytes[1]) << 8 |
            UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
    }

    static func littleEndianQuadlet(_ value: UInt32) -> Data {
        Data([UInt8(truncatingIfNeeded: value),
              UInt8(truncatingIfNeeded: value >> 8),
              UInt8(truncatingIfNeeded: value >> 16),
              UInt8(truncatingIfNeeded: value >> 24)])
    }

    static func readLittleEndianHalfword(_ bytes: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 1 < bytes.count else { return nil }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    /// Saved Fireface profiles encode one volume and pan value for an output
    /// pair. This is a snapshot from flash, not a live read of mixer RAM.
    static func savedGain(volume: UInt16, pan: UInt16, oddOutput: Bool) -> UInt32? {
        guard volume <= 1023, pan <= 256 else { return nil }
        let total = volume == 0x323 ? 32_768.0 :
            65_536.0 * (exp(3.0 * Double(volume) / 1023.0) - 1) / (exp(3.0) - 1)
        let fraction = oddOutput ? Double(pan) / 256 : 1 - Double(pan) / 256
        return UInt32(max(0, min(65_536, (total * fraction).rounded())))
    }

    static func savedOutputGain(volume: UInt16) -> UInt32? {
        guard volume <= 1023 else { return nil }
        return savedGain(volume: volume, pan: 0, oddOutput: false)
    }
}
