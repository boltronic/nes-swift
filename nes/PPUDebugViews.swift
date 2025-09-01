//
//  PaletteViews.swift
//  nes
//
//  Created by mike on 8/10/25.
//

import Foundation
import SwiftUI

// MARK: - NES Palette Extension
extension NESPalette {
    static func getNSColor(_ index: UInt8) -> NSColor {
        let rgb = getColor(index)  // Use your existing getColor method
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        return NSColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
    
    static func getSwiftUIColor(_ index: UInt8) -> Color {
        let rgb = getColor(index)  // Use your existing getColor method
        let red = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8) & 0xFF) / 255.0
        let blue = Double(rgb & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }
}

// MARK: - Palette Viewer
struct PaletteViewer: View {
    let paletteData: [UInt8]  // 32 bytes of palette RAM (0x3F00-0x3F1F)
    @Binding var selectedPalette: Int
    let swatchSize: CGFloat = 20
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Palettes")
                .font(.headline)
            
            // Background Palettes (0-3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Background Palettes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { palette in
                        PaletteSwatch(
                            paletteIndex: palette,
                            paletteData: paletteData,
                            isBackground: true,
                            isSelected: selectedPalette == palette,
                            swatchSize: swatchSize
                        ) {
                            selectedPalette = palette
                        }
                    }
                }
            }
            
            // Sprite Palettes (4-7)
            VStack(alignment: .leading, spacing: 4) {
                Text("Sprite Palettes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 2) {
                    ForEach(4..<8, id: \.self) { palette in
                        PaletteSwatch(
                            paletteIndex: palette,
                            paletteData: paletteData,
                            isBackground: false,
                            isSelected: selectedPalette == palette,
                            swatchSize: swatchSize
                        ) {
                            selectedPalette = palette
                        }
                    }
                }
            }
            
            // Selected Palette Details
            PaletteDetailView(
                selectedPalette: selectedPalette,
                paletteData: paletteData
            )
        }
//        .padding(.trailing, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Individual Palette Swatch
struct PaletteSwatch: View {
    let paletteIndex: Int
    let paletteData: [UInt8]
    let isBackground: Bool
    let isSelected: Bool
    let swatchSize: CGFloat
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 1) {
            Text("P\(paletteIndex)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary)
            
            HStack(spacing: 1) {
                ForEach(0..<4, id: \.self) { colorIndex in
                    let color = getColor(palette: paletteIndex, colorIndex: colorIndex)
                    
                    Rectangle()
                        .fill(Color(color))
                        .frame(width: swatchSize, height: swatchSize)
                        .overlay(
                            Rectangle()
                                .stroke(Color.primary, lineWidth: colorIndex == 0 ? 0.5 : 0)
                        )
                }
            }
            .overlay(
                Rectangle()
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
            )
        }
        .onTapGesture {
            onTap()
        }
    }
    
    private func getColor(palette: Int, colorIndex: Int) -> NSColor {
        // Calculate palette RAM address
        let baseAddr = isBackground ? 0 : 16  // Background: 0x3F00-0x3F0F, Sprite: 0x3F10-0x3F1F
        var addr = baseAddr + (palette % 4) * 4 + colorIndex
        
        // Handle transparency - color index 0 always maps to universal background
        if colorIndex == 0 {
            addr = 0  // Universal background color at 0x3F00
        }
        
        // Bounds check
        guard addr < paletteData.count else {
            return NSColor.black
        }
        
        let paletteIndex = paletteData[addr]
        return NESPalette.getNSColor(paletteIndex)
    }
}

// MARK: - Palette Detail View
struct PaletteDetailView: View {
    let selectedPalette: Int
    let paletteData: [UInt8]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Palette \(selectedPalette) Details")
                .font(.caption)
                .fontWeight(.semibold)
            
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { colorIndex in
                    let (paletteValue, nesColorIndex) = getColorInfo(colorIndex: colorIndex)
                    
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(Color(NESPalette.getNSColor(nesColorIndex)))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Rectangle().stroke(Color.primary, lineWidth: 0.5)
                            )
                        
                        Text(String(format: "%02X", paletteValue))
                            .font(.system(size: 8, design: .monospaced))
                        
                        Text("(\(nesColorIndex))")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.1))
        .cornerRadius(4)
    }
    
    private func getColorInfo(colorIndex: Int) -> (paletteValue: UInt8, nesColorIndex: UInt8) {
        let isBackground = selectedPalette < 4
        let baseAddr = isBackground ? 0 : 16
        var addr = baseAddr + (selectedPalette % 4) * 4 + colorIndex
        
        if colorIndex == 0 {
            addr = 0  // Universal background
        }
        
        guard addr < paletteData.count else {
            return (0, 0)
        }
        
        let paletteValue = paletteData[addr]
        return (paletteValue, paletteValue & 0x3F)  // NES palette is 6-bit
    }
}

