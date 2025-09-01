//
//  DebugViews.swift
//  nes
//
//  Created by mike on 8/10/25.
//
import Foundation
import SwiftUI
import Combine

class CPUDebugState: ObservableObject {
    @Published var pc: UInt16 = 0
    @Published var a: UInt8 = 0
    @Published var x: UInt8 = 0
    @Published var y: UInt8 = 0
    @Published var sp: UInt8 = 0
    @Published var status: UInt8 = 0
    
    @Published var currentInstruction: String = ""
    @Published var nextInstructions: [String] = []
    
    @Published var cycleCount: Int = 0
    @Published var frameCount: Int = 0
    
    func update(from cpu: OLC6502, bus: SystemBus) {
        pc = cpu.pc
        a = cpu.a
        x = cpu.x
        y = cpu.y
        sp = cpu.stkp
        status = cpu.status
        
        // Decode current instruction
        currentInstruction = decodeInstruction(at: pc, bus: bus)
        
        // Decode next few instructions
        nextInstructions = []
        var addr = pc
        for _ in 0..<5 {
            let (decoded, size) = decodeInstructionWithSize(at: addr, bus: bus)
            nextInstructions.append(decoded)
            addr = addr &+ UInt16(size)
        }
    }
    
    private func decodeInstruction(at address: UInt16, bus: SystemBus) -> String {
        let opcode = bus.cpuRead(address: address, readOnly: true)
        let op1 = bus.cpuRead(address: address &+ 1, readOnly: true)
        let op2 = bus.cpuRead(address: address &+ 2, readOnly: true)
        
        return String(format: "$%04X: %02X %02X %02X", address, opcode, op1, op2)
    }
    
    private func decodeInstructionWithSize(at address: UInt16, bus: SystemBus) -> (String, Int) {
        let opcode = bus.cpuRead(address: address, readOnly: true)
        let op1 = bus.cpuRead(address: address &+ 1, readOnly: true)
        let op2 = bus.cpuRead(address: address &+ 2, readOnly: true)
        
        // Simplified - return 3 bytes for now
        let decoded = String(format: "$%04X: %02X %02X %02X", address, opcode, op1, op2)
        return (decoded, 3)
    }
}

class MemoryDebugState: ObservableObject {
    @Published var viewAddress: UInt16 = 0x0000
    @Published var memoryData: [UInt8] = []
    @Published var stackData: [UInt8] = []
    @Published var stackPointer: UInt8 = 0xFF
    @Published var changedAddresses: Set<UInt16> = []
    
    func update(from bus: SystemBus) {
        // Update memory view
        memoryData = []
        for i in 0..<256 {
            let addr = viewAddress &+ UInt16(i)
            memoryData.append(bus.cpuRead(address: addr, readOnly: true))
        }
        
        // Update stack view
        stackData = []
        for i in 0x0100...0x01FF {
            stackData.append(bus.cpuRam[i])
        }
        
        stackPointer = bus.cpu.stkp
    }
    
    func markChanged(_ address: UInt16) {
        changedAddresses.insert(address)
        // Clear old changes after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.changedAddresses.remove(address)
        }
    }
}

// MARK: - Debug Views

struct CPUStateView: View {
    @ObservedObject var cpuState: CPUDebugState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CPU State")
                .font(.headline)
                .padding(.horizontal)
            
            Divider()
            
            // Registers
            VStack(alignment: .leading, spacing: 4) {
                RegisterRow(name: "PC", value16: cpuState.pc)
                RegisterRow(name: "A", value8: cpuState.a)
                RegisterRow(name: "X", value8: cpuState.x)
                RegisterRow(name: "Y", value8: cpuState.y)
                RegisterRow(name: "SP", value8: cpuState.sp)
            }
            .padding(.horizontal)
            
            Divider()
            
            // Status Flags
            StatusFlagsView(status: cpuState.status)
                .padding(.horizontal)
            
            Divider()
            
