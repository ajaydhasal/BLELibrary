//
//  File.swift
//  
//
//  Created by KO158L8 on 07/11/23.
//

import Foundation
extension Array {

    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }

    subscript (safe index: Int) -> Element? {
        return indices ~= index ? self[index] : nil
    }
}
