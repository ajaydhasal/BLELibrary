//
//  File.swift
//  
//
//  Created by KO158L8 on 26/09/23.
//

import Foundation
import CoreBluetooth

enum BLEErrors: Swift.Error {

    case missingNSBluetoothAlwaysUsageDescription
    case missingNSBluetoothPeripheralUsageDescription
    case cbManagerStateUnknown
    case cbManagerStateResetting
    case cbUnsupported
    case cbUnauthorized
    case cbPoweredOff
    case cbpoweredOn

    var localizedDescription: String {
        switch self {
            
        case .missingNSBluetoothAlwaysUsageDescription:
            return "Missing NSBluetoothAlwaysUsageDescription Key in Plist"
        case .missingNSBluetoothPeripheralUsageDescription:
            return "Missing NSBluetoothPeripheralUsageDescription Key in Plist"
        case .cbManagerStateUnknown:
            return "Unknown"
        case .cbManagerStateResetting:
            return "Resetting"
        case .cbUnsupported:
            return "UnSupported"
        case .cbUnauthorized:
            return "UnAuthorized"
        case .cbPoweredOff:
            return "Device Bluetooth Powered Off"
        case .cbpoweredOn:
            return "Device Bluetooth Powered On"
        }
    }
}


struct BLEManagerConstants {
    static let legacyServiceUUID = "bccb0001-ca66-11e5-88a4-0002a5d5c51b"
    static let legacyTxUUID = "bccb0003-ca66-11e5-88a4-0002a5d5c51b"
    static let legacyRxUUID = "bccb0002-ca66-11e5-88a4-0002a5d5c51b"
    
    static let gcsServiceUUID = "267f0001-eb15-43f5-94c3-67d2221188f7"
    static let gcsTxUUID = "267f0003-eb15-43f5-94c3-67d2221188f7"
    static let gcsRxUUID = "267f0002-eb15-43f5-94c3-67d2221188f7"
    
}

struct TimerConstant {
    static let bleScanningWaitTimer = 5
    static let blePollingTimer = 1.0
    static let pairingWaitTimer = 30
}