            // Cycle/Frame counts
            VStack(alignment: .leading, spacing: 2) {
                Text("Cycle: \(cpuState.cycleCount)")
                    .font(.system(.caption, design: .monospaced))
                Text("Frame: \(cpuState.frameCount)")
                    .font(.system(.caption, design: .monospaced))
            }
            .padding(.horizontal)
            
            Divider()
            
            // Current/Next Instructions
            VStack(alignment: .leading, spacing: 4) {
                Text("Instructions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(cpuState.currentInstruction)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.blue)
                
                ForEach(cpuState.nextInstructions, id: \.self) { instruction in
                    Text(instruction)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct RegisterRow: View {
    let name: String
    let value16: UInt16?
    let value8: UInt8?
    
    init(name: String, value16: UInt16) {
        self.name = name
        self.value16 = value16
        self.value8 = nil
    }
    
    init(name: String, value8: UInt8) {
        self.name = name
        self.value16 = nil
        self.value8 = value8
    }
    
    var body: some View {
        HStack {
            Text("\(name):")
                .font(.system(.body, design: .monospaced))
                .frame(width: 30, alignment: .leading)
            
            if let value16 = value16 {
                Text(String(format: "$%04X", value16))
                    .font(.system(.body, design: .monospaced))
            } else if let value8 = value8 {
                Text(String(format: "$%02X", value8))
                    .font(.system(.body, design: .monospaced))
            }
            
            Spacer()
        }
    }
}

struct StatusFlagsView: View {
    let status: UInt8
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Status Flags")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                FlagIndicator(name: "N", isSet: status & 0x80 != 0)
                FlagIndicator(name: "V", isSet: status & 0x40 != 0)
                FlagIndicator(name: "B", isSet: status & 0x10 != 0)
                FlagIndicator(name: "D", isSet: status & 0x08 != 0)
                FlagIndicator(name: "I", isSet: status & 0x04 != 0)
                FlagIndicator(name: "Z", isSet: status & 0x02 != 0)
                FlagIndicator(name: "C", isSet: status & 0x01 != 0)
            }
        }
    }
}

struct FlagIndicator: View {
    let name: String
    let isSet: Bool
    
    var body: some View {
        Text(name)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(isSet ? .white : .gray)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isSet ? Color.green : Color.gray.opacity(0.3))
            )
    }
}

struct DebugContainer: View {
    @ObservedObject var memoryState: MemoryDebugState
    @ObservedObject var ppuDebugState: PPUDebugState
    @ObservedObject var mapperDebugState: MapperDebugState
    @State private var selectedDebugView = "RAM"
    @State private var addressInput = ""
    
    let debugViews = ["RAM", "Palette", "Instructions", "Mapper"]
    
    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar with debug view list
            VStack(alignment: .leading, spacing: 0) {
                Text("Debug Views")
                    .font(.headline)
                    .padding(8)
                
                List(debugViews, id: \.self, selection: $selectedDebugView) { viewName in
                    Text(viewName)
                        .tag(viewName)
                }
                .listStyle(SidebarListStyle())
            }
            .frame(width: 120)
            
            Divider()
            
