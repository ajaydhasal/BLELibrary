//
//  File.swift
//  
//
//  Created by KO158L8 on 26/09/23.
//

import Foundation
import CoreBluetooth

struct BLEManagerConstants {
    static let legacyServiceUUID = "bccb0001-ca66-11e5-88a4-0002a5d5c51b"
    static let legacyTxUUID = "bccb0003-ca66-11e5-88a4-0002a5d5c51b"
    static let legacyRxUUID = "bccb0002-ca66-11e5-88a4-0002a5d5c51b"
    
    static let gcsServiceUUID = "267f0001-eb15-43f5-94c3-67d2221188f7"
    static let gcsTxUUID = "267f0003-eb15-43f5-94c3-67d2221188f7"
    static let gcsRxUUID = "267f0002-eb15-43f5-94c3-67d2221188f7"
    
}

public final class BLEManager: NSObject, CBCentralManagerDelegate {
    public static var shared = BLEManager()
    
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
    
    public var didChangeBLEState: ((CBManagerState) -> Void)?
    public var didDiscoverDevice: ((BLEDevice) -> Void)?
    public var peripheralDidUpdateName: ((BLEDevice) -> Void)?
    public var didConnectPeripheral: ((CBPeripheral) -> Void)?
    public var didFailToConnectPeripheral: ((CBPeripheral, Error?) -> Void)?
    public var didLossConnection: ((_ peripheral: CBPeripheral?) -> Void)?
    public var isConnected: Bool { return connectedPeripheral != nil }
    
    // MARK: - Initializer
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        print("BLEManager initialized")
    }
    
    public func dispose() {
        centralManager = nil
        connectedPeripheral = nil
        print("BLEManager disposed")
    }
    
    // MARK: - Central Manger Methods
    public func startScanning() {
        print("BLEManager will start scanning")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { //To wait until the centralManagerDidUpdateState(_ central: CBCentralManager) callback has been called. And then, verify that the state is PoweredOn before scanning for peripherals
            
            guard case .poweredOn = self.bleState else { return }
            self.centralManager.scanForPeripherals(withServices: [CBUUID(string: BLEManagerConstants.legacyServiceUUID), CBUUID(string: BLEManagerConstants.gcsServiceUUID)], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            print("BLEManager started scanning")
            
        }
    }
    
    public func stopScanning() {
        if centralManager.isScanning {
            print("BLEManager stopped scanning")
            centralManager.stopScan()
        }
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
    
    // MARK: - CBCentralManagerDelegate
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        
        connectedPeripheral = peripheral
        //        connectedPeripheral?.delegate = self
        //
        //        connectedPeripheral?.discoverServices([CBUUID(string: BLEManagerConstants.serviceUUID)])
        
        
        if let block = didConnectPeripheral {
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
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let block = self.didDiscoverDevice {
                let device = BLEDevice(peripheral: peripheral, advertisementData: advertisementData, rssiNumber: RSSI)
                block(device)
            }
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        if let block = peripheralDidUpdateName {
            block(BLEDevice(peripheral: peripheral))
        }
        print("Updated name: - \(peripheral.name ?? "no_name")")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        if let error = error {
            print("Error discovering services: - \(error.localizedDescription)")
            return
        }
        
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        if let error = error {
            print("Error discovering characteristics: - \(error.localizedDescription)")
            return
        }
        
        if service.uuid.isEqual(CBUUID(string: BLEManagerConstants.gcsRxUUID)) ||  service.uuid.isEqual(CBUUID(string: BLEManagerConstants.legacyRxUUID)){
            
            for characteristic: CBCharacteristic in service.characteristics! {
                
                if characteristic.uuid.isEqual(CBUUID(string: BLEManagerConstants.gcsRxUUID)) ||  characteristic.uuid.isEqual(CBUUID(string: BLEManagerConstants.legacyRxUUID)){
                    writeCharacteristic = characteristic
                    
                } else if characteristic.uuid.isEqual(CBUUID(string: BLEManagerConstants.gcsRxUUID)) ||  characteristic.uuid.isEqual(CBUUID(string: BLEManagerConstants.legacyRxUUID)){
                    readCharacteristic = characteristic
                }
            }
        }
        
        for characteristic in (service.characteristics)! where !characteristic.isNotifying {
            if readCharacteristic != nil && writeCharacteristic != nil {
                peripheral.setNotifyValue(true, for: readCharacteristic!)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        //Request
        if let error = error {
            print("Error writing value: \(error.localizedDescription)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Response
        // This method should not do any insertion/deletion in the queue or queue buffer.
        guard let data = characteristic.value else {
            print("Characteristic data is null.")
            return
        }
        
        //        //guard let first = queue.first else { return }
        //
        //        let count = data.count / MemoryLayout<UInt8>.size
        //        var array = [UInt8](repeating: 0, count: count)
        //
        //        (data as NSData).getBytes(&array, length: count)
        //
        //        handle(response: array, error: error, for: first)
    }
}


