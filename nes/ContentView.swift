//
//  ContentView.swift
//  nes
//
//  Created by mike on 7/27/25.
//

import SwiftUI
import SpriteKit
import UniformTypeIdentifiers

struct SpriteKitView: NSViewRepresentable {
    let emulatorState: EmulatorState
    
    func makeNSView(context: Context) -> SKView {
        let skView = SKView()
        
        let scene = GameScene(size: CGSize(width: 512, height: 480))
        scene.size = CGSize(width: 512, height: 480)
        scene.scaleMode = .aspectFit
        scene.emulator = emulatorState.bus
        emulatorState.scene = scene  // Connect scene to emulator state
        
        skView.presentScene(scene)
        skView.ignoresSiblingOrder = true
        skView.showsFPS = true
        
        return skView
    }
    
    func updateNSView(_ nsView: SKView, context: Context) {}
}


struct ContentView: View {
    @StateObject private var emulatorState = EmulatorState()
    @State private var showingRomPicker = false
    @State private var romLoaded = false
    @State private var showDebugPanel = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Menu bar at the top
            HStack {
                Button("Load ROM") {
                    showingRomPicker = true
                }
                .padding()
                Button("Load Test Program") {
                    emulatorState.loadTestProgram()
                    romLoaded = true
                }
                .padding()
                Button(emulatorState.isPaused ? "Resume" : "Pause") {
                    emulatorState.togglePause()
                }
                .padding()
                
                Button("Step") {
                    emulatorState.step()
                }
                .padding()
                Toggle("Show Debug", isOn: $showDebugPanel)
                    .padding()
                Spacer()
            }
            .background(Color.gray.opacity(0.2))
            
            if showDebugPanel {
                VStack(spacing: 0) {
                    // Top section - SpriteKit with CPU State and Stack on sides
                    HStack(spacing: 0) {
                        // Left side - CPU State
                        CPUStateView(cpuState: emulatorState.cpuDebugState)
                            .frame(width: 200)
                            .background(Color(NSColor.controlBackgroundColor))
                        
                        Divider()
                        
                        // Center - SpriteKit view only
                        SpriteKitView(emulatorState: emulatorState)
                            .frame(minWidth: 512, minHeight: 480)
                        
                        Divider()
                        
                        // Right side - Stack
                        VStack(spacing: 0) {
                            Text("Stack")
                                .font(.headline)
                                .padding(.top, 8)
                            Divider()
                            ScrollView {
                                StackView(
                                    stackData: emulatorState.memoryDebugState.stackData,
                                    stackPointer: emulatorState.memoryDebugState.stackPointer
                                )
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(width: 150)
                        .background(Color(NSColor.controlBackgroundColor))
                    }
                    
                    Divider()
                    
                    // Bottom section - Memory viewer spans full width
                    DebugContainer(
                        memoryState: emulatorState.memoryDebugState,
                        ppuDebugState: emulatorState.ppuDebugState,
                        mapperDebugState: emulatorState.mapperDebugState
                    )
                    .frame(maxWidth: .infinity, maxHeight: 300)
                }
            } else {
                // Just the SpriteKit view when debug panel is hidden
                SpriteKitView(emulatorState: emulatorState)
                    .frame(minWidth: 512, minHeight: 480)
            }
        }
        .fileImporter(
            isPresented: $showingRomPicker,
            allowedContentTypes: [UTType(filenameExtension: "nes") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    loadROM(from: url)
                }
            case .failure(let error):
                print("Error selecting file: \(error)")
            }
        }
    }

    
    private func loadROM(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Couldn't access file")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        if emulatorState.loadROM(from: url) {
            romLoaded = true
        }
    }
}

struct DebugPanel: View {
    @ObservedObject var cpuState: CPUDebugState
    @ObservedObject var memoryState: MemoryDebugState
    @ObservedObject var ppuDebugState: PPUDebugState
    @ObservedObject var mapperDebugState: MapperDebugState

