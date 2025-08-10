//
//  olc2C02.swift
//  nes
//
//  Created by mike on 8/2/25.
//
// PPU

import Foundation

// TODO: - is this dumb?
private extension Bool {
    mutating func toggle() {
        self = !self
    }
}

class OLC2C02 {
    weak var bus: SystemBus?
    weak var cart: Cartridge?
    var nmi = false // when vblank occurs
    var frameCount: Int = 0
    
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
    
    struct OAMEntry {
        let y: UInt8        // Y position
        let id: UInt8       // Tile ID
        let attribute: UInt8 // Attributes (palette, flip, priority)
        let x: UInt8        // X position
        
        var palette: UInt8 { (attribute & 0x03) + 4 }  // Sprite palettes are 4-7
        var priority: Bool { attribute & 0x20 == 0 }   // 0 = front, 1 = behind
        var flipH: Bool { attribute & 0x40 != 0 }
        var flipV: Bool { attribute & 0x80 != 0 }
    }
    
    // MARK: - VRAM & Palette
    private var tblName: [[UInt8]]  = Array(repeating: Array(repeating: 0, count: 1024), count: 2)
    private var tblPalette: [UInt8] = Array(repeating: 0, count: 32)
    
    // MARK: - Frame Output
    internal var framebuffer: [UInt32] = Array(repeating: 0xFF000000, count: 256 * 240)
    internal var frameComplete = false
    
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
    internal var oam: [UInt8] = Array(repeating: 0, count: 256)
    private var ppuDataBuffer: UInt8    = 0x00  // For delayed reads
    private var oamAddr: UInt8          = 0x00  // OAM address pointer
    
    // MARK: - LoopyRegister
    private var vramAddrReg = LoopyRegister()  // Real VRAM address
    private var tempAddrReg = LoopyRegister()  // Temporary VRAM address
    
    // MARK: - Background Rendering
    private var bg_next_tile_id: UInt8          = 0x00
    private var bg_next_tile_attrib: UInt8      = 0x00
    private var bg_next_tile_lsb: UInt8         = 0x00
    private var bg_next_tile_msb: UInt8         = 0x00
    private var bg_shifter_pattern_lo: UInt16   = 0x0000
    private var bg_shifter_pattern_hi: UInt16   = 0x0000
    private var bg_shifter_attribute_lo: UInt16 = 0x0000
    private var bg_shifter_attribute_hi: UInt16 = 0x0000
    private var pixelDebugCount                 = 0
    
    
    //MARK: - Sprite Rendering
    private var spriteScanline: [OAMEntry] = []  // Sprites on current scanline
    internal var spriteCount: Int = 0
    private var spriteShifterPatternLo: [UInt8] = Array(repeating: 0, count: 8)
    private var spriteShifterPatternHi: [UInt8] = Array(repeating: 0, count: 8)
    internal var spriteZeroHitPossible = false
    private var spriteZeroBeingRendered = false
    
    func writeOAM(addr: UInt8, data: UInt8) {
        oam[Int(addr)] = data
        #if DEBUG_GRANULAR
        if addr < 4 {
            print("writeOAM[\(addr)] = \(String(format: "%02X", data))")
        }
        #endif
    }
    
    // MARK: - Debug Visualization
    private var patternTableDebug: [[UInt32]] = [
        Array(repeating: 0xFF000000, count: 128 * 128),  // Pattern table 0
        Array(repeating: 0xFF000000, count: 128 * 128)   // Pattern table 1
    ]
    
    private var nametableDebug: [[UInt32]] = [
        Array(repeating: 0xFF000000, count: 256 * 240),  // Nametable 0
        Array(repeating: 0xFF000000, count: 256 * 240)   // Nametable 1
    ]
    
    private var internalPatternTables: [[UInt8]] = [
        Array(repeating: 0, count: 0x1000),  // $0000-$0FFF
        Array(repeating: 0, count: 0x1000)   // $1000-$1FFF
    ]
    
