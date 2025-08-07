//
//  bus.swift
//  nes
//
//  Created by mike on 7/27/25.
//
// SystemBus (owns with strong references)
//    ├── cpu: OLC6502 (strong)
//    │     └── bus: SystemBus? (weak) <- Points back to parent
//    ├── ppu: OLC2C02 (strong)
//    │     ├── bus: SystemBus? (weak) <- Points back to parent
//    │     └── cart: Cartridge? (weak) <- Doesn't own the cartridge
//    └── cart: Cartridge? (strong) <- SystemBus owns the cartridge

import Foundation

class SystemBus: Bus {
    let cpu: OLC6502
    let ppu: OLC2C02
    var cart: Cartridge?
    var cpuRam: [UInt8]
    
    private var systemClockCounter: UInt32 = 0
    
    init() {
        cpu = OLC6502()
        ppu = OLC2C02()
        cpuRam = Array(repeating: 0x00, count: 64 * 1024)
        
        cpu.connectBus(self)
        ppu.connectBus(self)
    }
    
    func read(address: UInt16) -> UInt8 {
        return cpuRead(address: address, readOnly: false)
    }
    
    func write(address: UInt16, data: UInt8) {
        cpuWrite(address: address, data: data)
    }
    
    func cpuWrite(address: UInt16, data: UInt8) {
        // Try cartridge first
        if let cart = cart, cart.cpuWrite(address: address, data: data) {
            return  // Cartridge handled it
        }
        if address == 0x4014 {
            // OAM DMA - copy 256 bytes from CPU page to OAM
            let page = UInt16(data) << 8
            
            // DEBUG
            print("DMA from page \(String(format: "%02X", data)) (address \(String(format: "%04X", page)))")

            
            for i in 0..<256 {
                let byte = cpuRead(address: page + UInt16(i), readOnly: true)
                ppu.writeOAM(addr: UInt8(i), data: byte)
            }
            // DMA takes 513 or 514 CPU cycles
            // For now, we'll just do it instantly
            return
        }
        // No cartridge or cartridge didn't handle it
        if address >= 0x0000 && address <= 0x1FFF {
            cpuRam[Int(address & 0x07FF)] = data
        }
        else if address >= 0x2000 && address <= 0x3FFF {
            ppu.cpuWrite(address & 0x0007, data)
        }
        else if address >= 0x8000 && address <= 0xFFFF {
            // For testing without cartridge - write to RAM
            cpuRam[Int(address)] = data
        }
    }
    
    func cpuRead(address: UInt16, readOnly: Bool = false) -> UInt8 {
        var data: UInt8 = 0x00
        
        // Try cartridge first
        if let cart = cart, cart.cpuRead(address: address, data: &data) {
            return data  // Cartridge provided data
        }
        
        // No cartridge or cartridge didn't handle it
        if address >= 0x0000 && address <= 0x1FFF {
            return cpuRam[Int(address & 0x07FF)]
        }
        else if address >= 0x2000 && address <= 0x3FFF {
            return ppu.cpuRead(address & 0x0007, readOnly)
        }
        else if address >= 0x8000 && address <= 0xFFFF {
            // For testing without cartridge - read from RAM
            return cpuRam[Int(address)]
        }
        
        return data
    }
    
    // MARK: - System Interface
    func insertCartridge(_ cartridge: Cartridge) {
        self.cart = cartridge
        ppu.connectCartridge(cartridge)
    }
    
    func reset() {
        cpu.reset()
        ppu.reset()
        cart?.reset()
        systemClockCounter = 0
    }
    
    func clock() {
        ppu.clock()
        
        if systemClockCounter % 3 == 0 {
            cpu.clock();
        }
        
        if (ppu.nmi) {
            ppu.nmi = false
            cpu.nmi()
        }
        systemClockCounter += 1
    }
}
