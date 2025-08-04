//
//  olc2C02.swift
//  nes
//
//  Created by mike on 8/2/25.
//
// PPU

import Foundation
import SpriteKit

private extension Bool {
    mutating func toggle() {
        self = !self
    }
}

class OLC2C02 {
    weak var bus: SystemBus?
    weak var cart: Cartridge?
    var nmi = false // when vblank occurs
    
    //    struct PPUControl {
    //        var reg: UInt8 = 0x00
    //
    //        var nametableX: Bool {
    //            get { reg & 0x01 != 0 }
    //            set { reg = newValue ? (reg | 0x01) : (reg & ~0x01) }
    //        }
    //
    //        var nametableY: Bool {
    //            get { reg & 0x02 != 0 }
    //            set { reg = newValue ? (reg | 0x02) : (reg & ~0x02) }
    //        }
    //
    //        var incrementMode: Bool {
    //            get { reg & 0x04 != 0 }
    //            set { reg = newValue ? (reg | 0x04) : (reg & ~0x04) }
    //        }
    //
    //        // Base nametable address (0 = $2000; 1 = $2400; 2 = $2800; 3 = $2C00)
    //        var baseNametableAddr: UInt16 {
    //            0x2000 + UInt16(reg & 0x03) * 0x400
    //        }
    //    }
    
    // MARK: - PPU Flags
    struct PPUControl: OptionSet {
        let rawValue: UInt8
        
        static let nametableX             = PPUControl(rawValue: 0x01)
        static let nametableY             = PPUControl(rawValue: 0x02)
        static let incrementMode          = PPUControl(rawValue: 0x04)
        static let spritePatternTable     = PPUControl(rawValue: 0x08)
        static let backgroundPatternTable = PPUControl(rawValue: 0x10)
        static let spriteSize             = PPUControl(rawValue: 0x20)
        static let clientMode             = PPUControl(rawValue: 0x40)
        static let enableNMI              = PPUControl(rawValue: 0x80)
    }
    
    struct PPUMask: OptionSet {
        let rawValue: UInt8
        
        static let grayscale              = PPUMask(rawValue: 0x01)
        static let showBackgroundLeft     = PPUMask(rawValue: 0x02)
        static let showSpritesLeft        = PPUMask(rawValue: 0x04)
        static let showBackground         = PPUMask(rawValue: 0x08)
        static let showSprites            = PPUMask(rawValue: 0x10)
        static let emphasizeRed           = PPUMask(rawValue: 0x20)
        static let emphasizeGreen         = PPUMask(rawValue: 0x40)
        static let emphasizeBlue          = PPUMask(rawValue: 0x80)
    }
    
    struct PPUStatus: OptionSet {
        let rawValue: UInt8
        
        static let spriteOverflow         = PPUStatus(rawValue: 0x20)
        static let spriteZeroHit          = PPUStatus(rawValue: 0x40)
        static let verticalBlank          = PPUStatus(rawValue: 0x80)
        // Lower 5 bits: "open bus"/unused
    }
    
    struct LoopyRegister {
        var reg: UInt16 = 0x0000
        
        var coarseX: UInt8 {
            get { UInt8(reg & 0x001F) }
            set { reg = (reg & ~0x001F) | UInt16(newValue & 0x1F) }
        }
        
        var coarseY: UInt8 {
            get { UInt8((reg >> 5) & 0x001F) }
            set { reg = (reg & ~0x03E0) | (UInt16(newValue & 0x1F) << 5) }
        }
        
        var nametableX: Bool {
            get { reg & 0x0400 != 0 }
            set { reg = newValue ? (reg | 0x0400) : (reg & ~0x0400) }
        }
        
        var nametableY: Bool {
            get { reg & 0x0800 != 0 }
            set { reg = newValue ? (reg | 0x0800) : (reg & ~0x0800) }
        }
        
        var fineY: UInt8 {
            get { UInt8((reg >> 12) & 0x07) }
            set { reg = (reg & ~0x7000) | (UInt16(newValue & 0x07) << 12) }
        }
    }
    
    // MARK: - VRAM & Palette
    private var tblName: [[UInt8]]  = Array(repeating: Array(repeating: 0, count: 1024), count: 2)
    private var tblPalette: [UInt8] = Array(repeating: 0, count: 32)
    
