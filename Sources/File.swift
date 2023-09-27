//
//  File.swift
//  
//
//  Created by KO158L8 on 26/09/23.
//

import Foundation

public final class BLEManager: NSObject {
    public static var shared = BLEManager()

    deinit {
        print("Deinit called.")
    }
    
    public func log(string: String) {
        print(string)
    }
}
