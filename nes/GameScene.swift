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

    
    weak var emulator: SystemBus?
    
    override func didMove(to view: SKView) {
        backgroundColor = .black
        
        // NES Display (256x240)
        pixelBuffer = Array(repeating: 0xFF000000, count: 256 * 240)  // Black initially
        
        // Create texture from pixel buffer
        screenTexture = SKMutableTexture(size: CGSize(width: 256, height: 240))
        
        // Create sprite node to display the texture
        screenNode = SKSpriteNode(texture: screenTexture)
        screenNode.size = CGSize(width: 512, height: 480)  // Scale 2x
        screenNode.position = CGPoint(x: frame.midX, y: frame.midY)
        screenNode.texture?.filteringMode = .nearest  // Pixelated look
        
        // NES renders from top left to bottom right, so flip vertically
        screenNode.yScale = -1
        
        addChild(screenNode)
        
        self.view?.window?.makeFirstResponder(self)
        
        DispatchQueue.main.async { [weak self] in
            self?.view?.window?.makeFirstResponder(self)
            print("GameScene: Requested first responder")
        }
        
    }
    
    override var acceptsFirstResponder: Bool {
        print("GameScene: acceptsFirstResponder called")
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        handleKeyEvent(event, isPressed: true)
    }
    
    override func keyUp(with event: NSEvent) {
        handleKeyEvent(event, isPressed: false)
    }
    
    private func handleKeyEvent(_ event: NSEvent, isPressed: Bool) {
        guard let emulator = emulator else { return }
        
        let controller = emulator.controller1
        
        #if DEBUG_GRANULAR
        print("Key \(isPressed ? "DOWN" : "UP"): \(event.charactersIgnoringModifiers ?? "?")")
        #endif
        
        // Map keyboard to NES buttons
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w":
            if isPressed {
                controller.buttons.insert(.up)
            } else {
                controller.buttons.remove(.up)
            }
        case "a":
            if isPressed {
                controller.buttons.insert(.left)
            } else {
                controller.buttons.remove(.left)
            }
        case "s":
            if isPressed {
                controller.buttons.insert(.down)
            } else {
                controller.buttons.remove(.down)
            }
        case "d":
            if isPressed {
                controller.buttons.insert(.right)
            } else {
                controller.buttons.remove(.right)
            }
        case "k":
            if isPressed {
                controller.buttons.insert(.a)
            } else {
                controller.buttons.remove(.a)
            }
        case "l":
            if isPressed {
                controller.buttons.insert(.b)
            } else {
                controller.buttons.remove(.b)
            }
        case "i":
            if isPressed {
                controller.buttons.insert(.select)
            } else {
                controller.buttons.remove(.select)
            }
        case "o":
            if isPressed {
                controller.buttons.insert(.start)
            } else {
                controller.buttons.remove(.start)
            }
        default:
            print("Unmapped key: \(event.charactersIgnoringModifiers ?? "?")")
            return
        }
        
        #if DEBUG_GRANULAR
        // Always print current button state after any change
        print("Controller buttons: \(String(format: "%02X", controller.buttons.rawValue))")
        #endif
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
        pixelBuffer.withUnsafeBytes { ptr in
            screenTexture.modifyPixelData { pixelData, lengthInBytes in
                memcpy(pixelData, ptr.baseAddress, lengthInBytes)
            }
        }
    }
}
