//
//  GameScene.swift
//  nes
//
//  Created by mike on 8/3/25.
//

import SpriteKit

class GameScene: SKScene {
    private var screenNode: SKSpriteNode!
    private var screenTexture: SKMutableTexture!
    private var pixelBuffer: [UInt32] = []
//    weak var scene: GameScene?
    
    weak var emulator: SystemBus?  // Reference to our emulator
    
    override func didMove(to view: SKView) {
        backgroundColor = .black
        
        // Create a buffer for our NES display (256x240)
        pixelBuffer = Array(repeating: 0xFF000000, count: 256 * 240)  // Black initially
        
        // Create texture from our pixel buffer
        screenTexture = SKMutableTexture(size: CGSize(width: 256, height: 240))
        
        // Create sprite node to display the texture
        screenNode = SKSpriteNode(texture: screenTexture)
        screenNode.size = CGSize(width: 512, height: 480)  // Scale 2x
        screenNode.position = CGPoint(x: frame.midX, y: frame.midY)
        screenNode.texture?.filteringMode = .nearest  // Pixelated look
        
        addChild(screenNode)
        
        // Test pattern - gradient
//        testPattern()
//        updateScreen()
    }
    
    func testPattern() {
        // Create a test pattern to verify palette colors
        for y in 0..<240 {
            for x in 0..<256 {
                let paletteIndex = UInt8((x / 4) & 0x3F)  // Cycle through palette
                pixelBuffer[y * 256 + x] = NESPalette.getColor(paletteIndex)
            }
        }
    }
    
    func updateFromPPU() {
        guard let emulator = emulator else { return }
        
        // Direct array copy
        pixelBuffer = emulator.ppu.framebuffer
        
        updateScreen()
    }
    
    func updateScreen() {
        // Convert our UInt32 buffer to raw bytes for the texture
        pixelBuffer.withUnsafeBytes { ptr in
            screenTexture.modifyPixelData { pixelData, lengthInBytes in
                memcpy(pixelData, ptr.baseAddress, lengthInBytes)
            }
        }
    }
}