            // Right content area
            VStack(spacing: 0) {
                // Controls header (only for RAM)
                if selectedDebugView == "RAM" {
                    HStack(spacing: 8) {
                        // Quick jump buttons
                        Button("Zero") { jumpToAddress(0x0000) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        Button("Stack") { jumpToAddress(0x0100) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        Button("PPU") { jumpToAddress(0x2000) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        Button("ROM") { jumpToAddress(0x8000) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        
                        Spacer()
                        
                        // Address input
                        Text("Go to:")
                            .font(.caption)
                        TextField("2000", text: $addressInput)
                            .frame(width: 50)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(.caption, design: .monospaced))
                            .onSubmit { jumpToInputAddress() }
                        
                        Button("Go") { jumpToInputAddress() }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                }
                
                // Main content
                ScrollView([.vertical]) {
                    switch selectedDebugView {
                    case "RAM":
                        MemoryHexView(
                            baseAddress: memoryState.viewAddress,
                            data: memoryState.memoryData,
                            changedAddresses: memoryState.changedAddresses,
                            rowsToShow: 20
                        )
                    case "Palette":
                        PPUDebugViewer(ppuDebugState: ppuDebugState)
                    case "Mapper":
                        MapperDebugView(mapperState: mapperDebugState)
                    default:
                        Text("Coming Soon")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func jumpToAddress(_ address: UInt16) {
        memoryState.viewAddress = address
        addressInput = String(format: "%04X", address)
    }
    
    private func jumpToInputAddress() {
        if let addr = UInt16(addressInput, radix: 16) {
            memoryState.viewAddress = addr
        }
    }
}

struct MemoryHexView: View {
    let baseAddress: UInt16
    let data: [UInt8]
    let changedAddresses: Set<UInt16>
    let rowsToShow: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("Address")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 60, alignment: .leading)
                
                ForEach(0..<16, id: \.self) { col in
                    Text(String(format: "%X", col))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 24)
                        .foregroundColor(.secondary)
                }
                
                Text("ASCII")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 140, alignment: .leading)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            
            // Memory rows with more data
            LazyVStack(spacing: 1) {
                ForEach(0..<min(rowsToShow, (data.count + 15) / 16), id: \.self) { row in
                    MemoryRow(
                        baseAddress: baseAddress,
                        data: data,
                        changedAddresses: changedAddresses,
                        row: row
                    )
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

struct MemoryRow: View {
    let baseAddress: UInt16
    let data: [UInt8]
    let changedAddresses: Set<UInt16>
    let row: Int
    
    var body: some View {
        HStack(spacing: 0) {
            // Address
            Text(String(format: "%04X:", baseAddress &+ UInt16(row * 16)))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 60, alignment: .leading)
                .foregroundColor(.secondary)
            
            // Hex values
            ForEach(0..<16, id: \.self) { col in
                let index = row * 16 + col
                if index < data.count {
                    let address = baseAddress &+ UInt16(index)
                    let isChanged = changedAddresses.contains(address)
                    
                    Text(String(format: "%02X", data[index]))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 24)
                        .foregroundColor(isChanged ? .red : .primary)
                        .background(isChanged ? Color.red.opacity(0.2) : Color.clear)
                } else {
                    Text("  ")
                        .frame(width: 24)
                }
            }
            
            // ASCII representation
            HStack(spacing: 0) {
                ForEach(0..<16, id: \.self) { col in
                    let index = row * 16 + col
                    if index < data.count {
                        let byte = data[index]
                        let char = (byte >= 32 && byte <= 126) ? String(Character(UnicodeScalar(byte))) : "."
                        Text(char)
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 8)
                    } else {
                        Text(" ")
                            .frame(width: 8)
                    }
                }
            }
            .frame(width: 140, alignment: .leading)
            
            Spacer()
        }
        .padding(.vertical, 1)
    }
}

struct StackView: View {
    let stackData: [UInt8]
    let stackPointer: UInt8
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(stackDisplayRange, id: \.self) { address in
                let index = address - 0x0100
                
                guard index >= 0 && index < stackData.count else {
                    return AnyView(EmptyView())
                }
                
                let isSP = (address == 0x0100 + Int(stackPointer))
                let hasData = address > (0x0100 + Int(stackPointer))
                
                return AnyView(
                    HStack {
                        Text(String(format: "$%04X:", address))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Text(String(format: "%02X", stackData[index]))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(getColor(isSP: isSP, hasData: hasData))
                        
                        Text(getLabel(isSP: isSP, hasData: hasData))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(isSP ? .red : .secondary)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                )
            }
        }
    }
    
    private var stackDisplayRange: [Int] {
        // Always show the top portion of the stack for context
        let topOfStack = 0x01FF
        let bottomDisplay = max(0x0100, 0x0100 + Int(stackPointer) - 5) // Show 5 below SP
        
        return Array((bottomDisplay...topOfStack)).reversed()
    }
    
    private func getColor(isSP: Bool, hasData: Bool) -> Color {
        if isSP { return .red }
        if hasData { return .primary }
        return .secondary
    }
    
    private func getLabel(isSP: Bool, hasData: Bool) -> String {
        if isSP { return "← SP" }
        if !hasData { return "(empty)" }
        return ""
    }
}

struct CompactMemoryControls: View {
    @ObservedObject var memoryState: MemoryDebugState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Memory Info")
                .font(.headline)
                .padding(.horizontal, 8)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current: $\(String(format: "%04X", memoryState.viewAddress))")
                        .font(.system(.caption, design: .monospaced))
                    
                    Text("Region: \(getMemoryRegion(memoryState.viewAddress))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stack: $\(String(format: "%02X", memoryState.stackPointer))")
                        .font(.system(.caption, design: .monospaced))
                    
                    Text("Changes: \(memoryState.changedAddresses.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Color.black.opacity(0.05))
    }
    
    private func getMemoryRegion(_ address: UInt16) -> String {
        switch address {
        case 0x0000...0x00FF: return "Zero Page"
        case 0x0100...0x01FF: return "Stack"
        case 0x0200...0x07FF: return "RAM"
        case 0x2000...0x3FFF: return "PPU"
        case 0x4000...0x401F: return "APU/IO"
        case 0x8000...0xFFFF: return "ROM"
        default: return "Unknown"
        }
    }
}

// MARK: - Mapper Debug
class MapperDebugState: ObservableObject {
    @Published var mapperID: UInt8 = 0
    @Published var mapperName: String = ""
    
    // MMC3 specific state
    @Published var prgBanks: UInt8 = 0
    @Published var chrBanks: UInt8 = 0
    @Published var chrBankOffsets: [UInt32] = []
    @Published var prgBankOffsets: [UInt32] = []
    @Published var registers: [UInt8] = Array(repeating: 0, count: 8)
    @Published var targetRegister: UInt8 = 0
    @Published var prgBankMode: Bool = false
    @Published var chrInversion: Bool = false
    @Published var mirrorMode: String = ""
    
    // IRQ state
    @Published var irqActive: Bool = false
    @Published var irqEnabled: Bool = false
    @Published var irqCounter: UInt16 = 0
    @Published var irqReload: UInt16 = 0
    
    // Bank switch history
    @Published var bankSwitches: [BankSwitchEvent] = []
    private let maxHistoryEntries = 50
    
    func update(from bus: SystemBus) {
        guard let cart = bus.cart else {
            mapperName = "No Cartridge"
            return
        }
        
        mapperID = cart.mapperID
        mapperName = getMapperName(cart.mapperID)
        
        // Use DebugSupport protocol
        if let debugInfo = cart.getMapperDebugInfo() {
            updateFromDebugInfo(debugInfo)
        }
        
        // Use BankSwitching protocol
        if let bankSwitcher = cart.mapper as? BankSwitching {
            // Can get current bank info if needed
        }
        
        // Use IRQGeneration protocol
        if let irqMapper = cart.mapper as? IRQGeneration {
            irqActive = irqMapper.irqActive
        }
        
        // Use MirrorControl protocol
        if let mirrorMapper = cart.mapper as? MirrorControl {
            mirrorMode = String(describing: mirrorMapper.mirrorMode)
        }
    }
    
    func addBankSwitch(register: UInt8, oldValue: UInt8, newValue: UInt8) {
        let event = BankSwitchEvent(
            register: register,
            oldValue: oldValue,
            newValue: newValue,
            timestamp: Date()
        )
        bankSwitches.insert(event, at: 0)
        if bankSwitches.count > maxHistoryEntries {
            bankSwitches.removeLast()
        }
    }
    
    private func updateFromDebugInfo(_ debugInfo: [String: Any]) {
        // Extract the info returned by MMC3 getDebugInfo()
        if let prgBanks = debugInfo["prg_banks"] as? UInt8 { self.prgBanks = prgBanks }
        if let chrBanks = debugInfo["chr_banks"] as? UInt8 { self.chrBanks = chrBanks }
        if let prgMode = debugInfo["prg_bank_mode"] as? Bool { self.prgBankMode = prgMode }
        if let chrInv = debugInfo["chr_inversion"] as? Bool { self.chrInversion = chrInv }
        if let target = debugInfo["target_register"] as? UInt8 { self.targetRegister = target }

        if let chrOffsets = debugInfo["chr_bank_offsets"] as? [UInt32] {
            self.chrBankOffsets = chrOffsets
        }
        if let prgOffsets = debugInfo["prg_bank_offsets"] as? [UInt32] {
            self.prgBankOffsets = prgOffsets
        }
        if let regs = debugInfo["registers"] as? [UInt8] {
            self.registers = regs
        }
    }
    
    private func getMapperName(_ id: UInt8) -> String {
        switch id {
        case 0: return "NROM"
        case 1: return "MMC1"
        case 4: return "MMC3"
        default: return "Unknown"
        }
    }
}

struct BankSwitchEvent {
    let register: UInt8
    let oldValue: UInt8
    let newValue: UInt8
    let timestamp: Date
}

struct MapperDebugView: View {
    @ObservedObject var mapperState: MapperDebugState
    @State private var selectedSection = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with mapper info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Mapper \(mapperState.mapperID): \(mapperState.mapperName)")
                        .font(.headline)
                    Text("Mode:")
                        .font(.caption)
                    Text(mapperState.prgBankMode ? "PRG" : "Normal")
                        .font(.system(.caption, design: .monospaced,))
                        .foregroundColor(.green)
                    Text("CHR:")
                        .font(.caption)
                    Text(mapperState.chrInversion ? "Inverted" : "Normal")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green)
                    Text("Mirror:")
                        .font(.caption)
                    Text(mapperState.mirrorMode)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green)
                    Spacer()
                    Text("PRG: \(mapperState.prgBanks) | CHR: \(mapperState.chrBanks)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            
            // Section picker
            Picker("", selection: $selectedSection) {
                Text("Banks").tag(0)
                Text("Registers").tag(1)
                Text("IRQ").tag(2)
                Text("History").tag(3)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            // Content area
            ScrollView {
                switch selectedSection {
                case 0:
                    BankMappingView(mapperState: mapperState)
                case 1:
                    RegistersView(mapperState: mapperState)
                case 2:
                    IRQStatusView(mapperState: mapperState)
                case 3:
                    BankSwitchHistoryView(mapperState: mapperState)
                default:
                    EmptyView()
                }
            }
        }
    }
}

struct BankMappingView: View {
    @ObservedObject var mapperState: MapperDebugState
    
