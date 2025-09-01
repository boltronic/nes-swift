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
    internal var mapperID: UInt8    = 0
    internal var prgBanks: UInt8    = 0
    internal var chrBanks: UInt8    = 0
    private var mirror: Mirror      = .horizontal
    private var staticRAM: [UInt8] = Array(repeating: 0, count: 8192)
    internal var mapper: Mapper?

    
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
                let chrSize = Int(header.chrRomChunks) * 8192  // Still load 8KB chunks from file
                guard data.count >= dataOffset + chrSize else { return nil }
                chrMemory = Array(data[dataOffset..<(dataOffset + chrSize)])
                
                #if DEBUG_GRANULAR
                // Debug: Verify CHR data was loaded
                print("CHR ROM loaded: \(chrSize) bytes")
                print("First 16 bytes of CHR:")
                for i in 0..<min(16, chrMemory.count) {
                    print(String(format: "%02X ", chrMemory[i]), terminator: "")
                    if i % 8 == 7 { print("") }
                }
                #endif
            } else {
                // CHR RAM - allocate 8KB
                chrMemory = Array(repeating: 0, count: 8192)
                print("No CHR ROM - using CHR RAM")
            }
        }
        
        if fileType == 3 {
            
        }
        
        chrBanks = header.chrRomChunks  
        if chrBanks > 0 {
            let chrSize = Int(chrBanks) * 8192  // 8KB per bank
            guard data.count >= dataOffset + chrSize else { return nil }
            chrMemory = Array(data[dataOffset..<(dataOffset + chrSize)])
        } else {
            chrMemory = Array(repeating: 0, count: 8192)
            print("No CHR ROM - using CHR RAM")
        }
        
        // Create appropriate mapper
        switch mapperID {
        case 0:
            mapper = Mapper000(prgBanks: prgBanks, chrBanks: chrBanks)
        case 1:
            mapper = MMC1Mapper(prgBanks: prgBanks, chrBanks: chrBanks)
        case 4:
            let chr1kBanksForMMC3: UInt32 = (chrBanks > 0) ? UInt32(chrBanks) * 8 : 8
            mapper = MMC3Mapper(prgBanks: prgBanks, chrBanks: UInt8(truncatingIfNeeded: chr1kBanksForMMC3))
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
    func cpuRead(address: UInt16) -> UInt8? {
        guard let mapper = mapper else { return nil }
        guard let mappedAddr = mapper.cpuMapRead(address: address) else { return nil }
        
        if mappedAddr == 0xFFFFFFFF {
            // Check if mapper supports PRG-RAM
            if let prgRAMMapper = mapper as? PRGRAMSupport {
                return prgRAMMapper.readPRGRAM(address: address)
            }
            return nil
        } else {
            guard mappedAddr < prgMemory.count else { return nil }
            return prgMemory[Int(mappedAddr)]
        }
    }

    func cpuWrite(address: UInt16, data: UInt8) -> Bool {
        guard mapper != nil else {
            return false
        }
        
        guard let mappedAddr = mapper!.cpuMapWrite(address: address, value: data) else {
            return false
        }
        
        return true
    }
    
    func ppuRead(address: UInt16) -> UInt8? {
        guard let mapper = mapper else {
            return nil
        }

        guard let mappedAddr = mapper.ppuMapRead(address: address) else {
            return nil
        }
                
        guard mappedAddr < chrMemory.count else {
            return nil
        }
    
        let data = chrMemory[Int(mappedAddr)]
        
        return data
    }
    
    func ppuWrite(address: UInt16, data: UInt8) -> Bool {
        guard var mapper = mapper,
              let mappedAddr = mapper.ppuMapWrite(address: address, value: data),
              mappedAddr < chrMemory.count else {
            return false
        }
        
        // Should this be PRG instead of chr? 
        chrMemory[Int(mappedAddr)] = data
        return true
    }
    
    func getMirrorMode() -> Mirror {
        if let m = mapper as? MirrorControl {
            switch m.mirrorMode {
            case .horizontal: return .horizontal
            case .vertical:   return .vertical
            case .oneScreenLow:  return .oneScreenLo
            case .oneScreenHigh: return .oneScreenHi
            }
        }
        return mirror // fallback to header
    }

    func getMapperDebugInfo() -> [String: Any]? {
        if let debugSupport = mapper as? DebugSupport {
            return debugSupport.getDebugInfo()
        }
        return nil
    }

    func getMapperBankInfo() -> [String: UInt8]? {
        if let debugSupport = mapper as? DebugSupport {
            return debugSupport.getBankInfo()
        }
        return nil
    }
    
    func handleScanline(scanline: UInt16) {
        guard var scanlineMapper = mapper as? (Mapper & ScanlineAware) else { return }
        scanlineMapper.handleScanline(scanline: scanline)
        
        // Update the stored mapper if it's a value type (struct)
        if mapper is MMC3Mapper {
            mapper = scanlineMapper
        }
    }
    
    func clearMapperIRQ() {
        if var irqMapper = mapper as? IRQGeneration {
            irqMapper.clearIRQ()
            mapper = irqMapper as? any Mapper
        }
    }
    
    func reset() {
        mapper?.reset()
    }
}

