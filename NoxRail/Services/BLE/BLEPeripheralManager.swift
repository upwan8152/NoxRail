import Foundation
import CoreBluetooth
import Combine

/// Delegate protocol for peripheral manager events
protocol BLEPeripheralManagerDelegate: AnyObject {
    func peripheralManager(_ manager: BLEPeripheralManager, didReceiveData data: Data, from centralId: String)
    func peripheralManager(_ manager: BLEPeripheralManager, centralDidConnect centralId: String)
    func peripheralManager(_ manager: BLEPeripheralManager, centralDidDisconnect centralId: String)
    func peripheralManagerDidUpdateState(_ manager: BLEPeripheralManager, state: BLEPowerState)
}

/// Manages the peripheral (advertiser) role in BLE mesh
final class BLEPeripheralManager: NSObject, @unchecked Sendable {
    
    // MARK: - Properties
    
    private var peripheralManager: CBPeripheralManager?
    private var service: CBMutableService?
    private var writeCharacteristic: CBMutableCharacteristic?
    private var notifyCharacteristic: CBMutableCharacteristic?
    
    private var connectedCentrals: [String: CBCentral] = [:]
    private let queue = DispatchQueue(label: "com.noxrail.peripheral", qos: .userInitiated)
    
    weak var delegate: BLEPeripheralManagerDelegate?
    
    private(set) var powerState: BLEPowerState = .unknown
    private(set) var isAdvertising = false
    
    var localName: String = "NoxRail"
    
    // List of data chunks waiting to be sent
    private var transmissionQueue: [TransmissionChunk] = []