    var body: some View {
        HStack(spacing: 8) {
            // CHR Bank Mapping
            VStack(alignment: .leading, spacing: 4) {
                Text("CHR Banks (1KB each)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(0..<8, id: \.self) { i in
                    if i < mapperState.chrBankOffsets.count {
                        let bankNum = mapperState.chrBankOffsets[i] / 0x0400
                        let ppuStart = i * 0x0400
                        let ppuEnd = ppuStart + 0x03FF
                        
                        HStack {
                            Text("PPU $\(String(format: "%04X", ppuStart))-$\(String(format: "%04X", ppuEnd))")
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 120, alignment: .leading)
                            
                            Text("→")
                                .foregroundColor(.secondary)
                            
                            Text("CHR Bank \(bankNum)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(bankNum > mapperState.chrBanks ? .red : .primary)
                            
                            Spacer()
                        }
                    }
                }
            }
            .padding(8)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(4)
            
            // PRG Bank Mapping
            VStack(alignment: .leading, spacing: 4) {
                Text("PRG Banks (8KB each)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                let cpuRanges = [
                    (0x8000, 0x9FFF, 0),
                    (0xA000, 0xBFFF, 1),
                    (0xC000, 0xDFFF, 2),
                    (0xE000, 0xFFFF, 3)
                ]
                
                ForEach(cpuRanges, id: \.2) { start, end, index in
                    if index < mapperState.prgBankOffsets.count {
                        let bankNum = mapperState.prgBankOffsets[index] / 0x2000
                        
                        HStack {
                            Text("CPU $\(String(format: "%04X", start))-$\(String(format: "%04X", end))")
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 120, alignment: .leading)
                            
                            Text("→")
                                .foregroundColor(.secondary)
                            
                            Text("PRG Bank \(bankNum)")
                                .font(.system(.caption, design: .monospaced))
                            
                            Spacer()
                        }
                    }
                }
            }
            .padding(8)
            .background(Color.green.opacity(0.05))
            .cornerRadius(4)
        }
        .padding(8)
    }
}

