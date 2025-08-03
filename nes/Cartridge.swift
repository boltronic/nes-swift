//
//  Cartridge.swift
//  nes
//
//  Created by mike on 8/2/25.
//

import Foundation

class Cartridge {
    // MARK: - iNES Header Structure
    struct Header {
        var name: [UInt8] = Array(repeating: 0, count: 4) // "NES\x1A"
        var prgRomChunks: UInt8 = 0     // Number of 16KB PRG ROM banks
        var chrRomChunks: UInt8 = 0     // Number of 8KB CHR ROM banks
        var mapper1: UInt8      = 0     // Mapper, mirroring, battery, trainer
        var mapper2: UInt8      = 0     // Mapper, VS/Playchoice, NES 2.0
        var prgRamSize: UInt8   = 0     // PRG RAM size (rarely used)
        var tvSystem1: UInt8    = 0     // TV system (rarely used)
        var tvSystem2: UInt8    = 0     // TV system, PRG RAM presence
        var unused: [UInt8] = Array(repeating: 0, count: 5)
    }
    
    enum Mirror {
        case horizontal
        case vertical
        case oneScreenLo
        case oneScreenHi
    }
    
    // MARK: - Properties
    private var imageValid          = false
    private var prgMemory: [UInt8]  = []
    private var chrMemory: [UInt8]  = []
    private var mapperID: UInt8     = 0
    private var prgBanks: UInt8     = 0
    private var chrBanks: UInt8     = 0
    private var mirror: Mirror      = .horizontal
    private var mapper: Mapper?
    
    // MARK: - Initialization
    init?(fileName: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: fileName)) else {
            return nil
        }
        
        // Read header (16 bytes)
        guard data.count >= 16 else { return nil }
        
        var header = Header()
        data.withUnsafeBytes { bytes in
            header.name = Array(bytes[0..<4])
            header.prgRomChunks = bytes[4]
            header.chrRomChunks = bytes[5]
            header.mapper1 = bytes[6]
            header.mapper2 = bytes[7]
            header.prgRamSize = bytes[8]
            header.tvSystem1 = bytes[9]
            header.tvSystem2 = bytes[10]
            // bytes 11-15 are unused
        }
        
        // Verify "NES\x1A" header
        let nesHeader: [UInt8] = [0x4E, 0x45, 0x53, 0x1A] // "NES\x1A"
        guard header.name == nesHeader else { return nil }
        
        // Calculate data offset (skip trainer if present)
        var dataOffset = 16
        if header.mapper1 & 0x04 != 0 {
            dataOffset += 512  // Skip trainer
        }
        
        // Determine mapper ID
        mapperID = ((header.mapper2 >> 4) << 4) | (header.mapper1 >> 4)
        mirror = (header.mapper1 & 0x01) != 0 ? .vertical : .horizontal
        
        // File type 1 (iNES)
        let fileType: UInt8 = 1
        
        if fileType == 0 {
            
        }
        
        if fileType == 1 {
            // Load PRG ROM
            prgBanks = header.prgRomChunks
            let prgSize = Int(prgBanks) * 16384  // 16KB per bank
            
            guard data.count >= dataOffset + prgSize else { return nil }
            prgMemory = Array(data[dataOffset..<(dataOffset + prgSize)])
            dataOffset += prgSize
            
            // Load CHR ROM
            chrBanks = header.chrRomChunks
            if chrBanks > 0 {
                let chrSize = Int(chrBanks) * 8192  // 8KB per bank
                guard data.count >= dataOffset + chrSize else { return nil }
                chrMemory = Array(data[dataOffset..<(dataOffset + chrSize)])
            } else {
                // CHR RAM - allocate 8KB
                chrMemory = Array(repeating: 0, count: 8192)
            }
        }
        
        if fileType == 3 {
            
        }
        
        // Create appropriate mapper
        switch mapperID {
        case 0:
            mapper = Mapper000(prgBanks: prgBanks, chrBanks: chrBanks)
        default:
            print("Mapper \(mapperID) not implemented")
            return nil
        }
        
        imageValid = true
    }
    
    // MARK: - Public Interfaces
    var isImageValid: Bool {
        return imageValid
    }
    // cpuRead/Write -- Program memory
    // ppuRead/Write -- Character memory
    func cpuRead(address: UInt16, data: inout UInt8) -> Bool {
        var mappedAddr: UInt32 = 0
        if let mapper = mapper, mapper.cpuMapRead(addr: address, mappedAddr: &mappedAddr) {
            if mappedAddr < prgMemory.count {
                data = prgMemory[Int(mappedAddr)]
                return true
            }
        }
        return false
    }
    
    func cpuWrite(address: UInt16, data: UInt8) -> Bool {
        var mappedAddr: UInt32 = 0
        if let mapper = mapper, mapper.cpuMapWrite(addr: address, mappedAddr: &mappedAddr) {
            if mappedAddr < prgMemory.count {
                prgMemory[Int(mappedAddr)] = data
                return true
            }
        }
        return false
    }
    
    func ppuRead(address: UInt16, data: inout UInt8) -> Bool {
        var mappedAddr: UInt32 = 0
        if let mapper = mapper, mapper.ppuMapRead(addr: address, mappedAddr: &mappedAddr) {
            if mappedAddr < chrMemory.count {
                data = chrMemory[Int(mappedAddr)]
                return true
            }
        }
        return false
    }
    
    func ppuWrite(address: UInt16, data: UInt8) -> Bool {
        var mappedAddr: UInt32 = 0
        if let mapper = mapper, mapper.ppuMapWrite(addr: address, mappedAddr: &mappedAddr) {
            if mappedAddr < chrMemory.count {
                chrMemory[Int(mappedAddr)] = data
                return true
            }
        }
        return false
    }
    
    func getMirrorMode() -> Mirror {
        return mirror
    }
    
    func reset() {
        mapper?.reset()
    }
}

