//
//  bus.swift
//  nes
//
//  Created by mike on 7/27/25.
//

import Foundation

class SystemBus: Bus {
    let cpu: OLC6502
    var ram: [UInt8]
    
    init() {
        cpu = OLC6502()
        ram = Array(repeating: 0x00, count: 64 * 1024)
        
        cpu.connectBus(self)
    }
    
    func write(address: UInt16, data: UInt8) {
        if address >= 0x0000 && address <= 0xFFFF {
            ram[Int(address)] = data
        }
    }
    
    func read(address: UInt16) -> UInt8 {
        if address >= 0x0000 && address <= 0xFFFF {
            return ram[Int(address)]
        }
        return 0x00
    }
    
    func read(address: UInt16, readOnly: Bool) -> UInt8 {
        if address >= 0x0000 && address <= 0xFFFF {
            return ram[Int(address)]
        }
        return 0x00
    }
}
