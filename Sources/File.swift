//
//  File.swift
//  
//
//  Created by KO158L8 on 26/09/23.
//

import Foundation

public final class BLEManager: NSObject {
    
    // MARK: - Properties
    public struct Static {
        public static var shared: BLEManager?
    }
    
    public var shared: BLEManager {
        if Static.shared == nil { Static.shared = BLEManager() }
        return Static.shared!
    }
    
    deinit {
        print("Deinit called.")
    }
    
    public func log(string: String) {
        print(string)
    }
}