    var testPatternTable: [UInt8]? = nil
    
    
    // MARK: - Background Rendering Helpers
    private func fetchSpritePatterns() {
        for i in 0..<spriteCount {
            let sprite = spriteScanline[i]
            
            // Calculate pattern address
            var spritePatternAddrLo: UInt16 = 0
            var spritePatternAddrHi: UInt16 = 0
            
            if !control.contains(.spriteSize) {
                // 8x8 sprites
                let patternTable: UInt16 = control.contains(.spritePatternTable) ? 0x1000 : 0x0000
                
                // Handle vertical flip
                var row = (scanline + 1) - UInt16(sprite.y)
                if sprite.flipV {
                    row = 7 &- row
                }
                
                spritePatternAddrLo = patternTable | (UInt16(sprite.id) << 4) | row
            } else {
                // 8x16 sprites - TODO: implement later
            }
            
            spritePatternAddrHi = spritePatternAddrLo &+ 8
            
            // Fetch the patterns
            var patternLo = ppuRead(spritePatternAddrLo)
            var patternHi = ppuRead(spritePatternAddrHi)
            
            // Handle horizontal flip
            if sprite.flipH {
                patternLo = flipByte(patternLo)
                patternHi = flipByte(patternHi)
            }
            
            spriteShifterPatternLo[i] = patternLo
            spriteShifterPatternHi[i] = patternHi
            
            #if DEBUG_GRANULAR
            if i == 0 {  // Sprite 0 debug
                print("Sprite 0 pattern: scanline=\(scanline), spriteY=\(sprite.y), row=\(scanline - UInt16(sprite.y))")
                print("  PatternTable=\(control.contains(.spritePatternTable) ? "1000" : "0000"), tile=\(sprite.id)")
                print("  AddrLo=\(String(format: "%04X", spritePatternAddrLo)), AddrHi=\(String(format: "%04X", spritePatternAddrHi))")
                print("  PatternLo=\(String(format: "%02X", patternLo)), PatternHi=\(String(format: "%02X", patternHi))")
                print("  Attribute=\(String(format: "%02X", sprite.attribute)), flipH=\(sprite.flipH), flipV=\(sprite.flipV)")
            }
            #endif
        }
    }
    
    private func flipByte(_ b: UInt8) -> UInt8 {
        var b = b
        b = (b & 0xF0) >> 4 | (b & 0x0F) << 4
        b = (b & 0xCC) >> 2 | (b & 0x33) << 2
        b = (b & 0xAA) >> 1 | (b & 0x55) << 1
        return b
    }
    
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
        
        let attrib = bg_next_tile_attrib & 0x03  // 2-bit palette selection
        
        // Expand 2-bit palette to 8 bits (each bit becomes 0x00 or 0xFF)
        let attribBit0 = (attrib & 0x01) != 0 ? UInt16(0xFF) : UInt16(0x00)
        let attribBit1 = (attrib & 0x02) != 0 ? UInt16(0xFF) : UInt16(0x00)
        
