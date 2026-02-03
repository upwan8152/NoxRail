import Foundation
import CoreBluetooth
import Combine

/// Delegate protocol for central manager events
protocol BLECentralManagerDelegate: AnyObject {
    func centralManager(_ manager: BLECentralManager, didDiscoverPeer peer: BLEPeer)
    func centralManager(_ manager: BLECentralManager, didConnectPeer peerId: String)
    func centralManager(_ manager: BLECentralManager, didDisconnectPeer peerId: String)
    func centralManager(_ manager: BLECentralManager, didReceiveData data: Data, from peerId: String)
    func centralManagerDidUpdateState(_ manager: BLECentralManager, state: BLEPowerState)
}

/// Manages the central (scanner) role in BLE mesh
final class BLECentralManager: NSObject, @unchecked Sendable {
    
    // MARK: - Properties
    
    private var centralManager: CBCentralManager?
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var connectedPeripherals: [String: BLEPeer] = [:]
    private var pendingConnections: Set<String> = []
    
    private let queue = DispatchQueue(label: "com.noxrail.central", qos: .userInitiated)
    private var scanTimer: Timer?
    
    weak var delegate: BLECentralManagerDelegate?
    
    private(set) var powerState: BLEPowerState = .unknown
    private(set) var isScanning = false
    