// MARK: - Pattern Table Viewer
struct PatternTableViewer: View {
    let patternTable0: NSImage?  // 128x128 image of pattern table 0
    let patternTable1: NSImage?  // 128x128 image of pattern table 1
    let selectedPalette: Int
    
    private let tileSize: CGFloat = 16  // Each 8x8 tile displayed as 16x16
    private let tableSize: CGFloat = 256  // 16 tiles * 16 pixels each
    
    @State private var selectedTile: TileInfo? = nil
    
    struct TileInfo {
        let table: Int
        let index: Int
        let x: Int
        let y: Int
        let address: UInt16
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pattern Tables (Palette \(selectedPalette))")
                    .font(.headline)
                
                HStack(spacing: 20) {
                    VStack {
                        Text("Table 0 ($0000)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ZStack {
                            if let image = patternTable0 {
                                Image(nsImage: image)
                                    .interpolation(.none)  // Pixel-perfect scaling
                                    .resizable()  // Allow the image to be resized
                                    .frame(width: tableSize, height: tableSize)
                            } else {
                                Rectangle()
                                    .fill(Color.black)
                                    .frame(width: tableSize, height: tableSize)
                                    .overlay(
                                        Text("No CHR Data")
                                            .foregroundColor(.white)
                                            .font(.caption)
                                    )
                            }
                            
                            // Grid overlay for tile boundaries
                            GridOverlay(size: tableSize, tileSize: tileSize)
                            
                            // Selection highlight for table 0
                            if let tile = selectedTile, tile.table == 0 {
                                TileSelectionOverlay(
                                    tileX: tile.x,
                                    tileY: tile.y,
                                    tileSize: tileSize
                                )
                            }
                        }
                        .border(Color.gray, width: 1)
                        .onTapGesture { location in
                            handleTileClick(location: location, table: 0)
                        }
                    }
                    
                    VStack {
                        Text("Table 1 ($1000)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ZStack {
                            if let image = patternTable1 {
                                Image(nsImage: image)
                                    .interpolation(.none)
                                    .resizable()  // Allow the image to be resized
                                    .frame(width: tableSize, height: tableSize)
                            } else {
                                Rectangle()
                                    .fill(Color.black)
                                    .frame(width: tableSize, height: tableSize)
                                    .overlay(
                                        Text("No CHR Data")
                                            .foregroundColor(.white)
                                            .font(.caption)
                                    )
                            }
                            
                            // Grid overlay for tile boundaries
                            GridOverlay(size: tableSize, tileSize: tileSize)
                            
                            // Selection highlight for table 1
                            if let tile = selectedTile, tile.table == 1 {
                                TileSelectionOverlay(
                                    tileX: tile.x,
                                    tileY: tile.y,
                                    tileSize: tileSize
                                )
                            }
                        }
                        .border(Color.gray, width: 1)
                        .onTapGesture { location in
                            handleTileClick(location: location, table: 1)
                        }
                    }
                }
            }
            
            // Tile details panel
            if let tile = selectedTile {
                TileDetailPanel(tile: tile, selectedPalette: selectedPalette)
                    .frame(width: 200)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func handleTileClick(location: CGPoint, table: Int) {
        let tileX = Int(location.x / tileSize)
        let tileY = Int(location.y / tileSize)
        
        // Clamp to valid range
        guard tileX >= 0 && tileX < 16 && tileY >= 0 && tileY < 16 else { return }
        
        let tileIndex = tileY * 16 + tileX
        let baseAddress: UInt16 = table == 0 ? 0x0000 : 0x1000
        let tileAddress = baseAddress + UInt16(tileIndex * 16)
        
        selectedTile = TileInfo(
            table: table,
            index: tileIndex,
            x: tileX,
            y: tileY,
            address: tileAddress
        )
    }
}

struct GridOverlay: View {
    let size: CGFloat
    let tileSize: CGFloat
    
    var body: some View {
        Canvas { context, canvasSize in
            let gridColor = Color.white.opacity(0.3)
            
            // Vertical lines
            for i in 1..<16 {  // 15 lines for 16 tiles
                let x = CGFloat(i) * tileSize
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size))
                    },
                    with: .color(gridColor),
                    lineWidth: 0.5
                )
            }
            
            // Horizontal lines
            for i in 1..<16 {  // 15 lines for 16 tiles
                let y = CGFloat(i) * tileSize
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size, y: y))
                    },
                    with: .color(gridColor),
                    lineWidth: 0.5
                )
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)  // Let clicks pass through to the image
    }
}

