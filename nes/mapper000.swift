//
//  mapper000.swift
//  nes
//
//  Created by mike on 8/2/25.
//

// MARK: - Mapper 000 (NROM)
class Mapper000: Mapper {
    private let prgBanks: UInt8
    private let chrBanks: UInt8
    
    init(prgBanks: UInt8, chrBanks: UInt8) {
        self.prgBanks = prgBanks
        self.chrBanks = chrBanks
    }
    
    func cpuMapRead(addr: UInt16, mappedAddr: inout UInt32) -> Bool {
        // if PRGROM is 16KB
        //     CPU Address Bus          PRG ROM
        //     0x8000 -> 0xBFFF: Map    0x0000 -> 0x3FFF
        //     0xC000 -> 0xFFFF: Mirror 0x0000 -> 0x3FFF
        // if PRGROM is 32KB
        //     CPU Address Bus          PRG ROM
        //     0x8000 -> 0xFFFF: Map    0x0000 -> 0x7FFF
        if addr >= 0x8000 && addr <= 0xFFFF {
            mappedAddr = UInt32(addr & (prgBanks > 1 ? 0x7FFF : 0x3FFF))
            return true
        }
        return false
    }
    
    func cpuMapWrite(addr: UInt16, mappedAddr: inout UInt32) -> Bool {
        if addr >= 0x8000 && addr <= 0xFFFF {
            mappedAddr = UInt32(addr & (prgBanks > 1 ? 0x7FFF : 0x3FFF))
            return true
        }
        return false
    }
    
    func ppuMapRead(addr: UInt16, mappedAddr: inout UInt32) -> Bool {
        // There is no mapping required for PPU
        // PPU Address Bus          CHR ROM
        // 0x0000 -> 0x1FFF: Map    0x0000 -> 0x1FFF 
        if addr >= 0x0000 && addr <= 0x1FFF {
            mappedAddr = UInt32(addr)
            return true  // <-- This needs to return true!
        }

        return false
    }
    
    func ppuMapWrite(addr: UInt16, mappedAddr: inout UInt32) -> Bool {
        if addr >= 0x0000 && addr <= 0x1FFF && chrBanks == 0 {
            // Treat as CHR RAM
            mappedAddr = UInt32(addr)
            return true
        }
        return false
    }
    
    func reset() {
        // Nothing to reset for mapper 0
    }
}
