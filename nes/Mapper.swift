//
//  Mapper.swift
//  nes
//
//  Created by mike on 8/2/25.
//

import Foundation

// MARK: - Mapper Protocol
protocol Mapper {
    func cpuMapRead(address: UInt16) -> UInt32?
    func ppuMapRead(address: UInt16) -> UInt32?
    mutating func cpuMapWrite(address: UInt16, value: UInt8) -> UInt32?
    mutating func ppuMapWrite(address: UInt16, value: UInt8) -> UInt32?
    mutating func reset()

    var mapperID: UInt8 { get }
    var name: String { get }
}

// MARK: - Capability Protocols
protocol PRGRAMSupport {
    func readPRGRAM(address: UInt16) -> UInt8?
    mutating func writePRGRAM(address: UInt16, value: UInt8) -> Bool
}

protocol BankSwitching {
    var currentPRGBank: UInt8 { get }
    var currentCHRBank: UInt8 { get }
    mutating func switchPRGBank(bank: UInt8)
    mutating func switchCHRBank(bank: UInt8)
}

protocol BatteryBacked {
    var hasBattery: Bool { get }
    func savePersistentRAM() throws
    func loadPersistentRAM() throws
}

protocol IRQGeneration {
    var irqActive: Bool { get }
    mutating func clearIRQ()
    mutating func updateIRQ()
}

protocol ScanlineAware {
    mutating func handleScanline(scanline: UInt16)
}

protocol MirrorControl {
    var mirrorMode: MirrorMode { get set }
}

protocol RAMStorage {
    var staticRAM: [UInt8] { get set }
}

protocol DebugSupport {
    func getDebugInfo() -> [String: Any]
    func getBankInfo() -> [String: UInt8]
}

protocol AddressMapping {
    func isInRange(address: UInt16, range: ClosedRange<UInt16>) -> Bool
    func mirrorAddress(address: UInt16, mask: UInt16) -> UInt16
}

protocol PPUEventReceiver: AnyObject {
    func onScanlineStart(scanline: UInt16)
    func onScanlineEnd(scanline: UInt16)
    func onA12Rise(address: UInt16)  // Critical for MMC3
}

protocol PPUEventSource: AnyObject {
    func addEventReceiver(_ receiver: PPUEventReceiver)
    func removeEventReceiver(_ receiver: PPUEventReceiver)
}

// MARK: - Protocol Extensions
extension Mapper {
    mutating func cpuMapWrite(addr: UInt16) -> UInt32? { return nil }
    mutating func ppuMapWrite(addr: UInt16) -> UInt32? { return nil }
    mutating func reset() { }
    
    func readPRGRAM(address: UInt16) -> UInt8? { return nil }
    mutating func writePRGRAM(address: UInt16, value: UInt8) -> Bool { return false }
    
    static func create(id: UInt8, prgBanks: UInt8, chrBanks: UInt8,
                       hasBattery: Bool = false) -> (any Mapper)? {
        switch id {
        case 0: return Mapper000(prgBanks: prgBanks, chrBanks: chrBanks)
        case 1: return MMC1Mapper(prgBanks: prgBanks, chrBanks: chrBanks,
                                  hasBattery: hasBattery)
        case 4: return MMC3Mapper(prgBanks: prgBanks, chrBanks: chrBanks)
        default: return nil
        }
    }
    
    // Check if mapper supports a specific capability
    func supportsFeature<T>(_ feature: T.Type) -> Bool {
        return self is T
    }
    
    // Get the feature if supported
    func getFeature<T>(_ feature: T.Type) -> T? {
        return self as? T
    }
}

extension AddressMapping {
    func isInRange(address: UInt16, range: ClosedRange<UInt16>) -> Bool {
        return range.contains(address)
    }
    
    func mirrorAddress(address: UInt16, mask: UInt16) -> UInt16 {
        return address & mask
    }
}

extension BankSwitching {
    // Default implementation for mappers that don't support CHR banking
    mutating func switchCHRBank(bank: UInt8) {
        // Do nothing - not all mappers support CHR banking
    }
}

extension DebugSupport {
    func getDebugInfo() -> [String: Any] {
        return [
            "mapper_id": type(of: self),
            "name": (self as? Mapper)?.name ?? "Unknown"
        ]
    }
}