        bg_shifter_attribute_lo = (bg_shifter_attribute_lo & 0xFF00) | attribBit0
        bg_shifter_attribute_hi = (bg_shifter_attribute_hi & 0xFF00) | attribBit1
    }
    
    private func fetchNametableByte() -> UInt8 {
        // Fetch tile ID from nametable
        let addr = 0x2000 | (vramAddrReg.reg & 0x0FFF)
        return ppuRead(addr)
    }
    
    private func fetchAttributeByte() -> UInt8 {
        // IMPROVEMENT: Cleaner attribute calculation with explicit UInt16 conversions
        let addr = 0x23C0
        | (vramAddrReg.nametableY ? 0x800 : 0x000)  // Bit 11
        | (vramAddrReg.nametableX ? 0x400 : 0x000)  // Bit 10
        | (UInt16(vramAddrReg.coarseY >> 2) << 3)   // Bits 6-3
        | UInt16(vramAddrReg.coarseX >> 2)          // Bits 2-0
        
        let attrib = ppuRead(addr)
        
        // Determine which 2-bit section of the attribute byte to use
        let quadrantY = (vramAddrReg.coarseY & 0x02) != 0
        let quadrantX = (vramAddrReg.coarseX & 0x02) != 0
        
        switch (quadrantY, quadrantX) {
        case (false, false): return attrib & 0x03        // Top-left
        case (false, true):  return (attrib >> 2) & 0x03 // Top-right
        case (true, false):  return (attrib >> 4) & 0x03 // Bottom-left
        case (true, true):   return (attrib >> 6) & 0x03 // Bottom-right
        }
    }
    
    private func fetchPatternTableLow() -> UInt8 {
        // Fetch the low byte of the tile pattern
        let patternTable: UInt16 = control.contains(.backgroundPatternTable) ? 0x1000 : 0x0000
        let addr = patternTable
        + (UInt16(bg_next_tile_id) << 4)
        + UInt16(vramAddrReg.fineY)
        
        return ppuRead(addr)
    }
    
    private func fetchPatternTableHigh() -> UInt8 {
        // Fetch the high byte of the tile pattern (8 bytes after low)
        let patternTable: UInt16 = control.contains(.backgroundPatternTable) ? 0x1000 : 0x0000
        let addr = patternTable
        + (UInt16(bg_next_tile_id) << 4)
        + UInt16(vramAddrReg.fineY)
        + 8
        
        return ppuRead(addr)
    }
    
    private func incrementScrollX() {
        // IMPROVEMENT: Add rendering condition check for better accuracy
        if (mask.contains(.showBackground) || mask.contains(.showSprites)) &&
            (scanline < 240 || scanline == 261) {  // Only during rendering scanlines
            if vramAddrReg.coarseX == 31 {
                vramAddrReg.coarseX = 0
                vramAddrReg.nametableX.toggle()
            } else {
                vramAddrReg.coarseX += 1
            }
        }
    }
    
    private func incrementScrollY() {
        // IMPROVEMENT: Add rendering condition check for better accuracy
        if (mask.contains(.showBackground) || mask.contains(.showSprites)) &&
            (scanline < 240 || scanline == 261) {  // Only during rendering scanlines
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
        if (mask.contains(.showBackground) || mask.contains(.showSprites)) &&
            (scanline < 240 || scanline == 261) {  // Only during rendering scanlines
            vramAddrReg.nametableX = tempAddrReg.nametableX
            vramAddrReg.coarseX = tempAddrReg.coarseX
        }
    }
    
    private func transferAddressY() {
        if (mask.contains(.showBackground) || mask.contains(.showSprites)) &&
            (scanline < 240 || scanline == 261) {  // Only during rendering scanlines
            vramAddrReg.fineY = tempAddrReg.fineY
            vramAddrReg.nametableY = tempAddrReg.nametableY
            vramAddrReg.coarseY = tempAddrReg.coarseY
        }
    }
    
    private func renderPixel() {
        guard mask.contains(.showBackground) || mask.contains(.showSprites) else { return }
        
        let x = Int(cycle - 1)
        let y = Int(scanline)
        
        
        // Get background pixel
        var bgPixel: UInt8 = 0
        var bgPalette: UInt8 = 0
        
        
        
        if mask.contains(.showBackground) {
            // Check if we should show background on left edge
            if mask.contains(.showBackgroundLeft) || x >= 8 {
                let bitMux: UInt16 = 0x8000 >> fineX
                
                let p0 = (bg_shifter_pattern_lo & bitMux) != 0 ? 1 : 0
                let p1 = (bg_shifter_pattern_hi & bitMux) != 0 ? 1 : 0
                bgPixel = UInt8((p1 << 1) | p0)
                
                let pal0 = (bg_shifter_attribute_lo & bitMux) != 0 ? 1 : 0
                let pal1 = (bg_shifter_attribute_hi & bitMux) != 0 ? 1 : 0
                bgPalette = UInt8((pal1 << 1) | pal0)
            }
        }
        
        // Get sprite pixel
        var spritePixel: UInt8 = 0
        var spritePalette: UInt8 = 0
        var spritePriority = false
        
        #if DEBUG_GRANULAR
        if x >= 88 && x < 96 && y == 25 {
            let bgVisible = mask.contains(.showBackground) &&
            (mask.contains(.showBackgroundLeft) || x >= 8)
            let spritesVisible = mask.contains(.showSprites) &&
            (mask.contains(.showSpritesLeft) || x >= 8)
            print("""
            [Sprite 0 Hit Debug] x=\(x) y=\(y) scanline=\(scanline) cycle=\(cycle)
              spriteZeroHitPossible=\(spriteZeroHitPossible)
              spriteZeroBeingRendered=\(spriteZeroBeingRendered)
              bgPixel=\(bgPixel) spritePixel=\(spritePixel)
              bgVisible=\(bgVisible) spritesVisible=\(spritesVisible)
              status.contains(.spriteZeroHit)=\(status.contains(.spriteZeroHit))
            """)
        }
        #endif

        
        if mask.contains(.showSprites) {
            spriteZeroBeingRendered = false
            
            for i in 0..<spriteCount {
                let sprite = spriteScanline[i]
                
                // Check if sprite is in range for this pixel
                let spriteX = Int(sprite.x)
                if x >= spriteX && x < spriteX + 8 {
                    let pixelX = x - spriteX
                    
                    let p0 = (spriteShifterPatternLo[i] & (0x80 >> pixelX)) != 0 ? 1 : 0
                    let p1 = (spriteShifterPatternHi[i] & (0x80 >> pixelX)) != 0 ? 1 : 0
                    let pixel = UInt8((p1 << 1) | p0)
                    
                    if pixel != 0 {  // Non-transparent pixel
                        if i == 0 && spriteZeroHitPossible {
                            spriteZeroBeingRendered = true
                        }
                        
                        if spritePixel == 0 {  // Use first non-transparent sprite
                            spritePixel = pixel
                            spritePalette = sprite.palette
                            spritePriority = sprite.priority
                        }
                    }
                }
            }
        }
        
        // Combine background and sprite
        var finalPixel: UInt8 = 0
        var finalPalette: UInt8 = 0
        
        if bgPixel == 0 && spritePixel == 0 {
            // Both transparent - use backdrop
            finalPixel = 0
            finalPalette = 0
        } else if bgPixel == 0 && spritePixel != 0 {
            // Only sprite visible
            finalPixel = spritePixel
            finalPalette = spritePalette
        } else if bgPixel != 0 && spritePixel == 0 {
            // Only background visible
            finalPixel = bgPixel
            finalPalette = bgPalette
        } else {
            // Both visible - check priority
            if spritePriority {
                finalPixel = spritePixel
                finalPalette = spritePalette
            } else {
                finalPixel = bgPixel
                finalPalette = bgPalette
            }
            
            
            // Sprite 0 hit detection
            if spriteZeroHitPossible && spriteZeroBeingRendered {
                let bgVisible = mask.contains(.showBackground) &&
                (mask.contains(.showBackgroundLeft) || x >= 8)
                let spritesVisible = mask.contains(.showSprites) &&
                (mask.contains(.showSpritesLeft) || x >= 8)
                if bgVisible && spritesVisible && !status.contains(.spriteZeroHit) {
                    #if DEBUG_GRANULAR
                    print("Sprite 0 Hit SET at X=\(x), Y=\(y), scanline=\(scanline), cycle=\(cycle)")
                    #endif
                    status.insert(.spriteZeroHit)
                }
            }
        }
        
        #if DEBUG_GRANULAR
        if y == 25 && x >= 88 && x < 96 {
            print("At Sprite 0 area: x=\(x), y=\(y), bgPixel=\(bgPixel), spritePixel=\(spritePixel)")
        }

        if x == 50 && y == 50 {
            // Background nametable lookup
            let tileX = x / 8
            let tileY = y / 8
            let nametableIndex = tileY * 32 + tileX
            let ntselect = Int((control.contains(.nametableX) ? 1 : 0) | (control.contains(.nametableY) ? 2 : 0))
            let bgTileIndex = tblName[ntselect][nametableIndex]

            // Print pattern table bytes for BG and Sprite
            print("At (50,50):")
            print("  BG: tile=\(String(format: "%02X", bgTileIndex)), patternlsb=\(String(format: "%02X", bg_next_tile_lsb)), patternmsb=\(String(format: "%02X", bg_next_tile_msb)), bgPixel=\(bgPixel)")
            print("  Sprite0: OAM[0]=\(oam[0]) OAM[1]=\(oam[1]) OAM[2]=\(oam[2]) OAM[3]=\(oam[3]), spritePixel=\(spritePixel), spriteZeroBeingRendered=\(spriteZeroBeingRendered)")
            print("  mask=\(mask), control=\(control)")
            print("  spriteZeroHitPossible=\(spriteZeroHitPossible), status=\(status)")
        }
        #endif
        
        // Get final color
        var paletteAddr: UInt16 = 0x3F00
        if finalPixel == 0 {
            paletteAddr = 0x3F00  // Universal backdrop
        } else {
            // Check if the final pixel came from a sprite or background
            if spritePixel != 0 && (bgPixel == 0 || !spritePriority) {
                // Final pixel is from sprite - use sprite palette base (0x3F10)
                paletteAddr = 0x3F10 + (UInt16(finalPalette) << 2) + UInt16(finalPixel)
            } else {
                // Final pixel is from background - use background palette base (0x3F00)
                paletteAddr = 0x3F00 + (UInt16(finalPalette) << 2) + UInt16(finalPixel)
            }
        }
        
        let paletteIndex = ppuRead(paletteAddr)
        
        // Store RGB value
        if x < 256 && y < 240 {
            framebuffer[y * 256 + x] = NESPalette.getColor(paletteIndex)
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
            // Background tile fetching pipeline
            if (cycle >= 2 && cycle < 258) || (cycle >= 321 && cycle < 338) {
                updateShifters()
                
                // Every 8 cycles we perform a set of fetches
                switch (cycle - 1) % 8 {
                case 0:
                    // Load the current background tile pattern and attributes into the "shifter"
                    // The bottom 12 bits of the loopy register provide an index into
                    // the 4 nametables, regardless of nametable mirroring configuration.
                    // nametable_y(1) nametable_x(1) coarse_y(5) coarse_x(5)
                    loadBackgroundShifters()
                    bg_next_tile_id = fetchNametableByte()
                case 2:
                    bg_next_tile_attrib = fetchAttributeByte()
                case 4:
                    bg_next_tile_lsb = fetchPatternTableLow()
                case 6:
                    bg_next_tile_msb = fetchPatternTableHigh()
                case 7:
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
                transferAddressX()
                
                #if DEBUG_GRANULAR
                print("=== OAM Debug at cycle 257, scanline \(scanline) ===")
                print("OAM[0]: Y=\(oam[0]), Tile=\(oam[1]), Attr=\(oam[2]), X=\(oam[3])")
                print("Looking for sprites on scanline \(scanline)")
                #endif
                // Sprite evaluation happens here
                spriteScanline = []
                spriteCount = 0
                spriteZeroHitPossible = false
                
                // Evaluate which sprites are visible on the CURRENT scanline (not next)
                for n in 0..<64 {
                    let spriteY = oam[n * 4]
                    let spriteHeight: Int = control.contains(.spriteSize) ? 16 : 8
                    let diff = Int(scanline) - Int(spriteY)  // Changed: use current scanline
                                        
                    if diff >= 0 && diff < spriteHeight && spriteCount < 8 {
                        let entry = OAMEntry(
                            y: spriteY,
                            id: oam[n * 4 + 1],
                            attribute: oam[n * 4 + 2],
                            x: oam[n * 4 + 3]
                        )
                        
                        spriteScanline.append(entry)
                        
                        if n == 0 {
                            spriteZeroHitPossible = true
                        }
                        
                        spriteCount += 1
                    }
                }
                
                if spriteCount >= 8 {
                    status.insert(.spriteOverflow)
                }

            }
            
            // Actually render the pixel
            if cycle >= 1 && cycle <= 256 {
                renderPixel()
            }
            
            // Fetch sprite patterns
            if cycle == 320 {
                fetchSpritePatterns()
            }
            
            // Unused fetches at end of scanline (for MMC3 compatibility)
            if cycle == 337 || cycle == 339 {
                bg_next_tile_id = fetchNametableByte()
            }
        }
        
        
        // Vblank
        if scanline == 241 && cycle == 1 {
            status.insert(.verticalBlank)
            if control.contains(.enableNMI) {
                nmi = true
            }
        }
        
        // Pre-render scanline
        if scanline == 261 {
            if cycle == 1 {
                let hadVBlank = status.contains(.verticalBlank)
                status.remove(.verticalBlank)
                status.remove(.spriteZeroHit)
                status.remove(.spriteOverflow)
                if hadVBlank {
                    print("PPU: VBlank cleared at pre-render")
                }
            }
        }
        #if DEBUG_GRANULAR
        if scanline == 0 && cycle == 1 {
            print("Sprite 0 OAM: Y=\(oam[0]), Tile=\(oam[1]), Attr=\(oam[2]), X=\(oam[3])")
        }
        #endif
        
        // Advance cycle and scanline
        cycle += 1
        if cycle > 340 {
            cycle = 0
            scanline += 1
            
            if scanline > 261 {
                scanline = 0
                frameComplete = true
                frameCount += 1
                //                print("PPU: Frame \(frameCount) complete")
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
                // First write to scroll register contains X offset in pixel space
                // which we split into coarse and fine x values
                fineX = data & 0x07 //
                tempAddrReg.coarseX = data >> 3
                addressLatch = 1
            } else {
                // Second write (Y scroll)
                tempAddrReg.fineY = data & 0x07 // Bottom 3 bits
                tempAddrReg.coarseY = data >> 3 // Top 5 bits
                addressLatch = 0
            }
        case 0x0006: // PPU Address
            if addressLatch == 0 {
                // First write (high byte)
                // PPU address bus can be accessed by CPU via the ADDR and DATA
                // registers. The fisrt write to this register latches the high byte
                // of the address, the second is the low byte. Note the writes
                // are stored in the tram register...
                tempAddrReg.reg = (tempAddrReg.reg & 0x00FF) | (UInt16(data & 0x3F) << 8)
                addressLatch = 1
            } else {
                // Second write (low byte)
                // ...when a whole address has been written, the internal vram address
                // buffer is updated. Writing to the PPU is unwise during rendering
                // as the PPU will maintam the vram address automatically whilst
                // rendering the scanline position.
                tempAddrReg.reg = (tempAddrReg.reg & 0xFF00) | UInt16(data)
                vramAddrReg = tempAddrReg  // Copy temp to real address
                addressLatch = 0
            }
        case 0x0007: // PPU Data
            ppuWrite(vramAddrReg.reg, data)
            // All writes from PPU data automatically increment the nametable
            // address depending upon the mode set in the control register.
            // If set to vertical mode, the increment is 32, so it skips
            // one whole nametable row; in horizontal mode it just increments
            // by 1, moving to the next column
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
            //            print("Reading PPU status: raw=\(String(format: "%02X", status.rawValue)), vblank=\(status.contains(.verticalBlank))")
            data = (status.rawValue & 0xE0) | (ppuDataBuffer & 0x1F)
            if !readOnly {
                status.remove(.verticalBlank)
                addressLatch = 0
            }
            //            print("Returning status: \(String(format: "%02X", data))")
        case 0x0003: // OAM Address
            // Write-only
            break
        case 0x0004: // OAM Data
            data = oam[Int(oamAddr)]
            if !readOnly {
                oamAddr &+= 1  // Safetly increment and wrap OAM address
            }
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
        
        // Try cartridge first - most reads come from CHR ROM
        if let cart = cart, cart.ppuRead(address: address, data: &data) {
            return data
        }
        
        // Pattern tables - fallback storage
        else if address >= 0x0000 && address <= 0x1FFF {
            // Test pattern table takes priority during debugging
            if let testPattern = testPatternTable {
                return testPattern[Int(address)]
            }
            
            // No cartridge CHR data available
            return 0x00
        }
        
        // Nametables - handle mirroring modes
        else if address >= 0x2000 && address <= 0x3EFF {
            let addr = address & 0x0FFF
            
            guard let mirrorMode = cart?.getMirrorMode() else {
                let (table, offset) = getMirroredNametableIndex(addr: address)
                return tblName[table][offset]
            }
            
            // Apply cartridge-specific mirroring
            switch mirrorMode {
            case .vertical:
                if addr >= 0x0000 && addr <= 0x03FF {
                    data = tblName[0][Int(addr & 0x03FF)]
                } else if addr >= 0x0400 && addr <= 0x07FF {
                    data = tblName[1][Int(addr & 0x03FF)]
                } else if addr >= 0x0800 && addr <= 0x0BFF {
                    data = tblName[0][Int(addr & 0x03FF)]
                } else if addr >= 0x0C00 && addr <= 0x0FFF {
                    data = tblName[1][Int(addr & 0x03FF)]
                }
                
            case .horizontal:
                if addr >= 0x0000 && addr <= 0x03FF {
                    data = tblName[0][Int(addr & 0x03FF)]
                } else if addr >= 0x0400 && addr <= 0x07FF {
                    data = tblName[0][Int(addr & 0x03FF)]
                } else if addr >= 0x0800 && addr <= 0x0BFF {
                    data = tblName[1][Int(addr & 0x03FF)]
                } else if addr >= 0x0C00 && addr <= 0x0FFF {
                    data = tblName[1][Int(addr & 0x03FF)]
                }
                
            case .oneScreenLo:
                data = tblName[0][Int(addr & 0x03FF)]
                
            case .oneScreenHi:
                data = tblName[1][Int(addr & 0x03FF)]
            }
        }
        
        // Palette RAM - handle mirroring and masking
        else if address >= 0x3F00 && address <= 0x3FFF {
            var paletteAddr = address & 0x001F
            
            // Mirror sprite palette transparencies to background
            if paletteAddr == 0x0010 { paletteAddr = 0x0000 }
            else if paletteAddr == 0x0014 { paletteAddr = 0x0004 }
            else if paletteAddr == 0x0018 { paletteAddr = 0x0008 }
            else if paletteAddr == 0x001C { paletteAddr = 0x000C }
            
            let paletteValue = tblPalette[Int(paletteAddr)]
            
            // Apply 6-bit masking with grayscale support
            if mask.contains(.grayscale) {
                data = paletteValue & 0x30
            } else {
                data = paletteValue & 0x3F
            }
        }
        
        return data
    }
    
    func ppuWrite(_ addr: UInt16, _ data: UInt8) {
        let address = addr & 0x3FFF
        
        // Try cartridge first
        if cart?.ppuWrite(address: address, data: data) == true {
            return
        }
        
        switch address {
        case 0x0000...0x1FFF:
            writePatternTable(address: address, data: data)
            
        case 0x2000...0x3EFF:
            writeNametable(address: address, data: data)
            
        case 0x3F00...0x3FFF:
            writePalette(address: address, data: data)
            
        default:
            break
        }
    }
    
    // MARK: - Write Helpers
    
    private func writePatternTable(address: UInt16, data: UInt8) {
        // Test pattern table takes priority
        if testPatternTable != nil {
            testPatternTable![Int(address)] = data
            return
        }
        
        // Write to internal storage
        let tableIndex = Int((address & 0x1000) >> 12)
        let patternAddr = Int(address & 0x0FFF)
        
        // Swift-safe array access
        guard tableIndex < internalPatternTables.count,
              patternAddr < internalPatternTables[tableIndex].count else {
            return
        }
        
        internalPatternTables[tableIndex][patternAddr] = data
    }
    
    private func writeNametable(address: UInt16, data: UInt8) {
        let addr = address & 0x0FFF
        let mirrorMode = cart?.getMirrorMode() ?? .vertical
        
        let (tableIndex, offset) = calculateNametableMapping(addr: addr, mirror: mirrorMode)
        
        // Safe array access - bounds are guaranteed by nametable design
        tblName[tableIndex][offset] = data
    }
    
    private func writePalette(address: UInt16, data: UInt8) {
        let paletteAddr = mirrorPaletteAddress(address & 0x001F)
        tblPalette[Int(paletteAddr)] = data & 0x3F
    }
    
    // MARK: - Helper Functions
    
    private func calculateNametableMapping(addr: UInt16, mirror: Cartridge.Mirror) -> (table: Int, offset: Int) {
        let offset = Int(addr & 0x03FF)
        
        let table: Int
        switch (addr, mirror) {
        case (0x0000...0x03FF, _):
            table = 0
        case (0x0400...0x07FF, .vertical), (0x0800...0x0BFF, .vertical):
            table = 1
        case (0x0400...0x07FF, .horizontal):
            table = 0
        case (0x0800...0x0BFF, .horizontal), (0x0C00...0x0FFF, _):
            table = 1
        case (_, .oneScreenLo):
            table = 0
        case (_, .oneScreenHi):
            table = 1
        default:
            table = 0
        }
        
        return (table, offset)
    }
    
    private func mirrorPaletteAddress(_ addr: UInt16) -> UInt16 {
        switch addr {
        case 0x0010: return 0x0000
        case 0x0014: return 0x0004
        case 0x0018: return 0x0008
        case 0x001C: return 0x000C
        default: return addr
        }
    }
}
