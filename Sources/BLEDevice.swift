//
//  File.swift
//  
//
//  Created by KO158L8 on 27/09/23.
//

import Foundation
import CoreBluetooth

public class BLEDevice {

    var peripheral: CBPeripheral!
    var advertisementData: [String: Any]!
    var rssiNumber: NSNumber!

    init(peripheral: CBPeripheral, advertisementData: [String: Any] = [:], rssiNumber: NSNumber = 0) {

        self.peripheral = peripheral
        self.advertisementData = advertisementData
        self.rssiNumber = rssiNumber

    }

    func getLocalName() -> String? {
        return advertisementData?[CBAdvertisementDataLocalNameKey] as? String
    }
}

// MARK: - Equatable
extension BLEDevice: Equatable {
    public static func == (lhs: BLEDevice, rhs: BLEDevice) -> Bool {
        return lhs.peripheral.identifier == rhs.peripheral.identifier
    }
}