    // MARK: - Frame Output
    var framebuffer: [UInt8] = Array(repeating: 0, count: 256 * 240)
    var frameComplete = false
    
    // MARK: - PPU Timing
    var cycle: UInt16       = 0
    var scanline: UInt16    = 0
    
    // MARK: - PPU Registers (CPU accessible)
    var control: PPUControl = []
    var mask: PPUMask       = []
    var status: PPUStatus   = []
    
    // MARK: - Internal Registers
    private var vramAddr: UInt16    = 0x0000
    private var tempAddr: UInt16    = 0x0000
    private var fineX: UInt8        = 0x00
    private var addressLatch: UInt8 = 0x00
    
    // MARK: - OAM (Sprite memory)
    private var oam: [UInt8] = Array(repeating: 0, count: 256)
    private var ppuDataBuffer: UInt8    = 0x00  // For delayed reads
    private var oamAddr: UInt8          = 0x00  // OAM address pointer
    
    // MARK: - LoopyRegister
    private var vramAddrReg = LoopyRegister()  // "Real" VRAM address
    private var tempAddrReg = LoopyRegister()  // "Temporary" VRAM address
    
    // MARK: - Background Rendering
    private var bg_next_tile_id: UInt8          = 0x00
    private var bg_next_tile_attrib: UInt8      = 0x00
    private var bg_next_tile_lsb: UInt8         = 0x00
    private var bg_next_tile_msb: UInt8         = 0x00
    private var bg_shifter_pattern_lo: UInt16   = 0x0000
    private var bg_shifter_pattern_hi: UInt16   = 0x0000
    private var bg_shifter_attribute_lo: UInt16 = 0x0000
    private var bg_shifter_attribute_hi: UInt16 = 0x0000
    
    // MARK: - Background Rendering Helpers
    private func updateShifters() {
        if mask.contains(.showBackground) {
            // Shift the pattern shifters left by 1
            bg_shifter_pattern_lo <<= 1
            bg_shifter_pattern_hi <<= 1
            
            // Shift the attribute shifters left by 1
            bg_shifter_attribute_lo <<= 1
            bg_shifter_attribute_hi <<= 1
        }
    }

    private func loadBackgroundShifters() {
        // Load the pattern shifters with the fetched tile row
        bg_shifter_pattern_lo = (bg_shifter_pattern_lo & 0xFF00) | UInt16(bg_next_tile_lsb)
        bg_shifter_pattern_hi = (bg_shifter_pattern_hi & 0xFF00) | UInt16(bg_next_tile_msb)
        
        // Load the attribute shifters
        let attrib = (bg_next_tile_attrib & 0x03)  // 2-bit palette selection
        bg_shifter_attribute_lo = (bg_shifter_attribute_lo & 0xFF00) | (attrib & 0x01 != 0 ? 0xFF : 0x00)
        bg_shifter_attribute_hi = (bg_shifter_attribute_hi & 0xFF00) | (attrib & 0x02 != 0 ? 0xFF : 0x00)
    }

    private func fetchNametableByte() -> UInt8 {
        // Fetch tile ID from nametable
        let addr = 0x2000 | (vramAddrReg.reg & 0x0FFF)
        return ppuRead(addr)
    }

    private func fetchAttributeByte() -> UInt8 {
        // Fetch attribute byte (palette selection for 2x2 tile area)
        // TODO: - Should uint16 conversion happen before shift?
        let addr = 0x23C0
            | (UInt16(vramAddrReg.nametableY ? 1 : 0) << 11)
            | (UInt16(vramAddrReg.nametableX ? 1 : 0) << 10)
            | (UInt16(vramAddrReg.coarseY >> 2) << 3)
            | (UInt16(vramAddrReg.coarseX >> 2))
        
        let attrib = ppuRead(addr)
        
        // Determine which 2-bit section of the attribute byte to use
        if vramAddrReg.coarseY & 0x02 != 0 {
            // Bottom half of the 4x4 tile area
            if vramAddrReg.coarseX & 0x02 != 0 {
                // Bottom-right
                return (attrib >> 6) & 0x03
            } else {
                // Bottom-left
                return (attrib >> 4) & 0x03
            }
        } else {
            // Top half of the 4x4 tile area
            if vramAddrReg.coarseX & 0x02 != 0 {
                // Top-right
                return (attrib >> 2) & 0x03
            } else {
                // Top-left
                return attrib & 0x03
            }
        }
    }

