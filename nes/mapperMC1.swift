//
//  mapperMC1.swift
//  nes
//
//  Created by mike on 8/19/25.
//

struct MMC1Mapper: Mapper, BankSwitching, BatteryBacked,
                    AddressMapping, PRGRAMSupport, DebugSupport {
    mutating func ppuMapWrite(address: UInt16, value: UInt8) -> UInt32? {
        return nil
    }
    

    mutating func cpuMapWrite(address: UInt16, value: UInt8) -> UInt32? {
        return nil
    }
    
    let mapperID: UInt8 = 1
    let name = "MMC1"
    let hasBattery: Bool
    
    // MMC1 state
    private var shiftRegister: UInt8 = 0x10
    private var writeCount: Int = 0
    private var control: UInt8 = 0x0C
    private var chrBank0: UInt8 = 0
    private var chrBank1: UInt8 = 0
    private var prgBank: UInt8 = 0
    
    private let prgBanks: UInt8
    private let chrBanks: UInt8
    
    init(prgBanks: UInt8, chrBanks: UInt8, hasBattery: Bool = false) {
        self.prgBanks = prgBanks
        self.chrBanks = chrBanks
        self.hasBattery = hasBattery
    }
    
    // Read only computed props
    var currentPRGBank: UInt8 { prgBank }
    var currentCHRBank: UInt8 { chrBank0 }
    
    func cpuMapRead(address: UInt16) -> UInt32? {
        switch address {
        case 0x6000...0x7FFF:
            // PRG-RAM
            return UInt32(address - 0x6000)
            
        case 0x8000...0xFFFF:
            // PRG-ROM with banking
            let bankMode = (control >> 2) & 0x03
            return calculatePRGAddress(address, bankMode: bankMode)
            
        default:
            return nil
        }
    }
    
    func ppuMapRead(address: UInt16) -> UInt32? {
        guard isInRange(address: address, range: 0x0000...0x1FFF) else { return nil }
        
        // CHR banking logic
        if control & 0x10 != 0 {
            // 4KB CHR banking
            if address < 0x1000 {
                return UInt32(UInt16(chrBank0) * 0x1000 + address)
            } else {
                return UInt32(UInt16(chrBank1) * 0x1000 + (address - 0x1000))
            }
        } else {
            // 8KB CHR banking
            return UInt32(UInt16(chrBank0 & 0xFE) * 0x1000 + address)
        }
    }
    
    mutating func switchPRGBank(bank: UInt8) {
        prgBank = bank & 0x0F  // 4-bit PRG bank
    }
    
    mutating func switchCHRBank(_ bank: UInt8) {
        chrBank0 = bank
    }
    
    func savePersistentRAM() throws {
        // Implementation for battery-backed RAM
        let filename = "save_\(mapperID).sav"
        // Save PRG-RAM to file...
    }
    
    func loadPersistentRAM() throws {
        // Implementation for loading battery-backed RAM
        let filename = "save_\(mapperID).sav"
        // Load PRG-RAM from file...
    }
    
    func getBankInfo() -> [String: UInt8] {
        return [
            "prg_banks": prgBanks,
            "chr_banks": chrBanks,
            "current_prg_bank": currentPRGBank,
            "current_chr_bank": currentCHRBank,
            "control": control
        ]
    }
    
    private func calculatePRGAddress(_ addr: UInt16, bankMode: UInt8) -> UInt32? {
        // MMC1 PRG banking logic
        switch bankMode {
        case 0, 1:
            // 32KB mode
            let bank = prgBank >> 1
            return UInt32(bank) * 0x8000 + UInt32(addr - 0x8000)
            
        case 2:
            // Fix first bank, switch last
            if addr < 0xC000 {
                return UInt32(addr - 0x8000)  // Bank 0
            } else {
                return UInt32(prgBank) * 0x4000 + UInt32(addr - 0xC000)
            }
            
        case 3:
            // Switch first bank, fix last
            if addr < 0xC000 {
                return UInt32(prgBank) * 0x4000 + UInt32(addr - 0x8000)
            } else {
                let lastBank = prgBanks - 1
                return UInt32(lastBank) * 0x4000 + UInt32(addr - 0xC000)
            }
            
        default:
            return nil
        }
    }
}