    // Data buffer for partial packets
    private var dataBuffers: [String: Data] = [:]
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    /// Starts the central manager
    func start() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            if self.centralManager == nil {
                self.centralManager = CBCentralManager(
                    delegate: self,
                    queue: self.queue,
                    options: [
                        CBCentralManagerOptionShowPowerAlertKey: true
                    ]
                )
            }
        }
    }
    
    /// Stops the central manager
    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.stopScanning()
            self.disconnectAll()
            self.centralManager = nil
        }
    }
    
    /// Starts scanning for NoxRail peripherals
    func startScanning() {
        queue.async { [weak self] in
            guard let self = self,
                  let centralManager = self.centralManager,
                  centralManager.state == .poweredOn,
                  !self.isScanning else {
                return
            }
            
            centralManager.scanForPeripherals(
                withServices: [BLEConstants.serviceUUID],
                options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: true
                ]
            )
            
            self.isScanning = true
            NoxLogger.ble.info("Started scanning for peripherals")
        }
    }
    
    /// Stops scanning
    func stopScanning() {
        queue.async { [weak self] in
            guard let self = self,
                  let centralManager = self.centralManager,
                  self.isScanning else {
                return
            }
            
            centralManager.stopScan()
            self.isScanning = false
            NoxLogger.ble.info("Stopped scanning")
        }
    }
    
    /// Connects to a peripheral
    func connect(peerId: String) {
        queue.async { [weak self] in
            guard let self = self,
                  let centralManager = self.centralManager,
                  let peripheral = self.discoveredPeripherals[peerId],
                  !self.pendingConnections.contains(peerId),
                  self.connectedPeripherals[peerId] == nil else {
                return
            }
            
            self.pendingConnections.insert(peerId)
            centralManager.connect(peripheral, options: nil)
            
            NoxLogger.ble.info("Connecting to peripheral \(peerId)")
        }
    }
    
    /// Disconnects from a peripheral
    func disconnect(peerId: String) {
        queue.async { [weak self] in
            guard let self = self,
                  let centralManager = self.centralManager,
                  let peripheral = self.discoveredPeripherals[peerId] else {
                return
            }
            
            centralManager.cancelPeripheralConnection(peripheral)
            NoxLogger.ble.info("Disconnecting from peripheral \(peerId)")
        }
    }
    
    /// Disconnects from all peripherals
    func disconnectAll() {
        queue.async { [weak self] in
            guard let self = self,
                  let centralManager = self.centralManager else {
                return
            }
            
            for (_, peripheral) in self.discoveredPeripherals {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            
            self.connectedPeripherals.removeAll()
            self.pendingConnections.removeAll()
        }
    }
    
    /// Sends data to a connected peripheral
    func sendData(_ data: Data, to peerId: String) -> Bool {
        var success = false
        
        queue.sync { [weak self] in
            guard let self = self,
                  let peer = self.connectedPeripherals[peerId],
                  let peripheral = peer.peripheral,
                  let characteristic = peer.writeCharacteristic else {
                return
            }
            
            // Prepend length header
            var packet = Data()
            var length = UInt32(data.count).bigEndian
            packet.append(Data(bytes: &length, count: 4))
            packet.append(data)
            
            // Split framed packet
            let chunks = self.splitData(packet, maxSize: BLEConstants.maxPacketSize)
            
            for chunk in chunks {
                peripheral.writeValue(
                    chunk,
                    for: characteristic,
                    type: .withResponse
                )
            }
            
            success = true
            NoxLogger.ble.debug("Sent \(data.count) bytes to peripheral \(peerId)")
        }
        
        return success
    }
    
    /// Sends data to all connected peripherals
    func sendToAllConnected(data: Data) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            for (peerId, peer) in self.connectedPeripherals {
                guard let peripheral = peer.peripheral,
                      let characteristic = peer.writeCharacteristic else {
                    continue
                }
                
                // Prepend length header
                var packet = Data()
                var length = UInt32(data.count).bigEndian
                packet.append(Data(bytes: &length, count: 4))
                packet.append(data)
                
                let chunks = self.splitData(packet, maxSize: BLEConstants.maxPacketSize)
                
                for chunk in chunks {
                    peripheral.writeValue(
                        chunk,
                        for: characteristic,
                        type: .withResponse
                    )
                }
                
                NoxLogger.ble.debug("Sent \(data.count) bytes to peripheral \(peerId)")
            }
        }
    }
    
    /// Gets connected peer IDs
    func getConnectedPeerIds() -> [String] {
        var ids: [String] = []
        queue.sync {
            ids = Array(connectedPeripherals.keys)
        }
        return ids
    }
    
    /// Gets a connected peer by ID
    func getPeer(id: String) -> BLEPeer? {
        var peer: BLEPeer?
        queue.sync {
            peer = connectedPeripherals[id]
        }
        return peer
    }
    
    // MARK: - Private Methods
    
    private func discoverServices(for peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([BLEConstants.serviceUUID])
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

// MARK: - CBCentralManagerDelegate

extension BLECentralManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        powerState = BLEPowerState(from: central.state)
        
        NoxLogger.ble.info("Central manager state: \(powerState.rawValue)")
        
        if central.state == .poweredOn {
            startScanning()
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.centralManagerDidUpdateState(self, state: self.powerState)
        }
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let peerId = peripheral.identifier.uuidString
        
        // Store peripheral reference
        discoveredPeripherals[peerId] = peripheral
        
        // Extract display name from advertisement
        let displayName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        
        let peer = BLEPeer(
            id: peerId,
            peripheral: peripheral,
            displayName: displayName,
            rssi: RSSI.intValue,
            lastSeen: Date(),
            connectionState: connectedPeripherals[peerId]?.connectionState ?? .disconnected
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.centralManager(self, didDiscoverPeer: peer)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let peerId = peripheral.identifier.uuidString
        pendingConnections.remove(peerId)
        
        NoxLogger.ble.info("Connected to peripheral \(peerId)")
        
        // Start service discovery
        discoverServices(for: peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let peerId = peripheral.identifier.uuidString
        pendingConnections.remove(peerId)
        
        NoxLogger.ble.warning("Failed to connect to peripheral \(peerId): \(error?.localizedDescription ?? "unknown")")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let peerId = peripheral.identifier.uuidString
        connectedPeripherals.removeValue(forKey: peerId)
        dataBuffers.removeValue(forKey: peerId)
        
        NoxLogger.ble.info("Disconnected from peripheral \(peerId)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.centralManager(self, didDisconnectPeer: peerId)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLECentralManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            NoxLogger.ble.error("Service discovery failed: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == BLEConstants.serviceUUID {
                peripheral.discoverCharacteristics(
                    [BLEConstants.writeCharacteristicUUID, BLEConstants.notifyCharacteristicUUID],
                    for: service
                )
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            NoxLogger.ble.error("Characteristic discovery failed: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        let peerId = peripheral.identifier.uuidString
        var peer = connectedPeripherals[peerId] ?? BLEPeer(
            id: peerId,
            peripheral: peripheral,
            displayName: peripheral.name ?? "Unknown",
            connectionState: .connected
        )
        
        for characteristic in characteristics {
            if characteristic.uuid == BLEConstants.writeCharacteristicUUID {
                peer.writeCharacteristic = characteristic
            } else if characteristic.uuid == BLEConstants.notifyCharacteristicUUID {
                peer.notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        
        peer.connectionState = .connected
        connectedPeripherals[peerId] = peer
        
        NoxLogger.ble.info("Characteristics discovered for peripheral \(peerId)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.centralManager(self, didConnectPeer: peerId)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            NoxLogger.ble.error("Failed to receive data: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else { return }
        
        let peerId = peripheral.identifier.uuidString
        
        NoxLogger.ble.debug("Received chunk of \(data.count) bytes from peripheral \(peerId)")
        
        // Append to buffer
        var buffer = dataBuffers[peerId] ?? Data()
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
                
                NoxLogger.ble.debug("Reassembled packet of \(packetLength) bytes from \(peerId)")
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.centralManager(self, didReceiveData: payload, from: peerId)
                }
            } else {
                break // Wait for more data
            }
        }
        
        dataBuffers[peerId] = buffer
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            NoxLogger.ble.warning("Write failed: \(error.localizedDescription)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            NoxLogger.ble.warning("Notification state update failed: \(error.localizedDescription)")
            return
        }
        
        if characteristic.isNotifying {
            NoxLogger.ble.debug("Notifications enabled for \(characteristic.uuid)")
        }
    }
}