public final class BLEManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public static var shared = BLEManager()
    
    var readValveStatus:[UInt8] = [170, 85, 0, 43, 1, 2, 211];
    
    deinit {
        print("Deinit called.")
    }
    
    public func log(string: String) {
        print(string)
    }
    
    public var bleState: CBManagerState { return centralManager.state }
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    
    private var readCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    
    public var isScanning: Bool { return centralManager.isScanning }
    var isWaitingForResponse = true
    
    public var didChangeBLEState: ((CBManagerState) -> Void)?
    public var didDiscoverDevice: ((BLEDevice) -> Void)?
    public var didScanEnd: (([BLEDevice]) -> Void)?
    public var peripheralDidUpdateName: ((BLEDevice) -> Void)?
    public var didConnectPeripheral: ((CBPeripheral) -> Void)?
    public var didFailToConnectPeripheral: ((CBPeripheral, Error?) -> Void)?
    public var didLossConnection: ((_ peripheral: CBPeripheral?) -> Void)?
    public var didReceiveResponse:((_ response: [UInt8]) -> Void)?
    public var didPairingFailed:(() -> Void)?
    
    public var isConnected: Bool { return connectedPeripheral != nil }
    
    var scanningTimer: Timer?
    var pollingTimer: Timer?
    
    var scannedDevices = [BLEDevice]()
    
    // MARK: - Initializer
    fileprivate func initilizeCentralManager() throws {
        guard let nsBluetoothAlwaysUsageDescription = Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") else {
            throw BLEErrors.missingNSBluetoothAlwaysUsageDescription
        }
        
        guard let snBluetoothPeripheralUsageDescription = Bundle.main.object(forInfoDictionaryKey: "NSBluetoothPeripheralUsageDescription") else {
            throw BLEErrors.missingNSBluetoothPeripheralUsageDescription
        }
        centralManager = CBCentralManager(delegate: self, queue: .main)
        
    }
    
    private override init() {
        super.init()
        do {
            try initilizeCentralManager()
            print("BLEManager initialized")
        } catch {
            print(error.localizedDescription)
        }
    }
    
    public func dispose() {
        centralManager = nil
        connectedPeripheral = nil
        print("BLEManager disposed")
    }
    
    
    func startWaitTimer() {
        invalidateWaitTimer()
        let timeInterval: Int = TimerConstant.bleScanningWaitTimer
        
        scanningTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeInterval), repeats: false) { [weak self] _ in
            guard let self = self else {return}
            self.invalidateWaitTimer()
            self.stopScanning()
            
            if let block = self.didScanEnd {
                block(self.scannedDevices)
            }
        }
    }
    
    func invalidateWaitTimer() {
        scanningTimer?.invalidate()
        scanningTimer = nil
    }
    
    public func startPolling() {
        stopPolling()
        let timeInterval = TimerConstant.blePollingTimer
        var pairingWaitTimer = TimerConstant.pairingWaitTimer
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeInterval), repeats: true) { [weak self] _ in
            guard let self = self else {return}
            if pairingWaitTimer < 0 {
                self.isWaitingForResponse = true
                self.didPairingFailed?()
            } else {
                pairingWaitTimer -= 1
                self.write(frame: readValveStatus)
            }
        }
    }
    
    public func stopPolling() {
        self.pollingTimer?.invalidate()
        self.pollingTimer = nil
    }
    
    // MARK: - Central Manger Methods
    public func startScanning() {
        startWaitTimer()
        self.scannedDevices.removeAll()
        print("BLEManager will start scanning")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { //To wait until the centralManagerDidUpdateState(_ central: CBCentralManager) callback has been called. And then, verify that the state is PoweredOn before scanning for peripherals
            
            guard case .poweredOn = self.bleState else { return }
            self.centralManager.scanForPeripherals(withServices: [CBUUID(string: BLEManagerConstants.gcsServiceUUID)], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            //CBUUID(string: BLEManagerConstants.legacyServiceUUID),
            print("BLEManager started scanning")
            
        }
    }
    
    public func stopScanning() {
        if centralManager.isScanning {
            print("BLEManager stopped scanning")
            centralManager.stopScan()
        }
    }
    
    public func connect(device: BLEDevice) {
        self.connect(peripheral: device.peripheral)
    }
    
    func connect(peripheral: CBPeripheral, options: [String: Any]? = nil) {
        centralManager.connect(peripheral, options: options)
        print("\(#function)")
    }
    
    func cancelConnection(with peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
        print("Cancelled connection with \(peripheral.name ?? "NO_NAME")")
    }
    
    func peripheralName() -> String? {
        return connectedPeripheral?.name
    }
    
    private func cleanup() {
        print("Cleaning up")
        guard let peripheral = connectedPeripheral, case .connected = peripheral.state else {
            print("No periphral is connected")
            return
        }
        
        guard let services = peripheral.services else {
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        services.forEach {
            if let characteristics = $0.characteristics as [CBCharacteristic]? {
                characteristics.forEach {
                    if $0.uuid.isEqual(CBUUID(string: BLEManagerConstants.gcsRxUUID)) || $0.uuid.isEqual(CBUUID(string: BLEManagerConstants.legacyRxUUID)) && $0.isNotifying {
                        peripheral.setNotifyValue(false, for: $0)
                        return
                    }
                }
            }
        }
        centralManager?.cancelPeripheralConnection(connectedPeripheral!)
    }
    
    private func write(frame: [UInt8]) {
        guard let peripheral = connectedPeripheral else { return }
        guard writeCharacteristic != nil else { return}
        let chunked = frame.chunked(into: 20)
        for subFrame in chunked {
            let data = Data(bytes: UnsafePointer<UInt8>(subFrame), count: subFrame.count)
            peripheral.writeValue(data, for: writeCharacteristic!, type: .withResponse)
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        connectedPeripheral = peripheral
        connectedPeripheral?.delegate = self
        connectedPeripheral?.discoverServices([CBUUID(string: BLEManagerConstants.gcsServiceUUID)])
        
        
        if let block = didConnectPeripheral {
            self.startPolling()
            block(peripheral)
        }
    }
    
    @objc public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if let block = didChangeBLEState {
            block(central.state)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let block = didFailToConnectPeripheral {
            block(peripheral, error)
        }
        cleanup()
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        guard isConnected else {
            if let block = didFailToConnectPeripheral {
                block(peripheral, error)
            }
            return
        }
        if let block = didLossConnection {
            block(connectedPeripheral)
        }
        
        if let connected = connectedPeripheral, connected == peripheral {
            connectedPeripheral = nil
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        
        print("peripheral name =\(advertisementData[CBAdvertisementDataLocalNameKey] ?? peripheral.name ?? "NO Name")")

        guard advertisementData[CBAdvertisementDataLocalNameKey] != nil || peripheral.name != nil else { return } // Prevents the devices with no name.
        
        let device = BLEDevice(peripheral: peripheral, advertisementData: advertisementData, rssiNumber: RSSI)
        self.scannedDevices.append(device)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let block = self.didDiscoverDevice {
                block(device)
            }
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    public func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        if let block = peripheralDidUpdateName {
            block(BLEDevice(peripheral: peripheral))
        }
        print("Updated name: - \(peripheral.name ?? "no_name")")
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        if let error = error {
            print("Error discovering services: - \(error.localizedDescription)")
            return
        }
        
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        if let error = error {
            print("Error discovering characteristics: - \(error.localizedDescription)")
            return
        }
        
        if service.uuid.isEqual(CBUUID(string: BLEManagerConstants.gcsServiceUUID)) {
            
            for characteristic: CBCharacteristic in service.characteristics! {
                
                if characteristic.uuid.isEqual(CBUUID(string: BLEManagerConstants.gcsRxUUID)){
                    writeCharacteristic = characteristic
                    print("writeCharacteristic characteristics discovered:")
                    
                } else if characteristic.uuid.isEqual(CBUUID(string: BLEManagerConstants.gcsTxUUID)){
                    readCharacteristic = characteristic
                    print("readCharacteristic characteristics discovered:")
                }
            }
        }
        
        for characteristic in (service.characteristics)! where !characteristic.isNotifying {
            if readCharacteristic != nil && writeCharacteristic != nil {
                peripheral.setNotifyValue(true, for: readCharacteristic!)
                peripheral.setNotifyValue(true, for: writeCharacteristic!)
                print("setNotifyValue read and write")
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        //Request
        if let error = error {
            print("Error writing value: \(error.localizedDescription)")
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Response
        // This method should not do any insertion/deletion in the queue or queue buffer.
        guard let data = characteristic.value else {
            print("Characteristic data is null.")
            return
        }
        
        let count = data.count / MemoryLayout<UInt8>.size
        var array = [UInt8](repeating: 0, count: count)
        (data as NSData).getBytes(&array, length: count)
        handle(response: array, error: error)
    }
    
    func handle(response: [UInt8], error: Error?) {

        // Check here, if the request is continuous, use the continuousResponseBuffer instead of passing the response to controllers.

        isWaitingForResponse = false
        self.stopPolling()
        if let block = didReceiveResponse {
            block(response)
            print("response =\(response)")
        }
    }
}


