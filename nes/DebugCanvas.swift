//
//  DebugCanvas.swift
//  nes
//
//  Created by mike on 8/10/25.
//

import SwiftUI

// MARK: - Live Debug Canvas
struct DebugLiveCanvas: View {
    @ObservedObject var cpuState: CPUDebugState
    @ObservedObject var memoryState: MemoryDebugState
    @ObservedObject var ppuState: PPUDebugState
    
    @State private var selectedView = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Canvas selector
            HStack {
                Text("Live Debug")
                    .font(.headline)
                
                Spacer()
                
                Picker("View", selection: $selectedView) {
                    Text("CPU Activity").tag(0)
                    Text("Memory Map").tag(1)
                    Text("Stack Visual").tag(2)
                    Text("Bus Activity").tag(3)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 400)
            }
            .padding()
            
            Divider()
            
            // Canvas content
            ScrollView {
                switch selectedView {
                case 0:
                    CPUActivityCanvas(cpuState: cpuState)
                case 1:
                    MemoryMapCanvas(memoryState: memoryState)
                case 2:
                    StackVisualCanvas(memoryState: memoryState)
                case 3:
                    BusActivityCanvas(cpuState: cpuState, memoryState: memoryState)
                default:
                    CPUActivityCanvas(cpuState: cpuState)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - CPU Activity Canvas
struct CPUActivityCanvas: View {
    @ObservedObject var cpuState: CPUDebugState
    @State private var instructionHistory: [InstructionEntry] = []
    
    struct InstructionEntry: Identifiable {
        let id = UUID()
        let pc: UInt16
        let instruction: String
        let timestamp: Date
        let cycleCount: Int
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // CPU State Visualization
            HStack(alignment: .top, spacing: 20) {
                // Register visualization
                VStack(alignment: .leading, spacing: 8) {
                    Text("Registers")
                        .font(.headline)
                    
                    RegisterBar(name: "A", value: cpuState.a, max: 255)
                    RegisterBar(name: "X", value: cpuState.x, max: 255)
                    RegisterBar(name: "Y", value: cpuState.y, max: 255)
                    RegisterBar(name: "SP", value: cpuState.sp, max: 255)
                }
                .frame(width: 200)
                
                // Status flags visualization
                VStack(alignment: .leading, spacing: 8) {
                    Text("Status Flags")
                        .font(.headline)
                    
                    StatusFlagsVisual(status: cpuState.status)
                }
                .frame(width: 200)
                
                // Program counter visualization
                VStack(alignment: .leading, spacing: 8) {
                    Text("Program Counter")
                        .font(.headline)
                    
                    Text(String(format: "$%04X", cpuState.pc))
                        .font(.system(.title, design: .monospaced))
                        .foregroundColor(.blue)
                    
                    // Memory region indicator
                    MemoryRegionIndicator(address: cpuState.pc)
                }
            }
            .padding()
            
            Divider()
            
            // Instruction execution timeline
            VStack(alignment: .leading, spacing: 8) {
                Text("Instruction Timeline")
                    .font(.headline)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(instructionHistory.suffix(20)) { entry in
                            InstructionBlock(entry: entry, isLatest: entry.id == instructionHistory.last?.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 60)
            }
            .padding()
        }
        .onChange(of: cpuState.pc) { newPC in
            // Add new instruction to history
            let entry = InstructionEntry(
                pc: newPC,
                instruction: cpuState.currentInstruction,
                timestamp: Date(),
                cycleCount: cpuState.cycleCount
            )
            instructionHistory.append(entry)
            
            // Keep only last 50 entries
            if instructionHistory.count > 50 {
                instructionHistory.removeFirst()
            }
        }
    }
}

// MARK: - Memory Map Canvas
struct MemoryMapCanvas: View {
    @ObservedObject var memoryState: MemoryDebugState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Memory Map Visualization")
                .font(.headline)
                .padding()
            
            // Memory regions overview
            VStack(spacing: 8) {
                MemoryRegionView(
                    name: "Zero Page",
                    range: "0000-00FF",
                    color: .green,
                    isActive: memoryState.viewAddress <= 0x00FF
                )
                
                MemoryRegionView(
                    name: "Stack",
                    range: "0100-01FF",
                    color: .blue,
                    isActive: memoryState.viewAddress >= 0x0100 && memoryState.viewAddress <= 0x01FF
                )
                
                MemoryRegionView(
                    name: "RAM",
                    range: "0200-07FF",
                    color: .orange,
                    isActive: memoryState.viewAddress >= 0x0200 && memoryState.viewAddress <= 0x07FF
                )
                
                MemoryRegionView(
                    name: "PPU Registers",
                    range: "2000-3FFF",
                    color: .purple,
                    isActive: memoryState.viewAddress >= 0x2000 && memoryState.viewAddress <= 0x3FFF
                )
                
                MemoryRegionView(
                    name: "ROM",
                    range: "8000-FFFF",
                    color: .red,
                    isActive: memoryState.viewAddress >= 0x8000
                )
            }
            .padding()
            
            // Memory usage heatmap
            Text("Memory Activity Heatmap")
                .font(.headline)
                .padding(.horizontal)
            
            MemoryHeatmap(changedAddresses: memoryState.changedAddresses)
                .padding()
        }
    }
}

// MARK: - Stack Visual Canvas
struct StackVisualCanvas: View {
    @ObservedObject var memoryState: MemoryDebugState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stack Visualization")
                .font(.headline)
                .padding()
            
