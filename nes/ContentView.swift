//
//  ContentView.swift
//  nes
//
//  Created by mike on 7/27/25.
//

import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var emulatorState = EmulatorState()
    
    var body: some View {
        SpriteKitView(emulatorState: emulatorState)
            .frame(minWidth: 512, minHeight: 480)
            .onAppear {
                emulatorState.start()
            }
    }
}

class EmulatorState: ObservableObject {
    let bus = SystemBus()
    private var timer: Timer?
    private var frameCount = 0
    weak var scene: GameScene?
    
    init() {
        // Load a simple test program that changes background color
        loadTestProgram()
        bus.reset()
    }
    
    func loadTestProgram() {
        // Simple program to set PPU background color
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
    }
    
    func start() {
        // Use CADisplayLink instead of Timer for better sync with display
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.runFrame()
        }
    }
    
    func runFrame() {
        // Run multiple frames if we're behind
        let startTime = CACurrentMediaTime()
        
        repeat {
            bus.clock()
        } while !bus.ppu.frameComplete
        
        scene?.updateFromPPU()
        bus.ppu.frameComplete = false

// FPS Timer
//        let elapsed = CACurrentMediaTime() - startTime
//        if elapsed > 1.0/60.0 {
//            print("Frame took \(elapsed * 1000)ms - too slow!")
//        }
    }
}

struct SpriteKitView: NSViewRepresentable {
    let emulatorState: EmulatorState
    
    func makeNSView(context: Context) -> SKView {
        let skView = SKView()
        
        let scene = GameScene()
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
