//
//  mapper000.swift
//  nes
//
//  Created by mike on 8/2/25.
//

struct Mapper000: Mapper, AddressMapping, DebugSupport {
    let mapperID: UInt8 = 0
    let name = "NROM"
    
    private let prgBanks: UInt8
    private let chrBanks: UInt8
    
    init(prgBanks: UInt8, chrBanks: UInt8) {
        self.prgBanks = prgBanks
        self.chrBanks = chrBanks
    }
    
    func cpuMapRead(address: UInt16) -> UInt32? {  // Fixed: back to address
        guard isInRange(address: address, range: 0x8000...0xFFFF) else { return nil }
        
        let mask: UInt16 = prgBanks > 1 ? 0x7FFF : 0x3FFF
        return UInt32(mirrorAddress(address: address, mask: mask))
    }
    
    mutating func cpuMapWrite(address: UInt16, value: UInt8) -> UInt32? {
        return nil
    }
    
    func ppuMapRead(address: UInt16) -> UInt32? {  // Fixed: address parameter name
        guard isInRange(address: address, range: 0x0000...0x1FFF) else { return nil }
        return UInt32(address)
    }
    
    mutating func ppuMapWrite(address: UInt16, value: UInt8) -> UInt32? {  // Fixed: signature
        guard isInRange(address: address, range: 0x0000...0x1FFF),
              chrBanks == 0 else { return nil }  // Only CHR-RAM
        return UInt32(address)
    }
    
    mutating func reset() {

    }
    
    func getBankInfo() -> [String: UInt8] {
        return [
            "prg_banks": prgBanks,
            "chr_banks": chrBanks,
            "current_bank": 0  
        ]
    }
}
