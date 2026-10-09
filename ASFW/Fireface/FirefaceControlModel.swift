import Combine
import Foundation

/// Owns the UI's live connection to the embedded DriverKit extension. Device
/// identity is checked around every operation so an old node number is never
/// retained across a FireWire bus reset.
final class FirefaceControlModel: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var deviceName = "Fireface 800 не обнаружена"
    @Published private(set) var generation: UInt32?
    @Published private(set) var mixerReady = false
    @Published private(set) var loading = false
    @Published private(set) var applying = false
    @Published private(set) var clockStatus: UInt32?
    @Published private(set) var errorMessage: String?
    @Published var selectedOutput = 0 { didSet { refresh() } }
    @Published var inputDecibels = [Double](repeating: -90, count: FirefaceMixerProtocol.channelCount)
    @Published var playbackDecibels = [Double](repeating: -90, count: FirefaceMixerProtocol.channelCount)
    @Published var outputDecibels = [Double](repeating: -90, count: FirefaceMixerProtocol.channelCount)

    private let connector = ASFWDriverConnector()
    private let queue = DispatchQueue(label: "com.marsproo.firefacestudio.control", qos: .userInitiated)
    private var subscriptions = Set<AnyCancellable>()
    private var deviceGUID: UInt64?
    private var liveOverrides: [String: Double] = [:]

    init() {
        connector.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                self.connected = connected
                if connected {
                    self.refresh()
                } else {
                    self.deviceGUID = nil
                    self.generation = nil
                    self.mixerReady = false
                    self.liveOverrides.removeAll()
                    self.deviceName = "Драйвер не подключён"
                }
            }
            .store(in: &subscriptions)
    }

    func start() { _ = connector.connect(forceAttempt: false) }

    func refresh() {
        guard connector.isConnected, !loading, !applying else { return }
        loading = true
        mixerReady = false
        let destination = selectedOutput
        queue.async { [weak self] in
            guard let self else { return }
            guard let device = self.findDevice() else {
                DispatchQueue.main.async {
                    self.loading = false
                    self.deviceGUID = nil
                    self.generation = nil
                    self.deviceName = "Fireface 800 не обнаружена"
                    self.errorMessage = nil
                }
                return
            }
            let node = UInt16(0xFFC0) | UInt16(device.nodeId)
            let q1 = self.readQuad(node: node, address: 0x801C_0004)
            let pair = destination / 2
            let inputOffset = UInt64(pair * 128)
            let playbackOffset = inputOffset + 64
            let inputVolume = self.readBlock(node: node,
                                             address: FirefaceMixerProtocol.savedVolumeBase + inputOffset,
                                             length: 64)
            let inputPan = self.readBlock(node: node,
                                          address: FirefaceMixerProtocol.savedPanBase + inputOffset,
                                          length: 64)
            let playbackVolume = self.readBlock(node: node,
                                                address: FirefaceMixerProtocol.savedVolumeBase + playbackOffset,
                                                length: 64)
            let playbackPan = self.readBlock(node: node,
                                             address: FirefaceMixerProtocol.savedPanBase + playbackOffset,
                                             length: 64)
            let output = self.readBlock(node: node,
                                        address: FirefaceMixerProtocol.savedOutputBase,
                                        length: 64)
            let stable = self.sameDevice(as: device)
            DispatchQueue.main.async {
                self.loading = false
                if self.selectedOutput != destination {
                    self.refresh()
                    return
                }
                if self.deviceGUID != device.guid || self.generation != device.generation {
                    self.liveOverrides.removeAll()
                }
                self.deviceGUID = device.guid
                self.generation = device.generation
                self.deviceName = device.modelName.isEmpty ? "RME Fireface 800" : device.modelName
                self.clockStatus = q1
                guard stable, let inputVolume, let inputPan,
                      let playbackVolume, let playbackPan, let output,
                      var ins = Self.decodeSavedPair(volume: inputVolume, pan: inputPan,
                                                      oddOutput: destination.isMultiple(of: 2) == false),
                      var plays = Self.decodeSavedPair(volume: playbackVolume, pan: playbackPan,
                                                        oddOutput: destination.isMultiple(of: 2) == false),
                      var outs = Self.decodeSavedOutputs(output) else {
                    self.errorMessage = stable ? "Не удалось прочитать сохранённый профиль карты" : "Шина FireWire изменилась; обновите состояние"
                    self.mixerReady = false
                    return
                }
                for channel in 0..<FirefaceMixerProtocol.channelCount {
                    if let value = self.liveOverrides[Self.overrideKey(.input(channel), destination: destination)] { ins[channel] = value }
                    if let value = self.liveOverrides[Self.overrideKey(.playback(channel), destination: destination)] { plays[channel] = value }
                    if let value = self.liveOverrides[Self.overrideKey(.output(channel), destination: destination)] { outs[channel] = value }
                }
                self.inputDecibels = ins
                self.playbackDecibels = plays
                self.outputDecibels = outs
                self.mixerReady = true
                self.errorMessage = nil
            }
        }
    }

    func setDraft(_ decibels: Double, source: FirefaceMixerProtocol.Source) {
        guard mixerReady else { return }
        switch source {
        case .input(let channel) where (0..<28).contains(channel): inputDecibels[channel] = decibels
        case .playback(let channel) where (0..<28).contains(channel): playbackDecibels[channel] = decibels
        case .output(let channel) where (0..<28).contains(channel): outputDecibels[channel] = decibels
        default: break
        }
    }

    func commit(_ source: FirefaceMixerProtocol.Source) {
        guard mixerReady, !applying,
              let expectedGUID = deviceGUID,
              let expectedGeneration = generation,
              let address = FirefaceMixerProtocol.address(for: source, destination: selectedOutput) else { return }
        let destination = selectedOutput
        let dB: Double
        switch source {
        case .input(let channel): dB = inputDecibels[channel]
        case .playback(let channel): dB = playbackDecibels[channel]
        case .output(let channel): dB = outputDecibels[channel]
        }
        let gain = FirefaceMixerProtocol.gain(for: dB)
        applying = true
        queue.async { [weak self] in
            guard let self else { return }
            guard let before = self.findDevice(), before.guid == expectedGUID,
                  before.generation == expectedGeneration else {
                DispatchQueue.main.async {
                    self.applying = false
                    self.mixerReady = false
                    self.errorMessage = "Шина FireWire изменилась; запись отменена"
                }
                return
            }
            let node = UInt16(0xFFC0) | UInt16(before.nodeId)
            let payload = FirefaceMixerProtocol.littleEndianQuadlet(gain)
            let written = self.writeQuad(node: node, address: address, payload: payload)
            let stable = self.sameDevice(as: before)
            DispatchQueue.main.async {
                self.applying = false
                if !written || !stable {
                    self.mixerReady = false
                    self.errorMessage = "Карта не подтвердила запись микшера"
                } else {
                    self.liveOverrides[Self.overrideKey(source, destination: destination)] = dB
                    self.errorMessage = nil
                }
            }
        }
    }

    private func findDevice() -> ASFWDriverConnector.FWDeviceInfo? {
        connector.getDiscoveredDevices()?.first {
            // The FF800 advertises 0x101800 in its unit directory, but its
            // root device model ID may be absent (zero) in the discovery API.
            $0.vendorId == FirefaceMixerProtocol.vendorID &&
            ($0.modelId == FirefaceMixerProtocol.modelID ||
             $0.modelName.localizedCaseInsensitiveContains("Fireface 800"))
        }
    }

    private func sameDevice(as previous: ASFWDriverConnector.FWDeviceInfo) -> Bool {
        guard let current = connector.getDiscoveredDevices()?.first(where: { $0.guid == previous.guid }) else { return false }
        return current.nodeId == previous.nodeId && current.generation == previous.generation
    }

    private func readQuad(node: UInt16, address: UInt64) -> UInt32? {
        guard let bytes = readBlock(node: node, address: address, length: 4) else { return nil }
        return FirefaceMixerProtocol.readLittleEndianQuadlet(bytes)
    }

    private func readBlock(node: UInt16, address: UInt64, length: Int) -> Data? {
        let high = UInt16(truncatingIfNeeded: address >> 32)
        let low = UInt32(truncatingIfNeeded: address)
        let handle = length == 4
            ? connector.asyncRead(destinationID: node, addressHigh: high,
                                  addressLow: low, length: 4)
            : connector.asyncBlockRead(destinationID: node, addressHigh: high,
                                       addressLow: low, length: UInt32(length))
        guard let handle else { return nil }
        guard let result = awaitResult(handle: handle, capacity: length, acceptsAckComplete: false),
              result.payload.count >= length else { return nil }
        return Data(result.payload.prefix(length))
    }

    private func writeQuad(node: UInt16, address: UInt64, payload: Data) -> Bool {
        guard let handle = connector.asyncWrite(destinationID: node,
                                                addressHigh: UInt16(truncatingIfNeeded: address >> 32),
                                                addressLow: UInt32(truncatingIfNeeded: address),
                                                payload: payload) else { return false }
        return awaitResult(handle: handle, capacity: 0, acceptsAckComplete: true) != nil
    }

    private func awaitResult(handle: UInt16, capacity: Int,
                             acceptsAckComplete: Bool) -> ASFWDriverConnector.AsyncTransactionResult? {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let result = connector.getTransactionResult(handle: handle,
                                                           initialPayloadCapacity: capacity + 32) {
                // A successful FireWire write may finish with ACK_COMPLETE and
                // no separate response packet. The driver reports that as 0xFF.
                let responseAccepted = result.responseCode == 0 ||
                    (acceptsAckComplete && result.responseCode == 0xFF)
                return result.status == 0 && responseAccepted ? result : nil
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    private static func decodeSavedPair(volume: Data, pan: Data, oddOutput: Bool) -> [Double]? {
        guard volume.count >= 56, pan.count >= 56 else { return nil }
        var result: [Double] = []
        for channel in 0..<FirefaceMixerProtocol.channelCount {
            guard let v = FirefaceMixerProtocol.readLittleEndianHalfword(volume, at: channel * 2),
                  let p = FirefaceMixerProtocol.readLittleEndianHalfword(pan, at: channel * 2),
                  let gain = FirefaceMixerProtocol.savedGain(volume: v, pan: p,
                                                            oddOutput: oddOutput) else { return nil }
            result.append(FirefaceMixerProtocol.decibels(for: gain))
        }
        return result
    }

    private static func decodeSavedOutputs(_ bytes: Data) -> [Double]? {
        guard bytes.count >= 56 else { return nil }
        var result: [Double] = []
        for channel in 0..<FirefaceMixerProtocol.channelCount {
            guard let v = FirefaceMixerProtocol.readLittleEndianHalfword(bytes, at: channel * 2),
                  let gain = FirefaceMixerProtocol.savedOutputGain(volume: v) else { return nil }
            result.append(FirefaceMixerProtocol.decibels(for: gain))
        }
        return result
    }

    private static func overrideKey(_ source: FirefaceMixerProtocol.Source, destination: Int) -> String {
        switch source {
        case .input(let channel): return "i.\(destination).\(channel)"
        case .playback(let channel): return "p.\(destination).\(channel)"
        case .output(let channel): return "o.\(channel)"
        }
    }
}