struct RegistersView: View {
    @ObservedObject var mapperState: MapperDebugState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Control registers
            VStack(alignment: .leading, spacing: 4) {
                Text("Control State")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("Target: R\(mapperState.targetRegister)")
                        .font(.system(.caption, design: .monospaced))
                    Spacer()
                    Text("PRG Mode: \(mapperState.prgBankMode ? "ON" : "OFF")")
                        .font(.system(.caption, design: .monospaced))
                    Spacer()
                    Text("CHR Inv: \(mapperState.chrInversion ? "ON" : "OFF")")
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(4)
            
            // Internal registers
            VStack(alignment: .leading, spacing: 4) {
                Text("Internal Registers")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 4) {
                    ForEach(0..<8, id: \.self) { i in
                        if i < mapperState.registers.count {
                            HStack {
                                Text("R\(i):")
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 25, alignment: .leading)
                                
                                Text("$\(String(format: "%02X", mapperState.registers[i]))")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(i == mapperState.targetRegister ? .blue : .primary)
                                
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.05))
            .cornerRadius(4)
        }
        .padding(8)
    }
}

struct IRQStatusView: View {
    @ObservedObject var mapperState: MapperDebugState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("IRQ Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Circle()
                        .fill(mapperState.irqActive ? Color.red : Color.gray)
                        .frame(width: 8, height: 8)
                    Text("Active")
                        .font(.system(.caption, design: .monospaced))
                    
                    Spacer()
                    
                    Circle()
                        .fill(mapperState.irqEnabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text("Enabled")
                        .font(.system(.caption, design: .monospaced))
                }
                
                HStack {
                    Text("Counter:")
                        .font(.system(.caption, design: .monospaced))
                    Text("\(mapperState.irqCounter)")
                        .font(.system(.caption, design: .monospaced))
                    
                    Spacer()
                    
                    Text("Reload:")
                        .font(.system(.caption, design: .monospaced))
                    Text("\(mapperState.irqReload)")
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .padding(8)
            .background(Color.red.opacity(0.05))
            .cornerRadius(4)
        }
        .padding(8)
    }
}

struct BankSwitchHistoryView: View {
    @ObservedObject var mapperState: MapperDebugState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Bank Switches")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            
            if mapperState.bankSwitches.isEmpty {
                Text("No bank switches recorded")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
            } else {
                ForEach(mapperState.bankSwitches.indices, id: \.self) { index in
                    let event = mapperState.bankSwitches[index]
                    HStack {
                        Text("R\(event.register):")
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 25)
                        
                        Text("$\(String(format: "%02X", event.oldValue)) → $\(String(format: "%02X", event.newValue))")
                            .font(.system(.caption, design: .monospaced))
                        
                        Spacer()
                        
                        Text(timeAgo(event.timestamp))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 1 { return "now" }
        if interval < 60 { return "\(Int(interval))s" }
        return "\(Int(interval/60))m"
    }
}