    var body: some View {
        HStack(spacing: 0) {
            // Left side - CPU state
            CPUStateView(cpuState: cpuState)
                .frame(width: 200, height: 300)

            Divider()

            // Center - Memory viewer
            DebugContainer(
                memoryState: memoryState,
                ppuDebugState: ppuDebugState,
                mapperDebugState: mapperDebugState
            )
            .frame(minWidth: 600, maxHeight: 300)

            Divider()

            // Right side - Stack
            VStack(spacing: 0) {
                Text("Stack")
                    .font(.headline)
                    .padding(.top, 8)

                Divider()

                ScrollView {
                    StackView(
                        stackData: memoryState.stackData,
                        stackPointer: memoryState.stackPointer
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 150, height: 300)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}


class EmulatorState: ObservableObject {
    let bus = SystemBus()
    private var timer: Timer?
    private var frameCount = 0
    weak var scene: GameScene?
    
    // Debug
    @Published var cpuDebugState = CPUDebugState()
    @Published var memoryDebugState = MemoryDebugState()
    @Published var ppuDebugState = PPUDebugState()
    @Published var mapperDebugState = MapperDebugState()  // Add this line
    @Published var isPaused = false
    
    init() {

    }
    
    func updateDebugInfo() {
        cpuDebugState.update(from: bus.cpu, bus: bus)
        cpuDebugState.frameCount = frameCount
        memoryDebugState.update(from: bus)
        ppuDebugState.update(from: bus)
        mapperDebugState.update(from: bus)
    }
    
    func step() {
        guard isPaused else { return }
        // Execute one instruction
        repeat {
            bus.clock()
        } while !bus.cpu.complete()
        
        updateDebugInfo()
    }
    
    func togglePause() {
        isPaused.toggle()
        if isPaused {
            timer?.invalidate()
            updateDebugInfo()
        } else {
            start()
        }
    }
    
    func loadROM(from url: URL) -> Bool {
        // Stop current emulation
        timer?.invalidate()
        
        // Clear test pattern table
        bus.ppu.testPatternTable = nil
        
        // Try to load cartridge
        guard let cartridge = Cartridge(fileName: url.path) else {
            print("Failed to load ROM from \(url.path)")
            loadTestProgram()
            return false
        }
        
        print("\n=== ROM loaded successfully ===")
        print("- File: \(url.lastPathComponent)")
        print("- PRG Banks: \(cartridge.prgBanks)")
        print("- CHR Banks: \(cartridge.chrBanks)")
        print("- Mapper: \(cartridge.mapperID)")
        print("- Mirror mode: \(cartridge.getMirrorMode())")
        
        bus.insertCartridge(cartridge)
        bus.reset()
        
        // Verify reset vector
        let resetLo = bus.cpuRead(address: 0xFFFC, readOnly: true)
        let resetHi = bus.cpuRead(address: 0xFFFD, readOnly: true)
        let resetVector = UInt16(resetHi) << 8 | UInt16(resetLo)
        print("- Reset vector: $\(String(format: "%04X", resetVector))")
        
        updateDebugInfo()
        
        start()
        
        return true
    }
    
    func runFrame() {
        guard !isPaused else { return }
        
        var cycleCount:Int = 0
        let maxCycles = 100000
        
        repeat {
            bus.clock()
            cycleCount += 1
            
            if cycleCount > maxCycles {
                print("WARNING: Frame taking too long (\(cycleCount) cycles), forcing completion")
                bus.ppu.frameComplete = true
                break
            }
        } while !bus.ppu.frameComplete
        
        scene?.updateFromPPU()
        bus.ppu.frameComplete = false
        frameCount += 1
        
        // MARK: - Debug Update Frequency
        if frameCount % 10 == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.updateDebugInfo()
            }
        }
    }
    
    func loadTestProgram() {
        // Your existing test program code
        let program: [UInt8] = [
            // Set PPU address to palette location $3F00
            0xA9, 0x3F,  // LDA #$3F
            0x8D, 0x06, 0x20,  // STA $2006
            0xA9, 0x00,  // LDA #$00
            0x8D, 0x06, 0x20,  // STA $2006
            
            // Write color to palette
            0xA9, 0x31,  // LDA #$31 (light blue)
            0x8D, 0x07, 0x20,  // STA $2007
            
            // Enable rendering
            0xA9, 0x08,  // LDA #$08
            0x8D, 0x01, 0x20,  // STA $2001 (PPUMASK - show background)
            
            // Infinite loop
            0x4C, 0x12, 0x80  // JMP $8012
        ]
        
        // Load program at $8000
        for (i, byte) in program.enumerated() {
            bus.cpuRam[0x8000 + i] = byte
        }
        
        // Set reset vector
        bus.cpuRam[0xFFFC] = 0x00
        bus.cpuRam[0xFFFD] = 0x80
        
        bus.reset()
        start()
    }
    
    func start() {
        // Stop any existing timer
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPaused else { return }
            self.runFrame()
        }
    }
}

struct DebugPanel_Previews: PreviewProvider {
    static var previews: some View {
        DebugPanel(
            cpuState: mockCPUState,
            memoryState: mockMemoryState,
            ppuDebugState: mockPPUDebugState,
            mapperDebugState: mockMapperDebugState
        )
        .frame(width: 1000, height: 350)
        .previewLayout(.sizeThatFits)
    }

    static var mockCPUState: CPUDebugState {
        let state = CPUDebugState()
        state.pc = 0x8000
        state.a = 0x42
        state.x = 0x10
        state.y = 0x20
        state.sp = 0xFF
        state.status = 0b10101010
        state.currentInstruction = "$8000: A9 42"
        state.nextInstructions = ["$8002: 8D 00 02", "$8005: EA", "$8006: 4C 00 80"]
        state.cycleCount = 1234
        state.frameCount = 56
        return state
    }

    static var mockMemoryState: MemoryDebugState {
        let state = MemoryDebugState()
        state.memoryData = Array(repeating: 0xAA, count: 256)
        state.stackData = Array(repeating: 0xBB, count: 256)
        state.stackPointer = 0xF0
        return state
    }

    static var mockPPUDebugState: PPUDebugState {
        let state = PPUDebugState()
        state.paletteData = Array(0..<32)
        // You can add more mock data if your MemoryViewer/PaletteViewer needs it
        return state
    }
    
    static var mockMapperDebugState: MapperDebugState {
        let state = MapperDebugState()
        // TODO: - implement
        return state
    }
}
