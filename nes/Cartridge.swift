//
//  Cartridge.swift
//  nes
//
//  Created by mike on 8/2/25.
//

import Foundation

class Cartridge {
    func cpuRead(address: UInt16, data: inout UInt8) -> Bool {
        // Return true if cartridge handles this address
        return false
    }
    
    func cpuWrite(address: UInt16, data: UInt8) -> Bool {
        // Return true if cartridge handles this address
        return false
    }
    
    func ppuRead(address: UInt16, data: inout UInt8) -> Bool {
        return false
    }
    
    func ppuWrite(address: UInt16, data: UInt8) -> Bool {
        return false
    }
    
    func reset() {
        // Reset cartridge state
    }
}