            HStack(alignment: .top, spacing: 20) {
                // Stack pointer position
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stack Pointer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "$%02X", memoryState.stackPointer))
                        .font(.system(.title, design: .monospaced))
                        .foregroundColor(.red)
                    
                    Text("Address: $\(String(format: "%04X", 0x0100 + Int(memoryState.stackPointer)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Visual stack representation
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stack Contents")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    StackVisualizer(
                        stackData: memoryState.stackData,
                        stackPointer: memoryState.stackPointer
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Bus Activity Canvas
struct BusActivityCanvas: View {
    @ObservedObject var cpuState: CPUDebugState
    @ObservedObject var memoryState: MemoryDebugState
    
    @State private var busActivity: [BusTransaction] = []
    
    struct BusTransaction: Identifiable {
        let id = UUID()
        let address: UInt16
        let data: UInt8
        let isWrite: Bool
        let timestamp: Date
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bus Activity Monitor")
                .font(.headline)
                .padding()
            
            // Bus statistics
            HStack(spacing: 40) {
                VStack {
                    Text("\(busActivity.filter { !$0.isWrite }.count)")
                        .font(.title)
                        .foregroundColor(.blue)
                    Text("Reads")
                        .font(.caption)
                }
                
                VStack {
                    Text("\(busActivity.filter { $0.isWrite }.count)")
                        .font(.title)
                        .foregroundColor(.red)
                    Text("Writes")
                        .font(.caption)
                }
                
                VStack {
                    Text("\(Set(busActivity.map { $0.address }).count)")
                        .font(.title)
                        .foregroundColor(.green)
                    Text("Unique Addresses")
                        .font(.caption)
                }
            }
            .padding()
            
            // Recent bus transactions
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Transactions")
                    .font(.subheadline)
                
                LazyVStack(spacing: 2) {
                    ForEach(busActivity.suffix(10).reversed()) { transaction in
                        BusTransactionRow(transaction: transaction)
                    }
                }
                .padding(.horizontal)
            }
        }
        .onChange(of: memoryState.changedAddresses) { addresses in
            // Simulate bus activity tracking
            for address in addresses {
                let transaction = BusTransaction(
                    address: address,
                    data: 0, // Would need actual data from bus
                    isWrite: true,
                    timestamp: Date()
                )
                busActivity.append(transaction)
                
                // Keep only recent transactions
                if busActivity.count > 100 {
                    busActivity.removeFirst()
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct RegisterBar: View {
    let name: String
    let value: UInt8
    let max: UInt8
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.caption)
                    .frame(width: 20, alignment: .leading)
                
                Text(String(format: "$%02X", value))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.blue)
                
                Spacer()
                
                Text("(\(value))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: Double(value), total: Double(max))
                .progressViewStyle(LinearProgressViewStyle(tint: getBarColor()))
                .frame(height: 4)
        }
    }
    
    private func getBarColor() -> Color {
        let percentage = Double(value) / Double(max)
        if percentage > 0.8 { return .red }
        if percentage > 0.5 { return .orange }
        return .green
    }
}

struct StatusFlagsVisual: View {
    let status: UInt8
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            FlagBox(name: "N", isSet: status & 0x80 != 0)
            FlagBox(name: "V", isSet: status & 0x40 != 0)
            FlagBox(name: "B", isSet: status & 0x10 != 0)
            FlagBox(name: "D", isSet: status & 0x08 != 0)
            FlagBox(name: "I", isSet: status & 0x04 != 0)
            FlagBox(name: "Z", isSet: status & 0x02 != 0)
            FlagBox(name: "C", isSet: status & 0x01 != 0)
        }
    }
}

