//
//  olc2C02.swift
//  nes
//
//  Created by mike on 8/2/25.
//
// PPU

import Foundation

class OLC2C02 {
    weak var bus: SystemBus?
    weak var cart: Cartridge?
    var nmi = false // when vblank occurs

    // VRAM
    private var tblName: [[UInt8]] = Array(repeating: Array(repeating: 0, count: 1024), count: 2)
    
    // Pallete
    private var tblPalette: [UInt8] = Array(repeating: 0, count: 32)
    
    func connectBus(_ bus: SystemBus) {
        self.bus = bus
    }
    
    func connectCartridge(_ cartridge: Cartridge) {
        self.cart = cartridge
    }
    
    func clock() {
        
    }
    
    func reset() {
        
    }
    
    func cpuWrite(_ addr: UInt16, _ data: UInt8) {
        switch addr {
        case 0x0000: // Control
            // Handle PPUCTRL write
            break
        case 0x0001: // Mask
            // Handle PPUMASK write
            break
        case 0x0002: // Status
            // PPUSTATUS is read-only
            break
        case 0x0003: // OAM Address
            // Handle OAMADDR write
            break
        case 0x0004: // OAM Data
            // Handle OAMDATA write
            break
        case 0x0005: // Scroll
            // Handle PPUSCROLL write
            break
        case 0x0006: // PPU Address
            // Handle PPUADDR write
            break
        case 0x0007: // PPU Data
            // Handle PPUDATA write
            break
        default:
            break
        }
    }
    
    func cpuRead(_ addr: UInt16, _ readOnly: Bool = false) -> UInt8 {
        var data: UInt8 = 0x00
        
        switch addr {
        case 0x0000: // Control
            // Control is write-only
            break
        case 0x0001: // Mask
            // Mask is write-only
            break
        case 0x0002: // Status
            // Return PPUSTATUS and clear vblank flag if not readonly
            data = registers[2]
            if !readOnly {
                // Clear vblank flag after reading
                registers[2] &= ~0x80
            }
        case 0x0003: // OAM Address
            // OAM Address is write-only
            break
        case 0x0004: // OAM Data
            // Return OAM data
            data = registers[4]
        case 0x0005: // Scroll
            // Scroll is write-only
            break
        case 0x0006: // PPU Address
            // PPU Address is write-only
            break
        case 0x0007: // PPU Data
            // Return PPU data
            data = registers[7]
        default:
            break
        }
        
        return data
    }
    
    func ppuRead(_ addr: UInt16, _ readOnly: Bool = true) -> UInt8 {
        let data: UInt8 = 0x00
        let maskedAddr = addr & 0x3FFF
        
        return data
    }
    
    func ppuWrite(_ addr: UInt16, _ data: UInt8) {
        let maskedAddr = addr & 0x3FFF
    }
}

