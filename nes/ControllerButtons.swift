//
//  Input.swift
//  nes
//
//  Created by mike on 8/5/25.
//

import Foundation

struct Controller: OptionSet {
    let rawValue: UInt8
    
    static let a       = Controller(rawValue: 0x01) // bit 0 (read first)
    static let b       = Controller(rawValue: 0x02) // bit 1
    static let select  = Controller(rawValue: 0x04) // bit 2
    static let start   = Controller(rawValue: 0x08) // bit 3
    static let up      = Controller(rawValue: 0x10) // bit 4
    static let down    = Controller(rawValue: 0x20) // bit 5
    static let left    = Controller(rawValue: 0x40) // bit 6
    static let right   = Controller(rawValue: 0x80) // bit 7 (read last)
}



