//
//  Mapper.swift
//  nes
//
//  Created by mike on 8/2/25.
//

import Foundation

// MARK: - Mapper Protocol
protocol Mapper {
    func cpuMapRead(addr: UInt16, mappedAddr: inout UInt32) -> Bool
    func cpuMapWrite(addr: UInt16, mappedAddr: inout UInt32) -> Bool
    func ppuMapRead(addr: UInt16, mappedAddr: inout UInt32) -> Bool
    func ppuMapWrite(addr: UInt16, mappedAddr: inout UInt32) -> Bool
    func reset()
}
