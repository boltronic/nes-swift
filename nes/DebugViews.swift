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
        
        // This is a simplified decoder - you'd want to use your actual instruction set
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

struct MemoryViewer: View {
    @ObservedObject var memoryState: MemoryDebugState
    @ObservedObject var ppuDebugState: PPUDebugState
    @State private var selectedTab = 0
    @State private var addressInput = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Compact header with tabs and controls in one row
            HStack(spacing: 8) {
                // Memory type picker
                Picker("", selection: $selectedTab) {
                    Text("RAM").tag(0)
                    Text("Palette").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 280)
                
                // Quick jump buttons (only for RAM view)
                if selectedTab == 0 {
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
                }
                
                Spacer()
                
                // Address input (only for RAM view)
                if selectedTab == 0 {
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            
            // Main content area
            ScrollView([.vertical]) {
                switch selectedTab {
                case 0:
                    // RAM view
                    MemoryHexView(
                        baseAddress: memoryState.viewAddress,
                        data: memoryState.memoryData,
                        changedAddresses: memoryState.changedAddresses,
                        rowsToShow: 20
                    )
                case 1:
                    // Palette view
                    PPUDebugViewer(ppuDebugState: ppuDebugState)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