    private func fetchPatternTableLow() -> UInt8 {
        // Fetch the low byte of the tile pattern
        let addr = (control.contains(.backgroundPatternTable) ? 0x1000 : 0x0000)
            + (UInt16(bg_next_tile_id) << 4)
            + UInt16(vramAddrReg.fineY)
        
        return ppuRead(addr)
    }

    private func fetchPatternTableHigh() -> UInt8 {
        // Fetch the high byte of the tile pattern (8 bytes after low)
        let addr = (control.contains(.backgroundPatternTable) ? 0x1000 : 0x0000)
            + (UInt16(bg_next_tile_id) << 4)
            + UInt16(vramAddrReg.fineY)
            + 8
        
        return ppuRead(addr)
    }

    private func incrementScrollX() {
        if mask.contains(.showBackground) || mask.contains(.showSprites) {
            if vramAddrReg.coarseX == 31 {
                vramAddrReg.coarseX = 0
                vramAddrReg.nametableX.toggle()
            } else {
                vramAddrReg.coarseX += 1
            }
        }
    }

    private func incrementScrollY() {
        if mask.contains(.showBackground) || mask.contains(.showSprites) {
            if vramAddrReg.fineY < 7 {
                vramAddrReg.fineY += 1
            } else {
                vramAddrReg.fineY = 0
                
                if vramAddrReg.coarseY == 29 {
                    vramAddrReg.coarseY = 0
                    vramAddrReg.nametableY.toggle()
                } else if vramAddrReg.coarseY == 31 {
                    vramAddrReg.coarseY = 0
                } else {
                    vramAddrReg.coarseY += 1
                }
            }
        }
    }

    private func transferAddressX() {
        if mask.contains(.showBackground) || mask.contains(.showSprites) {
            vramAddrReg.nametableX = tempAddrReg.nametableX
            vramAddrReg.coarseX = tempAddrReg.coarseX
        }
    }

    private func transferAddressY() {
        if mask.contains(.showBackground) || mask.contains(.showSprites) {
            vramAddrReg.fineY = tempAddrReg.fineY
            vramAddrReg.nametableY = tempAddrReg.nametableY
            vramAddrReg.coarseY = tempAddrReg.coarseY
        }
    }

    private func renderPixel() {
        let x = Int(cycle - 1)
        let y = Int(scanline)
        
        // Get the pixel from the shifters
        let bit_mux: UInt16 = 0x8000 >> fineX
        
        let p0_pixel: UInt8 = (bg_shifter_pattern_lo & bit_mux) > 0 ? 1 : 0
        let p1_pixel: UInt8 = (bg_shifter_pattern_hi & bit_mux) > 0 ? 1 : 0
        let bg_pixel: UInt8 = (p1_pixel << 1) | p0_pixel
        
        let bg_pal0: UInt8 = (bg_shifter_attribute_lo & bit_mux) > 0 ? 1 : 0
        let bg_pal1: UInt8 = (bg_shifter_attribute_hi & bit_mux) > 0 ? 1 : 0
        let bg_palette: UInt8 = (bg_pal1 << 1) | bg_pal0
        
        // Get the palette index (0-63)
        var paletteIndex: UInt8 = 0x00
        if bg_pixel == 0 {
            // Use the universal background color
            paletteIndex = ppuRead(0x3F00)
        } else {
            // Use the selected palette and pixel value
            paletteIndex = ppuRead(0x3F00 + (UInt16(bg_palette) << 2) + UInt16(bg_pixel))
        }
        
        // Store palette index in framebuffer
        if x < 256 && y < 240 {
            framebuffer[y * 256 + x] = paletteIndex
        }
    }
    