    // Data buffer for partial packets (incoming)
    private var dataBuffers: [String: Data] = [:]
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    /// Starts the peripheral manager
    func start() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            if self.peripheralManager == nil {
                self.peripheralManager = CBPeripheralManager(
                    delegate: self,
                    queue: self.queue,
                    options: [
                        CBPeripheralManagerOptionShowPowerAlertKey: true
                    ]
                )
            }
        }
    }
    
    /// Stops the peripheral manager
    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.stopAdvertising()
            self.connectedCentrals.removeAll()
            self.peripheralManager = nil
        }
    }
    
    /// Starts advertising
    func startAdvertising() {
        queue.async { [weak self] in
            guard let self = self,
                  let peripheralManager = self.peripheralManager,
                  peripheralManager.state == .poweredOn,
                  !self.isAdvertising else {
                return
            }
            
            let advertisementData: [String: Any] = [
                CBAdvertisementDataLocalNameKey: self.localName,
                CBAdvertisementDataServiceUUIDsKey: [BLEConstants.serviceUUID]
            ]
            
            peripheralManager.startAdvertising(advertisementData)
            self.isAdvertising = true
            NoxLogger.ble.info("Started advertising as '\(self.localName)'")
        }
    }
    
    /// Stops advertising
    func stopAdvertising() {
        queue.async { [weak self] in
            guard let self = self,
                  let peripheralManager = self.peripheralManager,
                  self.isAdvertising else {
                return
            }
            
            peripheralManager.stopAdvertising()
            self.isAdvertising = false
            NoxLogger.ble.info("Stopped advertising")
        }
    }
    
    /// Sends data to all connected centrals
    func sendToAllCentrals(data: Data) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.enqueuePacket(data, for: nil)
        }
    }
    
    /// Sends data to a specific central
    func sendToCentral(centralId: String, data: Data) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.enqueuePacket(data, for: centralId)
        }
    }
    
    /// Enqueues a packet to be sent
    private func enqueuePacket(_ data: Data, for centralId: String?) {
        // Prepend length header
        var packet = Data()
        var length = UInt32(data.count).bigEndian
        packet.append(Data(bytes: &length, count: 4))
        packet.append(data)
        
        // Split framed packet
        let chunks = splitData(packet, maxSize: BLEConstants.maxPacketSize)
        
        for chunk in chunks {
            transmissionQueue.append(TransmissionChunk(data: chunk, targetCentralId: centralId))
        }
        
        // Trigger transmission
        processTransmissionQueue()
    }
    
    /// Processes the transmission queue
    private func processTransmissionQueue() {
        guard let peripheralManager = peripheralManager,
              let notifyCharacteristic = notifyCharacteristic,
              !transmissionQueue.isEmpty else {
            return
        }
        
        // Process queue while buffer space is available
        while !transmissionQueue.isEmpty {
            let chunk = transmissionQueue[0]
            
            var targetCentrals: [CBCentral]? = nil
            
            // If targeting specific central, resolve it
            if let centralId = chunk.targetCentralId {
                if let central = connectedCentrals[centralId] {
                    targetCentrals = [central]
                } else {
                    // Central disconnected, drop chunk
                    transmissionQueue.removeFirst()
                    continue
                }
            }
            // else: targetCentrals = nil (all subscribed)
            
            // Attempt to send
            let ready = peripheralManager.updateValue(
                chunk.data,
                for: notifyCharacteristic,
                onSubscribedCentrals: targetCentrals
            )
            
            if ready {
                // Success, remove from queue
                transmissionQueue.removeFirst()
            } else {
                // Buffer full, wait for peripheralManagerIsReady
                NoxLogger.ble.debug("BLE buffer full, pausing transmission (queue size: \(transmissionQueue.count))")
                return
            }
        }
    }
    
    /// Gets connected central IDs
    func getConnectedCentralIds() -> [String] {
        var ids: [String] = []
        queue.sync {
            ids = Array(connectedCentrals.keys)
        }
        return ids
    }
    
    // MARK: - Private Methods
    
    private func setupService() {
        guard let peripheralManager = peripheralManager else { return }
        
        // Create write characteristic (for receiving data from centrals)
        writeCharacteristic = CBMutableCharacteristic(
            type: BLEConstants.writeCharacteristicUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        
        // Create notify characteristic (for sending data to centrals)
        notifyCharacteristic = CBMutableCharacteristic(
            type: BLEConstants.notifyCharacteristicUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        
        // Create service
        service = CBMutableService(type: BLEConstants.serviceUUID, primary: true)
        service?.characteristics = [writeCharacteristic!, notifyCharacteristic!]
        
        // Add service
        peripheralManager.add(service!)
        
        NoxLogger.ble.info("Peripheral service configured")
    }
    
    private func splitData(_ data: Data, maxSize: Int) -> [Data] {
        guard data.count > maxSize else { return [data] }
        
        var chunks: [Data] = []
        var offset = 0
        
        while offset < data.count {
            let length = min(maxSize, data.count - offset)
            let chunk = data.subdata(in: offset..<(offset + length))
            chunks.append(chunk)
            offset += length
        }
        
        return chunks
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheralManager: CBPeripheralManagerDelegate {
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        powerState = BLEPowerState(from: peripheral.state)
        
        NoxLogger.ble.info("Peripheral manager state: \(powerState.rawValue)")
        
        if peripheral.state == .poweredOn {
            setupService()
        }
        
        delegate?.peripheralManagerDidUpdateState(self, state: powerState)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            NoxLogger.ble.error("Failed to add service: \(error.localizedDescription)")
            return
        }
        
        NoxLogger.ble.info("Service added successfully")
        startAdvertising()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let centralId = central.identifier.uuidString
        connectedCentrals[centralId] = central
        
        NoxLogger.ble.info("Central \(centralId) subscribed")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.peripheralManager(self, centralDidConnect: centralId)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        let centralId = central.identifier.uuidString
        connectedCentrals.removeValue(forKey: centralId)
        dataBuffers.removeValue(forKey: centralId)
        
        NoxLogger.ble.info("Central \(centralId) unsubscribed")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.peripheralManager(self, centralDidDisconnect: centralId)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard let data = request.value else { continue }
            
            let centralId = request.central.identifier.uuidString
            
            // Store central reference
            connectedCentrals[centralId] = request.central
            
            NoxLogger.ble.debug("Received chunk of \(data.count) bytes from central \(centralId)")
            
            // Append to buffer
            var buffer = dataBuffers[centralId] ?? Data()
            buffer.append(data)
            
            // Process complete packets
            while buffer.count >= 4 {
                var length: UInt32 = 0
                _ = withUnsafeMutableBytes(of: &length) { buffer.prefix(4).copyBytes(to: $0) }
                length = UInt32(bigEndian: length)
                let packetLength = Int(length)
                
                if buffer.count >= 4 + packetLength {
                    let start = buffer.startIndex
                    let payload = buffer.subdata(in: start + 4 ..< start + 4 + packetLength)
                    
                    // Remove processed packet
                    buffer.removeFirst(4 + packetLength)
                    
                    NoxLogger.ble.debug("Reassembled packet of \(packetLength) bytes from \(centralId)")
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.peripheralManager(self, didReceiveData: payload, from: centralId)
                    }
                } else {
                    break // Wait for more data
                }
            }
            
            dataBuffers[centralId] = buffer
            
            // Respond to write request
            peripheral.respond(to: request, withResult: .success)
        }
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        NoxLogger.ble.debug("Peripheral ready to update subscribers, resuming transmission")
        // Access queue on its thread
        queue.async { [weak self] in
            self?.processTransmissionQueue()
        }
    }
}

// MARK: - Supporting Types

private struct TransmissionChunk {
    let data: Data
    let targetCentralId: String? // nil means broadcast to all
}
