//
//  mapper004.swift
//  nes
//
//  Created by mike on 8/19/25.
//

import Foundation

// MARK: - Supporting Types

enum MirrorMode {
    case horizontal
    case vertical
    case oneScreenLow
    case oneScreenHigh
}

protocol MMC3DebugSupport: DebugSupport {
    func getBankConfiguration() -> [String: Any]
    func getIRQStatus() -> [String: Any]
    func getRegisterDump() -> [String: UInt8]
}

// MARK: - MMC3 Mapper Implementation

struct MMC3Mapper: Mapper, BankSwitching, IRQGeneration, ScanlineAware,
                   MirrorControl, RAMStorage, MMC3DebugSupport, AddressMapping,
                   PRGRAMSupport  {
    
    // MARK: - Mapper Protocol
    let mapperID: UInt8 = 4
    let name = "MMC3"
    
    // MARK: - Banking State
    private let prgBanks: UInt8
    private let chrBanks: UInt8
    
    // PRG and CHR bank pointers (in bytes, not bank numbers)
    private var prgBankOffsets: [UInt32] = Array(repeating: 0, count: 4)
    private var chrBankOffsets: [UInt32] = Array(repeating: 0, count: 8)
    
    // Internal registers
    private var registers: [UInt8] = Array(repeating: 0, count: 8)
    private var targetRegister: UInt8 = 0
    private var prgBankMode: Bool = false
    private var chrInversion: Bool = false
    
    // MARK: - IRQ State
    private var irqCounter: UInt16 = 0
    private var irqReload: UInt16 = 0
    private var irqEnabled: Bool = false
    private var _irqActive: Bool = false
    
    // MARK: - Memory and Mirroring
    var staticRAM: [UInt8] = Array(repeating: 0, count: 8 * 1024) // 8KB PRG-RAM
    var mirrorMode: MirrorMode = .horizontal
    
    // MARK: - Init
    init(prgBanks: UInt8, chrBanks: UInt8) {
        self.prgBanks = prgBanks
        self.chrBanks = chrBanks
    }
    
    // MARK: - Mapper Protocol
    func cpuMapRead(address: UInt16) -> UInt32? {
        switch address {
        case 0x6000...0x7FFF:
            return 0xFFFFFFFF

        case 0x8000...0x9FFF:
            return prgBankOffsets[0] + UInt32(address & 0x1FFF)
            
        case 0xA000...0xBFFF:
            return prgBankOffsets[1] + UInt32(address & 0x1FFF)
            
        case 0xC000...0xDFFF:
            return prgBankOffsets[2] + UInt32(address & 0x1FFF)
            
        case 0xE000...0xFFFF:
            return prgBankOffsets[3] + UInt32(address & 0x1FFF)
            
        default:
            return nil
        }
    }
    
    mutating func cpuMapWrite(address: UInt16, value: UInt8) -> UInt32? {
        switch address {
        case 0x6000...0x7FFF:
            // PRG-RAM write
            staticRAM[Int(address & 0x1FFF)] = value
            return 0xFFFFFFFF // Special marker for internal handling
            
        case 0x8000...0x9FFF:
            handleBankSelect(address, value)
            return nil // Mapper register, no memory mapping
            
        case 0xA000...0xBFFF:
            handleMirrorAndRAMProtect(address, value)
            return nil
            
        case 0xC000...0xDFFF:
            handleIRQControl(address, value)
            return nil
            
        case 0xE000...0xFFFF:
            handleIRQEnable(address, value)
            return nil
            
        default:
            return nil
        }
    }
    
    func ppuMapRead(address: UInt16) -> UInt32? {
        guard isInRange(address: address, range: 0x0000...0x1FFF) else { return nil }
        
        let bankIndex = Int(address / 0x0400)
        return chrBankOffsets[bankIndex] + UInt32(address & 0x03FF)
    }
    
    func ppuMapWrite(address: UInt16, value: UInt8) -> UInt32? {
        // MMC3 uses CHR-ROM, so no writes allowed
        return nil
    }
    
    func readPRGRAM(address: UInt16) -> UInt8? {
        guard address >= 0x6000 && address <= 0x7FFF else { return nil }
        return staticRAM[Int(address & 0x1FFF)]
    }
    
    mutating func writePRGRAM(address: UInt16, value: UInt8) -> Bool {
        guard address >= 0x6000 && address <= 0x7FFF else { return false }
        staticRAM[Int(address & 0x1FFF)] = value
        return true
    }
    
    mutating func reset() {
        // Control registers
        targetRegister = 0
        prgBankMode = false
        chrInversion = false
        mirrorMode = .horizontal
        
        // IRQ state - all disabled/cleared on reset
        _irqActive = false
        irqEnabled = false
        irqCounter = 0
        irqReload = 0
        
        // Set up registers with proper initial values for sequential CHR banks
        registers[0] = 0x00  // 2KB bank pair starting at CHR bank 0
        registers[1] = 0x02  // 2KB bank pair starting at CHR bank 2
        registers[2] = 0x04  // 1KB bank 4
        registers[3] = 0x05  // 1KB bank 5
        registers[4] = 0x06  // 1KB bank 6
        registers[5] = 0x07  // 1KB bank 7
        registers[6] = 0x00  // PRG bank 0
        registers[7] = 0x01  // PRG bank 1
        
        // PRG: Standard MMC3 layout (8KB units)
        let prg8kCount = UInt32(prgBanks * 2)
        precondition(prg8kCount >= 2, "PRG must be at least 16KB for MMC3")
        
        // Now calculate all offsets based on the register values
        updateBankOffsets()
    }
    
    // MARK: - Debug
    var debugState: [String: Any] {
        return [
            "prgBanks": prgBanks,
            "chrBanks": chrBanks,
            "chrBankOffsets": chrBankOffsets,
            "prgBankOffsets": prgBankOffsets,
            "registers": registers,
            "targetRegister": targetRegister,
            "prgBankMode": prgBankMode,
            "chrInversion": chrInversion,
            "mirrorMode": mirrorMode,
            "irqActive": irqActive,
            "irqEnabled": irqEnabled,
            "irqCounter": irqCounter,
            "irqReload": irqReload
        ]
    }
    
    func debugCurrentBackgroundBanks(chrROM: [UInt8]) {
        let bgBanks = [116, 117, 22, 23]
        print("=== Current Background Banks ===")
        for bank in bgBanks {
            let offset = bank * 1024
            if offset + 32 < chrROM.count {
                let firstTile = chrROM[offset..<offset+16]
                let secondTile = chrROM[offset+16..<offset+32]
                let firstHex = firstTile.map { String(format: "%02X", $0) }.joined(separator: " ")
                let secondHex = secondTile.map { String(format: "%02X", $0) }.joined(separator: " ")
                print("Bank \(bank) Tile 0: \(firstHex)")
                print("Bank \(bank) Tile 1: \(secondHex)")
            }
        }
    }
    
    func debugCHRAccess(chrROM: [UInt8]) {
        print("=== CHR-ROM Debug ===")
        print("Total CHR-ROM size: \(chrROM.count) bytes")
        print("Expected size: \(Int(chrBanks) * 0x400) bytes")
        
        // Check first few bytes of each 1KB bank
        for bank in 0..<min(8, Int(chrBanks)) {
            let bankStart = bank * 0x0400
            if bankStart + 16 < chrROM.count {
                let bytes = chrROM[bankStart..<bankStart+16].map { String(format: "%02X", $0) }.joined(separator: " ")
                print("CHR Bank \(bank) first 16 bytes: \(bytes)")
            }
        }
    }
    
    func debugCurrentState() {
        print("=== MMC3 Current State ===")
        print("CHR Banks: \(chrBanks), PRG Banks: \(prgBanks)")
        print("CHR Inversion: \(chrInversion), PRG Bank Mode: \(prgBankMode)")
        print("Registers: \(registers.enumerated().map { "R\($0.0)=$\(String(format: "%02X", $0.1))" }.joined(separator: ", "))")
        print("CHR Bank Offsets:")
        for i in 0..<8 {
            let bankNum = chrBankOffsets[i] / 0x0400
            print("  PPU $\(String(format: "%04X", i * 0x0400))-$\(String(format: "%04X", i * 0x0400 + 0x03FF)) -> CHR Bank \(bankNum)")
        }
        print("========================")
    }

    func testDirectCHRAccess(chrROM: [UInt8]) {
        print("=== Direct CHR Test ===")
        
        // Simulate what happens when PPU requests background tile 0x01 from pattern table 0
        let tileID: UInt8 = 0x01
        let patternTableBase: UInt16 = 0x0000  // Background pattern table
        let tileAddress = patternTableBase + UInt16(tileID) * 16
        
        print("Testing tile ID $\(String(format: "%02X", tileID)) at PPU $\(String(format: "%04X", tileAddress))")
        
        if let chrOffset = ppuMapRead(address: tileAddress) {
            print("MMC3 maps to CHR offset: $\(String(format: "%06X", chrOffset))")
            
            if Int(chrOffset) + 15 < chrROM.count {
                let tileData = chrROM[Int(chrOffset)..<Int(chrOffset)+16]
                print("Tile data: \(tileData.map { String(format: "%02X", $0) }.joined(separator: " "))")
                
                // Check if this is blank data (all zeros)
                if tileData.allSatisfy({ $0 == 0 }) {
                    print("❌ Tile data is all zeros - this would render as blank!")
                } else {
                    print("✅ Tile contains data")
                }
            } else {
                print("❌ CHR offset \(chrOffset) exceeds ROM size \(chrROM.count)!")
            }
        } else {
            print("❌ MMC3 failed to map address!")
        }
    }
    
    // MARK: - Banking Protocol
    
    var currentPRGBank: UInt8 {
        return registers[6] & 0x3F
    }
    
    var currentCHRBank: UInt8 {
        return registers[0]
    }
    
    mutating func switchPRGBank(bank: UInt8) {
        registers[6] = bank & 0x3F
        updateBankOffsets()
    }
    
    mutating func switchCHRBank(bank: UInt8) {
        registers[0] = bank
        updateBankOffsets()
    }
    
    // MARK: - IRQ Protocol
    var irqActive: Bool {
        return _irqActive
    }
    
    mutating func clearIRQ() {
        _irqActive = false
    }
    
    mutating func updateIRQ() {
        // Called when IRQ state might need updating
    }
    
    // MARK: - Scanline Protocol
    mutating func handleScanline(scanline: UInt16) {
        if irqCounter == 0 {
            irqCounter = irqReload
        } else {
            irqCounter -= 1
        }
        
        if irqCounter == 0 && irqEnabled {
            _irqActive = true
            print("MMC3 IRQ fired: reload=\(irqReload), scanline=\(scanline), counter=\(irqCounter)")
        }
    }
    
    // MARK: - Debug Support
    
    func getDebugInfo() -> [String: Any] {
        return [
            "mapper_id": mapperID,
            "name": name,
            "prg_banks": prgBanks,
            "chr_banks": chrBanks,
            "prg_bank_mode": prgBankMode,
            "chr_inversion": chrInversion,
            "target_register": targetRegister,
            "chr_bank_offsets": chrBankOffsets,
            "prg_bank_offsets": prgBankOffsets,
            "registers": registers,
            "irq_active": irqActive,
            "irq_enabled": irqEnabled,
            "irq_counter": irqCounter,
            "irq_reload": irqReload
        ]
    }
    
    func getBankInfo() -> [String: UInt8] {
        return [
            "current_prg_bank": currentPRGBank,
            "current_chr_bank": currentCHRBank,
            "target_register": targetRegister
        ]
    }
    
    func getBankConfiguration() -> [String: Any] {
        return [
            "prg_bank_offsets": prgBankOffsets.map { $0 / 0x2000 },
            "chr_bank_offsets": chrBankOffsets.map { $0 / 0x0400 },
            "prg_bank_mode": prgBankMode,
            "chr_inversion": chrInversion
        ]
    }
    
    func getIRQStatus() -> [String: Any] {
        return [
            "irq_active": irqActive,
            "irq_enabled": irqEnabled,
            "irq_counter": irqCounter,
            "irq_reload": irqReload
        ]
    }
    
    func getRegisterDump() -> [String: UInt8] {
        var dump: [String: UInt8] = [:]
        for (index, value) in registers.enumerated() {
            dump["R\(index)"] = value
        }
        dump["target"] = targetRegister
        return dump
    }
    
    // MARK: - Private Implementation    
    private mutating func handleBankSelect(_ address: UInt16, _ value: UInt8) {
            if (address & 0x0001) == 0 {
                // Bank select register ($8000, even)
                let oldTarget = targetRegister
                let oldPrgMode = prgBankMode
                let oldChrInv = chrInversion
                
                targetRegister = value & 0x07
                prgBankMode = (value & 0x40) != 0
                chrInversion = (value & 0x80) != 0
            } else {
                // Bank data register ($8001, odd)
                let oldValue = registers[Int(targetRegister)]
                registers[Int(targetRegister)] = value
                
                updateBankOffsets()
            }
    }
    
    
    private mutating func handleMirrorAndRAMProtect(_ address: UInt16, _ value: UInt8) {
        if (address & 0x0001) == 0 {
            // Mirroring ($A000, even)
            mirrorMode = (value & 0x01) != 0 ? .horizontal : .vertical
        } else {
            // PRG-RAM protect ($A001, odd)
            // TODO: - Implement PRG-RAM protection
        }
    }
    
    private mutating func handleIRQControl(_ address: UInt16, _ value: UInt8) {
        if (address & 0x0001) == 0 {
            // IRQ latch ($C000, even)
            irqReload = UInt16(value)
        } else {
            // IRQ reload ($C001, odd)
            irqCounter = 0
        }
    }
    
    private mutating func handleIRQEnable(_ address: UInt16, _ value: UInt8) {
        if (address & 0x0001) == 0 {
            irqEnabled = false
            _irqActive = false
            print("MMC3: IRQ DISABLED at \(String(format: "%04X", address))")
        } else {
            irqEnabled = true
            print("MMC3: IRQ ENABLED at \(String(format: "%04X", address)) - reload=\(irqReload)")
        }
    }
    
    func debugHighCHRBanks(chrROM: [UInt8]) {
        print("=== High CHR Bank Debug ===")
        for bank in [120, 121, 122, 123] {
            let offset = bank * 1024
            if offset + 16 < chrROM.count {
                let data = chrROM[offset..<offset+16]
                let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                let isEmpty = data.allSatisfy({ $0 == 0 })
                print("CHR Bank \(bank): \(hex) \(isEmpty ? "❌ EMPTY" : "✅ DATA")")
            } else {
                print("CHR Bank \(bank): BEYOND ROM SIZE")
            }
        }
    }
    
    private mutating func updateBankOffsets() {
        let totalPrg8k = Int(prgBanks) * 2
        
        // CHR Banking (1KB granularity)
        if chrInversion {
            // Pattern table 0 ($0000-$0FFF): four 1KB banks R2-R5
            chrBankOffsets[0] = UInt32(registers[2]) * 0x0400
            chrBankOffsets[1] = UInt32(registers[3]) * 0x0400
            chrBankOffsets[2] = UInt32(registers[4]) * 0x0400
            chrBankOffsets[3] = UInt32(registers[5]) * 0x0400
            
            // Pattern table 1 ($1000-$1FFF): two 2KB banks R0,R1 (force even alignment)
            let r0Base = registers[0] & 0xFE
            let r1Base = registers[1] & 0xFE
            chrBankOffsets[4] = UInt32(r0Base) * 0x0400
            chrBankOffsets[5] = UInt32(r0Base + 1) * 0x0400
            chrBankOffsets[6] = UInt32(r1Base) * 0x0400
            chrBankOffsets[7] = UInt32(r1Base + 1) * 0x0400
        } else {
            // Pattern table 0 ($0000-$0FFF): two 2KB banks R0,R1 (force even alignment)
            let r0Base = registers[0] & 0xFE
            let r1Base = registers[1] & 0xFE
            chrBankOffsets[0] = UInt32(r0Base) * 0x0400
            chrBankOffsets[1] = UInt32(r0Base + 1) * 0x0400
            chrBankOffsets[2] = UInt32(r1Base) * 0x0400
            chrBankOffsets[3] = UInt32(r1Base + 1) * 0x0400
            
            // Pattern table 1 ($1000-$1FFF): four 1KB banks R2-R5
            chrBankOffsets[4] = UInt32(registers[2]) * 0x0400
            chrBankOffsets[5] = UInt32(registers[3]) * 0x0400
            chrBankOffsets[6] = UInt32(registers[4]) * 0x0400
            chrBankOffsets[7] = UInt32(registers[5]) * 0x0400
        }
        
        // PRG Banking (8KB granularity) - mask to available banks
        let r6 = Int(registers[6] & 0x3F) % totalPrg8k
        let r7 = Int(registers[7] & 0x3F) % totalPrg8k
        let lastBank = totalPrg8k - 1
        let secondLastBank = totalPrg8k - 2
        
        if prgBankMode {
            // Mode 1: R6 swappable at $C000
            prgBankOffsets[0] = UInt32(secondLastBank) * 0x2000  // $8000: fixed to second-last
            prgBankOffsets[1] = UInt32(r7) * 0x2000              // $A000: R7
            prgBankOffsets[2] = UInt32(r6) * 0x2000              // $C000: R6 (swappable)
            prgBankOffsets[3] = UInt32(lastBank) * 0x2000        // $E000: fixed to last
        } else {
            // Mode 0: R6 swappable at $8000
            prgBankOffsets[0] = UInt32(r6) * 0x2000              // $8000: R6 (swappable)
            prgBankOffsets[1] = UInt32(r7) * 0x2000              // $A000: R7
            prgBankOffsets[2] = UInt32(secondLastBank) * 0x2000  // $C000: fixed to second-last
            prgBankOffsets[3] = UInt32(lastBank) * 0x2000        // $E000: fixed to last
        }
    }
    
    func testCHRDataAtOffset(chrROM: [UInt8], ppuAddress: UInt16) {
        if let offset = ppuMapRead(address: ppuAddress) {
            print("Testing PPU $\(String(format: "%04X", ppuAddress)) -> CHR offset $\(String(format: "%06X", offset))")
            
            if Int(offset) + 15 < chrROM.count {
                let data = chrROM[Int(offset)..<Int(offset)+16]
                let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                print("Data at offset: \(hex)")
                
                if data.allSatisfy({ $0 == 0 }) {
                    print("❌ Data is all zeros!")
                } else {
                    print("✅ Data contains non-zero bytes")
                }
            } else {
                print("❌ Offset exceeds ROM size")
            }
        }
    }
    
}

//
//// MARK: - Advanced Usage with Emulator Integration
//
//protocol EmulatorIntegration {
//    mutating func integrateWithEmulator(ppu: OLC2C02, cpu: OLC6502)
//}
//
//extension MMC3Mapper: EmulatorIntegration {
//    mutating func integrateWithEmulator(ppu: OLC2C02, cpu: OLC6502) {
//        // MMC3 needs to hook into PPU scanline events for IRQ timing
//        // This would be set up to call handleScanline() at appropriate times
//        print("MMC3 integrated with emulator for scanline IRQ timing")
//    }
//}