    // MARK: - Mirroring Helpers
    private func getMirroredNametableIndex(addr: UInt16) -> (table: Int, offset: Int) {
        let addr = addr & 0x0FFF
        let offset = Int(addr & 0x03FF)
        
        guard let mirrorMode = cart?.getMirrorMode() else {
            // Default to vertical if no cart
            return ((addr & 0x0400) != 0 ? 1 : 0, offset)
        }
        let table: Int
        switch mirrorMode {
        case .vertical:
            // Vertical: A B
            //          A B
            table = (addr & 0x0400) != 0 ? 1 : 0
        case .horizontal:
            // Horizontal: A A
            //            B B
            table = (addr & 0x0800) != 0 ? 1 : 0
        case .oneScreenLo:
            // All nametables map to first table
            table = 0
        case .oneScreenHi:
            // All nametables map to second table
            table = 1
        }
        return (table, offset)
    }
    
    // MARK: - External Connections
    func connectBus(_ bus: SystemBus) {
        self.bus = bus
    }
    
    func connectCartridge(_ cartridge: Cartridge) {
        self.cart = cartridge
    }
    
    //MARK: - Core Operations
    func clock() {
        // Background rendering happens on visible scanlines
        if scanline < 240 {  // Visible scanlines 0-239
            // Visible portion of the frame
            if cycle >= 1 && cycle <= 256 {
                // Shift the shift registers
                updateShifters()
                // Every 8 cycles we perform a set of fetches
                switch (cycle - 1) % 8 {
                case 0:
                    // Load the shifters with the previously fetched data
                    loadBackgroundShifters()
                    // Fetch nametable byte (tile ID)
                    bg_next_tile_id = fetchNametableByte()
                case 2:
                    // Fetch attribute byte
                    bg_next_tile_attrib = fetchAttributeByte()
                case 4:
                    // Fetch pattern table tile low byte
                    bg_next_tile_lsb = fetchPatternTableLow()
                case 6:
                    // Fetch pattern table tile high byte
                    bg_next_tile_msb = fetchPatternTableHigh()
                case 7:
                    // Increment scroll counters
                    incrementScrollX()
                default:
                    break
                }
            }
            
            // Prepare for next scanline
            if cycle == 256 {
                incrementScrollY()
            }
            if cycle == 257 {
                // Reset X position
                transferAddressX()
            }
            // Unused fetches at end of scanline (for MMC3 compatibility)
            if cycle == 337 || cycle == 339 {
                bg_next_tile_id = fetchNametableByte()
            }
            // Actually render the pixel
            if cycle >= 1 && cycle <= 256 {
                renderPixel()
            }
        }
        
        // Pre-render scanline
        if scanline == 261 {
            if cycle == 1 {
                // Clear vblank flag at start of pre-render line
                status.remove(.verticalBlank)
            }
            if cycle >= 280 && cycle <= 304 {
                // Reset Y position
                transferAddressY()
            }
        }
        
        // Vblank scanlines (241-260)
        if scanline == 241 && cycle == 1 {
            if cycle == 1 {
                status.insert(.verticalBlank)
                
                if control.contains(.enableNMI) {
                    nmi = true
                }
            }
        }
        
        // Advance cycle and scanline
        cycle += 1
        if cycle > 340 {
            cycle = 0
            scanline += 1
            
            if scanline > 261 {
                scanline = 0  // Wrap back to scanline 0
                frameComplete = true
            }
        }
    }
    
    func reset() {
        
    }
    
    func cpuWrite(_ addr: UInt16, _ data: UInt8) {
        switch addr {
        case 0x0000: // Control
            control = PPUControl(rawValue: data)
            
            tempAddrReg.nametableX = control.contains(.nametableX)
            tempAddrReg.nametableY = control.contains(.nametableY)
        case 0x0001: // Mask
            mask = PPUMask(rawValue: data)
            break
        case 0x0002: // Status
            // PPUSTATUS is read-only
            break
        case 0x0003: // OAM Address
            oamAddr = data
        case 0x0004: // OAM Data
            oam[Int(oamAddr)] = data
            oamAddr &+= 1
        case 0x0005: // Scroll
            if addressLatch == 0 {
                // First write (X scroll)
                fineX = data & 0x07
                tempAddrReg.coarseX = data >> 3
                addressLatch = 1
            } else {
                // Second write (Y scroll)
                tempAddrReg.fineY = data & 0x07
                tempAddrReg.coarseY = data >> 3
                addressLatch = 0
            }
        case 0x0006: // PPU Address
            if addressLatch == 0 {
                // First write (high byte)
                tempAddrReg.reg = (tempAddrReg.reg & 0x00FF) | (UInt16(data & 0x3F) << 8)
                addressLatch = 1
            } else {
                // Second write (low byte)
                tempAddrReg.reg = (tempAddrReg.reg & 0xFF00) | UInt16(data)
                vramAddrReg = tempAddrReg  // Copy temp to real address
                addressLatch = 0
            }
        case 0x0007: // PPU Data
            ppuWrite(vramAddrReg.reg, data)
            // Increment VRAM address based on control bit
            vramAddrReg.reg += control.contains(.incrementMode) ? 32 : 1
        default:
            break
        }
    }
    