struct FlagBox: View {
    let name: String
    let isSet: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
            
            Circle()
                .fill(isSet ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 12, height: 12)
        }
    }
}

struct MemoryRegionIndicator: View {
    let address: UInt16
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Region:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(getRegionName())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(getRegionColor())
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(getRegionColor().opacity(0.2))
                .cornerRadius(4)
        }
    }
    
    private func getRegionName() -> String {
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
    
    private func getRegionColor() -> Color {
        switch address {
        case 0x0000...0x00FF: return .green
        case 0x0100...0x01FF: return .blue
        case 0x0200...0x07FF: return .orange
        case 0x2000...0x3FFF: return .purple
        case 0x4000...0x401F: return .yellow
        case 0x8000...0xFFFF: return .red
        default: return .gray
        }
    }
}

struct InstructionBlock: View {
    let entry: CPUActivityCanvas.InstructionEntry
    let isLatest: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%04X", entry.pc))
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white)
            
            Rectangle()
                .fill(isLatest ? Color.blue : Color.gray)
                .frame(width: 30, height: 20)
                .opacity(isLatest ? 1.0 : 0.6)
        }
        .animation(.easeInOut(duration: 0.2), value: isLatest)
    }
}

struct MemoryRegionView: View {
    let name: String
    let range: String
    let color: Color
    let isActive: Bool
    
    var body: some View {
        HStack {
            Rectangle()
                .fill(color)
                .frame(width: 4, height: 30)
                .opacity(isActive ? 1.0 : 0.3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                
                Text(range)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isActive {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal)
        .background(isActive ? color.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

struct MemoryHeatmap: View {
    let changedAddresses: Set<UInt16>
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 32), spacing: 1) {
            ForEach(0..<256, id: \.self) { i in
                let address = UInt16(i)
                Rectangle()
                    .fill(changedAddresses.contains(address) ? Color.red : Color.gray.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.3), value: changedAddresses.contains(address))
            }
        }
    }
}

struct StackVisualizer: View {
    let stackData: [UInt8]
    let stackPointer: UInt8
    
    var body: some View {
        VStack(spacing: 1) {
            ForEach((0x01F0...0x01FF).reversed(), id: \.self) { address in
                let index = address - 0x0100
                let isSP = address == 0x0100 + Int(stackPointer)
                let hasData = address > 0x0100 + Int(stackPointer)
                
                HStack(spacing: 4) {
                    Text(String(format: "%02X", address & 0xFF))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    Rectangle()
                        .fill(getStackColor(isSP: isSP, hasData: hasData))
                        .frame(width: 40, height: 12)
                        .overlay(
                            Text(index < stackData.count ? String(format: "%02X", stackData[index]) : "")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white)
                        )
                    
                    if isSP {
                        Text("← SP")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
    
    private func getStackColor(isSP: Bool, hasData: Bool) -> Color {
        if isSP { return .red }
        if hasData { return .blue }
        return .gray.opacity(0.3)
    }
}

struct BusTransactionRow: View {
    let transaction: BusActivityCanvas.BusTransaction
    
    var body: some View {
        HStack {
            Circle()
                .fill(transaction.isWrite ? Color.red : Color.blue)
                .frame(width: 8, height: 8)
            
            Text(transaction.isWrite ? "W" : "R")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 15)
            
            Text(String(format: "$%04X", transaction.address))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 50)
            
            Text(String(format: "$%02X", transaction.data))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 30)
            
            Spacer()
            
            Text(timeAgo(from: transaction.timestamp))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 1)
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 1 { return "now" }
        return "\(Int(interval))s"
    }
}