struct TileSelectionOverlay: View {
    let tileX: Int
    let tileY: Int
    let tileSize: CGFloat
    
    var body: some View {
        Rectangle()
            .stroke(Color.yellow, lineWidth: 2)
            .frame(width: tileSize, height: tileSize)
            .position(
                x: CGFloat(tileX) * tileSize + tileSize/2,
                y: CGFloat(tileY) * tileSize + tileSize/2
            )
            .allowsHitTesting(false)
    }
}

struct TileDetailPanel: View {
    let tile: PatternTableViewer.TileInfo
    let selectedPalette: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tile Details")
                .font(.headline)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Table: \(tile.table)")
                Text("Index: $\(String(format: "%02X", tile.index)) (\(tile.index))")
                Text("Position: (\(tile.x), \(tile.y))")
                Text("Address: $\(String(format: "%04X", tile.address))")
                Text("Palette: \(selectedPalette)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            Divider()
            
            Text("Pattern Data")
                .font(.subheadline)
                .fontWeight(.medium)
            
            // Placeholder for pattern data - you'll need to implement this
            VStack(alignment: .leading, spacing: 2) {
                Text("Low byte:  $XX")
                Text("High byte: $XX")
                Text("...")
                Text("(8 bytes each)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Combined Debug View
struct PPUDebugViewer: View {
    @ObservedObject var ppuDebugState: PPUDebugState
    @State private var selectedPalette = 0

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            PaletteViewer(
                paletteData: ppuDebugState.paletteData,
                selectedPalette: $selectedPalette
            )
            .frame(maxWidth: .infinity, alignment: .leading) // Allow it to expand
            
            PatternTableViewer(
                patternTable0: ppuDebugState.patternTable0Image,
                patternTable1: ppuDebugState.patternTable1Image,
                selectedPalette: selectedPalette
            )
            .frame(maxWidth: .infinity, alignment: .leading) // Allow it to expand
        }
        .onChange(of: selectedPalette) {
            ppuDebugState.updatePatternTables(selectedPalette: selectedPalette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

// MARK: - PPU Debug State
class PPUDebugState: ObservableObject {
    @Published var paletteData: [UInt8] = Array(repeating: 0, count: 32)
    @Published var patternTable0Image: NSImage?
    @Published var patternTable1Image: NSImage?
    
    private var bus: SystemBus?  // Keep reference to bus
    
    func update(from bus: SystemBus) {
        self.bus = bus  // Store bus reference
        
        // Update palette data (0x3F00-0x3F1F)
        paletteData = (0x3F00...0x3F1F).map { bus.ppu.ppuRead(UInt16($0)) }
    }
    
    func updatePatternTables(selectedPalette: Int) {
        guard let bus = bus else { return }
        
        // Generate both pattern table images
        patternTable0Image = generatePatternTableImage(bus: bus, table: 0, palette: selectedPalette)
        patternTable1Image = generatePatternTableImage(bus: bus, table: 1, palette: selectedPalette)
    }
    
    private func generatePatternTableImage(bus: SystemBus, table: Int, palette: Int) -> NSImage? {
        let tableSize = 128  // Each pattern table is 128x128 pixels (16x16 tiles, 8x8 each)
        let tileSize = 8
        let tilesPerRow = 16
        
        // Create bitmap data
        var imageData = [UInt8](repeating: 0, count: tableSize * tableSize * 4) // RGBA
        
        let baseAddress: UInt16 = table == 0 ? 0x0000 : 0x1000
        
        // Process each tile (256 tiles total per pattern table)
        for tileY in 0..<tilesPerRow {
            for tileX in 0..<tilesPerRow {
                let tileIndex = tileY * tilesPerRow + tileX
                let tileAddress = baseAddress + UInt16(tileIndex * 16)  // Each tile is 16 bytes
                
                // Process each pixel in the tile (8x8)
                for pixelY in 0..<tileSize {
                    for pixelX in 0..<tileSize {
                        // Read pattern table data
                        let patternLo = bus.ppu.ppuRead(tileAddress + UInt16(pixelY))
                        let patternHi = bus.ppu.ppuRead(tileAddress + UInt16(pixelY) + 8)
                        
                        // Extract 2-bit pixel value
                        let bit = 7 - pixelX
                        let p0 = (patternLo >> bit) & 1
                        let p1 = (patternHi >> bit) & 1
                        let pixelValue = (p1 << 1) | p0
                        
                        // Convert to color using selected palette
                        let color = getPixelColor(pixelValue: pixelValue, palette: palette)
                        
                        // Calculate position in final image
                        let imageX = tileX * tileSize + pixelX
                        let imageY = tileY * tileSize + pixelY
                        let pixelIndex = (imageY * tableSize + imageX) * 4
                        
                        // Set RGBA values
                        if pixelIndex + 3 < imageData.count {
                            imageData[pixelIndex + 0] = color.r     // Red
                            imageData[pixelIndex + 1] = color.g     // Green
                            imageData[pixelIndex + 2] = color.b     // Blue
                            imageData[pixelIndex + 3] = 255         // Alpha
                        }
                    }
                }
            }
        }
        
        // Create NSImage from bitmap data
        return createNSImageFromRGBA(data: imageData, width: tableSize, height: tableSize)
    }
    
    private func getPixelColor(pixelValue: UInt8, palette: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        // For pattern table viewing, we typically use one of the background palettes
        // You can modify this to use sprite palettes if needed
        
        let isBackground = palette < 4
        let baseAddr = isBackground ? 0 : 16
        var paletteAddr = baseAddr + (palette % 4) * 4 + Int(pixelValue)
        
        // Handle transparency
        if pixelValue == 0 {
            paletteAddr = 0  // Universal background
        }
        
        // Get palette index (bounds checking)
        let paletteIndex = paletteAddr < paletteData.count ? paletteData[paletteAddr] : 0
        
        // Convert to RGB
        let rgb = NESPalette.getColor(paletteIndex)
        let r = UInt8((rgb >> 16) & 0xFF)
        let g = UInt8((rgb >> 8) & 0xFF)
        let b = UInt8(rgb & 0xFF)
        
        return (r, g, b)
    }
    
    private func createNSImageFromRGBA(data: [UInt8], width: Int, height: Int) -> NSImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: UnsafeMutablePointer(mutating: data),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        guard let cgImage = context.makeImage() else {
            return nil
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        return nsImage
    }
}

extension PPUDebugState {
    func debugPatternTableData() {
        guard let bus = bus else {
            print("No bus available for pattern table debug")
            return
        }
        
        print("=== Pattern Table Debug ===")
        
        // Check if pattern tables have any data
        var hasData0 = false
        var hasData1 = false
        
        // Sample first few bytes of each table
        for i in 0..<16 {
            let byte0 = bus.ppu.ppuRead(UInt16(i))
            let byte1 = bus.ppu.ppuRead(0x1000 + UInt16(i))
            
            if byte0 != 0 { hasData0 = true }
            if byte1 != 0 { hasData1 = true }
            
            if i < 8 {
                print("Table 0 [\(String(format: "%04X", i))]: \(String(format: "%02X", byte0))")
                print("Table 1 [\(String(format: "%04X", 0x1000 + i))]: \(String(format: "%02X", byte1))")
            }
        }
        
        print("Pattern Table 0 has data: \(hasData0)")
        print("Pattern Table 1 has data: \(hasData1)")
        
        // Check if using test pattern table or real CHR ROM
        if bus.ppu.testPatternTable != nil {
            print("Using test pattern table")
        } else {
            print("Using cartridge CHR ROM")
        }
    }
}

//private func debugPPUState() {
//    print("\n=== PPU Debug Info ===")
//    print("Control: \(String(format: "%02X", bus.ppu.control.rawValue))")
//    print("Mask: \(String(format: "%02X", bus.ppu.mask.rawValue))")
//    print("Status: \(String(format: "%02X", bus.ppu.status.rawValue))")
//
//    // Check palette
//    print("\nBackground Palette:")
//    for i in 0..<16 {
//        let color = bus.ppu.ppuRead(0x3F00 + UInt16(i))
//        if i % 4 == 0 { print("") }
//        print(String(format: "%02X ", color), terminator: "")
//    }
//
//    print("\n\nSprite Palette:")
//    for i in 0..<16 {
//        let color = bus.ppu.ppuRead(0x3F10 + UInt16(i))
//        if i % 4 == 0 { print("") }
//        print(String(format: "%02X ", color), terminator: "")
//    }
//
//    // Check if pattern tables have data
//    print("\n\nPattern table 0 sample (first 16 bytes):")
//    for i in 0..<16 {
//        let byte = bus.ppu.ppuRead(UInt16(i))
//        print(String(format: "%02X ", byte), terminator: "")
//        if i % 8 == 7 { print("") }
//    }
//
//    // Check nametable
//    print("\nNametable 0 sample (first 32 bytes):")
//    for i in 0..<32 {
//        let byte = bus.ppu.ppuRead(0x2000 + UInt16(i))
//        print(String(format: "%02X ", byte), terminator: "")
//        if i % 16 == 15 { print("") }
//    }
//
//    // Check rendering position
//    print("\n\nPPU Internal state:")
//    print("Scanline: \(bus.ppu.scanline)")
//    print("Cycle: \(bus.ppu.cycle)")
//    print("Frame complete: \(bus.ppu.frameComplete)")
//}