    func cpuRead(_ addr: UInt16, _ readOnly: Bool = false) -> UInt8 {
        var data: UInt8 = 0x00
        
        switch addr {
        case 0x0000: // Control
            // Write-only
            break
        case 0x0001: // Mask
            // Write-only
            break
        case 0x0002: // Status
            // Reading status has side effects
            data = (status.rawValue & 0xE0) | (ppuDataBuffer & 0x1F)
            if !readOnly {
                status.remove(.verticalBlank)
                addressLatch = 0  // Reset latch
            }
        case 0x0003: // OAM Address
            // Write-only
            break
        case 0x0004: // OAM Data
            data = oam[Int(oamAddr)]
        case 0x0005: // Scroll
            // Write-only
            break
        case 0x0006: // PPU Address
            // Write-only
            break
        case 0x0007: // PPU Data
            // Delayed read (except for palette data)
            data = ppuDataBuffer
            ppuDataBuffer = ppuRead(vramAddrReg.reg)
            
            // Palette data isn't delayed
            if vramAddrReg.reg >= 0x3F00 {
                data = ppuDataBuffer
            }
            // Auto-increment
            vramAddrReg.reg += control.contains(.incrementMode) ? 32 : 1
        default:
            break
        }
        return data
    }
    
    func ppuRead(_ addr: UInt16, _ readOnly: Bool = false) -> UInt8 {
        var data: UInt8 = 0x00
        let address = addr & 0x3FFF
        
        if address >= 0x0000 && address <= 0x1FFF {
            // Pattern table (CHR ROM/RAM on cartridge)
            _ = cart?.ppuRead(address: address, data: &data)
        } else if address >= 0x2000 && address <= 0x3EFF {
            // Nametable RAM
            let (table, offset) = getMirroredNametableIndex(addr: address)
            data = tblName[table][offset]
        } else if address >= 0x3F00 && address <= 0x3FFF {
            // Palette RAM
            var paletteAddr = address & 0x001F
            
            if paletteAddr == 0x0010 { paletteAddr = 0x0000 }
            else if paletteAddr == 0x0014 { paletteAddr = 0x0004 }
            else if paletteAddr == 0x0018 { paletteAddr = 0x0008 }
            else if paletteAddr == 0x001C { paletteAddr = 0x000C }
            
            data = tblPalette[Int(paletteAddr)]
        }
        
        return data
    }
    
    func ppuWrite(_ addr: UInt16, _ data: UInt8) {
        let address = addr & 0x3FFF
        
        if address >= 0x0000 && address <= 0x1FFF {
            // Pattern table (CHR ROM/RAM on cartridge)
            _ = cart?.ppuWrite(address: address, data: data)
        } else if address >= 0x2000 && address <= 0x3EFF {
            // Nametable RAM
            let (table, offset) = getMirroredNametableIndex(addr: address)
            tblName[table][offset] = data
        } else if address >= 0x3F00 && address <= 0x3FFF {
            // Palette RAM
            var paletteAddr = address & 0x001F
            
            if paletteAddr == 0x0010 { paletteAddr = 0x0000 }
            else if paletteAddr == 0x0014 { paletteAddr = 0x0004 }
            else if paletteAddr == 0x0018 { paletteAddr = 0x0008 }
            else if paletteAddr == 0x001C { paletteAddr = 0x000C }
            
            tblPalette[Int(paletteAddr)] = data
        }
    }
}

